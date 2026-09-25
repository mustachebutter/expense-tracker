import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/core_providers.dart';
import 'package:expense_tracker/sync_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'test_database.dart';

// NOTE: Stands in for the real SyncEngine so widget tests never call Supabase.
// It just records that a sync was requested, and for which user
class FakeSyncEngine implements SyncEngine
{
  final List<String> syncedUserIds = [];

  @override
  Future<void> runStartUpSync(String userId) async => syncedUserIds.add(userId);

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
  List<Override> extraOverrides = const [],
}) async
{
  // NOTE: The default test screen is 800x600, which is small for the Dashboard.
  // Make it a big desktop window and put it back after the test
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final authEvent = userId == null ? AuthChangeEvent.signedOut : AuthChangeEvent.signedIn;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        currentUserIdProvider.overrideWithValue(userId),
        authStateProvider.overrideWith((ref) => Stream.value(AuthState(authEvent, null))),
        syncEngineProvider.overrideWithValue(syncEngine ?? FakeSyncEngine()),
        ...extraOverrides,
      ],
      child: MaterialApp(home: child),
    ),
  );
}
