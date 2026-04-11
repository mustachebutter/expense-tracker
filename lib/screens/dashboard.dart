import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/widgets/add_expense_dialog.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  final double _monthlyIncome = (2908.31 * 2);

  List<Expense> allExpenses = [
    Expense(id: '1', label: 'Rent', fixedAmount: 1100, tags: ['Fixed', 'Housing'], date: DateTime(2026, 4, 11)),
    Expense(id: '2', label: 'Hydro', fixedAmount: 0, variableAmount: 61, tags: ['Variable', 'Utility'], date: DateTime(2026, 4, 11)),
    Expense(id: '3', label: 'Internet and Phone', fixedAmount: 163.85, tags: ['Fixed', 'Utility'], date: DateTime(2026, 4, 11)),
  ];

  List<Expense> getExpensesForMonth(DateTime month)
  {
    return allExpenses.where((e) =>
      e.date.month == month.month && e.date.year == month.year
    ).toList();
  }

  double get totalOut => allExpenses.fold(0, (sum, item) => sum + item.total);
  double get cashFlow => _monthlyIncome - totalOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text("Butters' Cash Flow Tracker"),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            color: cashFlow >= 0 ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statTile("Income", "\$${_monthlyIncome.toStringAsFixed(2)}"),
                _statTile("Expenses", "\$${totalOut.toStringAsFixed(2)}"),
                _statTile("Cash Flow", "\$${cashFlow.toStringAsFixed(2)}", isBold: true),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: allExpenses.length,
              itemBuilder: (context, index) {
                final item = allExpenses[index];

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                  child: ListTile(
                    title: Text(item.label),
                    subtitle: Wrap(
                      spacing: 5,
                      children: item.tags.map((t) => Chip(label: Text(t), visualDensity: VisualDensity.compact,)).toList()
                    ),
                    trailing: SizedBox(
                      width: 100,
                      child: TextFormField(
                        initialValue: item.variableAmount.toString(),
                        decoration: const InputDecoration(prefixText: '\$'),
                        keyboardType: TextInputType.number,
                        onChanged: (val) {
                          setState(() {
                            item.variableAmount = double.tryParse(val) ?? 0;
                          });
                        },
                      ),
                    )
                  ),
                );
              }
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) {
              return AddExpenseDialog(
                onExpenseAdded: (Expense newlyCreatedExpense) {
                  setState(() {
                    allExpenses.add(newlyCreatedExpense);
                  });
                },
              );
            },
          );
        },
       ),
    );
  }

  Widget _statTile(String label, String value, {bool isBold = false}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: isBold ? FontWeight.bold : FontWeight.normal),)
      ]
    );
  }
}
