import 'package:drift/drift.dart' as drift;
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/extensions/number.dart';
import 'package:expense_tracker/main.dart';
import 'package:expense_tracker/screens/settings.dart';
import 'package:expense_tracker/sync_engine.dart';
import 'package:expense_tracker/widgets/add_expense_dialog.dart';
import 'package:expense_tracker/widgets/ledger_list.dart';
import 'package:expense_tracker/widgets/summary_card.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import "package:drift/drift.dart" as drift;

class Dashboard extends StatefulWidget {
  final VoidCallback onThemeToggle;
  
  const Dashboard({super.key, required this.onThemeToggle});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  final DateTime _selectedMonth = DateTime.now();
  final DateTime _startMonth = DateTime(2026, 3);
  final DateTime _endMonth = DateTime.now();
  
  final List<String> _filters = ["All", "food", "transport", "Entertainment", "Shopping", "Utility", "Health", "Other"];


  String _activeFilter = "All";

  List<Expense> _generateVariableExpensesOfFilter(List<Expense> expenses, DateTime targetDatetime)
  {
    var generatedExpenses = expenses.where((e) =>
      e.date.year == targetDatetime.year && e.date.month == targetDatetime.month
    ).toList();

    if (_activeFilter == "All") return generatedExpenses;
    return generatedExpenses.where((e) => e.categoryId == _activeFilter).toList();
  }
  
  void _generateFixedExpensesForMonth(List<Expense> expenses, DateTime targetDatetime) async
  {
    bool alreadyGenerated = expenses.any((e) => 
      e.date.year == targetDatetime.year &&
      e.date.month == targetDatetime.month
    );

    if (alreadyGenerated) return;

    var templates = await AppDatabase.instance.select(AppDatabase.instance.fixedExpenseTemplates).get();
    for (var template in templates) {
      final newExpense = FixedExpensesCompanion(
        id: drift.Value('${template.id}_${targetDatetime.millisecondsSinceEpoch}'),
        name: drift.Value(template.name),
        amount: drift.Value(template.amount), 
        date: drift.Value(DateTime(targetDatetime.year, targetDatetime.month, 1)),
        categoryId: drift.Value("$template.categoryId"),
        userId: const drift.Value(AppConstants.testUserId), //TODO: Hardcode until auth is added
      );

      await AppDatabase.instance.into(AppDatabase.instance.fixedExpenses).insert(newExpense);
    }
  }
  
  void onFilterChanged (String newFilter) 
  {
    setState(() => _activeFilter = newFilter);
  }

  int getMonthsBetween(DateTime startDt, DateTime endDt,) {
    return ((endDt.year - startDt.year) * 12) + (endDt.month - startDt.month);
  }

  double totalIncomeOfMonth(DateTime monthToFind) {
    return AppConstants.allIncome.firstWhere((item) => item.date.month == monthToFind.month).income;
  }

  double totalExpenseOfFilterOfMonth(List<Expense> expenses, DateTime monthToFind) {
    return _generateVariableExpensesOfFilter(expenses, monthToFind)
      .fold(0, (sum, item) => sum + item.amount);
  }

  double totalExpenseOfMonth(List<Expense> expenses, DateTime monthToFind) {
    var allExpenses = expenses.where((e) =>
      e.date.year == monthToFind.year && e.date.month == monthToFind.month
    ).toList();

    return allExpenses.fold(0, (sum, item) => sum + item.amount);
  }

  Future<void> _runFixedExpenseEngine() async
  {
    DateTime currentMonth = DateTime(_startMonth.year, _startMonth.month, 1);
    DateTime endMonth = DateTime(_endMonth.year, _endMonth.month, 1);

    final currentDbExpenses = await AppDatabase.instance.select(AppDatabase.instance.expenses).get();

    while (!currentMonth.isAfter(endMonth))
    {
      _generateFixedExpensesForMonth(currentDbExpenses, currentMonth);
      currentMonth = DateTime(currentMonth.year, currentMonth.month + 1, 1);
    }

  }

