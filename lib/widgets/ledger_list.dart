import 'package:flutter/material.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:intl/intl.dart';

class LedgerList extends StatelessWidget
{
  final DateTime selectedMonth;
  final List<Expense> expenses;
  final String activeFilter;
  final Function(String id) onDelete;
  final Function(String newFilter) onFilterChanged;

  const LedgerList({
    super.key,
    required this.selectedMonth,
    required this.expenses,
    required this.activeFilter,
    required this.onDelete,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final List<String> _filters = ["All", "Food", "Transport", "Entertainment", "Shopping", "Bills", "Health", "Other"];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          // !!!!PLACEHOLDER!!!!
          children: _filters.map((filterName) {
            bool isSelected = activeFilter == filterName;

            return ChoiceChip(
              label: Text(filterName),
              selected: isSelected,
              selectedColor: Colors.black,
              labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black),
              onSelected: (bool userClickedIt) {
                onFilterChanged(filterName);
              },
            );
          }).toList(),
        ),
      
        const SizedBox(height: 20,),
        
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(DateFormat("MMMM yyyy").format(selectedMonth), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const Icon(Icons.expand_less),
                  ],
                ),
              ),

              Divider(height: 1,),
              
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: expenses.length,
                separatorBuilder: (context, index) => const Divider(height: 1,),
                itemBuilder: (context, index) {
                  final expense = expenses[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    title: Text(expense.label, style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text("${expense.tags.first} - ${DateFormat("MMM d").format(expense.date)}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ),
                    trailing: Row( 
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("\$${expense.total.toStringAsFixed(2)}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),),
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
        ),
      ],
    );
  }
}