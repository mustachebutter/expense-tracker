import 'package:expense_tracker/main.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:flutter/material.dart';

class AddExpenseDialog extends StatefulWidget
{
  final Function(Expense) onExpenseAdded;
  final DateTime currentMonth;

  const AddExpenseDialog({super.key, required this.onExpenseAdded, required this.currentMonth});

  @override
  State<AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<AddExpenseDialog>
{
  String _label = "";
  double _amount = 0.0;

  String _selectedTag = "Food";

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
            onChanged: (val) => _label = val,
          ),

          const SizedBox(height: 15,),

          // Amount Input
          TextField(
            decoration: const InputDecoration(labelText: "Amount", prefixText: "\$ ",),
            keyboardType: TextInputType.number,
            onChanged: (val) => _amount = double.tryParse(val) ?? 0.0,
          ),
          
          const SizedBox(height: 15,),

          // Dropdown Menu
          DropdownButtonFormField<String>( 
            decoration: const InputDecoration(labelText: "Category",),
            dropdownColor: colorScheme.surface,
            icon: Icon(Icons.label),
            initialValue: _selectedTag,
            items: AppColors.categories.entries.map((var category) {
              return DropdownMenuItem<String>(
                value: category.key,
                child: Row(
                  children: [
                    category.value["icon"] as Icon,
                    SizedBox(width: 10,),
                    Text(
                      category.key,
                      style: TextStyle(
                        color: category.value["color"] as Color,
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
              onPressed: (){
                final newExpense = Expense(
                  id: DateTime.now().toString(),
                  label: _label,
                  fixedAmount: 0,
                  variableAmount: _amount,
                  date: widget.currentMonth,
                  tags: [_selectedTag],
                );

                if (newExpense.label.isEmpty || newExpense.variableAmount == 0) return;
                  
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