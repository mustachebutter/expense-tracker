import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/main.dart';
import 'package:expense_tracker/providers/category_providers.dart';
import 'package:expense_tracker/widgets/forms/form_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Pass a category to edit it, or nothing to add a new one.
// Returns true if something was saved
Future<bool> showCategoryFormDialog(BuildContext context, {Category? category}) async
{
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => CategoryFormDialog(category: category),
  );
  return saved ?? false;
}

class CategoryFormDialog extends ConsumerStatefulWidget
{
  final Category? category;

  const CategoryFormDialog({super.key, this.category});

  @override
  ConsumerState<CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends ConsumerState<CategoryFormDialog>
{
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late TransactionType _type;
  late String _iconKey;
  late String _colorHex;

  bool get _isEditing => widget.category != null;

  @override
  void initState() {
    super.initState();
    final category = widget.category;
    _nameController = TextEditingController(text: category?.name ?? "");
    _type = category?.type ?? TransactionType.expense;
    _iconKey = category?.iconKey ?? AppConstants.iconKeys.first;
    _colorHex = category?.colorHex ?? AppConstants.categoryColorHexes.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save()
  {
    final actions = ref.read(categoryActionsProvider);
    final name = _nameController.text.trim();

    if (!_isEditing)
    {
      return actions.add(name: name, colorHex: _colorHex, iconKey: _iconKey, type: _type);
    }

    return actions.update(widget.category!.copyWith(
      name: name,
      colorHex: _colorHex,
      iconKey: _iconKey,
      type: _type,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return FormDialogScaffold(
      title: _isEditing ? "Edit Category" : "Add Category",
      formKey: _formKey,
      onSave: _save,
      children: [
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: "Category Name"),
          textCapitalization: TextCapitalization.sentences,
          autofocus: !_isEditing,
          validator: (value) => requiredText(value, "Name"),
        ),

        TransactionTypeSelector(value: _type, onChanged: (type) => setState(() => _type = type)),

        const Text("Icon"),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AppConstants.iconKeys.map((key) {
            return ChoiceChip(
              key: Key("icon_$key"),
              label: AppConstants.getIcon(key),
              showCheckmark: false,
              selected: _iconKey == key,
              onSelected: (_) => setState(() => _iconKey = key),
            );
          }).toList(),
        ),

        const Text("Color"),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: AppConstants.categoryColorHexes.map((hex) {
            final bool isSelected = _colorHex == hex;
            return InkWell(
              key: Key("color_$hex"),
              customBorder: const CircleBorder(),
              onTap: () => setState(() => _colorHex = hex),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppConstants.getColorFromHex(hex),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? colorScheme.onSurface : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
