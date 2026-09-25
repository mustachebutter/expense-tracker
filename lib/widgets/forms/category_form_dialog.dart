import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/main.dart';
import 'package:expense_tracker/providers/category_providers.dart';
import 'package:expense_tracker/widgets/forms/form_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
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
    _colorHex = category?.colorHex ?? AppConstants.defaultCategoryColorHex;
  }

  // Same picker as shift_lunar: a dialog with a color wheel, applied when you tap Select
  Future<void> _pickColor() async
  {
    Color pickedColor = AppConstants.getColorFromHex(_colorHex);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Pick a color"),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickedColor,
            onColorChanged: (color) => pickedColor = color,
            // NOTE: No transparency, the color is saved as 6 hex digits (RRGGBB)
            enableAlpha: false,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              setState(() => _colorHex = AppConstants.colorToHex(pickedColor));
              Navigator.pop(dialogContext);
            },
            child: const Text("Select"),
          ),
        ],
      ),
    );
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
    final Color color = AppConstants.getColorFromHex(_colorHex);
    // NOTE: The chip theme in main.dart colors a selected chip's text but not its icon,
    // so match it here or the selected icon is black on dark grey (white on light grey)
    final Color selectedIconColor = Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white;

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
              label: AppConstants.getIcon(key, color: _iconKey == key ? selectedIconColor : null),
              showCheckmark: false,
              selected: _iconKey == key,
              onSelected: (_) => setState(() => _iconKey = key),
            );
          }).toList(),
        ),

        ListTile(
          key: const Key("category_color"),
          contentPadding: EdgeInsets.zero,
          title: const Text("Color"),
          subtitle: Text("#$_colorHex"),
          trailing: CircleAvatar(
            backgroundColor: color,
            radius: 16,
            child: AppConstants.getIcon(_iconKey, color: AppConstants.onColor(color)),
          ),
          onTap: _pickColor,
        ),
      ],
    );
  }
}
