import 'dart:async';

import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/sync_providers.dart';
import 'package:expense_tracker/widgets/sync_status_button.dart';
import 'package:expense_tracker/widgets/sync_triggers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';
import '../helpers/test_database.dart';

void main()
{
  late AppDatabase db;
  late FakeSyncEngine engine;

  setUp(() {
    db = createTestDatabase();
    engine = FakeSyncEngine();
  });
  tearDown(() => db.close());

  const Widget screen = SyncTriggers(
    child: Scaffold(body: Center(child: SyncStatusButton())),
  );

  testWidgets("syncs once as soon as it appears", (tester) async {
    await pumpApp(tester, screen, db: db, syncEngine: engine);
    await tester.pumpAndSettle();

    expect(engine.syncedUserIds, [userA]);
    expect(find.byIcon(Icons.cloud_done), findsOneWidget);
  });

  testWidgets("syncs again when the network comes back", (tester) async {
    final connectivity = StreamController<bool>();
    addTearDown(connectivity.close);

    await pumpApp(tester, screen, db: db, syncEngine: engine, connectivity: connectivity.stream);
    connectivity.add(false);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    final syncsWhileOffline = engine.syncedUserIds.length;

    connectivity.add(true);
    await tester.pumpAndSettle();

    expect(engine.syncedUserIds.length, syncsWhileOffline + 1);
    expect(find.byIcon(Icons.cloud_off), findsNothing);
  });

  testWidgets("a local change is synced a few seconds later", (tester) async {
    await pumpApp(tester, screen, db: db, syncEngine: engine);
    await tester.pumpAndSettle();
    expect(engine.syncedUserIds, hasLength(1));

    // NOTE: DB writes are real async work, so let them (and Drift re-running the
    // pending-changes query) finish outside the fake clock. Then the first pump delivers
    // the new count to the provider, and the second one redraws the widget with it
    await tester.runAsync(() async {
      await insertCategory(db, name: "Food");
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump();

    // The badge shows 1 change waiting
    expect(find.text("1"), findsOneWidget);
    expect(find.byIcon(Icons.cloud_upload), findsOneWidget);

    // NOTE: In widget tests time is fake, pump(duration) jumps the clock forward
    await tester.pump(SyncController.debounceDelay - const Duration(milliseconds: 100));
    expect(engine.syncedUserIds, hasLength(1), reason: "still waiting for more edits");

    await tester.pump(const Duration(milliseconds: 200));
    expect(engine.syncedUserIds, hasLength(2));
  });

  testWidgets("tapping the cloud icon syncs right away", (tester) async {
    await pumpApp(tester, screen, db: db, syncEngine: engine);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SyncStatusButton));
    await tester.pumpAndSettle();

    expect(engine.syncedUserIds, hasLength(2));
  });

  testWidgets("shows when a sync failed", (tester) async {
    engine.failWith = Exception("Supabase is down");

    await pumpApp(tester, screen, db: db, syncEngine: engine);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.sync_problem), findsOneWidget);
  });

  testWidgets("tapping the cloud icon says when everything synced", (tester) async {
    await pumpApp(tester, screen, db: db, syncEngine: engine);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SyncStatusButton));
    await tester.pumpAndSettle();

    expect(find.text("Everything is synced"), findsOneWidget);
  });

  testWidgets("tapping the cloud icon shows why a sync failed", (tester) async {
    await pumpApp(tester, screen, db: db, syncEngine: engine);
    await tester.pumpAndSettle();
    engine.failWith = Exception("Supabase is down");

    await tester.tap(find.byType(SyncStatusButton));
    await tester.pumpAndSettle();

    expect(find.textContaining("Sync failed"), findsOneWidget);
    expect(find.textContaining("Supabase is down"), findsOneWidget);
  });

  testWidgets("tapping the cloud icon while offline says the changes will wait", (tester) async {
    await pumpApp(tester, screen, db: db, syncEngine: engine, isOnline: false);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SyncStatusButton));
    await tester.pumpAndSettle();

    expect(find.textContaining("You're offline"), findsOneWidget);
  });
}
