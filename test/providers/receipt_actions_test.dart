import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;

import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/core_providers.dart';
import 'package:expense_tracker/providers/receipt_providers.dart';
import 'package:expense_tracker/providers/transaction_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_receipts.dart';
import '../helpers/test_database.dart';

void main()
{
  late AppDatabase db;
  late FakeReceiptImageStore images;
  late ProviderContainer container;

  setUp(() {
    db = createTestDatabase();
    images = FakeReceiptImageStore();
    container = ProviderContainer.test(
      overrides: [
        databaseProvider.overrideWithValue(db),
        currentUserIdProvider.overrideWithValue(userA),
        receiptImageStoreProvider.overrideWithValue(images),
      ],
    );
  });
  tearDown(() => db.close());

  ReceiptActions actions() => container.read(receiptActionsProvider);
  Future<Receipt> reload(String id) async => (await db.receiptsDao.getReceiptById(id, userA))!;

  group("ReceiptsDao", () {
    test("lists the user's receipts newest first, by receipt date or else when they were added", () async {
      await insertReceipt(db, merchant: "Old", date: DateTime(2026, 1, 5));
      await insertReceipt(db, merchant: "No date, added recently", createdAt: DateTime(2026, 6, 1));
      await insertReceipt(db, merchant: "New", date: DateTime(2026, 9, 1));
      await insertReceipt(db, merchant: "Deleted", date: DateTime(2026, 9, 2), isDeleted: true);
      await insertReceipt(db, merchant: "Someone else's", date: DateTime(2026, 9, 3), userId: userB);

      final receipts = await db.receiptsDao.watchReceipts(userA).first;

      expect(receipts.map((r) => r.merchant), ["New", "No date, added recently", "Old"]);
    });

    test("getTopBoardZ is the highest stacking order on the user's board", () async {
      expect(await db.receiptsDao.getTopBoardZ(userA), 0, reason: "an empty board");

      await insertReceipt(db, boardZ: 3);
      await insertReceipt(db, boardZ: 7);
      await insertReceipt(db, boardZ: 99, userId: userB);

      expect(await db.receiptsDao.getTopBoardZ(userA), 7);
    });
  });

  group("ReceiptActions", () {
    test("addFromImage saves the photo under the receipt's id and creates an empty receipt", () async {
      final bytes = Uint8List.fromList([9, 8, 7]);

      final receipt = await actions().addFromImage(bytes);

      expect(images.images[receipt.id], bytes);
      final saved = await reload(receipt.id);
      expect(saved.userId, userA);
      expect(saved.merchant, isNull);
      expect(saved.scanStatus, ReceiptScanStatus.waiting, reason: "every new photo is queued for the scanner");
      expect(saved.isSynced, isFalse);
    });

    test("update follows the sync rules and refuses another user's receipt", () async {
      final receipt = await insertReceipt(db);

      final saved = await actions().update(receipt.copyWith(total: const Value(12.5)));

      expect((await reload(receipt.id)).total, 12.5);
      expect(saved.updatedAt.isAfter(receipt.updatedAt), isTrue);

      final theirs = await insertReceipt(db, userId: userB);
      expect(() => actions().update(theirs.copyWith(total: const Value(1))), throwsStateError);
    });

    test("pinning puts the receipt on top of the pile", () async {
      await insertReceipt(db, isFavorite: true, boardZ: 4);
      final receipt = await insertReceipt(db);

      await actions().setFavorite(receipt, true);

      final saved = await reload(receipt.id);
      expect(saved.isFavorite, isTrue);
      expect(saved.boardZ, 5);
    });

    test("moving a receipt on the board saves where it was dropped and brings it to the front", () async {
      await insertReceipt(db, isFavorite: true, boardZ: 2);
      final receipt = await insertReceipt(db, isFavorite: true, boardZ: 1);

      final moved = await actions().moveOnBoard(receipt, 300, 450);

      expect((moved.boardX, moved.boardY, moved.boardZ), (300.0, 450.0, 3));

      // Already on top: moving it again doesn't keep climbing
      final movedAgain = await actions().moveOnBoard(moved, 10, 10);
      expect(movedAgain.boardZ, 3);
    });

    test("delete soft deletes the receipt and removes its photo", () async {
      final receipt = await actions().addFromImage(Uint8List.fromList([1]));

      await actions().delete(receipt.id);

      expect((await reload(receipt.id)).isDeleted, isTrue);
      expect(images.images, isEmpty);
    });

    test("addAsTransaction creates a transaction in the category's type and links it", () async {
      final salary = await insertCategory(db, name: "Salary", type: TransactionType.income);
      final receipt = await insertReceipt(db, merchant: "Payslip", total: 2000, date: DateTime(2026, 9, 1));

      await actions().addAsTransaction(receipt, salary);

      final transaction = (await db.transactionsDao.getAll()).single;
      expect(transaction.name, "Payslip");
      expect(transaction.amount, 2000);
      expect(transaction.date, DateTime(2026, 9, 1));
      expect(transaction.type, TransactionType.income);
      expect(transaction.userId, userA);

      final linked = await reload(receipt.id);
      expect(linked.transactionId, transaction.id);
      expect(linked.categoryId, salary.id);

      // A second time would double count it
      expect(() => actions().addAsTransaction(linked, salary), throwsStateError);
    });

    test("addAsTransaction needs a total", () async {
      final food = await insertCategory(db, name: "Food");
      final receipt = await insertReceipt(db, merchant: "No total");

      expect(() => actions().addAsTransaction(receipt, food), throwsStateError);
      expect(await db.transactionsDao.getAll(), isEmpty);
    });
  });

  group("filters", () {
    test("filter by category and search by shop name", () async {
      final food = await insertCategory(db, name: "Food");
      await insertReceipt(db, merchant: "Tesco", categoryId: food.id);
      await insertReceipt(db, merchant: "Shell", date: DateTime(2026, 1, 1));
      await insertReceipt(db, merchant: "Pizza Express", categoryId: food.id);
      container.listen(filteredReceiptsProvider, (previous, next) {});
      await container.read(receiptsProvider.future);

      List<String?> shown() => container.read(filteredReceiptsProvider).value!.map((r) => r.merchant).toList();

      container.read(receiptFilterProvider.notifier).selectCategory(food.id);
      expect(shown(), unorderedEquals(["Tesco", "Pizza Express"]));

      container.read(receiptFilterProvider.notifier).search("pizza");
      expect(shown(), ["Pizza Express"]);

      container.read(receiptFilterProvider.notifier).selectCategory(null);
      container.read(receiptFilterProvider.notifier).search("");
      expect(shown(), hasLength(3));
    });
  });

  group("splitting", () {
    test("your share is the total, an equal part, or the amount you typed", () async {
      final whole = await insertReceipt(db, total: 30);
      expect((whole.isSplit, whole.myShare), (false, 30.0));

      final equal = whole.copyWith(splitPeople: const Value(3));
      expect((equal.isSplit, equal.myShare), (true, 10.0));

      // NOTE: 10 / 3 people is rounded to cents, not 3.3333...
      expect(whole.copyWith(total: const Value(10), splitPeople: const Value(3)).myShare, 3.33);

      final custom = whole.copyWith(splitAmount: const Value(12.5));
      expect((custom.isSplit, custom.myShare), (true, 12.5));

      expect((await insertReceipt(db)).myShare, isNull, reason: "no total yet");
    });

    test("a split receipt only adds your share as a transaction", () async {
      final food = await insertCategory(db, name: "Food");
      final receipt = await insertReceipt(db, merchant: "Pizza night", total: 60);

      await actions().addAsTransaction(receipt.copyWith(splitPeople: const Value(4)), food);

      expect((await db.transactionsDao.getAll()).single.amount, 15.0);
    });

    test("changing the split later updates the linked transaction", () async {
      final food = await insertCategory(db, name: "Food");
      final receipt = await insertReceipt(db, merchant: "Pizza night", total: 60);
      await actions().addAsTransaction(receipt, food);
      final linked = await reload(receipt.id);
      final transactionBefore = (await db.transactionsDao.getAll()).single;
      expect(transactionBefore.amount, 60.0);

      await actions().update(linked.copyWith(splitPeople: const Value(3)));

      final transactionAfter = (await db.transactionsDao.getAll()).single;
      expect(transactionAfter.amount, 20.0);
      expect(transactionAfter.isSynced, isFalse, reason: "the new amount has to sync too");
      expect(transactionAfter.updatedAt.isAfter(transactionBefore.updatedAt), isTrue);
    });

    test("a deleted linked transaction isn't brought back", () async {
      final food = await insertCategory(db, name: "Food");
      final receipt = await insertReceipt(db, total: 60);
      await actions().addAsTransaction(receipt, food);
      final linked = await reload(receipt.id);
      await container.read(transactionActionsProvider).softDeleteById(linked.transactionId!);

      await actions().update(linked.copyWith(splitPeople: const Value(2)));

      final transaction = (await db.transactionsDao.getAll()).single;
      expect((transaction.isDeleted, transaction.amount), (true, 60.0));
    });
  });
}
