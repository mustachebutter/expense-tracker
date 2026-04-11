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
  final double _workIncome = 2908.31;

  List<Expense> allExpenses = [
    Expense(id: '1', label: 'Rent', fixedAmount: 1100, tags: ['Fixed', 'Housing'], date: DateTime(2026, 4, 11)),
    Expense(id: '2', label: 'Hydro', fixedAmount: 0, variableAmount: 61, tags: ['Variable', 'Utility'], date: DateTime(2026, 4, 11)),
    Expense(id: '3', label: 'Internet and Phone', fixedAmount: 163.85, tags: ['Fixed', 'Utility'], date: DateTime(2026, 4, 11)),
  ];

  final List<Expense> _fixedExpenseTemplates = [
    Expense(
      id: "template_rent",
      label: "Rent",
      fixedAmount: 1100.00,
      date: DateTime.now(),
      tags: ["FIXED", "HOUSING"],
    ),
    Expense(
      id: "template_internet",
      label: "Internet and Phone",
      fixedAmount: 163.85,
      date: DateTime.now(),
      tags: ["FIXED", "UTILITY"],
    ),
  ];

  List<Expense> getExpensesForMonth(DateTime month)
  {
    return allExpenses.where((e) =>
      e.date.month == month.month && e.date.year == month.year
    ).toList();
  }
  
  void _generateFixedExpensesForMonth(DateTime targetDatetime)
  {
    bool alreadyGenerated = allExpenses.any((e) => 
      e.date.year == targetDatetime.year &&
      e.date.month == targetDatetime.month &&
      e.tags.contains("FIXED")
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
  double get totalIncome => _workIncome * 2;
  double get totalOut => allExpenses.fold(0, (sum, item) => sum + item.total);
  double get cashFlow => totalIncome - totalOut;

  @override
  void initState() {
    super.initState();

    _generateFixedExpensesForMonth(DateTime(2026, 2));
    _generateFixedExpensesForMonth(DateTime(2026, 3));

    allExpenses.add(
      Expense(
        id: 'manual_1',
        label: 'Date Night',
        fixedAmount: 0.0,
        variableAmount: 120.50,
        date: DateTime(2026, 3, 14), // Happened mid-March
        tags: ['VARIABLE', 'LEISURE'],
      )
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text("Butters' Cash Flow Tracker"),
      ),
      // body: ListView.builder(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                _buildSummaryStat("INCOME", "\$${totalIncome.toStringAsFixed(2)}"),
                const SizedBox(width: 15,),
                _buildSummaryStat("EXPENSES", "\$${totalOut.toStringAsFixed(2)}"),
                const SizedBox(width: 15,),
                _buildSummaryStat("NET FLOW", "\$${cashFlow.toStringAsFixed(2)}"),
              ],
            ),
            
            const SizedBox(height: 20,),
            
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A24),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
              ),
              child: Column(
                children: <Widget>[
                  const Text("April 2026", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),),
                  const SizedBox(height: 8,),
                  Text(
                    "Net Cash Flow: +\$${cashFlow.toStringAsFixed(2)}",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.greenAccent)
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            
            Expanded(
              child: ListView(
                children: <Widget>[
                  _buildExpenseCard("Rent", 1100.00, ["FIXED", "HOUSING"], DateTime.now(), isLocked: true),
                  _buildExpenseCard("Rent", 1100.00, ["FIXED", "HOUSING"], DateTime.now(), isLocked: true),
                  _buildExpenseCard("Rent", 1100.00, ["FIXED", "HOUSING"], DateTime.now(), isLocked: false),
                ],
              ),
            ),
          ],
        ),
      ),
      //   itemCount: 12,
      //   itemBuilder: (context, index) {
      //     DateTime displayMonth = DateTime(2026, 4 - index);
      //     List<Expense> monthlyList = getExpensesForMonth(displayMonth);
      //     double monthlyTotal = monthlyList.fold(0, (sum, e) => sum + e.total);

      //     return ExpansionTile( 
      //       title: Text(DateFormat("MMMM yyyy").format(displayMonth)),
      //       subtitle: Text("Flow: \$${(_workIncome - monthlyTotal).toStringAsFixed(2)}"),
      //       children: monthlyList.map((expense) => Card(
      //         child: ListTile( 
      //           title: Text(expense.label, style: const TextStyle(fontWeight: FontWeight.bold),),
      //           subtitle: Column(
      //             crossAxisAlignment: CrossAxisAlignment.start,
      //             children: [
      //               Text(
      //                 "\$${expense.total.toStringAsFixed(2)}",
      //                 style: const TextStyle(color: Colors.black87, fontSize: 16)
      //               ),

      //               const SizedBox(height: 6,),
                    
      //               Wrap(
      //                 spacing: 4,
      //                 runSpacing: 4,
      //                 children: expense.tags.map((tag) => Chip(
      //                   label: Text(tag, style: const TextStyle(fontSize: 11)),
      //                   visualDensity: VisualDensity.compact,
      //                   padding: EdgeInsets.zero,
      //                   backgroundColor: Colors.blue.withOpacity(0.1),
      //                   side: BorderSide.none,
      //                 )).toList(),
      //               )
      //             ],
      //           ),
      //           trailing: Row(
      //             mainAxisSize: MainAxisSize.min,
      //             children: [
      //               expense.isEditing
      //                 ? SizedBox(
      //                   width: 80,
      //                   child: TextField(
      //                     decoration: const InputDecoration(hintText: "0.00"),
      //                     onSubmitted: (val) {
      //                       setState(() {
      //                         expense.variableAmount = double.tryParse(val) ?? 0.0;
      //                         expense.isEditing = false;
      //                       });
      //                     },
      //                   )
      //                 )
      //                 : IconButton(
      //                   icon: const Icon(Icons.edit_outlined),
      //                   onPressed: () => setState(() => expense.isEditing = true),
      //                 ),
      //             ],
      //           )
      //         )
      //       )).toList(),
      //     );
      //   },
      // ),
      floatingActionButton: FloatingActionButton(
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
        backgroundColor: const Color(0xFF448AFF),
        child: const Icon(Icons.add, color:Colors.white),
       ),
    );
  }

  Widget _buildSummaryStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, letterSpacing: 1.2)),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
      ],
    );
  }
  Widget _buildExpenseCard(String title, double amount, List<String> tags, DateTime date, {required bool isLocked}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding( 
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    if (isLocked) ...[
                      const SizedBox(width: 8,),
                      const Icon(Icons.lock_outline, size: 14, color: Colors.grey,),
                    ]
                  ],
                ),

                const SizedBox(height: 4,),

                Text("\$${amount.toStringAsFixed(2)}", style: const TextStyle(fontSize: 20, color: Colors.white),),
                
                const SizedBox(height: 8,),
                
                Text(date.toString()),
                
                const SizedBox(height: 8,),
                
                Row(
                  children: tags.map((tag) => Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Text(tag, style: const TextStyle(fontSize: 10, color:Colors.grey, letterSpacing: 1.0),),
                  )).toList(),
                ),
              ],
            ),

            IconButton(
              icon: const Icon(Icons.edit, color: Color(0xFF448AFF)),
              onPressed: () => print("hehe"),
            )
          ],
        )
      )
    );
  }
}
