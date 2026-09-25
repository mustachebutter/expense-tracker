import 'package:drift/drift.dart' as drift;
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/category_providers.dart';
import 'package:expense_tracker/providers/core_providers.dart';
import 'package:expense_tracker/providers/theme_provider.dart';
import 'package:expense_tracker/providers/transaction_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main()
{
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() => db.close());

  // NOTE: A ProviderContainer is what ProviderScope creates in the real app, minus the widgets.
  // overrides swap the real DB/Supabase for test versions, so nothing touches the network.
  // ProviderContainer.test() also disposes itself automatically when the test ends
  ProviderContainer createContainer({String? userId = userA})
  {
    return ProviderContainer.test(
      overrides: [
        databaseProvider.overrideWithValue(db),
        currentUserIdProvider.overrideWithValue(userId),
      ],
    );
  }

  group("activeCategoriesProvider", () {
    test("emits the signed in user's active categories", () async {
      await insertCategory(db, name: "Food");
      await insertCategory(db, name: "Hidden", isActive: false);
      await insertCategory(db, name: "Not mine", userId: userB);
      final container = createContainer();

      // NOTE: In Riverpod 3 a provider that nobody listens to is paused and never starts
      // its stream. In the app a widget's ref.watch is the listener, here we add one by hand
      container.listen(activeCategoriesProvider, (previous, next) {});

      // NOTE: .future waits for the first value of a StreamProvider/FutureProvider
      final categories = await container.read(activeCategoriesProvider.future);

      expect(categories.map((c) => c.name), ["Food"]);
    });

    test("emits an empty list when nobody is signed in", () async {
      await insertCategory(db, name: "Food");
      final container = createContainer(userId: null);
      container.listen(activeCategoriesProvider, (previous, next) {});

      expect(await container.read(activeCategoriesProvider.future), isEmpty);
    });
  });

  group("monthlyTransactionsProvider", () {
    test("only returns the requested month", () async {
      final food = await insertCategory(db, name: "Food");
      await insertTransaction(db, name: "March", categoryId: food.id, date: DateTime(2025, 3, 3));
      await insertTransaction(db, name: "April", categoryId: food.id, date: DateTime(2025, 4, 3));
      final container = createContainer();

      // NOTE: Same as above, and since this one is autoDispose it would also be
      // destroyed right away without a listener
      final provider = monthlyTransactionsProvider((year: 2025, month: 3));
      container.listen(provider, (previous, next) {});

      final rows = await container.read(provider.future);

      expect(rows.map((r) => r.expense.name), ["March"]);
    });
  });

  group("TransactionActions", () {
    test("add stamps the signed in user's id on the new row", () async {
      final food = await insertCategory(db, name: "Food");
      final container = createContainer();

      await container.read(transactionActionsProvider).add(
        TransactionsCompanion(
          name: const drift.Value("Coffee"),
          amount: const drift.Value(4.5),
          date: drift.Value(DateTime(2025, 3, 1)),
          type: const drift.Value(TransactionType.expense),
          categoryId: drift.Value(food.id),
        ),
      );

      final saved = await db.transactionsDao.getAll();
      expect(saved.single.name, "Coffee");
      expect(saved.single.userId, userA);
    });

    test("add throws when nobody is signed in", () async {
      final container = createContainer(userId: null);

      expect(
        () => container.read(transactionActionsProvider).add(const TransactionsCompanion()),
        throwsStateError,
      );
    });

    test("softDeleteById marks the row deleted and unsynced", () async {
      final food = await insertCategory(db, name: "Food");
      final lunch = await insertTransaction(db, name: "Lunch", categoryId: food.id, date: DateTime(2025, 3, 1));
      final container = createContainer();

      final deleted = await container.read(transactionActionsProvider).softDeleteById(lunch.id);

      expect(deleted?.name, "Lunch");
      final row = await db.transactionsDao.getTransactionById(lunch.id, userA);
      expect(row!.isDeleted, isTrue);
      expect(row.isSynced, isFalse);
    });

    test("softDeleteById can't delete another user's transaction", () async {
      final food = await insertCategory(db, name: "Food");
      final theirs = await insertTransaction(db, name: "Theirs", categoryId: food.id, date: DateTime(2025, 3, 1), userId: userB);
      final container = createContainer();

      expect(await container.read(transactionActionsProvider).softDeleteById(theirs.id), isNull);
      final row = await db.transactionsDao.getTransactionById(theirs.id, userB);
      expect(row!.isDeleted, isFalse);
    });
  });

  group("Notifiers", () {
    test("theme starts on system and toggles between dark and light", () {
      final container = createContainer();

      expect(container.read(themeModeProvider), ThemeMode.system);

      container.read(themeModeProvider.notifier).toggle();
      expect(container.read(themeModeProvider), ThemeMode.dark);

      container.read(themeModeProvider.notifier).toggle();
      expect(container.read(themeModeProvider), ThemeMode.light);
    });

    test("active filter starts on All and can be changed", () {
      final container = createContainer();

      expect(container.read(activeFilterProvider), ActiveFilterNotifier.all);

      container.read(activeFilterProvider.notifier).select("Food");
      expect(container.read(activeFilterProvider), "Food");
    });
  });
}
