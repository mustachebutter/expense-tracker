import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:expense_tracker/database.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/schema_v1.dart';

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
}
