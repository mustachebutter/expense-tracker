import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/main.dart';
import 'package:expense_tracker/providers/category_providers.dart';
import 'package:expense_tracker/providers/receipt_providers.dart';
import 'package:expense_tracker/providers/receipt_scan_providers.dart';
import 'package:expense_tracker/widgets/forms/form_helpers.dart';
import 'package:expense_tracker/widgets/receipts/receipt_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// Shows a receipt's photo and lets the user fill in or fix its details.
// Returns true if something was saved or the receipt was deleted
Future<bool> showReceiptFormDialog(BuildContext context, Receipt receipt) async
{
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => ReceiptFormDialog(receipt: receipt),
  );
  return changed ?? false;
}

class ReceiptFormDialog extends ConsumerStatefulWidget
{
  final Receipt receipt;

  const ReceiptFormDialog({super.key, required this.receipt});

  @override
  ConsumerState<ReceiptFormDialog> createState() => _ReceiptFormDialogState();
}

class _ReceiptFormDialogState extends ConsumerState<ReceiptFormDialog>
{
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _merchantController;
  late final TextEditingController _totalController;
  DateTime? _date;
  String? _categoryId;
  late bool _isFavorite;
  bool _addAsTransaction = false;
  bool _isScanning = false;

  // NOTE: The receipt as it is now. Scanning changes it while the dialog is open, and saving
  // has to build on that copy (otherwise it would put the scan status back to "waiting")
  late Receipt _current;

  bool get _isAlreadyTransaction => _current.transactionId != null;

