import 'package:expense_tracker/models/expense.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const ExpenseApp());
}

class ExpenseApp extends StatelessWidget {
  const ExpenseApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expense Tracker App',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      home: const Dashboard(),
      );
  }
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  final double _monthlyIncome = (2908.31 * 2);

  List<Expense> myExpenses = [
    Expense(id: '1', label: 'Rent', fixedAmount: 1100, tags: ['Fixed', 'Housing']),
    Expense(id: '2', label: 'Hydro', fixedAmount: 0, variableAmount: 61, tags: ['Variable', 'Utility']),
    Expense(id: '3', label: 'Internet and Phone', fixedAmount: 163.85, tags: ['Fixed', 'Utility']),
  ];

  double get totalOut => myExpenses.fold(0, (sum, item) => sum + item.total);
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
              itemCount: myExpenses.length,
              itemBuilder: (context, index) {
                final item = myExpenses[index];

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
