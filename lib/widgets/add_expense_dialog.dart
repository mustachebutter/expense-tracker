import 'package:drift/drift.dart' as drift;
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AddExpenseDialog extends StatefulWidget
{
  final Function(ExpensesCompanion) onExpenseAdded;
  final DateTime currentMonth;

  const AddExpenseDialog({super.key, required this.onExpenseAdded, required this.currentMonth});

  @override
  State<AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<AddExpenseDialog>
{
  String _name = "";
  double _amount = 0.0;

  String _selectedTag = "food";

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
          const Text("Add Expense", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          
          const SizedBox(height: 20,),
          
          // Label Input
          TextField(
            decoration: const InputDecoration(labelText: "Expense Name",),
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

          // Dropdown Menu
          DropdownButtonFormField<String>( 
            decoration: const InputDecoration(labelText: "Category",),
            dropdownColor: colorScheme.surface,
            icon: Icon(Icons.label),
            initialValue: _selectedTag,
            items: AppDatabase.instance.categoryList.map((var category) {
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
                // final newExpense = ExpensesCompanion(
                //   id: DateTime.now().toString(),
                //   label: _name,
                //   fixedAmount: 0,
                //   variableAmount: _amount,
                //   date: widget.currentMonth,
                //   tags: [_selectedTag],
                // );

                if (_name.isEmpty || _amount == 0) return;

                final newExpense = ExpensesCompanion(
                  id: drift.Value("exp_${DateTime.now().microsecondsSinceEpoch}"),
                  name: drift.Value(_name),
                  amount: drift.Value(_amount),
                  date: drift.Value(DateTime.now()),
                  categoryId: drift.Value(_selectedTag),
                  userId: drift.Value(AppConstants.testUserId), // TODO: Test only
                  isSynced: drift.Value(false),
                );

                print(newExpense);
                widget.onExpenseAdded(newExpense);
              },
              child: const Text("Add Expense", style: TextStyle(fontSize: 16)),
            ),
          )
        ],
      ),
    );
  }
}