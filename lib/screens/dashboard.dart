import 'package:drift/drift.dart' as drift;
import 'package:expense_tracker/daos/transactions_dao.dart';
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/extensions/number.dart';
import 'package:expense_tracker/main.dart';
import 'package:expense_tracker/screens/settings.dart';
import 'package:expense_tracker/sync_engine.dart';
import 'package:expense_tracker/widgets/add_expense_dialog.dart';
import 'package:expense_tracker/widgets/ledger_list.dart';
import 'package:expense_tracker/widgets/stream_ledger_list.dart';
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
  
  late Future<List<Category>> _categoriesFuture;

  String _activeFilter = "All";
    
  void onFilterChanged (String newFilter) 
  {
    setState(() => _activeFilter = newFilter);
  }

  int getMonthsBetween(DateTime startDt, DateTime endDt,) {
    return ((endDt.year - startDt.year) * 12) + (endDt.month - startDt.month);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SyncEngine.instance.runStartUpSync();
    });

    _categoriesFuture = AppDatabase.instance.categoriesDao.getAllActiveCategories();
  }
  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.sizeOf(context).width;
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

              // screenWidth < 600 
              // ? Column(
              //     children: [
              //     SummaryCard(title: "Monthly Income", amount: "\$${totalIncome.toStringAsFixed(2)}", icon: Icons.account_balance, iconColor: Colors.grey,),
              //     const SizedBox(height: 20,),
              //     SummaryCard(title: "Total Transaction", amount: "\$${totalOut.toStringAsFixed(2)}", icon: Icons.trending_down, iconColor: Colors.grey,),
              //     const SizedBox(height: 20,),
              //     SummaryCard(title: "Cash Flow", amount: "\$${cashFlow.toStringAsFixed(2)}", icon: Icons.trending_up, iconColor: Colors.green,),
              //   ],
              // )
              // : Row(
              //     children: [
              //       Expanded(child: SummaryCard(title: "Monthly Income", amount: "\$${totalIncome.toStringAsFixed(2)}", icon: Icons.account_balance, iconColor: Colors.grey,)),
              //       const SizedBox(width: 20,),
              //       Expanded(child: SummaryCard(title: "Total Transaction", amount: "\$${totalOut.toStringAsFixed(2)}", icon: Icons.trending_down, iconColor: Colors.grey,)),
              //       const SizedBox(width: 20,),
              //       Expanded(child: SummaryCard(title: "Cash Flow", amount: "\$${cashFlow.toStringAsFixed(2)}", icon: Icons.trending_up, iconColor: Colors.green,)),
              //     ],
              // ),


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
                              await AppDatabase.instance.transactionsDao.insertRow(newlyCreatedTransaction);
                            },
                          )
                        ),
                        const SizedBox(width: 30,),
                        
                        FutureBuilder(
                          future: _categoriesFuture,
                          builder: (context, snapshot) {
                            final categories = snapshot.data ?? [];
                            final categoryNames = categories.map((c) => c.name).toList();

                            final filters = ["All", ...categoryNames];

                            
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
                        AddTransactionDialog(
                          currentMonth: _selectedMonth,
                          onTransactionAdded: (TransactionsCompanion newlyCreatedTransaction) async {
                            await AppDatabase.instance.transactionsDao.insertRow(newlyCreatedTransaction);

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
    DateTime endMonth = DateTime(_startMonth.year, _startMonth.month, 1);
    List<Widget> lists = [];
    int counter = 0;
    while (!currentMonth.isBefore(_startMonth))
    {
      counter++;
      lists.add(
        StreamLedgerList(
          year: currentMonth.year,
          month: currentMonth.month,
          activeFilter: _activeFilter,
          onDelete: (String idToDelete) async {
            final expense = await AppDatabase.instance.transactionsDao.getTransactionById(idToDelete);

            if (expense != null)
            {
              await AppDatabase.instance.transactionsDao.softDelete(expense);
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
