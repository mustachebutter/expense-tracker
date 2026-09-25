import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/core_providers.dart';
import 'package:expense_tracker/providers/receipt_scan_providers.dart';
import 'package:expense_tracker/providers/settings_providers.dart';
import 'package:expense_tracker/providers/sync_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_receipts.dart';
import '../helpers/pump_app.dart';
import '../helpers/test_database.dart';

const List<String> tescoReceipt = ["TESCO EXPRESS", "MILK 1.45", "TOTAL 3.06", "CASH 10.00", "12/09/2026"];

void main()
{
  late AppDatabase db;
  late FakeReceiptImageStore photos;
  late FakeReceiptScanner scanner;

  setUp(() {
    db = createTestDatabase();
    photos = FakeReceiptImageStore();
    scanner = FakeReceiptScanner(rows: tescoReceipt);
  });
  tearDown(() => db.close());

  Future<ProviderContainer> createContainer({
    Map<String, Object> preferences = const {},
    List<Override> extraOverrides = const [],
  }) async
  {
    SharedPreferences.setMockInitialValues(preferences);
    final sharedPreferences = await SharedPreferences.getInstance();

    return ProviderContainer.test(
      overrides: [
        databaseProvider.overrideWithValue(db),
        currentUserIdProvider.overrideWithValue(userA),
        receiptImageStoreProvider.overrideWithValue(photos),
        receiptScannerProvider.overrideWithValue(scanner),
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        receiptDatesDayFirstProvider.overrideWithValue(true),
        ...extraOverrides,
      ],
    );
  }

  // A receipt whose photo is on this device, waiting to be read
  Future<Receipt> waitingReceipt({String? merchant, double? total}) async
  {
    final receipt = await insertReceipt(db, merchant: merchant, total: total);
    await photos.save(receipt.id, Uint8List.fromList([1]));
    return db.receiptsDao.getReceiptById(receipt.id, userA).then((r) async {
      await db.receiptsDao.updateRow(r!.copyWith(scanStatus: ReceiptScanStatus.waiting));
      return (await db.receiptsDao.getReceiptById(receipt.id, userA))!;
    });
  }

  Future<Receipt> reload(String id) async => (await db.receiptsDao.getReceiptById(id, userA))!;

  group("scan", () {
    test("fills in the shop, total and date and marks the receipt scanned", () async {
      final container = await createContainer();
      final receipt = await waitingReceipt();

      final scanned = await container.read(receiptScanServiceProvider).scan(receipt);

      expect((scanned.merchant, scanned.total, scanned.date), ("Tesco Express", 3.06, DateTime(2026, 9, 12)));
      expect(scanned.scanStatus, ReceiptScanStatus.scanned);
      expect(scanned.isSynced, isFalse, reason: "the scanned fields have to sync too");
      expect((await reload(receipt.id)).merchant, "Tesco Express");
    });

    test("keeps whatever the user already typed", () async {
      final container = await createContainer();
      final receipt = await waitingReceipt(merchant: "My corner shop");

      final scanned = await container.read(receiptScanServiceProvider).scan(receipt);

      expect(scanned.merchant, "My corner shop");
      expect(scanned.total, 3.06, reason: "empty fields are still filled in");
    });

    test("an edit made while the photo was being read wins", () async {
      final receipt = await waitingReceipt();
      scanner = _EditingScanner(onRead: () async {
        final latest = await reload(receipt.id);
        await db.receiptsDao.updateRow(latest.copyWith(total: const Value(99.99)));
      });
      final container = await createContainer();

      final scanned = await container.read(receiptScanServiceProvider).scan(receipt);

      expect(scanned.total, 99.99);
      expect(scanned.merchant, "Tesco Express");
    });

    test("a photo with nothing readable is marked failed", () async {
      scanner.rows = ["~~", ".."];
      final container = await createContainer();
      final receipt = await waitingReceipt();

      final scanned = await container.read(receiptScanServiceProvider).scan(receipt);

      expect(scanned.scanStatus, ReceiptScanStatus.failed);
      expect(scanned.merchant, isNull);
    });

    test("a scanner error is marked failed instead of crashing", () async {
      scanner.failWith = Exception("ML Kit is unhappy");
      final container = await createContainer();
      final receipt = await waitingReceipt();

      final scanned = await container.read(receiptScanServiceProvider).scan(receipt);

      expect(scanned.scanStatus, ReceiptScanStatus.failed);
    });

    test("suggests the category this shop was put in most recently", () async {
      final groceries = await insertCategory(db, name: "Groceries");
      final food = await insertCategory(db, name: "Food");
      // A transaction from January, then a receipt from today, both for the same shop
      await insertTransaction(db, name: "Tesco Express", categoryId: food.id, date: DateTime(2026, 1, 5));
      await insertReceipt(db, merchant: "tesco express", categoryId: groceries.id);
      final container = await createContainer();
      final receipt = await waitingReceipt();

      final scanned = await container.read(receiptScanServiceProvider).scan(receipt);

      expect(scanned.categoryId, groceries.id, reason: "the most recent use wins, whatever the capitals");
    });

    test("also learns from transactions, not just receipts", () async {
      final food = await insertCategory(db, name: "Food");
      await insertTransaction(db, name: "TESCO EXPRESS", categoryId: food.id, date: DateTime(2026, 1, 5));
      final container = await createContainer();
      final receipt = await waitingReceipt();

      final scanned = await container.read(receiptScanServiceProvider).scan(receipt);

      expect(scanned.categoryId, food.id);
    });

    test("doesn't suggest a category that was deleted", () async {
      final gone = await insertCategory(db, name: "Old", isDeleted: true);
      await insertReceipt(db, merchant: "Tesco Express", categoryId: gone.id);
      final container = await createContainer();
      final receipt = await waitingReceipt();

      final scanned = await container.read(receiptScanServiceProvider).scan(receipt);

      expect(scanned.categoryId, isNull);
    });
  });

  group("scanWaiting", () {
    test("reads every waiting receipt whose photo is on this device", () async {
      final container = await createContainer();
      final ready = await waitingReceipt();
      final notDownloaded = await insertReceipt(db);
      await db.receiptsDao.updateRow(notDownloaded.copyWith(scanStatus: ReceiptScanStatus.waiting));
      final alreadyDone = await insertReceipt(db, merchant: "Done");

      final count = await container.read(receiptScanServiceProvider).scanWaiting();

      expect(count, 1);
      expect((await reload(ready.id)).scanStatus, ReceiptScanStatus.scanned);
      expect((await reload(notDownloaded.id)).scanStatus, ReceiptScanStatus.waiting, reason: "no photo here yet");
      expect((await reload(alreadyDone.id)).scanStatus, ReceiptScanStatus.notScanned);
    });

    test("does nothing on a device without a scanner, like Windows", () async {
      scanner = FakeReceiptScanner(isAvailable: false, rows: tescoReceipt);
      final container = await createContainer();
      final receipt = await waitingReceipt();

      expect(await container.read(receiptScanServiceProvider).scanWaiting(), 0);
      expect((await reload(receipt.id)).scanStatus, ReceiptScanStatus.waiting);
    });

    test("does nothing when this device is set to use the self-hosted model", () async {
      final container = await createContainer(preferences: {"receipt_scan_mode": ReceiptScanMode.selfHosted.name});
      await waitingReceipt();

      expect(await container.read(receiptScanServiceProvider).scanWaiting(), 0);
    });
  });

  test("the scan mode setting is remembered", () async {
    final container = await createContainer();
    expect(container.read(receiptScanModeProvider), ReceiptScanMode.onDevice, reason: "the default");

    await container.read(receiptScanModeProvider.notifier).select(ReceiptScanMode.selfHosted);

    final saved = await SharedPreferences.getInstance();
    expect(saved.getString("receipt_scan_mode"), "selfHosted");
  });

  test("a sync scans receipts that arrived from another device", () async {
    final engine = FakeSyncEngine();
    final container = await createContainer(extraOverrides: [
      syncEngineProvider.overrideWithValue(engine),
      isOnlineProvider.overrideWithValue(true),
    ]);
    final receipt = await waitingReceipt();

    await container.read(syncControllerProvider.notifier).syncNow();

    expect(engine.syncedUserIds, [userA]);
    expect((await reload(receipt.id)).merchant, "Tesco Express");
  });
}

// Lets a test change the receipt at the exact moment the photo is being read
class _EditingScanner extends FakeReceiptScanner
{
  final Future<void> Function() onRead;

  _EditingScanner({required this.onRead}) : super(rows: tescoReceipt);

  @override
  Future<List<String>> readRows(File image) async
  {
    await onRead();
    return super.readRows(image);
  }
}
