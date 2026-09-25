import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/category_providers.dart';
import 'package:expense_tracker/providers/core_providers.dart';
import 'package:expense_tracker/providers/investment_providers.dart';
import 'package:expense_tracker/providers/savings_goal_providers.dart';
import 'package:expense_tracker/providers/template_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main()
{
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = createTestDatabase();
    container = ProviderContainer.test(
      overrides: [
        databaseProvider.overrideWithValue(db),
        currentUserIdProvider.overrideWithValue(userA),
      ],
    );
  });
  tearDown(() => db.close());

  Future<Category> getCategory(String id) => (db.select(db.categories)..where((t) => t.id.equals(id))).getSingle();

  group("CategoryActions", () {
    test("add creates an unsynced category for the signed in user", () async {
      await container.read(categoryActionsProvider).add(
        name: "Salary",
        colorHex: "4CAF50",
        iconKey: "attach_money",
        type: TransactionType.income,
      );

      final saved = (await db.categoriesDao.getAll()).single;
      expect(saved.name, "Salary");
      expect(saved.type, TransactionType.income);
      expect(saved.userId, userA);
      expect(saved.isSynced, isFalse);
    });

    test("update marks the row unsynced and moves updatedAt forward", () async {
      final food = await insertCategory(db, name: "Food", isSynced: true);

      await container.read(categoryActionsProvider).update(food.copyWith(name: "Groceries"));

      final saved = await getCategory(food.id);
      expect(saved.name, "Groceries");
      expect(saved.isSynced, isFalse);
      expect(saved.updatedAt.isAfter(food.updatedAt), isTrue);
    });

    test("update refuses another user's category", () async {
      final theirs = await insertCategory(db, name: "Theirs", userId: userB);

      expect(
        () => container.read(categoryActionsProvider).update(theirs.copyWith(name: "Mine now")),
        throwsStateError,
      );
    });

    test("delete is a soft delete that hides the category and syncs", () async {
      final food = await insertCategory(db, name: "Food", isSynced: true);
      container.listen(activeCategoriesProvider, (previous, next) {});

      await container.read(categoryActionsProvider).delete(food.id);

      final saved = await getCategory(food.id);
      expect(saved.isDeleted, isTrue);
      expect(saved.isSynced, isFalse);
      expect(await container.read(activeCategoriesProvider.future), isEmpty);
    });

    test("delete moves updatedAt forward even within the same second", () async {
      // NOTE: A clock "ahead" of now forces the same-second case nextUpdatedAt guards against
      final ahead = DateTime.now().add(const Duration(minutes: 1));
      final wholeSecond = DateTime(ahead.year, ahead.month, ahead.day, ahead.hour, ahead.minute, ahead.second);
      final food = await insertCategory(db, name: "Food", updatedAt: wholeSecond);

      await container.read(categoryActionsProvider).delete(food.id);

      expect((await getCategory(food.id)).updatedAt, wholeSecond.add(const Duration(seconds: 1)));
    });

    test("delete leaves another user's category alone", () async {
      final theirs = await insertCategory(db, name: "Theirs", userId: userB);

      await container.read(categoryActionsProvider).delete(theirs.id);

      expect((await getCategory(theirs.id)).isDeleted, isFalse);
    });
  });

  group("TemplateActions", () {
    test("add starts the fixed transaction this month", () async {
      final food = await insertCategory(db, name: "Food");

      await container.read(templateActionsProvider).add(
        name: "Rent",
        amount: 1200,
        billingDay: 31,
        type: TransactionType.expense,
        categoryId: food.id,
      );

      final saved = (await db.templatesDao.getAll()).single;
      final now = DateTime.now();
      expect(saved.name, "Rent");
      expect(saved.billingDay, 31);
      expect(saved.userId, userA);
      expect(saved.isSynced, isFalse);
      expect((saved.startDate.year, saved.startDate.month), (now.year, now.month));
    });

    test("update and delete follow the sync rules", () async {
      final food = await insertCategory(db, name: "Food");
      await container.read(templateActionsProvider).add(
        name: "Rent", amount: 1200, billingDay: 1, type: TransactionType.expense, categoryId: food.id,
      );
      final rent = (await db.templatesDao.getAll()).single;

      await container.read(templateActionsProvider).update(rent.copyWith(amount: 1300));
      final updated = (await db.templatesDao.getAll()).single;
      expect(updated.amount, 1300);
      expect(updated.updatedAt.isAfter(rent.updatedAt), isTrue);

      await container.read(templateActionsProvider).delete(rent.id);
      expect((await db.templatesDao.getAll()).single.isDeleted, isTrue);
    });
  });

  group("SavingsGoalActions and InvestmentActions", () {
    test("add, update and delete a savings goal", () async {
      final actions = container.read(savingsGoalActionsProvider);

      await actions.add(name: "Holiday", targetAmount: 2000, currentSavedAmount: 150);
      final goal = (await db.savingsGoalsDao.getAll()).single;
      expect((goal.name, goal.targetAmount, goal.currentSavedAmount, goal.userId), ("Holiday", 2000, 150, userA));

      await actions.update(goal.copyWith(currentSavedAmount: 400));
      expect((await db.savingsGoalsDao.getAll()).single.currentSavedAmount, 400);

      await actions.delete(goal.id);
      expect((await db.savingsGoalsDao.getAll()).single.isDeleted, isTrue);
    });

    test("add, update and delete an investment", () async {
      final actions = container.read(investmentActionsProvider);

      await actions.add(name: "Index fund", amount: 500);
      final investment = (await db.investmentsDao.getAll()).single;
      expect((investment.name, investment.amount, investment.userId), ("Index fund", 500, userA));

      await actions.update(investment.copyWith(amount: 750));
      expect((await db.investmentsDao.getAll()).single.amount, 750);

      await actions.delete(investment.id);
      expect((await db.investmentsDao.getAll()).single.isDeleted, isTrue);
    });
  });
}
