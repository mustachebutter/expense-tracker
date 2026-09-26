import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/core_providers.dart';
import 'package:expense_tracker/providers/receipt_providers.dart';
import 'package:expense_tracker/services/place_finder.dart';
import 'package:expense_tracker/services/receipt_photo_shrinker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_receipts.dart';
import '../helpers/test_database.dart';

// Etobicoke, Toronto
const double lat = 43.6205, lon = -79.5132;

void main()
{
  late AppDatabase db;
  late FakeReceiptPhotoShrinker shrinker;

  setUp(() {
    db = createTestDatabase();
    shrinker = FakeReceiptPhotoShrinker(details: (takenAt: DateTime(2026, 9, 12, 14, 32), latitude: lat, longitude: lon));
  });
  tearDown(() => db.close());

  ProviderContainer createContainer(FakePlaceFinder finder)
  {
    return ProviderContainer.test(overrides: [
      databaseProvider.overrideWithValue(db),
      currentUserIdProvider.overrideWithValue(userA),
      receiptImageStoreProvider.overrideWithValue(FakeReceiptImageStore()),
      receiptPhotoShrinkerProvider.overrideWithValue(shrinker),
      placeFinderProvider.overrideWithValue(finder),
    ]);
  }

  Future<Receipt> reload(String id) async => (await db.receiptsDao.getReceiptById(id, userA))!;

  group("adding a photo that has EXIF details", () {
    test("on a phone, the place is named straight away, suburb included, and no coordinates are kept", () async {
      final finder = FakePlaceFinder();
      final container = createContainer(finder);

      final receipt = await container.read(receiptActionsProvider).addFromImage(Uint8List(1));

      final saved = await reload(receipt.id);
      expect((saved.suburb, saved.city, saved.state, saved.country), ("Etobicoke", "Toronto", "Ontario", "Canada"));
      expect((saved.pendingLatitude, saved.pendingLongitude), (null, null));
      expect(finder.namedCoordinates, [(lat, lon)]);
    });

    test("the date the photo was taken becomes the receipt date", () async {
      final container = createContainer(FakePlaceFinder());

      final receipt = await container.read(receiptActionsProvider).addFromImage(Uint8List(1));

      expect((await reload(receipt.id)).date, DateTime(2026, 9, 12, 14, 32));
    });

    test("on Windows, the coordinates wait for the phone", () async {
      final container = createContainer(FakePlaceFinder(isAvailable: false));

      final receipt = await container.read(receiptActionsProvider).addFromImage(Uint8List(1));

      final saved = await reload(receipt.id);
      expect((saved.pendingLatitude, saved.pendingLongitude), (lat, lon));
      expect(saved.city, isNull);
    });

    test("on a phone without internet, they wait too", () async {
      final finder = FakePlaceFinder()..coordinatesProblem = PlaceProblem.noPlaceName;
      final container = createContainer(finder);

      final receipt = await container.read(receiptActionsProvider).addFromImage(Uint8List(1));

      expect((await reload(receipt.id)).pendingLatitude, lat);
    });

    test("a photo without GPS or a date adds nothing", () async {
      shrinker.details = noPhotoDetails;
      final finder = FakePlaceFinder();
      final container = createContainer(finder);

      final receipt = await container.read(receiptActionsProvider).addFromImage(Uint8List(1));

      final saved = await reload(receipt.id);
      expect((saved.date, saved.city, saved.pendingLatitude), (null, null, null));
      expect(finder.namedCoordinates, isEmpty);
    });
  });

  group("the phone naming places that wait", () {
    Future<Receipt> waiting({String? typedCity}) async
    {
      final receipt = await insertReceipt(db);
      await db.receiptsDao.updateRow(receipt.copyWith(
        city: Value(typedCity),
        pendingLatitude: const Value(lat),
        pendingLongitude: const Value(lon),
      ));
      return reload(receipt.id);
    }

    test("fills in the place and forgets the coordinates", () async {
      final receipt = await waiting();
      final container = createContainer(FakePlaceFinder());

      expect(await container.read(receiptPlaceNamerProvider).nameWaiting(), 1);

      final saved = await reload(receipt.id);
      expect((saved.suburb, saved.city), ("Etobicoke", "Toronto"));
      expect((saved.pendingLatitude, saved.pendingLongitude), (null, null));
      expect(saved.isSynced, isFalse, reason: "the named place has to sync back to the PC");
    });

    test("keeps a place that was typed meanwhile, but still forgets the coordinates", () async {
      final receipt = await waiting(typedCity: "Mississauga");
      final container = createContainer(FakePlaceFinder());

      await container.read(receiptPlaceNamerProvider).nameWaiting();

      final saved = await reload(receipt.id);
      expect((saved.suburb, saved.city), (null, "Mississauga"));
      expect(saved.pendingLatitude, isNull);
    });

    test("leaves it waiting when it can't name it yet", () async {
      final receipt = await waiting();
      final container = createContainer(FakePlaceFinder()..coordinatesProblem = PlaceProblem.noPlaceName);

      expect(await container.read(receiptPlaceNamerProvider).nameWaiting(), 0);

      expect((await reload(receipt.id)).pendingLatitude, lat);
    });

    test("does nothing on Windows", () async {
      await waiting();
      final finder = FakePlaceFinder(isAvailable: false);
      final container = createContainer(finder);

      expect(await container.read(receiptPlaceNamerProvider).nameWaiting(), 0);
      expect(finder.namedCoordinates, isEmpty);
    });
  });

  group("filtering by suburb", () {
    Future<void> placed(String merchant, String suburb, String city) async
    {
      final receipt = await insertReceipt(db, merchant: merchant);
      await db.receiptsDao.updateRow(receipt.copyWith(suburb: Value(suburb), city: Value(city), country: const Value("Canada")));
    }

    test("suburbs follow the chosen city, and picking a city resets the suburb", () async {
      await placed("A", "Etobicoke", "Toronto");
      await placed("B", "Scarborough", "Toronto");
      await placed("C", "Plateau", "Montreal");
      final container = createContainer(FakePlaceFinder());
      container.listen(filteredReceiptsProvider, (previous, next) {});
      container.listen(receiptPlacesProvider, (previous, next) {});
      await container.read(receiptsProvider.future);
      final filter = container.read(receiptFilterProvider.notifier);

      filter.selectCity("Toronto");
      expect(container.read(receiptPlacesProvider).suburbs, ["Etobicoke", "Scarborough"]);

      filter.selectSuburb("Etobicoke");
      expect(container.read(filteredReceiptsProvider).value!.map((r) => r.merchant), ["A"]);

      filter.selectCity("Montreal");
      expect(container.read(receiptFilterProvider).suburb, isNull);
      expect(container.read(receiptPlacesProvider).suburbs, ["Plateau"]);
    });
  });
}
