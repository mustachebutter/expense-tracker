import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/screens/receipts.dart';
import 'package:expense_tracker/services/receipt_images.dart';
import 'package:expense_tracker/widgets/receipts/receipt_board_view.dart';
import 'package:expense_tracker/widgets/receipts/receipt_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_receipts.dart';
import '../helpers/pump_app.dart';
import '../helpers/test_database.dart';

void main()
{
  late AppDatabase db;
  late FakeReceiptImageStore images;
  late FakeReceiptImagePicker picker;

  setUp(() {
    db = createTestDatabase();
    images = FakeReceiptImageStore();
    picker = FakeReceiptImagePicker();
  });
  tearDown(() => db.close());

  Future<void> openReceipts(WidgetTester tester) async
  {
    await pumpApp(tester, const ReceiptsScreen(), db: db, receiptImages: images, receiptPicker: picker);
    await tester.pumpAndSettle();
  }

  Future<void> openBoard(WidgetTester tester) async
  {
    await openReceipts(tester);
    await tester.tap(find.text("Board"));
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async
  {
    await tester.tap(find.widgetWithText(ElevatedButton, "Save"));
    await tester.pumpAndSettle();
  }

  group("adding", () {
    testWidgets("on desktop the button imports a file, then opens the new receipt to fill in", (tester) async {
      await openReceipts(tester);
      expect(find.text("No receipts yet! Add one with the button below ₍ᐢ•ﻌ•ᐢ₎"), findsOneWidget);

      await tester.tap(find.text("Import receipt"));
      await tester.pumpAndSettle();

      expect(picker.requestedSources, [ReceiptImageSource.gallery]);
      expect(find.text("Receipt"), findsOneWidget, reason: "the receipt dialog opened");

      await tester.enterText(find.widgetWithText(TextFormField, "Shop"), "Tesco");
      await tester.enterText(find.widgetWithText(TextFormField, "Total"), "23.40");
      await tapSave(tester);

      expect(find.widgetWithText(ReceiptCard, "Tesco"), findsOneWidget);
      final saved = (await db.receiptsDao.getAll()).single;
      expect((saved.merchant, saved.total), ("Tesco", 23.40));
      expect(images.images.keys, [saved.id], reason: "the photo is stored under the receipt's id");
    });

    testWidgets("on a phone it asks camera or gallery", (tester) async {
      picker = FakeReceiptImagePicker(canUseCamera: true);
      await openReceipts(tester);

      await tester.tap(find.text("Add receipt"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Take a photo"));
      await tester.pumpAndSettle();

      expect(picker.requestedSources, [ReceiptImageSource.camera]);
    });

    testWidgets("cancelling the picker adds nothing", (tester) async {
      picker.nextImage = null;
      await openReceipts(tester);

      await tester.tap(find.text("Import receipt"));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(await db.receiptsDao.getAll(), isEmpty);
    });
  });

  group("list", () {
    testWidgets("category chips and search narrow the list down", (tester) async {
      final food = await insertCategory(db, name: "Food");
      await insertCategory(db, name: "Travel");
      await insertReceipt(db, merchant: "Tesco", categoryId: food.id);
      await insertReceipt(db, merchant: "Pizza Express", categoryId: food.id);
      await insertReceipt(db, merchant: "Shell");
      await openReceipts(tester);

      expect(find.byType(ReceiptCard), findsNWidgets(3));

      await tester.tap(find.widgetWithText(ChoiceChip, "Food"));
      await tester.pumpAndSettle();
      expect(find.byType(ReceiptCard), findsNWidgets(2));

      await tester.enterText(find.widgetWithText(TextField, "Search by shop"), "pizza");
      await tester.pumpAndSettle();
      expect(find.byType(ReceiptCard), findsOneWidget);
      expect(find.widgetWithText(ReceiptCard, "Pizza Express"), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, "Travel"));
      await tester.pumpAndSettle();
      expect(find.text("No receipts match. Try another category or search"), findsOneWidget);
    });

    testWidgets("a receipt can be turned into a transaction from its dialog", (tester) async {
      final food = await insertCategory(db, name: "Food");
      await insertReceipt(db, merchant: "Tesco", total: 23.40, date: DateTime(2026, 9, 12));
      await openReceipts(tester);

      await tester.tap(find.widgetWithText(ReceiptCard, "Tesco"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Also add as a transaction"));
      await tapSave(tester);

      expect(find.text("A transaction needs a category"), findsOneWidget, reason: "category is still empty");

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Food").last);
      await tester.pumpAndSettle();
      await tapSave(tester);

      final transaction = (await db.transactionsDao.getAll()).single;
      expect((transaction.name, transaction.amount, transaction.categoryId), ("Tesco", 23.40, food.id));
      expect((await db.receiptsDao.getAll()).single.transactionId, transaction.id);

      // Opening it again shows it's done, and doesn't offer to add it twice
      await tester.tap(find.widgetWithText(ReceiptCard, "Tesco"));
      await tester.pumpAndSettle();
      expect(find.text("Added as a transaction"), findsOneWidget);
      expect(find.text("Also add as a transaction"), findsNothing);
    });

    testWidgets("delete asks first, then removes the receipt", (tester) async {
      await insertReceipt(db, merchant: "Tesco");
      await openReceipts(tester);

      await tester.tap(find.widgetWithText(ReceiptCard, "Tesco"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Delete receipt"));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, "Delete"));
      await tester.pumpAndSettle();

      expect(find.byType(ReceiptCard), findsNothing);
      expect((await db.receiptsDao.getAll()).single.isDeleted, isTrue);
    });
  });

  group("board", () {
    testWidgets("only pinned receipts are on the board", (tester) async {
      await insertReceipt(db, merchant: "Pinned", isFavorite: true);
      await insertReceipt(db, merchant: "Not pinned");
      await openBoard(tester);

      expect(find.textContaining("Pinned"), findsOneWidget);
      expect(find.textContaining("Not pinned"), findsNothing);
    });

    testWidgets("says how to pin when the board is empty", (tester) async {
      await openBoard(tester);

      expect(find.textContaining("Nothing pinned yet"), findsOneWidget);
    });

    testWidgets("pinning from the dialog puts the receipt on the board", (tester) async {
      await insertReceipt(db, merchant: "Tesco");
      await openReceipts(tester);

      await tester.tap(find.widgetWithText(ReceiptCard, "Tesco"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Pin to board"));
      await tapSave(tester);
      await tester.tap(find.text("Board"));
      await tester.pumpAndSettle();

      expect(find.textContaining("Tesco"), findsOneWidget);
    });

    testWidgets("dragging a receipt moves it, saves the spot and brings it to the front", (tester) async {
      await insertReceipt(db, merchant: "Top", isFavorite: true, boardX: 400, boardY: 400, boardZ: 5);
      final bottom = await insertReceipt(db, merchant: "Bottom", isFavorite: true, boardX: 100, boardY: 100, boardZ: 1);
      await openBoard(tester);

      await tester.drag(find.text("Bottom"), const Offset(120, 60));
      await tester.pumpAndSettle();

      final saved = (await db.receiptsDao.getReceiptById(bottom.id, userA))!;
      expect((saved.boardX, saved.boardY), (220.0, 160.0));
      expect(saved.boardZ, 6, reason: "picked up receipts go on top of the pile");
    });

    testWidgets("dragging the empty board pans it instead of moving receipts", (tester) async {
      final receipt = await insertReceipt(db, merchant: "Stays put", isFavorite: true, boardX: 100, boardY: 100);
      await openBoard(tester);

      final board = find.byKey(const Key("receipt_board"));
      await tester.dragFrom(tester.getTopLeft(board) + const Offset(1000, 900), const Offset(-200, -100));
      await tester.pumpAndSettle();

      final saved = (await db.receiptsDao.getReceiptById(receipt.id, userA))!;
      expect((saved.boardX, saved.boardY), (100.0, 100.0));
    });

    test("every receipt gets a gentle, stable tilt", () {
      for (final id in ["a", "receipt-1", "6f1c9a52-3d0b-4e57-9d6e-2b1f8c4a7e10"])
      {
        final tilt = ReceiptBoardView.tiltFor(id);
        expect(tilt.abs(), lessThanOrEqualTo(6 * 3.14159 / 180 + 0.0001));
        expect(ReceiptBoardView.tiltFor(id), tilt, reason: "the same receipt always has the same tilt");
      }
    });
  });
}