  @override
  void initState() {
    super.initState();
    final receipt = widget.receipt;
    _current = receipt;
    _merchantController = TextEditingController(text: receipt.merchant ?? "");
    _totalController = TextEditingController(text: receipt.total == null ? "" : amountText(receipt.total!));
    _date = receipt.date;
    _categoryId = receipt.categoryId;
    _isFavorite = receipt.isFavorite;

    // A new photo on a device that can read it: read it straight away
    if (receipt.scanStatus == ReceiptScanStatus.waiting && ref.read(canScanHereProvider))
    {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scan();
      });
    }
  }

  Future<void> _scan() async
  {
    setState(() => _isScanning = true);
    final scanned = await ref.read(receiptScanServiceProvider).scan(_current);
    if (!mounted) return;

    setState(() {
      _isScanning = false;
      _current = scanned;
      // Only fill what's still empty, the user may have started typing while it was reading
      if (_merchantController.text.isEmpty && scanned.merchant != null) _merchantController.text = scanned.merchant!;
      if (_totalController.text.isEmpty && scanned.total != null) _totalController.text = amountText(scanned.total!);
      _date ??= scanned.date;
      _categoryId ??= scanned.categoryId;
    });
  }

  // The line under the photo that says whether the receipt has been read
  Widget? _scanStatus(BuildContext context)
  {
    final bool canScanHere = ref.watch(canScanHereProvider);
    final TextStyle? style = Theme.of(context).textTheme.bodyMedium;

    Widget row(Widget icon, String text, {String? buttonLabel})
    {
      return Row(
        key: const Key("scan_status"),
        spacing: 10,
        children: [
          icon,
          Expanded(child: Text(text, style: style)),
          if (buttonLabel != null) TextButton(onPressed: _scan, child: Text(buttonLabel)),
        ],
      );
    }

    if (_isScanning)
    {
      return row(
        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        "Reading the receipt...",
      );
    }

    return switch (_current.scanStatus) {
      ReceiptScanStatus.waiting when canScanHere =>
        row(const Icon(Icons.document_scanner_outlined), "Not read yet", buttonLabel: "Scan now"),
      ReceiptScanStatus.waiting =>
        row(
          const Icon(Icons.phone_android),
          "Waiting for your phone to read this. Open the app on your phone and it's scanned there. "
          "You can also fill it in yourself.",
        ),
      ReceiptScanStatus.scanned =>
        row(const Icon(Icons.auto_awesome_outlined), "Filled in from the photo. Check it looks right."),
      ReceiptScanStatus.failed =>
        row(
          const Icon(Icons.error_outline),
          "Couldn't read this receipt. Fill it in yourself.",
          buttonLabel: canScanHere ? "Try again" : null,
        ),
      ReceiptScanStatus.notScanned => null,
    };
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _totalController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async
  {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async
  {
    final actions = ref.read(receiptActionsProvider);
    final merchant = _merchantController.text.trim();

    // NOTE: Each step returns the receipt as saved, and the next step builds on that copy
    var saved = await actions.update(_current.copyWith(
      merchant: Value(merchant.isEmpty ? null : merchant),
      total: Value(double.tryParse(_totalController.text)),
      date: Value(_date),
      categoryId: Value(_categoryId),
    ));

    if (_isFavorite != _current.isFavorite)
    {
      saved = await actions.setFavorite(saved, _isFavorite);
    }

    if (_addAsTransaction)
    {
      final categories = ref.read(activeCategoriesProvider).value ?? [];
      await actions.addAsTransaction(saved, categories.firstWhere((c) => c.id == _categoryId));
    }
  }

  Future<void> _delete() async
  {
    final confirmed = await confirmDelete(
      context,
      title: "Delete receipt?",
      message: "The receipt and its photo will be deleted. A transaction made from it stays.",
    );
    if (!confirmed) return;

    await ref.read(receiptActionsProvider).delete(widget.receipt.id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final categories = ref.watch(activeCategoriesProvider).value ?? [];
    final Widget? scanStatus = _scanStatus(context);
    final String? selectedCategoryId = categories.any((c) => c.id == _categoryId) ? _categoryId : null;

    return FormDialogScaffold(
      title: "Receipt",
      formKey: _formKey,
      onSave: _save,
      children: [
        // NOTE: Pinch or scroll to zoom in on small print
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 260,
            child: InteractiveViewer(
              maxScale: 5,
              child: ReceiptImage(receiptId: widget.receipt.id, fit: BoxFit.contain),
            ),
          ),
        ),

        ?scanStatus,

        TextFormField(
          controller: _merchantController,
          decoration: const InputDecoration(labelText: "Shop", hintText: "Where was this?"),
          textCapitalization: TextCapitalization.words,
        ),

        TextFormField(
          controller: _totalController,
          decoration: const InputDecoration(labelText: "Total", prefixText: "\$ "),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: amountInputFormatters,
          validator: (value) {
            if ((value ?? "").isEmpty) return _addAsTransaction ? "A transaction needs a total" : null;
            return positiveAmount(value);
          },
        ),

        ListTile(
          key: const Key("receipt_date"),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: Text(_date == null ? "Date unknown" : DateFormat("EEE, MMM d, yyyy").format(_date!)),
          subtitle: const Text("Tap to pick the date on the receipt"),
          onTap: _pickDate,
        ),

        DropdownButtonFormField<String>(
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
                  Text(category.name),
                ],
              ),
            );
          }).toList(),
          validator: (value) => _addAsTransaction && value == null ? "A transaction needs a category" : null,
          onChanged: (categoryId) => setState(() => _categoryId = categoryId),
        ),

        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: Icon(_isFavorite ? Icons.star : Icons.star_border),
          title: const Text("Pin to board"),
          value: _isFavorite,
          onChanged: (value) => setState(() => _isFavorite = value),
        ),

        if (_isAlreadyTransaction)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.check_circle_outline),
            title: Text("Added as a transaction"),
          )
        else
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Also add as a transaction"),
            subtitle: const Text("Uses the shop, total, date and category above"),
            value: _addAsTransaction,
            onChanged: (value) => setState(() => _addAsTransaction = value ?? false),
          ),

        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _delete,
            style: TextButton.styleFrom(foregroundColor: colorScheme.error),
            icon: const Icon(Icons.delete_outline),
            label: const Text("Delete receipt"),
          ),
        ),
      ],
    );
  }
}
