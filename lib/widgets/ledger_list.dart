import 'package:flutter/material.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:intl/intl.dart';

class LedgerList extends StatelessWidget
{
  final DateTime selectedMonth;
  final List<Expense> fixedExpenses;
  final List<Expense> variableExpenses;
  final (double, double, double) monthStat;
  final String activeFilter;
  final bool isInitiallyExpanded;
  final Function(String id) onDelete;

  const LedgerList({
    super.key,
    required this.selectedMonth,
    required this.fixedExpenses,
    required this.variableExpenses,
    required this.monthStat,
    required this.activeFilter,
    this.isInitiallyExpanded = false,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    Map<String, Map<String, Color>> filterConfigs = {
      "All": {
        "label_color": Colors.black,
      },
      "Food": {
        "label_color": Colors.yellow,
      },
      "Transport": {
        "label_color": Colors.green,
      },
      "Entertainment": {
        "label_color": Colors.blue,
      },
      "Shopping": {
        "label_color": Colors.orange,
      },
      "Utility": {
        "label_color": Colors.deepPurple,
      },
      "Health": {
        "label_color": Colors.red,
      },
      "Other": {
        "label_color": Colors.grey,
      },
    };

    double totalExpenseOfFilter() => variableExpenses.fold(0.0, (sum, item) => sum + item.fixedAmount + item.variableAmount);
    var (totalIncome, expense, cashFlow) = monthStat;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[        
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            children: <Widget>[
              ExpansionTile(
                title: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(DateFormat("MMMM yyyy").format(selectedMonth), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    Wrap(
                      spacing: 20,
                      children: [
                        Text.rich(
                          TextSpan(
                            text: "Income: ",
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                            children: [
                              TextSpan(
                                text: "\$${totalIncome.toStringAsFixed(2)}",
                                style: const TextStyle(color: Colors.black,  fontSize: 12, fontWeight: FontWeight.bold),
                              )
                            ]
                          )
                        ),
                        Text.rich(
                          TextSpan(
                            text: "Expenses: ",
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                            children: [
                              TextSpan(
                                text: "\$${expense.toStringAsFixed(2)}",
                                style: const TextStyle(color: Colors.black,  fontSize: 12, fontWeight: FontWeight.bold),
                              )
                            ]
                          )
                        ),
                        Text.rich(
                          TextSpan(
                            text: "Cash Flow: ",
                            style: const TextStyle(color: Colors.green, fontSize: 12),
                            children: [
                              TextSpan(
                                text: "\$${cashFlow.toStringAsFixed(2)}",
                                style: const TextStyle(color: Colors.green,  fontSize: 12, fontWeight: FontWeight.bold),
                              )
                            ]
                          )
                        ),
                      ],
                    )
                  ],
                ),
                initiallyExpanded: isInitiallyExpanded,
                shape: Border.all(color: Colors.transparent, width: 0),
                tilePadding: EdgeInsets.all(20.0),
                children: [                  
                  // Fixed Expenses 
                  Container(
                    decoration: BoxDecoration(
                      color: Color(0xFFFAFAFA),
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade300, width: 1.0),
                      ),
                    ),
                    child: Column(
                      children: [
                          const Divider(height: 1, color: Color(0xFFF0F0F0)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("Fixed Expenses", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),),
                                TextButton.icon( 
                                  onPressed: () {
                                    //TODO: Add fixed expenses handler
                                  },
                                  icon: const Icon(Icons.add, size: 16, color: Colors.black54),
                                  label: const Text("Add Fixed", style: TextStyle(color: Colors.black54),),
                                )
                              ],
                            )
                          ),
                          fixedExpenses.isEmpty
                            ? Padding(
                              padding: EdgeInsets.all(40.0),
                              child: Text(
                                "No fixed expenses! ദ്ദി(•ᴗ•)"
                              )
                            )
                            : ListView.separated( 
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: fixedExpenses.length,
                              separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF0F0F0)),
                              itemBuilder: (context, index) {
                                final expense = fixedExpenses[index];
                                return Container(
                                  color: Color(0xFFFAFAFA),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                                    title: Text(expense.label, style: const TextStyle(fontSize: 13)),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text("\$${expense.total.toStringAsFixed(2)}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),),
                                        const SizedBox(width: 16,),
                                        IconButton(
                                          onPressed: () => onDelete(expense.id),
                                          icon: const Icon(Icons.delete, color: Colors.grey, size: 20,),
                                        )
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                      ]
                    )
                  ),

                  // Variable Expenses
                  variableExpenses.isEmpty
                    ? Padding(
                      padding: EdgeInsets.all(40.0),
                      child: Text(
                        "No variable expenses! ᕙ( •̀ ᗜ •́ )ᕗ"
                      )
                    )
                    : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: variableExpenses.length,
                    separatorBuilder: (context, index) => const Divider(height: 1,),
                    itemBuilder: (context, index) {
                      final expense = variableExpenses[index];
                      String tag = expense.tags.isNotEmpty ? expense.tags.first : "Other";
                      Color chipColor = filterConfigs[tag]?["label_color"] ?? Colors.grey;
                      
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        title: Text(expense.label, style: const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Row(
                            children: [
                              Chip(
                                label: Text(
                                  tag,
                                  style: TextStyle(color: chipColor),
                                ),
                                backgroundColor: chipColor.withValues(alpha: 0.1),
                                padding: EdgeInsets.all(0.0),
                              ),
                              const SizedBox(width: 10,),
                              Text(DateFormat("MMM d").format(expense.date), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          )
                        ),
                        trailing: Row( 
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("\$${expense.total.toStringAsFixed(2)}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),),
                            const SizedBox(width: 16),
                            IconButton( 
                              icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                              onPressed: () => onDelete(expense.id),
                            )
                          ],
                        )
                      );
                    },
                  ),
                  Container(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Total Expense", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),),
                              Text(
                                "\$${totalExpenseOfFilter().toStringAsFixed(2)}",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              )
                            ],
                          )
                        ),
                      ],
                    )
                  ),
                ],
              ),

            ],
          ),
        ),
      ],
    );
  }
}