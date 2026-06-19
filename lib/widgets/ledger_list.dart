import 'package:expense_tracker/daos/transactions_dao.dart';
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/extensions/number.dart';
import 'package:expense_tracker/main.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class LedgerList extends StatelessWidget
{
  final DateTime selectedDateTime;
  final List<TransactionWithCategory> transactionsWithCategory;
  final String activeFilter;
  final bool isInitiallyExpanded;
  final Function(String id) onDelete;

  const LedgerList({
    super.key,
    required this.selectedDateTime,
    required this.transactionsWithCategory,
    required this.activeFilter,
    this.isInitiallyExpanded = false,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    double totalTransactionOfFilter() => transactionsWithCategory.sumBy((item) {
      if (activeFilter == "All" && item.expense.type == TransactionType.expense) return item.expense.amount;
      return item.category.name == activeFilter ? item.expense.amount : 0.0;
    });

    double totalTransaction() => transactionsWithCategory.sumBy((item) {
      return item.expense.type == TransactionType.expense ? item.expense.amount : 0.0;
    });
    double totalFixedTransaction() => transactionsWithCategory.sumBy((item) {
      return item.expense.templateId != null ? item.expense.amount : 0.0;
    });
    double totalIncome() => transactionsWithCategory.sumBy((item){
      return item.expense.type == TransactionType.income ? item.expense.amount : 0.0;
    });

    // NOTE: We filter the transaction here to render in the UI
    List<TransactionWithCategory> activeFilterTypeTransactions = transactionsWithCategory.where((t) {
      if (activeFilter == "All") return t.expense.type == TransactionType.expense;
      return t.category.name == activeFilter;
    }).toList();

    final List<TransactionWithCategory> fixedTransactions = transactionsWithCategory
      .where((t) => t.expense.templateId != null)
      .toList();
    
    final List<TransactionWithCategory> incomeTransactions = transactionsWithCategory
      .where((t) => t.expense.type == TransactionType.income)
      .toList();

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
                    Text(DateFormat("MMMM yyyy").format(selectedDateTime), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
                subtitle: LayoutBuilder(builder: (context, constraints) {
                  bool isMobile = constraints.maxWidth < 450;

                  return Padding(
                    padding: EdgeInsetsGeometry.only(top: 10),
                    child: Row(
                        mainAxisAlignment: isMobile ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
                        spacing: isMobile ? 5 : 10,
                        children: [
                          _buildStatBlock("Income: ", totalIncome(), variableTextColor, variableAmountTextColor, isMobile, textStyle),
                          _buildStatBlock("Transactions: ", totalTransaction(), variableTextColor, variableAmountTextColor, isMobile, textStyle),
                          _buildStatBlock("Cash Flow: ", (totalIncome() - totalTransaction()), Colors.green, Colors.green, isMobile, textStyle),
                        ],
                      )
                    );
                  }
                ),
                initiallyExpanded: isInitiallyExpanded,
                shape: Border.all(color: Colors.transparent, width: 0),
                tilePadding: EdgeInsets.all(20.0),
                children: [                  
                  // Fixed Transactions 
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
                                const Text("Income", style: TextStyle(fontWeight: FontWeight.w900),),
                                TextButton.icon( 
                                  onPressed: () {
                                    //TODO: Add fixed transactions handler
                                  },
                                  icon: const Icon(Icons.add,),
                                  label: const Text("Add Fixed",),
                                )
                              ],
                            )
                          ),

                          //TODO: Change this to income!
                          incomeTransactions.isEmpty
                            ? Padding(
                              padding: EdgeInsets.all(40.0),
                              child: Text(
                                "No income yet! ദ്ദി(•ᴗ•)"
                              )
                            )
                            : ListView.separated( 
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: incomeTransactions.length,
                              separatorBuilder: (context, index) => Divider(height: 1, color: colorScheme.outlineVariant),
                              itemBuilder: (context, index) {
                                final item = incomeTransactions[index];
                                return Container(
                                  color: colorScheme.surface,
                                  child: ListTile(
                                    title: Text(item.expense.name, style: textStyle.bodyMedium!.copyWith(fontWeight: FontWeight.w500)),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text("\$${item.expense.amount.toStringAsFixed(2)}", style: textStyle.labelLarge!.copyWith(fontWeight: FontWeight.bold),),
                                        const SizedBox(width: 16,),
                                        IconButton(
                                          onPressed: () => onDelete(item.expense.id),
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

                  // Variable Transactions
                  activeFilterTypeTransactions.isEmpty
                    ? Padding(
                      padding: EdgeInsets.all(40.0),
                      child: Text(
                        "No variable transactions! ᕙ( •̀ ᗜ •́ )ᕗ"
                      )
                    )
                    : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: activeFilterTypeTransactions.length,
                    separatorBuilder: (context, index) => const Divider(height: 1,),
                    itemBuilder: (context, index) {
                      final expense = activeFilterTypeTransactions[index].expense;
                      final category = activeFilterTypeTransactions[index].category;
                      
                      Color chipColor = AppConstants.getColorFromHex(category.colorHex ?? "9E9E9E");
                      
                      return ListTile(
                        title: Text(expense.name, style: textStyle.bodyLarge!.copyWith(fontWeight: FontWeight.w500)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Row(
                            children: [
                              Chip(
                                label: Text(
                                  category.name,
                                  style: TextStyle(color: chipColor),
                                ),
                                backgroundColor: chipColor.withValues(alpha: 0.1),
                                padding: EdgeInsets.all(0.0),
                              ),
                              const SizedBox(width: 5,),
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
                                  child: Text("\$${expense.amount.toStringAsFixed(2)}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),),
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
                              const Text("Total", style: TextStyle(fontWeight: FontWeight.bold),),
                              Text(
                                "\$${totalTransactionOfFilter().toStringAsFixed(2)}",
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