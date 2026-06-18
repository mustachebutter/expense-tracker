import 'package:drift/drift.dart' as drift;
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AddTransactionDialog extends StatefulWidget
{
  final Function(TransactionsCompanion) onTransactionAdded;
  final DateTime currentMonth;

  const AddTransactionDialog({super.key, required this.onTransactionAdded, required this.currentMonth});

  @override
  State<AddTransactionDialog> createState() => _AddTransactionDialogState();
}

class _AddTransactionDialogState extends State<AddTransactionDialog>
{
  String _name = "";
  double _amount = 0.0;

  String? _selectedTag;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
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

          StreamBuilder<List<Category>>(
            stream: AppDatabase.instance.categoriesDao.watchAllActiveCategories(),
            builder: (context, snapshot) {

              if (!snapshot.hasData) return const CircularProgressIndicator();
              
              final categories = snapshot.data ?? [];
              
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
                          userId: drift.Value(AppConstants.testUserId), // TODO: Test only
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