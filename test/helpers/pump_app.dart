import 'dart:async';

import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/core_providers.dart';
import 'package:expense_tracker/providers/receipt_crop_providers.dart';
import 'package:expense_tracker/providers/receipt_providers.dart';
import 'package:expense_tracker/providers/receipt_scan_providers.dart';
import 'package:expense_tracker/providers/settings_providers.dart';
import 'package:expense_tracker/services/receipt_scanner.dart';
import 'package:expense_tracker/providers/sync_providers.dart';
import 'package:expense_tracker/sync_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_receipts.dart';
import 'test_database.dart';

// NOTE: Stands in for the real SyncEngine so these tests never call Supabase.
// It records that a sync was requested, and for which user
class FakeSyncEngine implements SyncEngine
{
  final List<String> syncedUserIds = [];

  // Set to make the next syncs fail
  Object? failWith;

  // Set to make syncs wait until the test completes it, to test "sync already running"
  Completer<void>? gate;

  @override
  Future<void> runSync(String userId) async
  {
    syncedUserIds.add(userId);
    if (gate != null) await gate!.future;
    if (failWith != null) throw failWith!;
  }

  // Any other SyncEngine method a test didn't expect ends up here and fails loudly
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Renders [child] the same way main.dart does (ProviderScope + MaterialApp),
// but with the database, auth and sync swapped for test versions
Future<void> pumpApp(
  WidgetTester tester,
  Widget child, {
  required AppDatabase db,
  String? userId = userA,
  FakeSyncEngine? syncEngine,
  bool isOnline = true,
  // Pass a stream instead of isOnline to go on/offline in the middle of a test
  Stream<bool>? connectivity,
  FakeReceiptImageStore? receiptImages,
  FakeReceiptImagePicker? receiptPicker,
  FakeReceiptCropper? receiptCropper,
  // No GPS by default, like Windows
  FakePlaceFinder? placeFinder,
  // By default there's no scanner, like Windows. Pass a FakeReceiptScanner to act like a phone
  ReceiptScanner? receiptScanner,
  Map<String, Object> preferences = const {},
  List<Override> extraOverrides = const [],
}) async
{
  // NOTE: The default test screen is 800x600, which is small for the Dashboard.
  // Make it a big desktop window and put it back after the test
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final authEvent = userId == null ? AuthChangeEvent.signedOut : AuthChangeEvent.signedIn;

  // NOTE: A fresh, in-memory set of saved settings for every test
  SharedPreferences.setMockInitialValues(preferences);
  final sharedPreferences = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        currentUserIdProvider.overrideWithValue(userId),
        authStateProvider.overrideWith((ref) => Stream.value(AuthState(authEvent, null))),
        syncEngineProvider.overrideWithValue(syncEngine ?? FakeSyncEngine()),
        connectivityProvider.overrideWith((ref) => connectivity ?? Stream.value(isOnline)),
        receiptImageStoreProvider.overrideWithValue(receiptImages ?? FakeReceiptImageStore()),
        receiptImagePickerProvider.overrideWithValue(receiptPicker ?? FakeReceiptImagePicker()),
        receiptCropperProvider.overrideWithValue(receiptCropper ?? FakeReceiptCropper()),
        placeFinderProvider.overrideWithValue(placeFinder ?? FakePlaceFinder(isAvailable: false)),
        receiptPhotoShrinkerProvider.overrideWithValue(FakeReceiptPhotoShrinker()),
        receiptScannerProvider.overrideWithValue(receiptScanner ?? FakeReceiptScanner(isAvailable: false)),
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        // Tests read dates day first, whatever the machine running them is set to
        receiptDatesDayFirstProvider.overrideWithValue(true),
        ...extraOverrides,
      ],
      child: MaterialApp(home: child),
    ),
  );
}
