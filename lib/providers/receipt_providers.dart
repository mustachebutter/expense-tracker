import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/daos/receipts_dao.dart';
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/core_providers.dart';
import 'package:expense_tracker/providers/transaction_providers.dart';
import 'package:expense_tracker/services/receipt_images.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

// NOTE: receiptImageStoreProvider moved to core_providers so the sync engine can use it.
// Re-exported here so code that looks for it next to the other receipt providers still finds it
export 'package:expense_tracker/providers/core_providers.dart' show receiptImageStoreProvider;

final receiptImagePickerProvider = Provider<ReceiptImagePicker>((ref) => ReceiptImagePicker());

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
typedef ReceiptFilter = ({String? categoryId, String search});

class ReceiptFilterNotifier extends Notifier<ReceiptFilter>
{
  @override
  ReceiptFilter build() => (categoryId: null, search: "");

  void selectCategory(String? categoryId) => state = (categoryId: categoryId, search: state.search);

  void search(String text) => state = (categoryId: state.categoryId, search: text);
}

final receiptFilterProvider = NotifierProvider<ReceiptFilterNotifier, ReceiptFilter>(ReceiptFilterNotifier.new);

final filteredReceiptsProvider = Provider<AsyncValue<List<Receipt>>>((ref) {
  final filter = ref.watch(receiptFilterProvider);
  final search = filter.search.trim().toLowerCase();

  return ref.watch(receiptsProvider).whenData((receipts) => receipts.where((receipt) {
    if (filter.categoryId != null && receipt.categoryId != filter.categoryId) return false;
    if (search.isNotEmpty && !(receipt.merchant ?? "").toLowerCase().contains(search)) return false;
    return true;
  }).toList());
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

  // Saves the photo, then creates the receipt that points at it. Fields are filled in later
  Future<Receipt> addFromImage(Uint8List imageBytes) async
  {
    final userId = _ref.requireUserId();
    final id = const Uuid().v4();

    await _images.save(id, imageBytes);
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
    return saved;
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
  // added twice. The category decides income or expense, like the Add Transaction form
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
        amount: Value(receipt.total!),
        date: Value(receipt.date ?? DateTime.now()),
        type: Value(category.type),
        categoryId: Value(category.id),
      ));
      await update(receipt.copyWith(transactionId: Value(transactionId), categoryId: Value(category.id)));
    });
  }
}

final receiptActionsProvider = Provider<ReceiptActions>((ref) => ReceiptActions(ref));
