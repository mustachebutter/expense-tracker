import 'package:expense_tracker/main.dart';
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
    double totalExpenseOfFilter() => variableExpenses.fold(0.0, (sum, item) => sum + item.fixedAmount + item.variableAmount);
    var (totalIncome, expense, cashFlow) = monthStat;

    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textStyle = Theme.of(context).textTheme;
    final Brightness brightness = Theme.of(context).brightness;
    final Color variableTextColor = brightness == Brightness.light ? Colors.grey : Colors.blueGrey;
    final Color variableAmountTextColor = brightness == Brightness.light ? Colors.black : Colors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[        
        Container(
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outline),
          ),
          child: Column(
            children: <Widget>[
              ExpansionTile(
                title: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(DateFormat("MMMM yyyy").format(selectedMonth), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
                subtitle: LayoutBuilder(builder: (context, constraints) {
                  bool isMobile = constraints.maxWidth < 450;

                  return Padding(
                    padding: EdgeInsetsGeometry.only(top: 10),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildStatBlock("Income: ", totalIncome, variableTextColor, variableAmountTextColor, isMobile, textStyle),
                          _buildStatBlock("Expenses: ", totalIncome, variableTextColor, variableAmountTextColor, isMobile, textStyle),
                          _buildStatBlock("Cash Flow: ", totalIncome, Colors.green, Colors.green, isMobile, textStyle),
                        ],
                      )
                    );
                  }
                ),
                initiallyExpanded: isInitiallyExpanded,
                shape: Border.all(color: Colors.transparent, width: 0),
                tilePadding: EdgeInsets.all(20.0),
                children: [                  
                  // Fixed Expenses 
                  Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      border: Border(
                        bottom: BorderSide(color: colorScheme.outline, width: 1.0),
                      ),
                    ),
                    child: Column(
                      children: [
                          Divider(height: 1, color: colorScheme.outlineVariant),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("Fixed Expenses", style: TextStyle(fontWeight: FontWeight.w900),),
                                TextButton.icon( 
                                  onPressed: () {
                                    //TODO: Add fixed expenses handler
                                  },
                                  icon: const Icon(Icons.add,),
                                  label: const Text("Add Fixed",),
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
                              separatorBuilder: (context, index) => Divider(height: 1, color: colorScheme.outlineVariant),
                              itemBuilder: (context, index) {
                                final expense = fixedExpenses[index];
                                return Container(
                                  color: colorScheme.surface,
                                  child: ListTile(
                                    title: Text(expense.label, style: textStyle.bodyMedium!.copyWith(fontWeight: FontWeight.w500)),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text("\$${expense.total.toStringAsFixed(2)}", style: textStyle.labelLarge!.copyWith(fontWeight: FontWeight.bold),),
                                        const SizedBox(width: 16,),
                                        IconButton(
                                          onPressed: () => onDelete(expense.id),
                                          icon: const Icon(Icons.delete),
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
                      Color chipColor = AppColors.categories[tag]?["color"] as Color;
                      
                      return ListTile(
                        title: Text(expense.label, style: textStyle.bodyLarge!.copyWith(fontWeight: FontWeight.w500)),
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
                        trailing: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 150),
                          child: Row( 
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Text("\$${expense.total.toStringAsFixed(2)}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),),
                                ),
                              ),
                              IconButton( 
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => onDelete(expense.id),
                              )
                            ],
                          )
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
                              const Text("Total Expense", style: TextStyle(fontWeight: FontWeight.bold),),
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

  Widget _buildStatBlock(String label, double amount, Color labelColor, Color amountColor, bool isMobile, TextTheme textStyle)
  {
    if (isMobile)
    {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: textStyle.bodySmall!.copyWith(color: labelColor,),),
          const SizedBox(height: 2,),
          Text("\$${amount.toStringAsFixed(2)}", style: textStyle.bodySmall!.copyWith(color: amountColor, fontWeight: FontWeight.bold),)
        ],
      );
    }
    else
    {
      return Text.rich(
        TextSpan(
          text: label,
          style: textStyle.bodySmall!.copyWith(color: labelColor,),
          children: [
            TextSpan(
              text: "\$${amount.toStringAsFixed(2)}",
              style: textStyle.bodySmall!.copyWith(color: amountColor, fontWeight: FontWeight.bold),
            )
          ]
        )
      );
    }
  }
}