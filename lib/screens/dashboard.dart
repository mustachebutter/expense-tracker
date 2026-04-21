import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/screens/settings.dart';
import 'package:expense_tracker/widgets/add_expense_dialog.dart';
import 'package:expense_tracker/widgets/ledger_list.dart';
import 'package:expense_tracker/widgets/summary_card.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

  List<({double income, DateTime date})> allIncome = [
    (income: 2908.31 * 2, date: DateTime(2026, 3)),
    (income: 2908.31 * 2, date: DateTime(2026, 4)),
  ];

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
      tags: ["Fixed"],
    ),
  ];

  String _activeFilter = "All";

  List<Expense> _generateVariableExpensesOfFilter(DateTime targetDatetime)
  {
    var expenses = allExpenses.where((e) =>
      e.date.year == targetDatetime.year && e.date.month == targetDatetime.month && !e.tags.contains("Fixed")
    ).toList();

    if (_activeFilter == "All") return expenses;
    return expenses.where((e) => e.tags.contains(_activeFilter)).toList();
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

  int getMonthsBetween(DateTime startDt, DateTime endDt,) {
    return ((endDt.year - startDt.year) * 12) + (endDt.month - startDt.month);
  }

  double totalIncomeOfMonth(DateTime monthToFind) {
    return allIncome.firstWhere((item) => item.date.month == monthToFind.month).income;
  }

  double totalExpenseOfFilterOfMonth(DateTime monthToFind) {
    var expenses = _generateVariableExpensesOfFilter(monthToFind);
    return expenses.fold(0, (sum, item) => sum + item.fixedAmount + item.variableAmount);
  }

  double totalExpenseOfMonth(DateTime monthToFind) {
    var expenses = allExpenses.where((e) =>
      e.date.year == monthToFind.year && e.date.month == monthToFind.month
    ).toList();

    return expenses.fold(0, (sum, item) => sum + item.fixedAmount + item.variableAmount);
  }

  double totalCashFlowOfMonth(DateTime monthToFind) {
    return totalIncomeOfMonth(monthToFind) - totalExpenseOfMonth(monthToFind);
  }

  double get totalIncome => allIncome.fold(0, (sum, item) => sum + item.income);
  double get totalOut => allExpenses.fold(0, (sum, item) => sum + item.total);
  double get cashFlow => totalIncome - totalOut;

  @override
  void initState() {
    super.initState();
    DateTime currentMonth = DateTime(_startMonth.year, _startMonth.month, 1);
    DateTime endMonth = DateTime(_endMonth.year, _endMonth.month, 1);
    while (!currentMonth.isAfter(endMonth))
    {
      _generateFixedExpensesForMonth(currentMonth);
      currentMonth = DateTime(currentMonth.year, currentMonth.month + 1, 1);
    }
  }
  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  children: [
                    const Text("Expense Tracker", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                    const Text("Track and manage your spending", style: TextStyle(color: Colors.grey, fontSize: 16)),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.settings),
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const Settings()));
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.dark_mode),
                      onPressed: widget.onThemeToggle,
                    ),
                  ],
                )
              ],
            ),

            const SizedBox(height: 30,),

            Row(children: [
                Expanded(child: SummaryCard(title: "Monthly Income", amount: "\$${totalIncome.toStringAsFixed(2)}", icon: Icons.account_balance, iconColor: Colors.grey,)),
                const SizedBox(width: 20,),
                Expanded(child: SummaryCard(title: "Total Expense", amount: "\$${totalOut.toStringAsFixed(2)}", icon: Icons.trending_down, iconColor: Colors.grey,)),
                const SizedBox(width: 20,),
                Expanded(child: SummaryCard(title: "Cash Flow", amount: "\$${cashFlow.toStringAsFixed(2)}", icon: Icons.trending_up, iconColor: Colors.green,)),
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
                      _populateLedgerLists()
                    ],
                  )
                )
              ]
            ),
          ],
        )
      ),
    );
  }

  Widget _populateLedgerLists()
  {
    DateTime currentMonth = DateTime(_startMonth.year, _startMonth.month, 1);
    DateTime endMonth = DateTime(_endMonth.year, _endMonth.month, 1);
    List<Widget> lists = [];
    while (!currentMonth.isAfter(endMonth))
    {
      lists.add(
        LedgerList(
          selectedMonth: currentMonth,
          fixedExpenses: [for(var e in allExpenses) if (e.tags.contains("Fixed") && e.date.year == currentMonth.year && e.date.month == currentMonth.month) e],
          variableExpenses: _generateVariableExpensesOfFilter(currentMonth),
          monthStat: (totalIncomeOfMonth(currentMonth),totalExpenseOfMonth(currentMonth), totalCashFlowOfMonth(currentMonth)),
          activeFilter: _activeFilter,
          onDelete: (String idToDelete) {
            setState(() => allExpenses.removeWhere((e) => e.id == idToDelete));
          },
        )
      );
      currentMonth = DateTime(currentMonth.year, currentMonth.month + 1, 1);
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      spacing: 20,
      children: lists,
    );
  }
}
