import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/savings_goal_providers.dart';
import 'package:expense_tracker/widgets/forms/form_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Pass a goal to edit it, or nothing to add a new one. Returns true if something was saved
Future<bool> showSavingsGoalFormDialog(BuildContext context, {SavingsGoal? goal}) async
{
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => SavingsGoalFormDialog(goal: goal),
  );
  return saved ?? false;
}

class SavingsGoalFormDialog extends ConsumerStatefulWidget
{
  final SavingsGoal? goal;

  const SavingsGoalFormDialog({super.key, this.goal});

  @override
  ConsumerState<SavingsGoalFormDialog> createState() => _SavingsGoalFormDialogState();
}

class _SavingsGoalFormDialogState extends ConsumerState<SavingsGoalFormDialog>
{
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _targetController;
  late final TextEditingController _savedController;

  bool get _isEditing => widget.goal != null;

  @override
  void initState() {
    super.initState();
    final goal = widget.goal;
    _nameController = TextEditingController(text: goal?.name ?? "");
    _targetController = TextEditingController(text: goal == null ? "" : amountText(goal.targetAmount));
    _savedController = TextEditingController(text: amountText(goal?.currentSavedAmount ?? 0));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    _savedController.dispose();
    super.dispose();
  }

  Future<void> _save()
  {
    final actions = ref.read(savingsGoalActionsProvider);
    final name = _nameController.text.trim();
    final target = double.parse(_targetController.text);
    final saved = double.parse(_savedController.text);

    if (!_isEditing)
    {
      return actions.add(name: name, targetAmount: target, currentSavedAmount: saved);
    }

    return actions.update(widget.goal!.copyWith(name: name, targetAmount: target, currentSavedAmount: saved));
  }

  @override
  Widget build(BuildContext context) {
    return FormDialogScaffold(
      title: _isEditing ? "Edit Savings Goal" : "Add Savings Goal",
      formKey: _formKey,
      onSave: _save,
      children: [
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: "Goal Name", hintText: "e.g. Holiday, Emergency fund"),
          textCapitalization: TextCapitalization.sentences,
          autofocus: !_isEditing,
          validator: (value) => requiredText(value, "Name"),
        ),
        TextFormField(
          controller: _targetController,
          decoration: const InputDecoration(labelText: "Target Amount", prefixText: "\$ "),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: amountInputFormatters,
          validator: positiveAmount,
        ),
        TextFormField(
          controller: _savedController,
          decoration: const InputDecoration(labelText: "Saved So Far", prefixText: "\$ "),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: amountInputFormatters,
          validator: zeroOrMoreAmount,
        ),
      ],
    );
  }
}
