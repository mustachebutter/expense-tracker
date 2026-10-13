import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/core_providers.dart';
import 'package:expense_tracker/providers/receipt_providers.dart';
import 'package:expense_tracker/providers/receipt_scan_providers.dart';
import 'package:expense_tracker/providers/settings_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_receipts.dart';
import '../helpers/test_database.dart';

void main()
{
  late AppDatabase db;
  late FakeReceiptImageStore photos;
  late FakeReceiptScanner scanner;

  setUp(() {
    db = createTestDatabase();
    photos = FakeReceiptImageStore();
    scanner = FakeReceiptScanner(rows: const ["TESCO EXPRESS", "TOTAL 3.06"]);
  });
  tearDown(() => db.close());

  Future<ProviderContainer> createContainer() async
  {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer.test(overrides: [
      databaseProvider.overrideWithValue(db),
      currentUserIdProvider.overrideWithValue(userA),
      receiptImageStoreProvider.overrideWithValue(photos),
      receiptScannerProvider.overrideWithValue(scanner),
      sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
      receiptDatesDayFirstProvider.overrideWithValue(true),
    ]);
    container.listen(filteredReceiptsProvider, (previous, next) {});
    container.listen(receiptPlacesProvider, (previous, next) {});
    return container;
  }

  Future<Receipt> placed(String merchant, {String? city, String? state, String? country}) async
  {
    final receipt = await insertReceipt(db, merchant: merchant);
    await db.receiptsDao.updateRow(receipt.copyWith(city: Value(city), state: Value(state), country: Value(country)));
    return (await db.receiptsDao.getReceiptById(receipt.id, userA))!;
  }

  Future<List<String?>> shown(ProviderContainer container) async
  {
    await container.read(receiptsProvider.future);
    return container.read(filteredReceiptsProvider).value!.map((r) => r.merchant).toList();
  }

  group("filtering by place", () {
    test("by country, then by a city in it", () async {
      await placed("Opera Bar", city: "Sydney", country: "Australia");
      await placed("Pho 24", city: "Hanoi", country: "Vietnam");
      await placed("Banh Mi", city: "Ho Chi Minh City", country: "Vietnam");
      await placed("No place");
      final container = await createContainer();
      final filter = container.read(receiptFilterProvider.notifier);

      filter.selectCountry("Vietnam");
      expect(await shown(container), unorderedEquals(["Pho 24", "Banh Mi"]));

      filter.selectCity("Hanoi");
      expect(await shown(container), ["Pho 24"]);

      // Picking another country clears the city, Hanoi isn't in Australia
      filter.selectCountry("Australia");
      expect(container.read(receiptFilterProvider).city, isNull);
      expect(await shown(container), ["Opera Bar"]);

      filter.selectCountry(null);
      expect(await shown(container), hasLength(4));
    });

    test("ignores capitals and stray spaces, it's free text", () async {
      await placed("A", city: "Sydney", country: "Australia");
      await placed("B", city: " sydney ", country: "AUSTRALIA");
      final container = await createContainer();

      container.read(receiptFilterProvider.notifier).selectCity("SYDNEY");

      expect(await shown(container), unorderedEquals(["A", "B"]));
    });
  });

  test("the place lists have each place once, as first written, in order, and cities follow the country", () async {
    await placed("A", city: "Sydney", state: "NSW", country: "Australia");
    await placed("B", city: "sydney", country: "australia");
    await placed("C", city: "Melbourne", state: "VIC", country: "Australia");
    await placed("D", city: "Hanoi", country: "Vietnam");
    final container = await createContainer();
    await container.read(receiptsProvider.future);

    var places = container.read(receiptPlacesProvider);
    expect(places.countries, ["Australia", "Vietnam"]);
    expect(places.states, ["NSW", "VIC"]);
    expect(places.cities, ["Hanoi", "Melbourne", "Sydney"]);

    container.read(receiptFilterProvider.notifier).selectCountry("Vietnam");
    places = container.read(receiptPlacesProvider);
    expect(places.cities, ["Hanoi"], reason: "only cities in the picked country");
    expect(container.read(allReceiptPlacesProvider).cities, hasLength(3), reason: "suggestions still know every city");
  });

  group("same shop, same place", () {
    test("locationUsedBefore finds the most recent receipt from the shop that has a place", () async {
      final older = await placed("Tesco", city: "London", country: "UK");
      // NOTE: Times are stored in whole seconds, so make "older" clearly older
      await db.receiptsDao.updateRow(older.copyWith(updatedAt: DateTime(2026, 1, 1)));
      final newer = await placed("TESCO", city: "Manchester", country: "UK");
      await placed("Tesco"); // no place, doesn't count
      final gone = await placed("Tesco", city: "Leeds", country: "UK");
      await db.receiptsDao.softDeleteById(gone.id, userA);

      final found = await db.receiptsDao.locationUsedBefore("tesco", userA);
      expect(found?.city, "Manchester");
      expect(await db.receiptsDao.locationUsedBefore("tesco", userA, exceptId: newer.id).then((r) => r?.city), "London");
      expect(await db.receiptsDao.locationUsedBefore("Aldi", userA), isNull);
    });

    test("a scanned receipt gets the place from the last receipt at that shop", () async {
      await placed("Tesco Express", city: "London", state: "England", country: "UK");
      final container = await createContainer();
      final receipt = await insertReceipt(db);
      await photos.save(receipt.id, Uint8List.fromList([1]));

      final scanned = await container.read(receiptScanServiceProvider).scan(receipt);

      expect((scanned.city, scanned.state, scanned.country), ("London", "England", "UK"));
    });

    test("but never replaces a place that was already typed", () async {
      await placed("Tesco Express", city: "London", country: "UK");
      final container = await createContainer();
      final receipt = await placed("", country: "France");
      await photos.save(receipt.id, Uint8List.fromList([1]));

      final scanned = await container.read(receiptScanServiceProvider).scan(receipt.copyWith(merchant: const Value(null)));

      expect((scanned.city, scanned.country), (null, "France"));
    });
  });
}
