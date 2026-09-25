import 'package:expense_tracker/database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Only digits with up to 2 decimals, same as the Add Transaction form
final List<TextInputFormatter> amountInputFormatters = [
  FilteringTextInputFormatter.allow(RegExp(r"^\d*\.?\d{0,2}")),
];

String? requiredText(String? value, String label)
{
  return (value == null || value.trim().isEmpty) ? "$label is required" : null;
}

String? positiveAmount(String? value)
{
  final amount = double.tryParse(value ?? "");
  return (amount == null || amount <= 0) ? "Enter an amount above 0" : null;
}

String? zeroOrMoreAmount(String? value)
{
  final amount = double.tryParse(value ?? "");
  return (amount == null || amount < 0) ? "Enter 0 or more" : null;
}

// Pre-fills an amount field when editing, e.g. 12.5 -> "12.50"
String amountText(double amount) => amount.toStringAsFixed(2);

// Asks before deleting. Returns true only if the user tapped Delete
Future<bool> confirmDelete(BuildContext context, {required String title, required String message}) async
{
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("Cancel")),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: TextButton.styleFrom(foregroundColor: Theme.of(dialogContext).colorScheme.error),
          child: const Text("Delete"),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

// Income / Expense toggle used by the category and fixed transaction forms
class TransactionTypeSelector extends StatelessWidget
{
  final TransactionType value;
  final ValueChanged<TransactionType> onChanged;

  const TransactionTypeSelector({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<TransactionType>(
      segments: const [
        ButtonSegment(value: TransactionType.expense, label: Text("Expense"), icon: Icon(Icons.trending_down)),
        ButtonSegment(value: TransactionType.income, label: Text("Income"), icon: Icon(Icons.trending_up)),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.single),
    );
  }
}

// The frame every add/edit dialog shares: title, scrollable form, Cancel and Save.
// Save validates the form, runs [onSave], and closes the dialog when it succeeds
class FormDialogScaffold extends StatefulWidget
{
  final String title;
  final GlobalKey<FormState> formKey;
  final List<Widget> children;
  final Future<void> Function() onSave;

  const FormDialogScaffold({
    super.key,
    required this.title,
    required this.formKey,
    required this.children,
    required this.onSave,
  });

  @override
  State<FormDialogScaffold> createState() => _FormDialogScaffoldState();
}

class _FormDialogScaffoldState extends State<FormDialogScaffold>
{
  bool _isSaving = false;

  Future<void> _save() async
  {
    if (!widget.formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try
    {
      await widget.onSave();
      if (mounted) Navigator.pop(context, true);
    }
    catch (e)
    {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't save: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Form(
          key: widget.formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: [
                // NOTE: Room for the first field's floating label, which sits above the field
                const SizedBox(height: 0),
                ...widget.children,
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context, false),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text("Save"),
        ),
      ],
    );
  }
}
