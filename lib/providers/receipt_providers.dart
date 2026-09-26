import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/daos/receipts_dao.dart';
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/core_providers.dart';
import 'package:expense_tracker/providers/transaction_providers.dart';
import 'package:expense_tracker/services/place_finder.dart';
import 'package:expense_tracker/services/receipt_images.dart';
import 'package:expense_tracker/services/receipt_photo_shrinker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

// NOTE: receiptImageStoreProvider moved to core_providers so the sync engine can use it.
// Re-exported here so code that looks for it next to the other receipt providers still finds it
export 'package:expense_tracker/providers/core_providers.dart' show receiptImageStoreProvider;

final receiptImagePickerProvider = Provider<ReceiptImagePicker>((ref) => ReceiptImagePicker());

final placeFinderProvider = Provider<PlaceFinder>((ref) => PlaceFinder());

final receiptPhotoShrinkerProvider = Provider<ReceiptPhotoShrinker>((ref) => ReceiptPhotoShrinker());

extension ReceiptSplit on Receipt
{
  bool get isSplit => splitPeople != null || splitAmount != null;

  // What you paid yourself: the whole total, an equal part of it, or the amount you typed
  double? get myShare
  {
    if (splitAmount != null) return splitAmount;
    if (total == null) return null;
    if (splitPeople != null && splitPeople! > 1) return (total! / splitPeople! * 100).roundToDouble() / 100;
    return total;
  }
}

// The folder the photos live in. Widgets need it to build each receipt's file path
final receiptImageDirectoryProvider = FutureProvider<Directory>((ref) {
  return ref.watch(receiptImageStoreProvider).directory();
});

final receiptsProvider = StreamProvider<List<Receipt>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(const []);

  return ref.watch(databaseProvider).receiptsDao.watchReceipts(userId);
});

// What the receipts list is showing: one category (null = all) and a search on the shop name
// What the receipts list is showing: one category (null = all), a search on the shop name,
// and a place: a country, and a city in it (null = anywhere)
typedef ReceiptFilter = ({String? categoryId, String search, String? country, String? city});

class ReceiptFilterNotifier extends Notifier<ReceiptFilter>
{
  @override
  ReceiptFilter build() => (categoryId: null, search: "", country: null, city: null);

  void selectCategory(String? categoryId) =>
    state = (categoryId: categoryId, search: state.search, country: state.country, city: state.city);

  void search(String text) =>
    state = (categoryId: state.categoryId, search: text, country: state.country, city: state.city);

  // NOTE: Picking a country clears the city, which may be in another country
  void selectCountry(String? country) =>
    state = (categoryId: state.categoryId, search: state.search, country: country, city: null);

  void selectCity(String? city) =>
    state = (categoryId: state.categoryId, search: state.search, country: state.country, city: city);
}

final receiptFilterProvider = NotifierProvider<ReceiptFilterNotifier, ReceiptFilter>(ReceiptFilterNotifier.new);

