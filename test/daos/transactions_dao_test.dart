import 'package:expense_tracker/database.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main()
{
  late AppDatabase db;
  late Category food;

  // NOTE: setUp runs before EVERY test, tearDown after every test.
  // So each test starts with a fresh empty database plus one category
  setUp(() async {
    db = createTestDatabase();
    food = await insertCategory(db, name: "Food");
  });

  tearDown(() async {
    await db.close();
  });

  // Reads back what generateFixedTransactionsForMonth created
  Future<List<Transaction>> generatedTransactions() async
  {
    final rows = await db.transactionsDao.getAll();
    return rows.where((t) => t.templateId != null).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  group("generateFixedTransactionsForMonth", () {
    test("uses the billing day as the charge date", () async {
      await insertTemplate(db, name: "Rent", categoryId: food.id, billingDay: 15, startDate: DateTime(2025, 1, 1));

      await db.transactionsDao.generateFixedTransactionsForMonth(2025, 3, userA);

      final generated = await generatedTransactions();
      expect(generated, hasLength(1));
      expect(generated.single.name, "Rent");
      expect(generated.single.date, DateTime(2025, 3, 15));
      expect(generated.single.userId, userA);
    });

    test("clamps billing day 31 to the last day of short months", () async {
      await insertTemplate(db, name: "Gym", categoryId: food.id, billingDay: 31, startDate: DateTime(2024, 1, 1));

      await db.transactionsDao.generateFixedTransactionsForMonth(2025, 2, userA); // 28 days
      await db.transactionsDao.generateFixedTransactionsForMonth(2024, 2, userA); // leap year, 29 days
      await db.transactionsDao.generateFixedTransactionsForMonth(2025, 4, userA); // 30 days
      await db.transactionsDao.generateFixedTransactionsForMonth(2025, 1, userA); // 31 days

      final dates = (await generatedTransactions()).map((t) => t.date).toList();
      expect(dates, [
        DateTime(2024, 2, 29),
        DateTime(2025, 1, 31),
        DateTime(2025, 2, 28),
        DateTime(2025, 4, 30),
      ]);
    });

    test("does not create duplicates when run twice for the same month", () async {
      await insertTemplate(db, name: "Rent", categoryId: food.id, billingDay: 1, startDate: DateTime(2025, 1, 1));

      await db.transactionsDao.generateFixedTransactionsForMonth(2025, 3, userA);
      await db.transactionsDao.generateFixedTransactionsForMonth(2025, 3, userA);

      expect(await generatedTransactions(), hasLength(1));
    });

    // NOTE: Regression test for the old endOfMonth bug. It used to look ~25 days into
    // the NEXT month, so February's rent made January look "already generated"
    test("next month's transaction does not block this month", () async {
      await insertTemplate(db, name: "Rent", categoryId: food.id, billingDay: 10, startDate: DateTime(2025, 1, 1));

      await db.transactionsDao.generateFixedTransactionsForMonth(2025, 2, userA);
      await db.transactionsDao.generateFixedTransactionsForMonth(2025, 1, userA);

      final dates = (await generatedTransactions()).map((t) => t.date).toList();
      expect(dates, [DateTime(2025, 1, 10), DateTime(2025, 2, 10)]);
    });

    test("skips months before the template started", () async {
      await insertTemplate(db, name: "Rent", categoryId: food.id, billingDay: 1, startDate: DateTime(2025, 6, 1));

      await db.transactionsDao.generateFixedTransactionsForMonth(2025, 5, userA);

      expect(await generatedTransactions(), isEmpty);
    });

    test("skips charge dates that are still in the future", () async {
      final nextMonth = DateTime(DateTime.now().year, DateTime.now().month + 1, 1);
      await insertTemplate(db, name: "Rent", categoryId: food.id, billingDay: 1, startDate: DateTime(2025, 1, 1));

      await db.transactionsDao.generateFixedTransactionsForMonth(nextMonth.year, nextMonth.month, userA);

      expect(await generatedTransactions(), isEmpty);
    });

    test("ignores deleted, inactive and other users' templates", () async {
      final start = DateTime(2025, 1, 1);
      await insertTemplate(db, name: "Deleted", categoryId: food.id, billingDay: 1, startDate: start, isDeleted: true);
      await insertTemplate(db, name: "Inactive", categoryId: food.id, billingDay: 1, startDate: start, isActive: false);
      await insertTemplate(db, name: "Not mine", categoryId: food.id, billingDay: 1, startDate: start, userId: userB);
      await insertTemplate(db, name: "Mine", categoryId: food.id, billingDay: 1, startDate: start);

      await db.transactionsDao.generateFixedTransactionsForMonth(2025, 3, userA);

      final names = (await generatedTransactions()).map((t) => t.name);
      expect(names, ["Mine"]);
    });
  });

  group("watchDashboardMetrics", () {
    test("sums only the user's non-deleted transactions", () async {
      final date = DateTime(2025, 3, 5);
      await insertTransaction(db, name: "Salary", categoryId: food.id, date: date, amount: 1000, type: TransactionType.income);
      await insertTransaction(db, name: "Lunch", categoryId: food.id, date: date, amount: 30);
      await insertTransaction(db, name: "Deleted", categoryId: food.id, date: date, amount: 500, isDeleted: true);
      await insertTransaction(db, name: "Someone else", categoryId: food.id, date: date, amount: 999, userId: userB);

      // NOTE: .first takes the first value a Stream emits and turns it into a Future we can await
      final metrics = await db.transactionsDao.watchDashboardMetrics(userA).first;

      expect(metrics.income, 1000);
      expect(metrics.expense, 30);
      expect(metrics.cashFlow, 970);
    });
  });

  group("watchVisibleTransactionsWithCategory", () {
    test("returns the month's transactions newest first, with their category", () async {
      await insertTransaction(db, name: "Early", categoryId: food.id, date: DateTime(2025, 3, 1));
      await insertTransaction(db, name: "Late", categoryId: food.id, date: DateTime(2025, 3, 20));
      await insertTransaction(db, name: "Other month", categoryId: food.id, date: DateTime(2025, 4, 1));
      await insertTransaction(db, name: "Other user", categoryId: food.id, date: DateTime(2025, 3, 2), userId: userB);

      final rows = await db.transactionsDao.watchVisibleTransactionsWithCategory(2025, 3, userA).first;

      expect(rows.map((r) => r.expense.name), ["Late", "Early"]);
      expect(rows.first.category.name, "Food");
    });
  });

  group("getTransactionById", () {
    test("does not return another user's transaction", () async {
      final theirs = await insertTransaction(db, name: "Theirs", categoryId: food.id, date: DateTime(2025, 3, 1), userId: userB);

      expect(await db.transactionsDao.getTransactionById(theirs.id, userA), isNull);
      expect(await db.transactionsDao.getTransactionById(theirs.id, userB), isNotNull);
    });
  });
}
