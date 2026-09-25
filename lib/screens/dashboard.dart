import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/category_providers.dart';
import 'package:expense_tracker/providers/core_providers.dart';
import 'package:expense_tracker/providers/theme_provider.dart';
import 'package:expense_tracker/providers/transaction_providers.dart';
import 'package:expense_tracker/screens/settings.dart';
import 'package:expense_tracker/widgets/add_expense_dialog.dart';
import 'package:expense_tracker/widgets/monthly_ledger_list.dart';
import 'package:expense_tracker/widgets/summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Dashboard extends ConsumerStatefulWidget {
  const Dashboard({super.key});

  @override
  ConsumerState<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends ConsumerState<Dashboard> {
  final DateTime _selectedMonth = DateTime.now();
  final DateTime _startMonth = DateTime(2026, 3);
  final DateTime _endMonth = DateTime.now();

  int getMonthsBetween(DateTime startDt, DateTime endDt,) {
    return ((endDt.year - startDt.year) * 12) + (endDt.month - startDt.month);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // NOTE: AuthGate only shows the Dashboard when someone is signed in
      final userId = ref.read(currentUserIdProvider);
      if (userId != null) ref.read(syncEngineProvider).runStartUpSync(userId);
    });
  }
  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final metricsAsync = ref.watch(dashboardMetricsProvider);
    final categories = ref.watch(activeCategoriesProvider).value ?? [];
    final activeFilter = ref.watch(activeFilterProvider);
    final TextStyle titleTextStyle = screenWidth < 600
      ? TextStyle(fontSize: 28, fontWeight: FontWeight.bold)
      : TextStyle(fontSize: 32, fontWeight: FontWeight.bold);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Transaction Tracker", style: titleTextStyle),
                        const Text("Track and manage your spending", style: TextStyle(color: Colors.grey, fontSize: 16))
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 30,),

              metricsAsync.when(
                loading: () => const CircularProgressIndicator(),
                error: (error, stackTrace) => Text("Failed to load metrics: $error"),
                data: (metrics) {
                  return screenWidth < 600 
                    ? Column(
                        children: [
                        SummaryCard(title: "Monthly Income", amount: "\$${metrics.income.toStringAsFixed(2)}", icon: Icons.account_balance, iconColor: Colors.grey,),
                        const SizedBox(height: 20,),
                        SummaryCard(title: "Total Transaction", amount: "\$${metrics.expense.toStringAsFixed(2)}", icon: Icons.trending_down, iconColor: Colors.grey,),
                        const SizedBox(height: 20,),
                        SummaryCard(title: "Cash Flow", amount: "\$${metrics.cashFlow.toStringAsFixed(2)}", icon: Icons.trending_up, iconColor: Colors.green,),
                      ],
                    )
                    : Row(
                        children: [
                          Expanded(child: SummaryCard(title: "Monthly Income", amount: "\$${metrics.income.toStringAsFixed(2)}", icon: Icons.account_balance, iconColor: Colors.grey,)),
                          const SizedBox(width: 20,),
                          Expanded(child: SummaryCard(title: "Total Transaction", amount: "\$${metrics.expense.toStringAsFixed(2)}", icon: Icons.trending_down, iconColor: Colors.grey,)),
                          const SizedBox(width: 20,),
                          Expanded(child: SummaryCard(title: "Cash Flow", amount: "\$${metrics.cashFlow.toStringAsFixed(2)}", icon: Icons.trending_up, iconColor: Colors.green,)),
                        ],
                    );
                },
              ),

              const SizedBox(height: 30,),

              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth > 600) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 1,
                          child: AddTransactionDialog(
                            currentMonth: _selectedMonth,
                            onTransactionAdded: (TransactionsCompanion newlyCreatedTransaction) async {
                              await ref.read(transactionActionsProvider).add(newlyCreatedTransaction);
                            },
                          )
                        ),
                        const SizedBox(width: 30,),
                        
                        Builder(
                          builder: (context) {
                            final categoryNames = categories.map((c) => c.name).toList();

                            final filters = [ActiveFilterNotifier.all, ...categoryNames];

                            return Expanded(
                              flex: 2,
                              child: Column(
                                children: [
                                  SizedBox(
                                    width: double.infinity,
                                    child: Wrap(
                                      spacing: 8,
                                      alignment: WrapAlignment.start,
                                      children: filters.map((filterName) {
                                        bool isSelected = activeFilter == filterName;

                                        return ChoiceChip(
                                          label: Text(filterName),
                                          selected: isSelected,
                                          onSelected: (bool userClickedIt) {
                                            ref.read(activeFilterProvider.notifier).select(filterName);
                                          },
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                  const SizedBox(height: 20,),
                                  _populateLedgerLists()
                                ],
                              )
                            );
                          }
                        ),
                      ],
                    );
                  }

                  return _populateLedgerLists();
                }
              ),
            ],
          )
        ),
      ),
      appBar: AppBar(
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const Settings()));
            },
          ),
          IconButton(
            icon: Icon(Icons.dark_mode),
            onPressed: ()
            {
              ref.read(themeModeProvider.notifier).toggle();
            },
          ),
          IconButton(
            icon: Icon(Icons.exit_to_app),
            onPressed: () async
            {
              await ref.read(supabaseProvider).auth.signOut();
            },
          ),
        ],
      ),
      floatingActionButton: screenWidth < 600
        ? FloatingActionButton(
          onPressed: () {
            //NOTE: This is the new standard for Material 3. It's more user friendly compared to showDialog()
            showModalBottomSheet(
              context: context,
              //NOTE: This is to allow the sheet to float higher up the screen
              isScrollControlled: true,
              builder: (BuildContext context) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                    left: 16,
                    right: 16,
                    top: 16,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AddTransactionDialog(
                          currentMonth: _selectedMonth,
                          onTransactionAdded: (TransactionsCompanion newlyCreatedTransaction) async {
                            await ref.read(transactionActionsProvider).add(newlyCreatedTransaction);

                            // NOTE: This needs to be here as an exclusive for mobile
                            // on PC and web there won't be any modal to close! so it would errored out
                            // (Flutter requires checking 'mounted' after an await before navigating)
                            if (context.mounted)
                            {
                              Navigator.pop(context);
                            }
                          },
                        ),
                      ],
                    )
                  )
                );
              }
            );
          },
          child: const Icon(Icons.add),
        )
        : null,
    );
  }

  // TODO: Generate from start of usage date
  Widget _populateLedgerLists()
  {
    DateTime currentMonth = DateTime(_endMonth.year, _endMonth.month, 1);
    List<Widget> lists = [];
    int counter = 0;
    while (!currentMonth.isBefore(_startMonth))
    {
      counter++;
      lists.add(
        MonthlyLedgerList(
          year: currentMonth.year,
          month: currentMonth.month,
          onDelete: (String idToDelete) async {
            final expense = await ref.read(transactionActionsProvider).softDeleteById(idToDelete);

            if (expense != null)
            {
              if (context.mounted)
              {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Deleted ${expense.name}"))
                );
              }
            }
          },
          isInitiallyExpanded: counter == 1 ? true : false,
        )
      );
      // NOTE: Dart automatically converts this to previous year!
      currentMonth = DateTime(currentMonth.year, currentMonth.month - 1, 1);
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      spacing: 20,
      children: lists,
    );
  }
}
