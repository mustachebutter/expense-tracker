import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/main.dart';
import 'package:expense_tracker/providers/category_providers.dart';
import 'package:expense_tracker/providers/template_providers.dart';
import 'package:expense_tracker/widgets/forms/form_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Add or edit a fixed transaction (template). [initialType] pre-selects income or
// expense when adding, e.g. the ledger's "Add Fixed" button under Income.
// Returns true if something was saved
Future<bool> showTemplateFormDialog(
  BuildContext context, {
  Template? template,
  TransactionType initialType = TransactionType.expense,
}) async
{
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => TemplateFormDialog(template: template, initialType: initialType),
  );
  return saved ?? false;
}

class TemplateFormDialog extends ConsumerStatefulWidget
{
  final Template? template;
  final TransactionType initialType;

  const TemplateFormDialog({super.key, this.template, this.initialType = TransactionType.expense});

  @override
  ConsumerState<TemplateFormDialog> createState() => _TemplateFormDialogState();
}

class _TemplateFormDialogState extends ConsumerState<TemplateFormDialog>
{
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late final TextEditingController _billingDayController;
  late TransactionType _type;
  String? _categoryId;

  bool get _isEditing => widget.template != null;

  @override
  void initState() {
    super.initState();
    final template = widget.template;
    _nameController = TextEditingController(text: template?.name ?? "");
    _amountController = TextEditingController(text: template == null ? "" : amountText(template.amount));
    _billingDayController = TextEditingController(text: template?.billingDay.toString() ?? "");
    _type = template?.type ?? widget.initialType;
    _categoryId = template?.categoryId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _billingDayController.dispose();
    super.dispose();
  }

  Future<void> _save()
  {
    final actions = ref.read(templateActionsProvider);
    final name = _nameController.text.trim();
    final amount = double.parse(_amountController.text);
    final billingDay = int.parse(_billingDayController.text);

    if (!_isEditing)
    {
      return actions.add(name: name, amount: amount, billingDay: billingDay, type: _type, categoryId: _categoryId!);
    }

    return actions.update(widget.template!.copyWith(
      name: name,
      amount: amount,
      billingDay: billingDay,
      type: _type,
      categoryId: _categoryId!,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final categories = ref.watch(activeCategoriesProvider).value ?? [];

    // NOTE: If the template's category was deleted it's not in the list anymore, and a
    // dropdown can't show a value it doesn't have, so the user has to pick a new one
    final String? selectedCategoryId = categories.any((c) => c.id == _categoryId) ? _categoryId : null;

    return FormDialogScaffold(
      title: _isEditing ? "Edit Fixed Transaction" : "Add Fixed Transaction",
      formKey: _formKey,
      onSave: _save,
      children: [
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: "Name", hintText: "e.g. Rent, Salary, Netflix"),
          textCapitalization: TextCapitalization.sentences,
          autofocus: !_isEditing,
          validator: (value) => requiredText(value, "Name"),
        ),

        TextFormField(
          controller: _amountController,
          decoration: const InputDecoration(labelText: "Amount", prefixText: "\$ "),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: amountInputFormatters,
          validator: positiveAmount,
        ),

        TextFormField(
          controller: _billingDayController,
          decoration: const InputDecoration(
            labelText: "Day of the month",
            helperText: "Days after the month's last day (e.g. 31 in April) use the last day",
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
          validator: (value) {
            final day = int.tryParse(value ?? "");
            return (day == null || day < 1 || day > 31) ? "Enter a day from 1 to 31" : null;
          },
        ),

        TransactionTypeSelector(value: _type, onChanged: (type) => setState(() => _type = type)),

        if (categories.isEmpty)
          Text("Add a category first, every fixed transaction needs one.", style: TextStyle(color: colorScheme.error))
        else
          DropdownButtonFormField<String>(
            // NOTE: The key makes the dropdown start over if the selected value disappears
            key: ValueKey(selectedCategoryId),
            decoration: const InputDecoration(labelText: "Category"),
            dropdownColor: colorScheme.surface,
            initialValue: selectedCategoryId,
            items: categories.map((category) {
              return DropdownMenuItem<String>(
                value: category.id,
                child: Row(
                  children: [
                    AppConstants.getIcon(category.iconKey),
                    const SizedBox(width: 10),
                    Text(category.name, style: TextStyle(color: AppConstants.getColorFromHex(category.colorHex))),
                  ],
                ),
              );
            }).toList(),
            validator: (value) => value == null ? "Pick a category" : null,
            onChanged: (categoryId) {
              setState(() {
                _categoryId = categoryId;
                // Adding: follow the category's own type (Salary -> income), still changeable
                if (!_isEditing)
                {
                  _type = categories.firstWhere((c) => c.id == categoryId).type;
                }
              });
            },
          ),
      ],
    );
  }
}
