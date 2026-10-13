import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/core_providers.dart';
import 'package:expense_tracker/providers/receipt_crop_providers.dart';
import 'package:expense_tracker/providers/receipt_scan_providers.dart';
import 'package:expense_tracker/providers/settings_providers.dart';
import 'package:expense_tracker/services/receipt_crop.dart';
import 'package:expense_tracker/services/receipt_images.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_receipts.dart';
import '../helpers/test_database.dart';

void main()
{
  group("croppedReceiptFile (real files in a temporary folder)", () {
    late Directory folder;
    late ReceiptImageStore store;
    late FakeReceiptCropper cropper;

    setUp(() {
      folder = Directory.systemTemp.createTempSync("receipt_crop_test");
      store = ReceiptImageStore(() async => folder);
      cropper = FakeReceiptCropper();
    });
    tearDown(() => folder.deleteSync(recursive: true));

    Future<File?> cropped(String corners, {int turns = 0}) => croppedReceiptFile(
      store, cropper, receiptId: "r1", quarterTurns: turns, cropCorners: corners);

    test("makes the cropped copy once, then reuses it", () async {
      await store.save("r1", Uint8List.fromList([1, 2, 3]));
      final corners = encodeCorners(sampleCorners);

      final first = await cropped(corners);
      final second = await cropped(corners);

      expect(first!.path, second!.path);
      expect(await first.readAsBytes(), [7, 7, 7]);
      expect(cropper.renderedCorners, hasLength(1), reason: "the second time came from the cache");
    });

    test("a new crop or rotation replaces the old cached copy", () async {
      await store.save("r1", Uint8List.fromList([1, 2, 3]));
      final old = await cropped(encodeCorners(sampleCorners));

      final turned = await cropped(encodeCorners(sampleCorners), turns: 1);

      expect(turned!.path, isNot(old!.path));
      expect(await old.exists(), isFalse, reason: "the stale copy is cleaned up");
    });

    test("nothing to crop until the original photo is on this device", () async {
      expect(await cropped(encodeCorners(sampleCorners)), isNull);
    });

    test("deleting the receipt removes the cropped copies too", () async {
      await store.save("r1", Uint8List.fromList([1, 2, 3]));
      final copy = await cropped(encodeCorners(sampleCorners));

      await store.delete("r1");

      expect(await copy!.exists(), isFalse);
      expect(await store.exists("r1"), isFalse);
    });
  });

  group("scanning a cropped receipt", () {
    late AppDatabase db;
    late FakeReceiptImageStore photos;
    late FakeReceiptScanner scanner;
    late FakeReceiptCropper cropper;

    setUp(() {
      db = createTestDatabase();
      photos = FakeReceiptImageStore();
      scanner = FakeReceiptScanner(rows: const ["TESCO EXPRESS", "TOTAL 3.06"]);
      cropper = FakeReceiptCropper();
    });
    tearDown(() => db.close());

    Future<ProviderContainer> createContainer() async
    {
      SharedPreferences.setMockInitialValues({});
      return ProviderContainer.test(overrides: [
        databaseProvider.overrideWithValue(db),
        currentUserIdProvider.overrideWithValue(userA),
        receiptImageStoreProvider.overrideWithValue(photos),
        receiptScannerProvider.overrideWithValue(scanner),
        receiptCropperProvider.overrideWithValue(cropper),
        sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
        receiptDatesDayFirstProvider.overrideWithValue(true),
      ]);
    }

    test("reads the cropped copy, and keeps the rotation and crop it read as a pair", () async {
      final container = await createContainer();
      final receipt = await insertReceipt(db);
      await photos.save(receipt.id, Uint8List.fromList([1]));
      final corners = encodeCorners(sampleCorners);

      final scanned = await container.read(receiptScanServiceProvider).scan(
        receipt.copyWith(imageQuarterTurns: 1, cropCorners: Value(corners)),
      );

      expect(cropper.renderedCorners, [sampleCorners], reason: "the cropped copy was made to be read");
      expect(scanner.scannedPaths.single, contains("_crop_"));
      expect(scanner.triedTurns, [0], reason: "the cropped copy is already upright, no other ways round");
      expect(scanned.merchant, "Tesco Express");
      expect((scanned.imageQuarterTurns, scanned.cropCorners), (1, corners));
    });
  });
}
