import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:expense_tracker/database.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/schema_v1.dart';
import '../helpers/test_database.dart';

// The receipt columns each schema version added. To make an "old" database for a test,
// build today's schema and drop every column added after the version being tested
const Map<int, List<String>> receiptColumnsAddedIn = {
  5: ["image_uploaded"],
  6: ["image_quarter_turns", "split_people", "split_amount"],
  7: ["crop_corners"],
  8: ["city", "state", "country"],
  9: ["suburb", "pending_latitude", "pending_longitude"],
};

Future<void> dropReceiptColumnsAfter(AppDatabase db, int version) async
{
  for (final entry in receiptColumnsAddedIn.entries)
  {
    if (entry.key <= version) continue;
    for (final column in entry.value)
    {
      await db.customStatement("ALTER TABLE receipts DROP COLUMN $column");
    }
  }
  await db.customStatement("PRAGMA user_version = $version");
}

void main()
{
  // NOTE: This simulates a user updating the app. Their db.sqlite is still on version 1,
  // so opening it with the new AppDatabase must run onUpgrade without losing anything
  test("upgrading a version 1 database keeps every row and adds the sync columns", () async {
    final before = DateTime.now().subtract(const Duration(seconds: 1));

    final db = AppDatabase.forTesting(NativeDatabase.memory(setup: (rawDb) {
      // Only build the old tables the first time, setup runs every time the connection opens
      if (rawDb.userVersion != 0) return;

      for (final statement in schemaV1)
      {
        rawDb.execute(statement);
      }
      rawDb.execute(
        "INSERT INTO categories (id, name, color_hex, icon_key, type, user_id, is_synced) "
        "VALUES ('c1', 'Food', '4CAF50', 'restaurant', 1, 'user-a', 1)",
      );
      rawDb.execute(
        "INSERT INTO transactions (id, name, amount, date, type, category_id, user_id) "
        "VALUES ('t1', 'Lunch', 12.5, 1772366400, 1, 'c1', 'user-a')",
      );
      rawDb.userVersion = 1;
    }));
    addTearDown(db.close);

    final categories = await db.categoriesDao.getAll();
    expect(categories.single.name, "Food");
    expect(categories.single.isSynced, isTrue);
    expect(categories.single.updatedAt.isAfter(before), isTrue, reason: "existing rows get 'now' as updatedAt");

    final transactions = await db.transactionsDao.getAll();
    expect(transactions.single.name, "Lunch");
    expect(transactions.single.isSynced, isFalse);

    // The new table exists and works
    await db.into(db.syncCursors).insert(SyncCursorsCompanion.insert(scope: "user-a:categories", cursor: "x"));
    expect(await db.select(db.syncCursors).get(), hasLength(1));

    final version = await db.customSelect("PRAGMA user_version").getSingle();
    expect(version.read<int>("user_version"), db.schemaVersion);
  });

  // NOTE: Same idea, for phones that already have version 2. The Add Transaction form used
  // to save everything as an expense, so the upgrade gives those rows their category's type
  test("upgrading a version 2 database fixes transactions saved with the wrong type", () async {
    final folder = Directory.systemTemp.createTempSync("expense_tracker_test");
    addTearDown(() => folder.deleteSync(recursive: true));
    final file = File("${folder.path}/db.sqlite");

    // Build a version 2 database the way the old app left it
    final oldDb = AppDatabase.forTesting(NativeDatabase(file));
    final salary = await insertCategory(oldDb, name: "Salary", type: TransactionType.income);
    final food = await insertCategory(oldDb, name: "Food", type: TransactionType.expense);
    final date = DateTime(2026, 9, 1);
    final wrong = await insertTransaction(oldDb, name: "Paycheck", categoryId: salary.id, date: date, type: TransactionType.expense);
    final lunch = await insertTransaction(oldDb, name: "Lunch", categoryId: food.id, date: date);
    final fixed = await insertTransaction(oldDb, name: "Fixed", categoryId: salary.id, date: date, type: TransactionType.expense);
    await oldDb.customStatement("UPDATE transactions SET is_synced = 1");
    await oldDb.customStatement("UPDATE transactions SET template_id = 'some-template' WHERE id = ?", [fixed.id]);
    await oldDb.customStatement("PRAGMA user_version = 2");
    await oldDb.close();

    // Open it again with the current app, which runs the 2 -> 3 upgrade
    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);
    final rows = {for (final t in await db.transactionsDao.getAll()) t.id: t};

    expect(rows[wrong.id]!.type, TransactionType.income);
    expect(rows[wrong.id]!.isSynced, isFalse, reason: "the fix has to upload too");
    expect(rows[wrong.id]!.updatedAt.isAfter(wrong.updatedAt), isTrue, reason: "so it wins over the server's old copy");

    expect(rows[lunch.id]!.type, TransactionType.expense);
    expect(rows[lunch.id]!.isSynced, isTrue, reason: "rows that were already right are untouched");

    expect(rows[fixed.id]!.type, TransactionType.expense, reason: "fixed transactions come from templates, not the form");
    expect(rows[fixed.id]!.isSynced, isTrue);

    final version = await db.customSelect("PRAGMA user_version").getSingle();
    expect(version.read<int>("user_version"), db.schemaVersion);
  });

  test("upgrading a version 3 database adds the receipts table and keeps everything else", () async {
    final folder = Directory.systemTemp.createTempSync("expense_tracker_test");
    addTearDown(() => folder.deleteSync(recursive: true));
    final file = File("${folder.path}/db.sqlite");

    // A version 3 database: today's tables, minus receipts
    final oldDb = AppDatabase.forTesting(NativeDatabase(file));
    final food = await insertCategory(oldDb, name: "Food");
    await oldDb.customStatement("DROP TABLE receipts");
    await oldDb.customStatement("PRAGMA user_version = 3");
    await oldDb.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);

    expect((await db.categoriesDao.getAll()).single.id, food.id);
    await db.into(db.receipts).insert(ReceiptsCompanion.insert(userId: "user-a"));
    expect(await db.receiptsDao.getUnsynced("user-a"), hasLength(1));

    final version = await db.customSelect("PRAGMA user_version").getSingle();
    expect(version.read<int>("user_version"), db.schemaVersion);
  });

  test("upgrading a version 4 database adds image_uploaded to existing receipts", () async {
    final folder = Directory.systemTemp.createTempSync("expense_tracker_test");
    addTearDown(() => folder.deleteSync(recursive: true));
    final file = File("${folder.path}/db.sqlite");

    // A version 4 database: receipts without the columns versions 5 and 6 added
    final oldDb = AppDatabase.forTesting(NativeDatabase(file));
    await oldDb.into(oldDb.receipts).insert(ReceiptsCompanion.insert(userId: "user-a", merchant: const Value("Kept")));
    await dropReceiptColumnsAfter(oldDb, 4);
    await oldDb.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);

    final receipt = (await db.receiptsDao.getAll()).single;
    expect(receipt.merchant, "Kept");
    expect(receipt.imageUploaded, isFalse, reason: "existing photos haven't been uploaded yet");

    final version = await db.customSelect("PRAGMA user_version").getSingle();
    expect(version.read<int>("user_version"), db.schemaVersion);
  });

  test("upgrading a version 5 database adds rotation and splitting to existing receipts", () async {
    final folder = Directory.systemTemp.createTempSync("expense_tracker_test");
    addTearDown(() => folder.deleteSync(recursive: true));
    final file = File("${folder.path}/db.sqlite");

    final oldDb = AppDatabase.forTesting(NativeDatabase(file));
    await oldDb.into(oldDb.receipts).insert(ReceiptsCompanion.insert(
      userId: "user-a",
      merchant: const Value("Kept"),
      imageUploaded: const Value(true),
    ));
    await dropReceiptColumnsAfter(oldDb, 5);
    await oldDb.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);

    final receipt = (await db.receiptsDao.getAll()).single;
    expect((receipt.merchant, receipt.imageUploaded), ("Kept", true));
    expect((receipt.imageQuarterTurns, receipt.splitPeople, receipt.splitAmount), (0, null, null));
  });

  test("upgrading a version 6 database adds cropping to existing receipts", () async {
    final folder = Directory.systemTemp.createTempSync("expense_tracker_test");
    addTearDown(() => folder.deleteSync(recursive: true));
    final file = File("${folder.path}/db.sqlite");

    final oldDb = AppDatabase.forTesting(NativeDatabase(file));
    await oldDb.into(oldDb.receipts).insert(ReceiptsCompanion.insert(
      userId: "user-a",
      merchant: const Value("Kept"),
      imageQuarterTurns: const Value(1),
      splitPeople: const Value(3),
    ));
    await dropReceiptColumnsAfter(oldDb, 6);
    await oldDb.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);

    final receipt = (await db.receiptsDao.getAll()).single;
    expect((receipt.merchant, receipt.imageQuarterTurns, receipt.splitPeople), ("Kept", 1, 3));
    expect(receipt.cropCorners, isNull, reason: "existing receipts show the whole photo");
  });

  test("upgrading a version 7 database adds a location to existing receipts", () async {
    final folder = Directory.systemTemp.createTempSync("expense_tracker_test");
    addTearDown(() => folder.deleteSync(recursive: true));
    final file = File("${folder.path}/db.sqlite");

    final oldDb = AppDatabase.forTesting(NativeDatabase(file));
    await oldDb.into(oldDb.receipts).insert(ReceiptsCompanion.insert(
      userId: "user-a",
      merchant: const Value("Kept"),
      cropCorners: const Value("0,0,1,0,1,1,0,1"),
    ));
    await dropReceiptColumnsAfter(oldDb, 7);
    await oldDb.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);

    final receipt = (await db.receiptsDao.getAll()).single;
    expect((receipt.merchant, receipt.cropCorners), ("Kept", "0,0,1,0,1,1,0,1"));
    expect((receipt.city, receipt.state, receipt.country), (null, null, null));
  });

  test("upgrading a version 8 database adds suburbs to existing receipts", () async {
    final folder = Directory.systemTemp.createTempSync("expense_tracker_test");
    addTearDown(() => folder.deleteSync(recursive: true));
    final file = File("${folder.path}/db.sqlite");

    final oldDb = AppDatabase.forTesting(NativeDatabase(file));
    await oldDb.into(oldDb.receipts).insert(ReceiptsCompanion.insert(
      userId: "user-a",
      city: const Value("Toronto"),
      country: const Value("Canada"),
    ));
    await dropReceiptColumnsAfter(oldDb, 8);
    await oldDb.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);

    final receipt = (await db.receiptsDao.getAll()).single;
    expect((receipt.city, receipt.country), ("Toronto", "Canada"));
    expect((receipt.suburb, receipt.pendingLatitude, receipt.pendingLongitude), (null, null, null));
  });
}
