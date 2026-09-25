import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/investment_providers.dart';
import 'package:expense_tracker/widgets/forms/form_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Pass an investment to edit it, or nothing to add a new one. Returns true if something was saved
Future<bool> showInvestmentFormDialog(BuildContext context, {Investment? investment}) async
{
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => InvestmentFormDialog(investment: investment),
  );
  return saved ?? false;
}

class InvestmentFormDialog extends ConsumerStatefulWidget
{
  final Investment? investment;

  const InvestmentFormDialog({super.key, this.investment});

  @override
  ConsumerState<InvestmentFormDialog> createState() => _InvestmentFormDialogState();
}

class _InvestmentFormDialogState extends ConsumerState<InvestmentFormDialog>
{
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;

  bool get _isEditing => widget.investment != null;

  @override
  void initState() {
    super.initState();
    final investment = widget.investment;
    _nameController = TextEditingController(text: investment?.name ?? "");
    _amountController = TextEditingController(text: investment == null ? "" : amountText(investment.amount));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save()
  {
    final actions = ref.read(investmentActionsProvider);
    final name = _nameController.text.trim();
    final amount = double.parse(_amountController.text);

    if (!_isEditing) return actions.add(name: name, amount: amount);

    return actions.update(widget.investment!.copyWith(name: name, amount: amount));
  }

  @override
  Widget build(BuildContext context) {
    return FormDialogScaffold(
      title: _isEditing ? "Edit Investment" : "Add Investment",
      formKey: _formKey,
      onSave: _save,
      children: [
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: "Investment Name", hintText: "e.g. Index fund, Bitcoin"),
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
      ],
    );
  }
}
