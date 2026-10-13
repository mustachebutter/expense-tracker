import 'dart:async';

import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/core_providers.dart';
import 'package:expense_tracker/providers/sync_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  ProviderContainer createContainer({String? userId = userA, bool isOnline = true})
  {
    return ProviderContainer.test(
      overrides: [
        databaseProvider.overrideWithValue(db),
        currentUserIdProvider.overrideWithValue(userId),
        syncEngineProvider.overrideWithValue(engine),
        isOnlineProvider.overrideWithValue(isOnline),
      ],
    );
  }

  test("a successful sync goes back to idle and remembers when it happened", () async {
    final container = createContainer();

    await container.read(syncControllerProvider.notifier).syncNow();

    expect(engine.syncedUserIds, [userA]);
    final state = container.read(syncControllerProvider);
    expect(state.status, SyncStatus.idle);
    expect(state.lastSyncedAt, isNotNull);
  });

  test("doesn't try to sync while offline", () async {
    final container = createContainer(isOnline: false);

    await container.read(syncControllerProvider.notifier).syncNow();

    expect(engine.syncedUserIds, isEmpty);
    expect(container.read(syncControllerProvider).status, SyncStatus.offline);
  });

  test("doesn't sync when nobody is signed in", () async {
    final container = createContainer(userId: null);

    await container.read(syncControllerProvider.notifier).syncNow();

    expect(engine.syncedUserIds, isEmpty);
  });

  test("a failed sync shows the error, and the next one clears it", () async {
    final container = createContainer();
    engine.failWith = Exception("Supabase is down");

    await container.read(syncControllerProvider.notifier).syncNow();

    expect(container.read(syncControllerProvider).status, SyncStatus.error);
    expect(container.read(syncControllerProvider).errorMessage, contains("Supabase is down"));

    engine.failWith = null;
    await container.read(syncControllerProvider.notifier).syncNow();

    expect(container.read(syncControllerProvider).status, SyncStatus.idle);
    expect(container.read(syncControllerProvider).errorMessage, isNull);
  });

  test("requests during a running sync are merged into one more sync", () async {
    final container = createContainer();
    final controller = container.read(syncControllerProvider.notifier);
    engine.gate = Completer<void>();

    final first = controller.syncNow();
    // NOTE: A sync first checks for receipts to scan, let that finish before looking
    await pumpEventQueue();
    expect(container.read(syncControllerProvider).status, SyncStatus.syncing);

    // Three more requests arrive while the first sync is still running...
    controller.syncNow();
    controller.syncNow();
    controller.syncNow();

    engine.gate!.complete();
    await first;

    // ...and they become ONE follow up sync, not three
    expect(engine.syncedUserIds, hasLength(2));
  });

  test("scheduleSync waits, and a burst of calls becomes one sync", () async {
    final container = createContainer();
    final controller = container.read(syncControllerProvider.notifier);

    controller.scheduleSync(delay: const Duration(milliseconds: 50));
    controller.scheduleSync(delay: const Duration(milliseconds: 50));
    controller.scheduleSync(delay: const Duration(milliseconds: 50));

    expect(engine.syncedUserIds, isEmpty, reason: "nothing happens before the delay");

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(engine.syncedUserIds, hasLength(1));
  });

  test("pendingChangesProvider counts unsynced rows across tables", () async {
    final container = createContainer();
    container.listen(pendingChangesProvider, (previous, next) {});

    final food = await insertCategory(db, name: "Food");
    await insertTransaction(db, name: "Lunch", categoryId: food.id, date: DateTime(2026, 3, 1));
    await insertCategory(db, name: "Synced already", isSynced: true);
    await insertCategory(db, name: "Someone else's", userId: userB);

    expect(await container.read(pendingChangesProvider.future), 2);
  });
}
