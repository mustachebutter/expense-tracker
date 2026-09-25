import 'package:drift/drift.dart' as drift;
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/main.dart';
import 'package:expense_tracker/providers/category_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AddTransactionDialog extends ConsumerStatefulWidget
{
  final Function(TransactionsCompanion) onTransactionAdded;
  final DateTime currentMonth;

  const AddTransactionDialog({super.key, required this.onTransactionAdded, required this.currentMonth});

  @override
  ConsumerState<AddTransactionDialog> createState() => _AddTransactionDialogState();
}

class _AddTransactionDialogState extends ConsumerState<AddTransactionDialog>
{
  String _name = "";
  double _amount = 0.0;

  String? _selectedTag;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final categoriesAsync = ref.watch(activeCategoriesProvider);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Add Transaction", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          
          const SizedBox(height: 20,),
          
          // Label Input
          TextField(
            decoration: const InputDecoration(labelText: "Transaction Name",),
            onChanged: (val) => _name = val,
          ),

          const SizedBox(height: 15,),

          // Amount Input
          TextField(
            decoration: const InputDecoration(labelText: "Amount", prefixText: "\$ ",),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r"^\d*\.?\d{0,2}")),
            ],
            onChanged: (val) => _amount = double.tryParse(val) ?? 0.0,
          ),
          
          const SizedBox(height: 15,),

          categoriesAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (error, stackTrace) => Text("Failed to load categories: $error"),
            data: (categories) {
              if (categories.isEmpty) return Text("Please add categories in the settings!");

              final firstCategoryId = categories.first.id;
              final displayValue = _selectedTag ?? firstCategoryId;

              return Column(
                children: <Widget>[

                  DropdownButtonFormField<String>( 
                    decoration: const InputDecoration(labelText: "Category",),
                    dropdownColor: colorScheme.surface,
                    icon: Icon(Icons.label),
                    initialValue: displayValue,
                    items: categories.map((var category) {
                      print(category);
                      return DropdownMenuItem<String>(
                        value: category.id,
                        child: Row(
                          children: [
                            AppConstants.getIcon(category.iconKey),
                            SizedBox(width: 10,),
                            Text(
                              category.name,
                              style: TextStyle(
                                color: AppConstants.getColorFromHex(category.colorHex),
                              )
                            ),
                          ],
                        ),
                      );
                    }).toList(),

                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedTag = newValue!;
                      });
                    },
                  ),
                  
                  const SizedBox(height: 24,),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_name.isEmpty || _amount == 0) return;

                        final newTransaction = TransactionsCompanion(
                          name: drift.Value(_name),
                          amount: drift.Value(_amount),
                          date: drift.Value(DateTime.now()),
                          type: drift.Value(TransactionType.expense),
                          categoryId: drift.Value(_selectedTag ?? firstCategoryId),
                          isSynced: drift.Value(false),
                        );

                        print(newTransaction);
                        widget.onTransactionAdded(newTransaction);
                      },
                      child: const Text("Add Transaction", style: TextStyle(fontSize: 16)),
                    ),
                  )
                ],
              );
            }
          ),
          // Dropdown Menu

        ],
      ),
    );
  }
}