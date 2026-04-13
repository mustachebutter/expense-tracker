import 'package:flutter/material.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:intl/intl.dart';

class LedgerList extends StatelessWidget
{
  final DateTime selectedMonth;
  final List<Expense> expenses;
  final String activeFilter;
  final bool isInitiallyExpanded;
  final Function(String id) onDelete;

  const LedgerList({
    super.key,
    required this.selectedMonth,
    required this.expenses,
    required this.activeFilter,
    this.isInitiallyExpanded = false,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    Map<String, Map<String, Color>> filterConfigs = {
      "All": {
        "label_color": Colors.black,
        "font_color": Colors.white,
      },
      "Food": {
        "label_color": Colors.yellow,
        "font_color": Colors.black,
      },
      "Transport": {
        "label_color": Colors.green,
        "font_color": Colors.black,
      },
      "Entertainment": {
        "label_color": Colors.blue,
        "font_color": Colors.white,
      },
      "Shopping": {
        "label_color": Colors.orange,
        "font_color": Colors.black,
      },
      "Bills": {
        "label_color": Colors.deepPurple,
        "font_color": Colors.white,
      },
      "Health": {
        "label_color": Colors.red,
        "font_color": Colors.white,
      },
      "Other": {
        "label_color": Colors.grey,
        "font_color": Colors.black,
      },
    };
    final fixedExpenses = expenses.where((e) =>
      e.tags.map((t) => t.toLowerCase()).contains("fixed")
    ).toList();
    
    final variableExpenses = expenses.where((e) =>
      !e.tags.map((t) => t.toLowerCase()).contains("fixed")
    ).toList();


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
                title: Text(DateFormat("MMMM yyyy").format(selectedMonth), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                initiallyExpanded: isInitiallyExpanded,
                children: [
                  const Divider(height: 1,),
                  
                  // Fixed Expenses 
                  Container(
                    decoration: BoxDecoration(
                      color: Color(0xFFFAFAFA),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      children: [
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
                          ListView.separated( 
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
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: variableExpenses.length,
                    separatorBuilder: (context, index) => const Divider(height: 1,),
                    itemBuilder: (context, index) {
                      final expense = variableExpenses[index];
                      String tag = expense.tags.isNotEmpty ? expense.tags.first : "Other";
                      Color chipColor = filterConfigs[tag]?["label_color"] ?? Colors.grey;
                      Color fontColor = filterConfigs[tag]?["font_color"] ?? Colors.black;
                      
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
                                  style: new TextStyle(color: fontColor),
                                ),
                                backgroundColor: chipColor,
                                
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
                ],
              ),

            ],
          ),
        ),
      ],
    );
  }
}