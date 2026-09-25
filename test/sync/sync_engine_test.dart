import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:expense_tracker/daos/transactions_dao.dart';
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_sync_remote.dart';
import '../helpers/test_database.dart';

// NOTE: Drift stores DateTime in whole seconds, so test times are whole seconds too
final DateTime t0 = DateTime(2026, 3, 1, 12, 0, 0);

Map<String, dynamic> categoryJson({
  required String id,
  required String name,
  required DateTime updatedAt,
  String userId = userA,
}) => {
  "id": id,
  "name": name,
  "color_hex": "4CAF50",
  "icon_key": "restaurant",
  "type": TransactionType.expense.index,
  "user_id": userId,
  "is_active": true,
  "is_deleted": false,
  "updated_at": updatedAt.toUtc().toIso8601String(),
};

Future<Category> getCategory(AppDatabase db, String id)
{
  return (db.select(db.categories)..where((t) => t.id.equals(id))).getSingle();
}

// Same thing an edit screen would do: change the row, mark it dirty, move updatedAt forward
Future<void> renameCategoryLocally(AppDatabase db, String id, String newName, {DateTime? at}) async
{
  final row = await getCategory(db, id);
  await db.categoriesDao.updateRow(row.copyWith(
    name: newName,
    isSynced: false,
    updatedAt: at ?? nextUpdatedAt(row.updatedAt),
  ));
}

