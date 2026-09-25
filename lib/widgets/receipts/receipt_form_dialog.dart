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
  static const int _maxSplitPeople = 20;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _merchantController;
  late final TextEditingController _totalController;
  late final TextEditingController _shareController;
  DateTime? _date;
  String? _categoryId;
  late bool _isFavorite;
  late int _quarterTurns;
  bool _addAsTransaction = false;
  bool _isScanning = false;

  // Splitting the bill: equally between a number of people, or a share the user types
  late bool _isSplit;
  late bool _splitEqually;
  late int _splitPeople;

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
    _shareController = TextEditingController(text: receipt.splitAmount == null ? "" : amountText(receipt.splitAmount!));
    _date = receipt.date;
    _categoryId = receipt.categoryId;
    _isFavorite = receipt.isFavorite;
    _quarterTurns = receipt.imageQuarterTurns;
    _isSplit = receipt.isSplit;
    _splitEqually = receipt.splitAmount == null;
    _splitPeople = receipt.splitPeople ?? 2;

    // A new photo on a device that can read it: read it straight away
    if (receipt.scanStatus == ReceiptScanStatus.waiting && ref.read(canScanHereProvider))
    {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scan();
      });
    }
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _totalController.dispose();
    _shareController.dispose();
    super.dispose();
  }

  // [replace]: the user asked for a fresh reading, so it overwrites the fields instead of
  // only filling the empty ones
  Future<void> _scan({bool replace = false}) async
  {
    setState(() => _isScanning = true);
    // NOTE: Starts from the way the photo is shown now, including a rotation not saved yet
    final scanned = await ref.read(receiptScanServiceProvider).scan(
      _current.copyWith(imageQuarterTurns: _quarterTurns),
      replaceExisting: replace,
    );
    if (!mounted) return;

    setState(() {
      _isScanning = false;
      _current = scanned;
      // The scanner may have turned the photo upright to read it
      _quarterTurns = scanned.imageQuarterTurns;

      void fill(TextEditingController controller, String? value)
      {
        if (value != null && (replace || controller.text.isEmpty)) controller.text = value;
      }
      fill(_merchantController, scanned.merchant);
      fill(_totalController, scanned.total == null ? null : amountText(scanned.total!));
      if (replace || _date == null) _date = scanned.date ?? _date;
      _categoryId ??= scanned.categoryId;
    });
  }

  // What the user pays with the split as it's set in the form right now
  double? get _myShare
  {
    final total = double.tryParse(_totalController.text);
    if (!_isSplit) return total;
    if (!_splitEqually) return double.tryParse(_shareController.text);
    return total == null ? null : (total / _splitPeople * 100).roundToDouble() / 100;
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
          if (buttonLabel != null) TextButton(onPressed: () => _scan(replace: true), child: Text(buttonLabel)),
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
        row(
          const Icon(Icons.auto_awesome_outlined),
          "Filled in from the photo. Check it looks right.",
          buttonLabel: canScanHere ? "Scan again" : null,
        ),
      ReceiptScanStatus.failed =>
        row(
          const Icon(Icons.error_outline),
          "Couldn't read this receipt. Turn the photo upright with the rotate button and try again, "
          "or fill it in yourself.",
          buttonLabel: canScanHere ? "Try again" : null,
        ),
      ReceiptScanStatus.notScanned => null,
    };
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
      imageQuarterTurns: _quarterTurns,
      splitPeople: Value(_isSplit && _splitEqually ? _splitPeople : null),
      splitAmount: Value(_isSplit && !_splitEqually ? double.tryParse(_shareController.text) : null),
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

  List<Widget> _splitFields()
  {
    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.group_outlined),
        title: const Text("Split with friends"),
        value: _isSplit,
        onChanged: (value) => setState(() => _isSplit = value),
      ),
      if (_isSplit) ...[
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text("Equally"), icon: Icon(Icons.balance)),
            ButtonSegment(value: false, label: Text("My share"), icon: Icon(Icons.edit_outlined)),
          ],
          selected: {_splitEqually},
          onSelectionChanged: (selection) => setState(() => _splitEqually = selection.single),
        ),
        if (_splitEqually)
          Row(
            children: [
              const Expanded(child: Text("People, you included")),
              IconButton(
                tooltip: "One less person",
                onPressed: _splitPeople > 2 ? () => setState(() => _splitPeople--) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text("$_splitPeople", key: const Key("split_people"), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                tooltip: "One more person",
                onPressed: _splitPeople < _maxSplitPeople ? () => setState(() => _splitPeople++) : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          )
        else
          TextFormField(
            controller: _shareController,
            decoration: const InputDecoration(labelText: "Your share", prefixText: "\$ "),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: amountInputFormatters,
            onChanged: (_) => setState(() {}),
            validator: (value) {
              final problem = positiveAmount(value);
              if (problem != null) return problem;
              final total = double.tryParse(_totalController.text);
              if (total != null && double.parse(value!) > total) return "Can't be more than the total";
              return null;
            },
          ),
        Text(
          _myShare == null ? "Enter the total to see your share" : "You pay \$${_myShare!.toStringAsFixed(2)}",
          key: const Key("my_share"),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final categories = ref.watch(activeCategoriesProvider).value ?? [];
    final String? selectedCategoryId = categories.any((c) => c.id == _categoryId) ? _categoryId : null;
    final Widget? scanStatus = _scanStatus(context);

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
            child: Stack(
              fit: StackFit.expand,
              children: [
                InteractiveViewer(
                  maxScale: 5,
                  child: ReceiptImage(receiptId: widget.receipt.id, fit: BoxFit.contain, quarterTurns: _quarterTurns),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  // NOTE: Dark translucent circle with a white icon, readable on any photo
                  child: IconButton(
                    tooltip: "Rotate photo",
                    style: IconButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white),
                    onPressed: () => setState(() => _quarterTurns = (_quarterTurns + 1) % 4),
                    icon: const Icon(Icons.rotate_right),
                  ),
                ),
              ],
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
          onChanged: (_) => setState(() {}),
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

        ..._splitFields(),

        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: Icon(_isFavorite ? Icons.star : Icons.star_border),
          title: const Text("Pin to board"),
          value: _isFavorite,
          onChanged: (value) => setState(() => _isFavorite = value),
        ),

        if (_isAlreadyTransaction)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.check_circle_outline),
            title: const Text("Added as a transaction"),
            subtitle: _isSplit ? const Text("Its amount follows your share") : null,
          )
        else
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Also add as a transaction"),
            subtitle: Text(
              _isSplit
                ? "Adds only your share, with the shop, date and category above"
                : "Uses the shop, total, date and category above",
            ),
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
