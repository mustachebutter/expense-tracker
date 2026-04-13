import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/widgets/add_expense_dialog.dart';
import 'package:expense_tracker/widgets/ledger_list.dart';
import 'package:expense_tracker/widgets/summary_card.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  final double _workIncome = 2908.31;
  final DateTime _selectedMonth = DateTime.now();
  final DateTime _startMonth = DateTime(2026, 3);
  final DateTime _endMonth = DateTime.now();

  List<Expense> allExpenses = [
    Expense(id: '2', label: 'Hydro', fixedAmount: 0, variableAmount: 61, tags: ['Utility'], date: DateTime(2026, 4, 11)),
    Expense(id: '3', label: 'Water', fixedAmount: 0, variableAmount: 111, tags: ['Utility'], date: DateTime(2026, 4, 11)),
    Expense(id: '4', label: 'Hydro', fixedAmount: 0, variableAmount: 50, tags: ['Utility'], date: DateTime(2026, 3, 11)),
    Expense(id: '5', label: 'Uber', fixedAmount: 0, variableAmount: 15, tags: ['Transport'], date: DateTime(2026, 3, 11)),
  ];
  
  final List<String> _filters = ["All", "Food", "Transport", "Entertainment", "Shopping", "Utility", "Health", "Other"];

  final List<Expense> _fixedExpenseTemplates = [
    Expense(
      id: "template_rent",
      label: "Rent",
      fixedAmount: 1100.00,
      date: DateTime.now(),
      tags: ["Fixed"],
    ),
    Expense(
      id: "template_internet",
      label: "Internet and Phone",
      fixedAmount: 163.85,
      date: DateTime.now(),
      tags: ["FIXED"],
    ),
  ];

  String _activeFilter = "All";

  List<Expense> _currentMonthExpense(DateTime targetDatetime)
  {
    var monthList = allExpenses.where((e) =>
      e.date.year == targetDatetime.year && e.date.month == targetDatetime.month
    ).toList();

    if (_activeFilter == "All") return monthList;
    return monthList.where((e) => e.tags.contains(_activeFilter)).toList();
  }
  
  void _generateFixedExpensesForMonth(DateTime targetDatetime)
  {
    bool alreadyGenerated = allExpenses.any((e) => 
      e.date.year == targetDatetime.year &&
      e.date.month == targetDatetime.month &&
      e.tags.contains("Fixed")
    );

    if (alreadyGenerated) return;

    setState(() {
      for (var template in _fixedExpenseTemplates) {
        allExpenses.add(
          Expense(id: '${template.id}_${targetDatetime.millisecondsSinceEpoch}',
          label: template.label,
          fixedAmount: template.fixedAmount,
          variableAmount: 0.0,
          date: DateTime(targetDatetime.year, targetDatetime.month, 1),
          tags: List.from(template.tags),
          )
        );
      }
    });
  }
  
  void onFilterChanged (String newFilter) 
  {
    setState(() => _activeFilter = newFilter);
  }

  double get totalIncome => _workIncome * 2;
  double get totalOut => allExpenses.fold(0, (sum, item) => sum + item.total);
  double get cashFlow => totalIncome - totalOut;

  @override
  void initState() {
    super.initState();
    _generateFixedExpensesForMonth(_selectedMonth);
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(
      //   backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      //   title: const Text("Butters' Cash Flow Tracker"),
      // ),
      backgroundColor: const Color(0xFFF9FAFB),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Expense Tracker", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const Text("Track and manage your spending", style: TextStyle(color: Colors.grey, fontSize: 16)),
            const SizedBox(height: 30,),

            Row(children: [
                Expanded(child: SummaryCard(title: "Monthly Income", amount: "\$${totalIncome.toStringAsFixed(2)}", icon: Icons.account_balance, iconColor: Colors.blue, amountColor: Colors.black)),
                const SizedBox(width: 20,),
                Expanded(child: SummaryCard(title: "Total Expense", amount: "\$${totalOut.toStringAsFixed(2)}", icon: Icons.trending_down, iconColor: Colors.grey, amountColor: Colors.black)),
                const SizedBox(width: 20,),
                Expanded(child: SummaryCard(title: "Cash Flow", amount: "\$${cashFlow.toStringAsFixed(2)}", icon: Icons.trending_up, iconColor: Colors.green, amountColor: Colors.green)),
              ],
            ),

            const SizedBox(height: 30,),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 1,
                  child: AddExpenseDialog(
                    currentMonth: _selectedMonth,
                    onExpenseAdded: (Expense newlyCreatedExpense) {
                      setState(() {
                        allExpenses.add(newlyCreatedExpense);
                      });
                    },
                  )
                ),
                const SizedBox(width: 30,),
                
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      Wrap(
                        spacing: 8,
                        children: _filters.map((filterName) {
                          bool isSelected = _activeFilter == filterName;

                          return ChoiceChip(
                            label: Text(filterName),
                            selected: isSelected,
                            selectedColor: Colors.black,
                            labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black),
                            onSelected: (bool userClickedIt) {
                              onFilterChanged(filterName);
                            },
                          );
                        }).toList(),
                      ),
                    
                      const SizedBox(height: 20,),
                      ..._populateLedgerLists()
                    ],
                  )
                )
              ]
            ),
            // const SizedBox(width: 30,),
          ],
        )
      ),
      // floatingActionButton: FloatingActionButton(
      //   onPressed: () {
      //     showDialog(
      //       context: context,
      //       builder: (context) {
      //         return AddExpenseDialog(
      //           onExpenseAdded: (Expense newlyCreatedExpense) {
      //             setState(() {
      //               allExpenses.add(newlyCreatedExpense);
      //             });
      //           },
      //           currentMonth: _selectedMonth,
      //         );
      //       },
      //     );
      //   },
      //   backgroundColor: const Color(0xFF448AFF),
      //   child: const Icon(Icons.add, color:Colors.white),
      //  ),
    );
  }

  List<Widget> _populateLedgerLists()
  {
    DateTime currentMonth = DateTime(_startMonth.year, _startMonth.month, 1);
    DateTime endMonth = DateTime(_endMonth.year, _endMonth.month, 1);
    List<Widget> lists = [];
    while (!currentMonth.isAfter(endMonth))
    {
      lists.add(
        LedgerList(
          selectedMonth: currentMonth,
          expenses: _currentMonthExpense(currentMonth),
          activeFilter: _activeFilter,
          onDelete: (String idToDelete) {
            setState(() => allExpenses.removeWhere((e) => e.id == idToDelete));
          },
        )
      );
      currentMonth = DateTime(currentMonth.year, currentMonth.month + 1, 1);
    }

    return lists;
  }
}
