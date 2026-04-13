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

  final List<String> _categories = ["Food", "Transport", "Entertainment", "Shopping", "Utility", "Health", "Other"];
  String _selectedTag = "Food";

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Add Expense", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          
          const SizedBox(height: 20,),
          
          // Label Input
          TextField(
            decoration: const InputDecoration(labelText: "Expense Name", border: OutlineInputBorder()),
            onChanged: (val) => _label = val,
          ),

          const SizedBox(height: 15,),

          // Amount Input
          TextField(
            decoration: const InputDecoration(labelText: "Amount", prefixText: "\$ ", border: OutlineInputBorder()),
            keyboardType: TextInputType.number,
            onChanged: (val) => _amount = double.tryParse(val) ?? 0.0,
          ),
          
          const SizedBox(height: 15,),

          // Dropdown Menu
          DropdownButtonFormField<String>( 
            decoration: const InputDecoration(labelText: "Category", border: OutlineInputBorder()),
            initialValue: _selectedTag,
            items: _categories.map((String category) {
              return DropdownMenuItem<String>(
                value: category,
                child: Text(category),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2B6CB0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              onPressed: (){
                final newExpense = Expense(
                  id: DateTime.now().toString(),
                  label: _label,
                  fixedAmount: 0,
                  variableAmount: _amount,
                  date: widget.currentMonth,
                  tags: [_selectedTag],
                );

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