// NOTE: Places are free text, so "Sydney", "sydney " and "SYDNEY" all count as the same place
String? placeKey(String? place)
{
  final trimmed = place?.trim().toLowerCase();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

bool samePlace(String? a, String? b) => placeKey(a) != null && placeKey(a) == placeKey(b);

final filteredReceiptsProvider = Provider<AsyncValue<List<Receipt>>>((ref) {
  final filter = ref.watch(receiptFilterProvider);
  final search = filter.search.trim().toLowerCase();

  return ref.watch(receiptsProvider).whenData((receipts) => receipts.where((receipt) {
    if (filter.categoryId != null && receipt.categoryId != filter.categoryId) return false;
    if (search.isNotEmpty && !(receipt.merchant ?? "").toLowerCase().contains(search)) return false;
    if (filter.country != null && !samePlace(receipt.country, filter.country)) return false;
    if (filter.city != null && !samePlace(receipt.city, filter.city)) return false;
    return true;
  }).toList());
});

// Every different value of one place field across the user's receipts, spelled the way it
// was first written, in alphabetical order
List<String> _distinctPlaces(Iterable<String?> values)
{
  final byKey = <String, String>{};
  for (final value in values)
  {
    final key = placeKey(value);
    if (key != null) byKey.putIfAbsent(key, () => value!.trim());
  }
  return byKey.values.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

typedef ReceiptPlaces = ({List<String> countries, List<String> states, List<String> cities});

// The places the user has used, for the filter menus and the suggestions while typing.
// Cities follow the filter's country when one is picked
final receiptPlacesProvider = Provider<ReceiptPlaces>((ref) {
  final receipts = ref.watch(receiptsProvider).value ?? [];
  final country = ref.watch(receiptFilterProvider.select((filter) => filter.country));
  final inCountry = country == null ? receipts : receipts.where((r) => samePlace(r.country, country));

  return (
    countries: _distinctPlaces(receipts.map((r) => r.country)),
    states: _distinctPlaces(receipts.map((r) => r.state)),
    cities: _distinctPlaces(inCountry.map((r) => r.city)),
  );
});

// All the places the user has typed, whatever the filter says. For suggestions while typing
final allReceiptPlacesProvider = Provider<ReceiptPlaces>((ref) {
  final receipts = ref.watch(receiptsProvider).value ?? [];
  return (
    countries: _distinctPlaces(receipts.map((r) => r.country)),
    states: _distinctPlaces(receipts.map((r) => r.state)),
    cities: _distinctPlaces(receipts.map((r) => r.city)),
  );
});

// The receipts pinned on the board, bottom of the pile first so the last one is drawn on top
final boardReceiptsProvider = Provider<AsyncValue<List<Receipt>>>((ref) {
  return ref.watch(receiptsProvider).whenData((receipts) {
    return receipts.where((r) => r.isFavorite).toList()
      ..sort((a, b) => a.boardZ.compareTo(b.boardZ));
  });
});

// See CategoryActions for why changes go through an actions class
class ReceiptActions
{
  final Ref _ref;

  ReceiptActions(this._ref);

  AppDatabase get _db => _ref.read(databaseProvider);
  ReceiptsDao get _dao => _db.receiptsDao;
  ReceiptImageStore get _images => _ref.read(receiptImageStoreProvider);

  // Shrinks and saves the photo, then creates the receipt that points at it. Fields are
  // filled in later. [imageBytes] can come from anywhere: camera, gallery, document scanner,
  // a file on Windows, this is the one place they all go through
  Future<Receipt> addFromImage(Uint8List imageBytes) async
  {
    final userId = _ref.requireUserId();
    final id = const Uuid().v4();

    await _images.save(id, await _ref.read(receiptPhotoShrinkerProvider).shrink(imageBytes));
    try
    {
      // NOTE: Every new receipt waits for the scanner. On a phone that's a second away, on
      // Windows it waits for the phone to sync and read it
      return await _db.into(_db.receipts).insertReturning(
        ReceiptsCompanion.insert(id: Value(id), userId: userId, scanStatus: const Value(ReceiptScanStatus.waiting)),
      );
    }
    catch (e)
    {
      // Don't leave an orphaned photo behind if the row couldn't be saved
      await _images.delete(id);
      rethrow;
    }
  }

  // Returns the row as saved, so several changes in a row can build on each other
  Future<Receipt> update(Receipt edited) async
  {
    if (edited.userId != _ref.requireUserId()) throw StateError("Can't edit another user's receipt");

    final saved = edited.copyWith(isSynced: false, updatedAt: nextUpdatedAt(edited.updatedAt));
    await _dao.updateRow(saved);
    await _updateLinkedTransaction(saved);
    return saved;
  }

  // NOTE: Once a receipt is a transaction, the transaction's amount follows your share, so
  // splitting the bill afterwards (or fixing the total) doesn't leave the budget wrong
  Future<void> _updateLinkedTransaction(Receipt receipt) async
  {
    final share = receipt.myShare;
    if (receipt.transactionId == null || share == null) return;

    final transaction = await _db.transactionsDao.getTransactionById(receipt.transactionId!, receipt.userId);
    if (transaction == null || transaction.isDeleted || transaction.amount == share) return;

    await _db.transactionsDao.updateRow(transaction.copyWith(
      amount: share,
      isSynced: false,
      updatedAt: nextUpdatedAt(transaction.updatedAt),
    ));
  }

  // Pinning puts it on top of the pile. Where it lands is decided by the board until it's dragged
  Future<Receipt> setFavorite(Receipt receipt, bool isFavorite) async
  {
    final topZ = await _dao.getTopBoardZ(_ref.requireUserId());
    return update(receipt.copyWith(isFavorite: isFavorite, boardZ: isFavorite ? topZ + 1 : receipt.boardZ));
  }

  // Called when a receipt is dropped on the board: remember where, and put it on top
  Future<Receipt> moveOnBoard(Receipt receipt, double x, double y) async
  {
    final topZ = await _dao.getTopBoardZ(_ref.requireUserId());
    final boardZ = receipt.boardZ == topZ ? topZ : topZ + 1;
    return update(receipt.copyWith(boardX: Value(x), boardY: Value(y), boardZ: boardZ));
  }

  Future<void> delete(String id) async
  {
    await _dao.softDeleteById(id, _ref.requireUserId());
    await _images.delete(id);
  }

  // Turns the receipt into a transaction in its category, and links the two so it can't be
  // added twice. The category decides income or expense, like the Add Transaction form.
  // A split receipt only adds your share
  Future<void> addAsTransaction(Receipt receipt, Category category) async
  {
    if (receipt.transactionId != null) throw StateError("This receipt is already a transaction");
    if (receipt.total == null) throw StateError("A receipt needs a total to become a transaction");

    final transactionId = const Uuid().v4();

    // NOTE: Both writes succeed or neither does
    await _db.transaction(() async {
      await _ref.read(transactionActionsProvider).add(TransactionsCompanion(
        id: Value(transactionId),
        name: Value(receipt.merchant ?? "Receipt"),
        amount: Value(receipt.myShare!),
        date: Value(receipt.date ?? DateTime.now()),
        type: Value(category.type),
        categoryId: Value(category.id),
      ));
      await update(receipt.copyWith(transactionId: Value(transactionId), categoryId: Value(category.id)));
    });
  }
}

final receiptActionsProvider = Provider<ReceiptActions>((ref) => ReceiptActions(ref));
