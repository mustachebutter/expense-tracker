import 'package:expense_tracker/models/expense.dart';
import 'package:flutter/material.dart';

class AddExpenseDialog extends StatefulWidget
{
  final Function(Expense) onExpenseAdded;
  const AddExpenseDialog({super.key, required this.onExpenseAdded});

  @override
  State<AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<AddExpenseDialog>
{
  String _label = "";
  double _amount = 0.0;

  final List<String> _categories = ["Food", "Housing", "Utility", "Leisure", "Misc"];
  String _selectedTag = "Misc";

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Add Manual Expense"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Label Input
          TextField(
            decoration: const InputDecoration(labelText: "Expense Name"),
            onChanged: (val) => _label = val,
          ),

          // Amount Input
          TextField(
            decoration: const InputDecoration(labelText: "Amount"),
            keyboardType: TextInputType.number,
            onChanged: (val) => _amount = double.tryParse(val) ?? 0.0,
          ),
          
          const SizedBox(height: 15,),

          // Dropdown Menu
          DropdownButtonFormField<String>( 
            decoration: const InputDecoration(labelText: "Category"),
            initialValue: _selectedTag,
            items: _categories.map((String category) {
              return DropdownMenuItem<String>(
                value: category,
                child: Text(category),
              );
            }).toList(),
            onChanged: (String? newValue) {
              setState(() {
                // _selectedTag = newValue!;
                _selectedTag = newValue ?? "Misc";
              });
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: () {
            final newExpense = Expense( 
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              label: _label,
              fixedAmount: 0.0,
              variableAmount: _amount,
              date: DateTime.now(),
              tags: [_selectedTag],
            );
            // whenever you need to access a variable defined in the top 
            // StatefulWidget class from inside the State class, 
            // you prefix it with `widget.`
            widget.onExpenseAdded(newExpense);

            Navigator.pop(context);
          },
          child: const Text("Add"),
        )
      ],
    );
  }
}