import 'package:expense_tracker/database.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main()
{
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() => db.close());

  test("watchActiveCategories returns only the user's active categories, sorted by name", () async {
    await insertCategory(db, name: "Travel");
    await insertCategory(db, name: "Bills");
    await insertCategory(db, name: "Inactive", isActive: false);
    await insertCategory(db, name: "Deleted", isDeleted: true);
    await insertCategory(db, name: "Someone else", userId: userB);

    final categories = await db.categoriesDao.watchActiveCategories(userA).first;

    expect(categories.map((c) => c.name), ["Bills", "Travel"]);
  });

  test("watchCategories still includes inactive ones", () async {
    await insertCategory(db, name: "Active");
    await insertCategory(db, name: "Inactive", isActive: false);

    final categories = await db.categoriesDao.watchCategories(userA).first;

    expect(categories.map((c) => c.name), ["Active", "Inactive"]);
  });

  test("getUnsynced only returns the user's unsynced rows", () async {
    await insertCategory(db, name: "Mine");
    await insertCategory(db, name: "Theirs", userId: userB);

    final unsynced = await db.categoriesDao.getUnsynced(userA);

    expect(unsynced.map((c) => c.name), ["Mine"]);
  });
}