  @override
  void initState() {
    super.initState();
    SyncEngine.instance.pullAllDataFromServer();
    SyncEngine.instance.pushAllDataToServer();
    _runFixedExpenseEngine();
  }
  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final TextStyle titleTextStyle = screenWidth < 600
      ? TextStyle(fontSize: 28, fontWeight: FontWeight.bold)
      : TextStyle(fontSize: 32, fontWeight: FontWeight.bold);
    return Scaffold(
      body: StreamBuilder<List<FixedExpense>>(
        stream: AppDatabase.instance.watchAllFixedExpenses(),
        builder: (context, snapshot) {
          final fixedExpenses = snapshot.data ?? [];

          return StreamBuilder<List<Expense>>(
            stream: AppDatabase.instance.watchAllExpenses(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting)
              {
                return const CircularProgressIndicator();
              }

              final expenses = snapshot.data ?? [];
              double totalIncome = AppConstants.allIncome.sumBy((item) => item.income);
              double totalOut = expenses.sumBy((item) => item.amount);
              double cashFlow = totalIncome - totalOut;

              return SafeArea(
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
                                Text("Expense Tracker", style: titleTextStyle),
                                const Text("Track and manage your spending", style: TextStyle(color: Colors.grey, fontSize: 16))
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 30,),

                      screenWidth < 600 
                      ? Column(
                          children: [
                          SummaryCard(title: "Monthly Income", amount: "\$${totalIncome.toStringAsFixed(2)}", icon: Icons.account_balance, iconColor: Colors.grey,),
                          const SizedBox(height: 20,),
                          SummaryCard(title: "Total Expense", amount: "\$${totalOut.toStringAsFixed(2)}", icon: Icons.trending_down, iconColor: Colors.grey,),
                          const SizedBox(height: 20,),
                          SummaryCard(title: "Cash Flow", amount: "\$${cashFlow.toStringAsFixed(2)}", icon: Icons.trending_up, iconColor: Colors.green,),
                        ],
                      )
                      : Row(
                          children: [
                            Expanded(child: SummaryCard(title: "Monthly Income", amount: "\$${totalIncome.toStringAsFixed(2)}", icon: Icons.account_balance, iconColor: Colors.grey,)),
                            const SizedBox(width: 20,),
                            Expanded(child: SummaryCard(title: "Total Expense", amount: "\$${totalOut.toStringAsFixed(2)}", icon: Icons.trending_down, iconColor: Colors.grey,)),
                            const SizedBox(width: 20,),
                            Expanded(child: SummaryCard(title: "Cash Flow", amount: "\$${cashFlow.toStringAsFixed(2)}", icon: Icons.trending_up, iconColor: Colors.green,)),
                          ],
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
                                  child: AddExpenseDialog(
                                    currentMonth: _selectedMonth,
                                    onExpenseAdded: (ExpensesCompanion newlyCreatedExpense) async {
                                      await AppDatabase.instance.addExpense(newlyCreatedExpense);
                                      SyncEngine.instance.pushAllDataToServer();
                                    },
                                  )
                                ),
                                const SizedBox(width: 30,),
                                
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    children: [
                                      SizedBox(
                                        width: double.infinity,
                                        child: Wrap(
                                          spacing: 8,
                                          alignment: WrapAlignment.start,
                                          children: _filters.map((filterName) {
                                            bool isSelected = _activeFilter == filterName;

                                            return ChoiceChip(
                                              label: Text(filterName),
                                              selected: isSelected,
                                              onSelected: (bool userClickedIt) {
                                                onFilterChanged(filterName);
                                              },
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                      const SizedBox(height: 20,),
                                      _populateLedgerLists(fixedExpenses, expenses)
                                    ],
                                  )
                                )
                              ],
                            );
                          }

                          return _populateLedgerLists(fixedExpenses, expenses);
                        }
                      ),
                    ],
                  )
                ),
              );
            }
          );
        }
      ),
      appBar: AppBar(
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => Settings()));
            },
          ),
          IconButton(
            icon: Icon(Icons.dark_mode),
            onPressed: widget.onThemeToggle,
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
                        AddExpenseDialog(
                          currentMonth: _selectedMonth,
                          onExpenseAdded: (ExpensesCompanion newlyCreatedExpense) async {
                            await AppDatabase.instance.addExpense(newlyCreatedExpense);
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

  Widget _populateLedgerLists(List<FixedExpense> fixedExpenses, List<Expense> expenses)
  {
    DateTime currentMonth = DateTime(_endMonth.year, _endMonth.month, 1);
    DateTime endMonth = DateTime(_startMonth.year, _startMonth.month, 1);
    List<Widget> lists = [];
    int counter = 0;
    while (!currentMonth.isBefore(_startMonth))
    {
      counter++;

      final accIncomeOfMonth = totalIncomeOfMonth(currentMonth);
      final accExpenseOfMonth = totalExpenseOfMonth(expenses, currentMonth);
      final accCashFlowOfMonth = accIncomeOfMonth - accExpenseOfMonth;
      lists.add(
        LedgerList(
          selectedMonth: currentMonth,
          // TODO: We should fetch fixed expenses from the list based on month too
          fixedExpenses: fixedExpenses,
          variableExpenses: _generateVariableExpensesOfFilter(expenses, currentMonth),
          monthStat: (
            accIncomeOfMonth,
            accExpenseOfMonth,
            accCashFlowOfMonth,
          ),
          activeFilter: _activeFilter,
          onDelete: (String idToDelete) async {
            await AppDatabase.instance.deleteExpense(idToDelete);
            SyncEngine.instance.pushAllDataToServer();
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
