import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/receipt_providers.dart';
import 'package:expense_tracker/providers/settings_providers.dart';
import 'package:expense_tracker/screens/receipts.dart';
import 'package:expense_tracker/screens/settings.dart';
import 'package:expense_tracker/services/place_finder.dart';
import 'package:expense_tracker/services/receipt_crop.dart';
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

  group("cutting the receipt out of the photo", () {
    Future<void> openWith(WidgetTester tester, {FakeReceiptCropper? cropper, FakeReceiptImagePicker? picker}) async
    {
      await pumpApp(tester, const ReceiptsScreen(), db: db, receiptImages: photos,
        receiptPicker: picker ?? FakeReceiptImagePicker(),
        receiptScanner: FakeReceiptScanner(isAvailable: false),
        receiptCropper: cropper ?? FakeReceiptCropper());
      await tester.pumpAndSettle();
    }

    testWidgets("an imported photo is cropped to the receipt when its edges are clear", (tester) async {
      await openWith(tester, cropper: FakeReceiptCropper(detected: sampleCorners));

      await importReceipt(tester);

      expect((await db.receiptsDao.getAll()).single.cropCorners, encodeCorners(sampleCorners));
    });

    testWidgets("an imported photo with no clear receipt keeps the whole photo", (tester) async {
      await openWith(tester);

      await importReceipt(tester);

      expect((await db.receiptsDao.getAll()).single.cropCorners, isNull);
    });

    testWidgets("document scanner photos aren't cropped again", (tester) async {
      await openWith(tester,
        cropper: FakeReceiptCropper(detected: sampleCorners),
        picker: FakeReceiptImagePicker(canUseCamera: true, canScanDocuments: true));

      await tester.tap(find.text("Add receipt"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Scan receipt"));
      await tester.pumpAndSettle();

      expect((await db.receiptsDao.getAll()).single.cropCorners, isNull);
    });

    Future<Receipt> receiptWithPhoto(String merchant) async
    {
      final receipt = await insertReceipt(db, merchant: merchant);
      await photos.save(receipt.id, Uint8List.fromList([1]));
      return receipt;
    }

    Future<void> openCropEditor(WidgetTester tester, String merchant) async
    {
      await tester.tap(find.widgetWithText(ReceiptCard, merchant));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip("Crop out the background"));
      await tester.pumpAndSettle();
    }

    testWidgets("the crop editor starts on the detected edges, corners can be dragged, Done saves", (tester) async {
      await receiptWithPhoto("Tesco");
      await openWith(tester, cropper: FakeReceiptCropper(detected: sampleCorners));
      await openCropEditor(tester, "Tesco");

      expect(find.text("Crop receipt"), findsOneWidget);
      expect(find.text("Drag the corners onto the receipt's edges."), findsOneWidget);

      await tester.drag(find.byKey(const Key("crop_corner_0")), const Offset(-500, -500));
      await tester.tap(find.text("Done"));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, "Save"));
      await tester.pumpAndSettle();

      final corners = decodeCorners((await db.receiptsDao.getAll()).single.cropCorners)!;
      expect(corners[0], Offset.zero, reason: "dragged all the way to the photo's top-left, and no further");
      expect(corners.sublist(1), sampleCorners.sublist(1), reason: "the other corners stayed put");
    });

    testWidgets("Whole photo undoes the crop", (tester) async {
      final receipt = await receiptWithPhoto("Tesco");
      await db.receiptsDao.updateRow(receipt.copyWith(cropCorners: Value(encodeCorners(sampleCorners))));
      await openWith(tester);
      await openCropEditor(tester, "Tesco");

      await tester.tap(find.text("Whole photo"));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, "Save"));
      await tester.pumpAndSettle();

      expect((await db.receiptsDao.getAll()).single.cropCorners, isNull);
    });

    testWidgets("says so when it couldn't find the receipt's edges", (tester) async {
      await receiptWithPhoto("Tesco");
      await openWith(tester);
      await openCropEditor(tester, "Tesco");

      expect(find.textContaining("Couldn't find the receipt's edges"), findsOneWidget);
      expect(find.text("Auto-detect"), findsNothing);
    });

    testWidgets("rotating a cropped photo turns the crop with it", (tester) async {
      // A crop covering the left half of the photo
      const leftHalf = [Offset(0, 0), Offset(0.5, 0), Offset(0.5, 1), Offset(0, 1)];
      final receipt = await receiptWithPhoto("Tesco");
      await db.receiptsDao.updateRow(receipt.copyWith(cropCorners: Value(encodeCorners(leftHalf))));
      await openWith(tester);

      await tester.tap(find.widgetWithText(ReceiptCard, "Tesco"));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip("Rotate photo"));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, "Save"));
      await tester.pumpAndSettle();

      final saved = (await db.receiptsDao.getAll()).single;
      expect(saved.imageQuarterTurns, 1);
      expect(decodeCorners(saved.cropCorners), rotateCornersClockwise(leftHalf));
    });
  });

  group("location", () {
    Future<Receipt> placed(String merchant, {String? city, String? country}) async
    {
      final receipt = await insertReceipt(db, merchant: merchant);
      await db.receiptsDao.updateRow(receipt.copyWith(city: Value(city), country: Value(country)));
      return receipt;
    }

    Future<void> open(WidgetTester tester) async
    {
      await pumpApp(tester, const ReceiptsScreen(), db: db, receiptImages: photos,
        receiptScanner: FakeReceiptScanner(isAvailable: false));
      await tester.pumpAndSettle();
    }

    testWidgets("cards show where the receipt is from", (tester) async {
      await placed("Pho 24", city: "Hanoi", country: "Vietnam");
      await open(tester);

      expect(find.widgetWithText(ReceiptCard, "Hanoi, Vietnam"), findsOneWidget);
    });

    testWidgets("the place filters only appear once a receipt has a place", (tester) async {
      await placed("No place");
      await open(tester);

      expect(find.text("All countries"), findsNothing);
    });

    testWidgets("picking a country, then a city, narrows the list", (tester) async {
      await placed("Opera Bar", city: "Sydney", country: "Australia");
      await placed("Pho 24", city: "Hanoi", country: "Vietnam");
      await placed("Banh Mi", city: "Ho Chi Minh City", country: "Vietnam");
      await open(tester);
      expect(find.byType(ReceiptCard), findsNWidgets(3));

      await tester.tap(find.text("All countries"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Vietnam").last);
      await tester.pumpAndSettle();
      expect(find.byType(ReceiptCard), findsNWidgets(2));

      // The city menu only lists cities in Vietnam
      await tester.tap(find.text("All cities in Vietnam"));
      await tester.pumpAndSettle();
      expect(find.text("Sydney"), findsNothing);
      await tester.tap(find.text("Hanoi").last);
      await tester.pumpAndSettle();

      expect(find.byType(ReceiptCard), findsOneWidget);
      expect(find.widgetWithText(ReceiptCard, "Pho 24"), findsOneWidget);
    });

    testWidgets("the place is typed in the receipt dialog, with suggestions from earlier receipts", (tester) async {
      await placed("Pho 24", city: "Hanoi", country: "Vietnam");
      await insertReceipt(db, merchant: "New one");
      await open(tester);

      await tester.tap(find.widgetWithText(ReceiptCard, "New one"));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, "City"), "Han");
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, "Hanoi"));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, "Country"), "Vietnam");
      await tester.tap(find.widgetWithText(ElevatedButton, "Save"));
      await tester.pumpAndSettle();

      final saved = (await db.receiptsDao.getAll()).firstWhere((r) => r.merchant == "New one");
      expect((saved.city, saved.state, saved.country), ("Hanoi", null, "Vietnam"));
    });

    testWidgets("typing a shop you've been to before fills in its place", (tester) async {
      await placed("Pho 24", city: "Hanoi", country: "Vietnam");
      await insertReceipt(db, merchant: "Untitled");
      await open(tester);

      await tester.tap(find.widgetWithText(ReceiptCard, "Untitled"));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, "Shop"), "pho 24");
      // Moving on to the next field is what triggers it
      await tester.tap(find.widgetWithText(TextFormField, "Total"));
      await tester.pumpAndSettle();

      expect(fieldText(tester, "City"), "Hanoi");
      expect(fieldText(tester, "Country"), "Vietnam");
    });
  });

  group("use my location", () {
    Future<void> openReceipt(WidgetTester tester, FakePlaceFinder finder) async
    {
      await insertReceipt(db, merchant: "Pho 24");
      await pumpApp(tester, const ReceiptsScreen(), db: db, receiptImages: photos,
        receiptScanner: FakeReceiptScanner(isAvailable: false), placeFinder: finder);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ReceiptCard, "Pho 24"));
      await tester.pumpAndSettle();
    }

    testWidgets("fills in the city, state and country from where the phone is", (tester) async {
      await openReceipt(tester, FakePlaceFinder());

      await tester.enterText(find.widgetWithText(TextFormField, "City"), "Typed before");
      await tester.tap(find.text("Use my location"));
      await tester.pumpAndSettle();

      expect(fieldText(tester, "City"), "Hanoi", reason: "the user asked for it, so it replaces what was there");
      expect(fieldText(tester, "State / region"), "Hà Nội");
      expect(fieldText(tester, "Country"), "Vietnam");

      await tester.tap(find.widgetWithText(ElevatedButton, "Save"));
      await tester.pumpAndSettle();
      final saved = (await db.receiptsDao.getAll()).single;
      expect((saved.city, saved.country), ("Hanoi", "Vietnam"));
    });

    testWidgets("isn't offered where there's no GPS, like Windows", (tester) async {
      await openReceipt(tester, FakePlaceFinder(isAvailable: false));

      expect(find.text("Use my location"), findsNothing);
    });

    testWidgets("says why when it can't, and leaves the fields alone", (tester) async {
      final finder = FakePlaceFinder(problem: PlaceProblem.locationOff);
      await openReceipt(tester, finder);
      await tester.enterText(find.widgetWithText(TextFormField, "City"), "Kept");

      await tester.tap(find.text("Use my location"));
      await tester.pumpAndSettle();

      expect(find.text("Location is turned off on this phone. Turn it on and try again."), findsOneWidget);
      expect(fieldText(tester, "City"), "Kept");
    });

    testWidgets("a blocked permission offers a way to the phone's settings", (tester) async {
      final finder = FakePlaceFinder(problem: PlaceProblem.permissionBlocked);
      await openReceipt(tester, finder);

      await tester.tap(find.text("Use my location"));
      await tester.pumpAndSettle();
      // NOTE: Inside the form, not a snackbar behind the dialog where it couldn't be tapped
      await tester.tap(find.descendant(of: find.byKey(const Key("location_problem")), matching: find.text("Settings")));
      await tester.pumpAndSettle();

      expect(finder.settingsOpened, 1);
    });
  });

  testWidgets("stickers on the board show the city under the name, or the country without one", (tester) async {
    final hanoi = await insertReceipt(db, merchant: "Pho 24", isFavorite: true, boardX: 40, boardY: 40);
    await db.receiptsDao.updateRow(hanoi.copyWith(city: const Value("Hanoi"), country: const Value("Vietnam")));
    final countryOnly = await insertReceipt(db, merchant: "Duty free", isFavorite: true, boardX: 300, boardY: 40);
    await db.receiptsDao.updateRow(countryOnly.copyWith(country: const Value("Japan")));
    final nowhere = await insertReceipt(db, merchant: "Somewhere", isFavorite: true, boardX: 560, boardY: 40);

    await pumpApp(tester, const Scaffold(body: ReceiptBoardView()), db: db, receiptImages: photos);
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.byKey(Key("sticker_place_${hanoi.id}"))).data, "Hanoi");
    expect(tester.widget<Text>(find.byKey(Key("sticker_place_${countryOnly.id}"))).data, "Japan");
    expect(find.byKey(Key("sticker_place_${nowhere.id}")), findsNothing);
  });
}