void main()
{
  late AppDatabase db;
  late FakeSyncRemote remote;
  late SyncEngine engine;

  setUp(() {
    db = createTestDatabase();
    remote = FakeSyncRemote();
    engine = SyncEngine(db, remote);
  });

  tearDown(() => db.close());

  group("push", () {
    test("uploads every unsynced row and marks it synced", () async {
      final food = await insertCategory(db, name: "Food");
      await insertTransaction(db, name: "Lunch", categoryId: food.id, date: t0);
      await db.into(db.savingsGoals).insert(
        SavingsGoalsCompanion.insert(name: "Holiday", targetAmount: 1000, currentSavedAmount: 50, userId: userA),
      );
      await db.into(db.investments).insert(
        InvestmentsCompanion.insert(name: "Index fund", amount: 500, userId: userA),
      );

      await engine.runSync(userA);

      expect(remote.rows("categories"), hasLength(1));
      expect(remote.rows("transactions"), hasLength(1));
      expect(remote.rows("savings_goals"), hasLength(1));
      expect(remote.rows("investments"), hasLength(1));

      // The server copy has what other devices need to rebuild the row, and no local-only flags
      final uploaded = remote.rows("categories").single;
      expect(uploaded["type"], TransactionType.expense.index);
      expect(uploaded["updated_at"], isNotNull);
      expect(uploaded.containsKey("is_synced"), isFalse);

      expect((await getCategory(db, food.id)).isSynced, isTrue);
      expect((await db.transactionsDao.getUnsynced(userA)), isEmpty);
      expect((await db.savingsGoalsDao.getUnsynced(userA)), isEmpty);
      expect((await db.investmentsDao.getUnsynced(userA)), isEmpty);
    });

    // NOTE: Regression test for the old markAsSynced, which wrote back the copy it read
    // BEFORE the upload and silently threw away this edit
    test("an edit made while the upload is in flight is not lost", () async {
      final food = await insertCategory(db, name: "Food");

      remote.runDuringNextUpsert("categories", () => renameCategoryLocally(db, food.id, "Groceries"));
      await engine.runSync(userA);

      // The server got the old name, but locally the rename survived and is still waiting to go up
      expect(remote.rows("categories").single["name"], "Food");
      final local = await getCategory(db, food.id);
      expect(local.name, "Groceries");
      expect(local.isSynced, isFalse);

      await engine.runSync(userA);

      expect(remote.rows("categories").single["name"], "Groceries");
      expect((await getCategory(db, food.id)).isSynced, isTrue);
    });

    test("one failing table doesn't stop the others, and its rows stay unsynced", () async {
      final food = await insertCategory(db, name: "Food");
      await insertTransaction(db, name: "Lunch", categoryId: food.id, date: t0);
      remote.failingTables.add("transactions");

      await expectLater(engine.runSync(userA), throwsA(isA<SyncException>()));

      expect(remote.rows("categories"), hasLength(1));
      expect(await db.transactionsDao.getUnsynced(userA), hasLength(1));

      // Back online: the next sync picks up where it left off
      remote.failingTables.clear();
      await engine.runSync(userA);

      expect(remote.rows("transactions"), hasLength(1));
      expect(await db.transactionsDao.getUnsynced(userA), isEmpty);
    });
  });

  group("pull", () {
    test("saves server rows as synced and only asks for changes since the last pull", () async {
      remote.seed("categories", categoryJson(id: "c1", name: "Food", updatedAt: t0));

      await engine.runSync(userA);

      final food = await getCategory(db, "c1");
      expect(food.name, "Food");
      expect(food.isSynced, isTrue);
      expect(food.updatedAt, t0);

      remote.seed("categories", categoryJson(id: "c2", name: "Travel", updatedAt: t0));
      await engine.runSync(userA);

      final categoryFetches = remote.fetchCalls.where((call) => call.table == "categories").toList();
      expect(categoryFetches.first.since, isNull, reason: "first sync downloads everything");
      expect(categoryFetches.last.since, isNotNull, reason: "later syncs only download changes");
      expect((await getCategory(db, "c2")).name, "Travel");
    });

    test("each user on the device has their own sync position", () async {
      remote.seed("categories", categoryJson(id: "c1", name: "Food", updatedAt: t0));
      await engine.runSync(userA);

      await engine.runSync(userB);

      final userBFetch = remote.fetchCalls.lastWhere((call) => call.table == "categories");
      expect(userBFetch.since, isNull);
    });

    test("a template deleted on another device is deleted here too", () async {
      final food = await insertCategory(db, name: "Food", isSynced: true);
      final rent = await insertTemplate(db, name: "Rent", categoryId: food.id, billingDay: 1, startDate: DateTime(2025, 1, 1));
      await db.templatesDao.markAsSynced(rent.id, rent.updatedAt);

      remote.seed("templates", {
        "id": rent.id,
        "name": "Rent",
        "amount": rent.amount,
        "start_date": rent.startDate.toUtc().toIso8601String(),
        "billing_day": 1,
        "type": TransactionType.expense.index,
        "category_id": food.id,
        "user_id": userA,
        "is_active": true,
        "is_deleted": true,
        "updated_at": rent.updatedAt.add(const Duration(minutes: 5)).toUtc().toIso8601String(),
      });

      await engine.runSync(userA);

      final local = await (db.select(db.templates)..where((t) => t.id.equals(rent.id))).getSingle();
      expect(local.isDeleted, isTrue);
      // And a deleted template doesn't generate anything
      expect(await db.transactionsDao.getAll(), isEmpty);
    });
  });

  group("conflicts (last write wins)", () {
    test("a newer edit from another device replaces an older local edit", () async {
      await insertCategory(db, id: "c1", name: "Food", updatedAt: t0, isSynced: true);
      remote.seed("categories", categoryJson(id: "c1", name: "From phone", updatedAt: t0.add(const Duration(minutes: 10))));
      await renameCategoryLocally(db, "c1", "From PC", at: t0.add(const Duration(minutes: 5)));

      await engine.runSync(userA);

      final local = await getCategory(db, "c1");
      expect(local.name, "From phone");
      expect(local.isSynced, isTrue);
      expect(remote.rows("categories").single["name"], "From phone");
    });

    test("a newer local edit is kept and uploaded", () async {
      await insertCategory(db, id: "c1", name: "Food", updatedAt: t0, isSynced: true);
      remote.seed("categories", categoryJson(id: "c1", name: "From phone", updatedAt: t0.add(const Duration(minutes: 5))));
      await renameCategoryLocally(db, "c1", "From PC", at: t0.add(const Duration(minutes: 10)));

      await engine.runSync(userA);

      final local = await getCategory(db, "c1");
      expect(local.name, "From PC");
      expect(local.isSynced, isTrue);
      expect(remote.rows("categories").single["name"], "From PC");
    });
  });

  group("fixed transactions", () {
    test("two offline devices generating the same month end up with one transaction", () async {
      final deviceB = createTestDatabase();
      addTearDown(deviceB.close);
      final engineB = SyncEngine(deviceB, remote);

      // Both devices already have the same category and template from an earlier sync
      for (final device in [db, deviceB])
      {
        final food = await insertCategory(device, id: "cat-1", name: "Food", isSynced: true);
        final rent = await insertTemplate(device, id: "tpl-1", name: "Rent", categoryId: food.id, billingDay: 1, startDate: DateTime(2025, 1, 1));
        await device.templatesDao.markAsSynced(rent.id, rent.updatedAt);
      }

      // Both go offline and generate this month's rent on their own
      await engine.syncAllTransactionsFromTemplates(userA);
      await engineB.syncAllTransactionsFromTemplates(userA);

      // Then both come back online
      await engine.runSync(userA);
      await engineB.runSync(userA);
      await engine.runSync(userA);

      final now = DateTime.now();
      final expectedId = fixedTransactionId("tpl-1", now.year, now.month);

      expect(remote.rows("transactions").map((row) => row["id"]), [expectedId]);
      expect((await db.transactionsDao.getAll()).map((t) => t.id), [expectedId]);
      expect((await deviceB.transactionsDao.getAll()).map((t) => t.id), [expectedId]);
    });
  });

  test("nextUpdatedAt always moves forward by at least a second", () {
    final previous = DateTime.now().add(const Duration(minutes: 1)); // e.g. a clock that was ahead

    expect(nextUpdatedAt(previous), previous.add(const Duration(seconds: 1)));
    expect(nextUpdatedAt(t0).isAfter(t0), isTrue);
  });
}
