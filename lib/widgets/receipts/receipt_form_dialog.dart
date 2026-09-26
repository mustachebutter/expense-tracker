import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/main.dart';
import 'package:expense_tracker/providers/category_providers.dart';
import 'package:expense_tracker/providers/core_providers.dart';
import 'package:expense_tracker/providers/receipt_providers.dart';
import 'package:expense_tracker/providers/receipt_scan_providers.dart';
import 'package:expense_tracker/services/place_finder.dart';
import 'package:expense_tracker/services/receipt_crop.dart';
import 'package:expense_tracker/widgets/forms/form_helpers.dart';
import 'package:expense_tracker/widgets/forms/place_field.dart';
import 'package:expense_tracker/widgets/receipts/receipt_crop_editor.dart';
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
  late final TextEditingController _suburbController;
  late final TextEditingController _cityController;
  late final TextEditingController _stateController;
  late final TextEditingController _countryController;
  final FocusNode _merchantFocus = FocusNode();
  DateTime? _date;
  String? _categoryId;
  late bool _isFavorite;
  late int _quarterTurns;
  // Where the receipt is in the photo (encoded corners), null for the whole photo
  String? _cropCorners;
  bool _addAsTransaction = false;
  bool _isScanning = false;
  bool _isLocating = false;
  // Why "Use my location" didn't work, shown under the button until the next try
  PlaceProblem? _locationProblem;

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
    _suburbController = TextEditingController(text: receipt.suburb ?? "");
    _cityController = TextEditingController(text: receipt.city ?? "");
    _stateController = TextEditingController(text: receipt.state ?? "");
    _countryController = TextEditingController(text: receipt.country ?? "");

    // Leaving the Shop field: if this shop has a location from before and this receipt has
    // none yet, fill it in (visibly, so it can still be changed before saving)
    _merchantFocus.addListener(() {
      if (!_merchantFocus.hasFocus) _fillLocationFromSameShop();
    });
    _date = receipt.date;
    _categoryId = receipt.categoryId;
    _isFavorite = receipt.isFavorite;
    _quarterTurns = receipt.imageQuarterTurns;
    _cropCorners = receipt.cropCorners;
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
    _suburbController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _countryController.dispose();
    _merchantFocus.dispose();
    super.dispose();
  }

  // [replace]: the user asked for a fresh reading, so it overwrites the fields instead of
  // only filling the empty ones
  Future<void> _scan({bool replace = false}) async
  {
    setState(() => _isScanning = true);
    // NOTE: Starts from the way the photo is shown now, including a rotation not saved yet
    final scanned = await ref.read(receiptScanServiceProvider).scan(
      _current.copyWith(imageQuarterTurns: _quarterTurns, cropCorners: Value(_cropCorners)),
      replaceExisting: replace,
    );
    if (!mounted) return;

    setState(() {
      _isScanning = false;
      _current = scanned;
      // The scanner may have turned the photo upright to read it
      _quarterTurns = scanned.imageQuarterTurns;
      _cropCorners = scanned.cropCorners;

      void fill(TextEditingController controller, String? value)
      {
        if (value != null && (replace || controller.text.isEmpty)) controller.text = value;
      }
      fill(_merchantController, scanned.merchant);
      fill(_totalController, scanned.total == null ? null : amountText(scanned.total!));
      // A location the scan copied from the same shop, only if nothing has been typed here
      if (_locationIsEmpty)
      {
        _setPlace(suburb: scanned.suburb, city: scanned.city, state: scanned.state, country: scanned.country);
      }
      if (replace || _date == null) _date = scanned.date ?? _date;
      _categoryId ??= scanned.categoryId;
    });
  }

  List<TextEditingController> get _placeControllers => [_suburbController, _cityController, _stateController, _countryController];

  bool get _locationIsEmpty => _placeControllers.every((controller) => controller.text.trim().isEmpty);

  // The four place fields, in the same order as _placeControllers
  void _setPlace({String? suburb, String? city, String? state, String? country})
  {
    _suburbController.text = suburb ?? "";
    _cityController.text = city ?? "";
    _stateController.text = state ?? "";
    _countryController.text = country ?? "";
  }

  Future<void> _fillLocationFromSameShop() async
  {
    final merchant = _merchantController.text.trim();
    if (merchant.isEmpty || !_locationIsEmpty) return;

    final previous = await ref.read(databaseProvider).receiptsDao.locationUsedBefore(
      merchant,
      _current.userId,
      exceptId: _current.id,
    );
    if (previous == null || !mounted || !_locationIsEmpty) return;

    setState(() => _setPlace(suburb: previous.suburb, city: previous.city, state: previous.state, country: previous.country));
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

  // A quarter turn clockwise. A crop turns with the photo, so it stays on the receipt
  void _rotate()
  {
    setState(() {
      _quarterTurns = (_quarterTurns + 1) % 4;
      final corners = decodeCorners(_cropCorners);
      if (corners != null) _cropCorners = encodeCorners(rotateCornersClockwise(corners));
    });
  }

  Future<void> _crop() async
  {
    final photo = await ref.read(receiptImageStoreProvider).read(widget.receipt.id);
    if (!mounted) return;
    if (photo == null)
    {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("The photo isn't on this device yet, it arrives with the next sync")),
      );
      return;
    }

    final choice = await showReceiptCropEditor(
      context,
      photo: photo,
      quarterTurns: _quarterTurns,
      current: decodeCorners(_cropCorners),
    );
    if (choice == null || !mounted) return;
    setState(() => _cropCorners = choice.corners == null ? null : encodeCorners(choice.corners!));
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
    String? place(TextEditingController controller) => controller.text.trim().isEmpty ? null : controller.text.trim();

    // NOTE: Each step returns the receipt as saved, and the next step builds on that copy
    var saved = await actions.update(_current.copyWith(
      merchant: Value(merchant.isEmpty ? null : merchant),
      total: Value(double.tryParse(_totalController.text)),
      date: Value(_date),
      suburb: Value(place(_suburbController)),
      city: Value(place(_cityController)),
      state: Value(place(_stateController)),
      country: Value(place(_countryController)),
      // NOTE: A place the user typed (or filled with "Use my location") means the photo's
      // coordinates aren't needed any more, so they're not kept
      pendingLatitude: Value(_locationIsEmpty ? _current.pendingLatitude : null),
      pendingLongitude: Value(_locationIsEmpty ? _current.pendingLongitude : null),
      categoryId: Value(_categoryId),
      imageQuarterTurns: _quarterTurns,
      cropCorners: Value(_cropCorners),
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

  // Fills the place fields from where the phone is right now. The user tapped for it, so it
  // replaces what's there
  Future<void> _useMyLocation() async
  {
    final finder = ref.read(placeFinderProvider);
    setState(() {
      _isLocating = true;
      _locationProblem = null;
    });

    try
    {
      final place = await finder.findCurrentPlace();
      if (!mounted) return;
      setState(() => _setPlace(suburb: place.suburb, city: place.city, state: place.state, country: place.country));
    }
    on PlaceNotFound catch (e)
    {
      // NOTE: Shown inside the form, not as a snackbar: a snackbar would sit behind this
      // dialog, where its Settings button couldn't be tapped
      if (mounted) setState(() => _locationProblem = e.problem);
    }
    finally
    {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  List<Widget> _locationFields()
  {
    final places = ref.watch(allReceiptPlacesProvider);
    final bool canLocate = ref.watch(placeFinderProvider).isAvailable;

    return [
      Row(
        children: [
          const Expanded(child: Text("Where", style: TextStyle(fontWeight: FontWeight.bold))),
          if (canLocate)
            TextButton.icon(
              onPressed: _isLocating ? null : _useMyLocation,
              icon: _isLocating
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location),
              label: const Text("Use my location"),
            ),
        ],
      ),
      if (_current.pendingLatitude != null)
        // NOTE: Rebuilds as the place fields change, so it goes away as soon as a place is typed
        ListenableBuilder(
          listenable: Listenable.merge(_placeControllers),
          builder: (context, _) => !_locationIsEmpty ? const SizedBox.shrink() : const Row(
            key: Key("place_waiting"),
            spacing: 8,
            children: [
              Icon(Icons.phone_android, size: 18),
              Expanded(
                child: Text("The photo says where it was taken. Your phone will fill in the place on its next sync."),
              ),
            ],
          ),
        ),
      if (_locationProblem != null)
        Row(
          key: const Key("location_problem"),
          spacing: 8,
          children: [
            const Icon(Icons.location_off_outlined, size: 18),
            Expanded(
              child: Text(switch (_locationProblem!) {
                PlaceProblem.locationOff => "Location is turned off on this phone. Turn it on and try again.",
                PlaceProblem.permissionDenied => "The app needs location permission to fill this in.",
                PlaceProblem.permissionBlocked => "Location permission is blocked for this app. You can allow it in Settings.",
                PlaceProblem.noPosition => "Couldn't get your position in time. Indoors this can take a while, try again in a moment.",
                PlaceProblem.noPlaceName => "Found your position, but couldn't look up the place name. That needs an internet connection.",
                PlaceProblem.unavailable => "Location isn't working in this version of the app. Type the place in instead.",
              }),
            ),
            if (_locationProblem == PlaceProblem.permissionBlocked)
              TextButton(onPressed: ref.read(placeFinderProvider).openSettings, child: const Text("Settings")),
          ],
        ),
      PlaceField(label: "Suburb / area", icon: Icons.holiday_village_outlined, controller: _suburbController, suggestions: places.suburbs),
      PlaceField(label: "City", icon: Icons.location_city, controller: _cityController, suggestions: places.cities),
      PlaceField(label: "State / region", icon: Icons.map_outlined, controller: _stateController, suggestions: places.states),
      PlaceField(label: "Country", icon: Icons.public, controller: _countryController, suggestions: places.countries),
    ];
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
                  child: ReceiptImage(
                    receiptId: widget.receipt.id,
                    fit: BoxFit.contain,
                    quarterTurns: _quarterTurns,
                    cropCorners: _cropCorners,
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  // NOTE: Dark translucent circles with white icons, readable on any photo
                  child: Row(
                    spacing: 8,
                    children: [
                      IconButton(
                        tooltip: "Crop out the background",
                        style: IconButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white),
                        onPressed: _crop,
                        icon: const Icon(Icons.crop),
                      ),
                      IconButton(
                        tooltip: "Rotate photo",
                        style: IconButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white),
                        onPressed: _rotate,
                        icon: const Icon(Icons.rotate_right),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        ?scanStatus,

        TextFormField(
          controller: _merchantController,
          focusNode: _merchantFocus,
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

        ..._locationFields(),

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
