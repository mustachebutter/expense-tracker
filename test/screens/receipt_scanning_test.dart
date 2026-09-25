import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/receipt_providers.dart';
import 'package:expense_tracker/providers/settings_providers.dart';
import 'package:expense_tracker/screens/receipts.dart';
import 'package:expense_tracker/screens/settings.dart';
import 'package:expense_tracker/services/receipt_images.dart';
import 'package:expense_tracker/widgets/receipts/receipt_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_receipts.dart';
import '../helpers/pump_app.dart';
import '../helpers/test_database.dart';

void main()
{
  late AppDatabase db;
  late FakeReceiptImageStore photos;

  setUp(() {
    db = createTestDatabase();
    photos = FakeReceiptImageStore();
  });
  tearDown(() => db.close());

  Future<void> openReceipts(WidgetTester tester, {required FakeReceiptScanner scanner, bool canUseCamera = false}) async
  {
    await pumpApp(
      tester,
      const ReceiptsScreen(),
      db: db,
      receiptImages: photos,
      receiptPicker: FakeReceiptImagePicker(canUseCamera: canUseCamera),
      receiptScanner: scanner,
    );
    await tester.pumpAndSettle();
  }

  Future<void> importReceipt(WidgetTester tester) async
  {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
  }

  String fieldText(WidgetTester tester, String label)
  {
    return tester.widget<TextFormField>(find.widgetWithText(TextFormField, label)).controller!.text;
  }

  testWidgets("on a phone a new receipt is read straight away and the fields are filled in", (tester) async {
    final scanner = FakeReceiptScanner(rows: ["TESCO EXPRESS", "TOTAL 3.06", "12/09/2026"]);
    await openReceipts(tester, scanner: scanner);

    await importReceipt(tester);

    expect(scanner.scannedPaths, hasLength(1));
    expect(fieldText(tester, "Shop"), "Tesco Express");
    expect(fieldText(tester, "Total"), "3.06");
    expect(find.text("Sat, Sep 12, 2026"), findsOneWidget);
    expect(find.text("Filled in from the photo. Check it looks right."), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, "Save"));
    await tester.pumpAndSettle();

    final saved = (await db.receiptsDao.getAll()).single;
    expect((saved.merchant, saved.total, saved.scanStatus), ("Tesco Express", 3.06, ReceiptScanStatus.scanned));
  });

  testWidgets("on Windows a new receipt waits for the phone", (tester) async {
    final scanner = FakeReceiptScanner(isAvailable: false);
    await openReceipts(tester, scanner: scanner);

    await importReceipt(tester);

    expect(scanner.scannedPaths, isEmpty);
    expect(find.textContaining("Waiting for your phone to read this"), findsOneWidget);
    expect(fieldText(tester, "Shop"), isEmpty);

    // Filling it in by hand still works while it waits
    await tester.enterText(find.widgetWithText(TextFormField, "Shop"), "Typed on the PC");
    await tester.tap(find.widgetWithText(ElevatedButton, "Save"));
    await tester.pumpAndSettle();

    final saved = (await db.receiptsDao.getAll()).single;
    expect((saved.merchant, saved.scanStatus), ("Typed on the PC", ReceiptScanStatus.waiting));
    expect(find.widgetWithText(ReceiptCard, "Waiting to scan"), findsOneWidget, reason: "the card shows it's still waiting");
  });

  testWidgets("a receipt that couldn't be read can be tried again", (tester) async {
    final scanner = FakeReceiptScanner(rows: ["~~"]);
    await openReceipts(tester, scanner: scanner);

    await importReceipt(tester);
    expect(find.textContaining("Couldn't read this receipt"), findsOneWidget);

    scanner.rows = ["KMART", "TOTAL 9.00"];
    await tester.tap(find.text("Try again"));
    await tester.pumpAndSettle();

    expect(fieldText(tester, "Shop"), "Kmart");
    expect(fieldText(tester, "Total"), "9.00");
  });

  testWidgets("Settings shows how this device scans, with the self-hosted option not ready yet", (tester) async {
    await pumpApp(tester, const Settings(), db: db, receiptScanner: FakeReceiptScanner(isAvailable: false));
    await tester.pumpAndSettle();

    expect(find.text("Receipt scanning"), findsOneWidget);
    expect(find.textContaining("This device can't run ML Kit"), findsOneWidget);

    final selector = tester.widget<SegmentedButton<ReceiptScanMode>>(find.byType(SegmentedButton<ReceiptScanMode>));
    expect(selector.selected, {ReceiptScanMode.onDevice});
    expect(selector.segments.firstWhere((s) => s.value == ReceiptScanMode.selfHosted).enabled, isFalse);
  });

  group("receipt dialog", () {
    Future<void> openReceipt(WidgetTester tester, String merchant, {FakeReceiptScanner? scanner}) async
    {
      await openReceipts(tester, scanner: scanner ?? FakeReceiptScanner(isAvailable: false));
      await tester.tap(find.widgetWithText(ReceiptCard, merchant));
      await tester.pumpAndSettle();
    }

    Future<void> save(WidgetTester tester) async
    {
      await tester.tap(find.widgetWithText(ElevatedButton, "Save"));
      await tester.pumpAndSettle();
    }

    testWidgets("splitting equally shows your share and saves how many people", (tester) async {
      await insertReceipt(db, merchant: "Pizza night", total: 60);
      await openReceipt(tester, "Pizza night");

      await tester.tap(find.text("Split with friends"));
      await tester.pumpAndSettle();
      expect(find.text("You pay \$30.00"), findsOneWidget, reason: "two people to start with");

      await tester.tap(find.byTooltip("One more person"));
      await tester.tap(find.byTooltip("One more person"));
      await tester.pumpAndSettle();
      expect(find.text("You pay \$15.00"), findsOneWidget);

      await save(tester);

      final saved = (await db.receiptsDao.getAll()).single;
      expect((saved.splitPeople, saved.splitAmount), (4, null));
      expect(find.widgetWithText(ReceiptCard, "\$15.00 of \$60.00 · No date"), findsOneWidget);
    });

    testWidgets("a custom share can't be more than the total", (tester) async {
      await insertReceipt(db, merchant: "Groceries", total: 40);
      await openReceipt(tester, "Groceries");

      await tester.tap(find.text("Split with friends"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("My share"));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, "Your share"), "55");
      await save(tester);

      expect(find.text("Can't be more than the total"), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, "Your share"), "12.50");
      await tester.pumpAndSettle();
      expect(find.text("You pay \$12.50"), findsOneWidget);
      await save(tester);

      final saved = (await db.receiptsDao.getAll()).single;
      expect((saved.splitPeople, saved.splitAmount), (null, 12.5));
    });

    testWidgets("turning split off again clears it", (tester) async {
      final receipt = await insertReceipt(db, merchant: "Dinner", total: 50);
      await db.receiptsDao.updateRow(receipt.copyWith(splitPeople: const Value(2)));
      await openReceipt(tester, "Dinner");

      await tester.tap(find.text("Split with friends"));
      await save(tester);

      final saved = (await db.receiptsDao.getAll()).single;
      expect(saved.isSplit, isFalse);
    });

    testWidgets("the rotate button turns the photo a quarter turn each tap", (tester) async {
      await insertReceipt(db, merchant: "Sideways");
      await openReceipt(tester, "Sideways");

      await tester.tap(find.byTooltip("Rotate photo"));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip("Rotate photo"));
      await tester.pumpAndSettle();
      await save(tester);

      expect((await db.receiptsDao.getAll()).single.imageQuarterTurns, 2);
    });

    testWidgets("Scan again replaces what the earlier reading filled in", (tester) async {
      final receipt = await insertReceipt(db, merchant: "Misread");
      await db.receiptsDao.updateRow(receipt.copyWith(scanStatus: ReceiptScanStatus.scanned));
      await photos.save(receipt.id, Uint8List.fromList([1]));
      await openReceipt(tester, "Misread", scanner: FakeReceiptScanner(rows: ["KMART", "TOTAL 9.00"]));

      await tester.tap(find.text("Scan again"));
      await tester.pumpAndSettle();

      expect(fieldText(tester, "Shop"), "Kmart");
      expect(fieldText(tester, "Total"), "9.00");
    });
  });

  testWidgets("on Android, adding offers the document scanner that crops out the background", (tester) async {
    final picker = FakeReceiptImagePicker(canUseCamera: true, canScanDocuments: true);
    await pumpApp(tester, const ReceiptsScreen(), db: db, receiptImages: photos, receiptPicker: picker,
      receiptScanner: FakeReceiptScanner(isAvailable: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text("Add receipt"));
    await tester.pumpAndSettle();
    expect(find.text("Crops out the background and straightens it"), findsOneWidget);
    expect(find.text("Take a plain photo"), findsOneWidget);

    await tester.tap(find.text("Scan receipt"));
    await tester.pumpAndSettle();

    expect(picker.requestedSources, [ReceiptImageSource.documentScanner]);
  });
}
