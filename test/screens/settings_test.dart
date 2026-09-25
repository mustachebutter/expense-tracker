import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/screens/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';
import '../helpers/test_database.dart';

void main()
{
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() => db.close());

  Future<void> openSettings(WidgetTester tester) async
  {
    await pumpApp(tester, const Settings(), db: db);
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async
  {
    await tester.tap(find.widgetWithText(ElevatedButton, "Save"));
    await tester.pumpAndSettle();
  }

  testWidgets("every panel has its own title and an Add button", (tester) async {
    await openSettings(tester);

    // NOTE: Regression check, the last panel used to also say "Fixed Transactions"
    expect(find.text("Fixed Transactions"), findsOneWidget);
    expect(find.text("Investments"), findsOneWidget);
    expect(find.text("Savings Goals"), findsOneWidget);
    for (final label in ["Add Category", "Add Goal", "Add Fixed", "Add Investment"])
    {
      expect(find.widgetWithText(ElevatedButton, label), findsOneWidget);
    }
  });

  group("categories", () {
    testWidgets("Add Category opens a form and the new category shows up", (tester) async {
      await openSettings(tester);

      await tester.tap(find.widgetWithText(ElevatedButton, "Add Category"));
      await tester.pumpAndSettle();
      expect(find.text("Add Category"), findsNWidgets(2), reason: "the button and the dialog title");

      await tester.enterText(find.widgetWithText(TextFormField, "Category Name"), "Salary");
      await tester.tap(find.text("Income"));
      await tester.tap(find.byKey(const Key("icon_attach_money")));
      await tester.tap(find.byKey(const Key("color_2196F3")));
      await tapSave(tester);

      expect(find.byType(AlertDialog), findsNothing, reason: "the dialog closes after saving");
      expect(find.widgetWithText(ListTile, "Salary"), findsOneWidget);

      final saved = (await db.categoriesDao.getAll()).single;
      expect(saved.type, TransactionType.income);
      expect(saved.iconKey, "attach_money");
      expect(saved.colorHex, "2196F3");
      expect(saved.userId, userA);
    });

    testWidgets("a name is required", (tester) async {
      await openSettings(tester);

      await tester.tap(find.widgetWithText(ElevatedButton, "Add Category"));
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(find.text("Name is required"), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget, reason: "the dialog stays open");
      expect(await db.categoriesDao.getAll(), isEmpty);
    });

    testWidgets("edit opens the form filled in and saves the change", (tester) async {
      await insertCategory(db, name: "Food");
      await openSettings(tester);

      await tester.tap(find.byTooltip("Edit Food"));
      await tester.pumpAndSettle();

      expect(find.text("Edit Category"), findsOneWidget);
      expect(find.widgetWithText(TextFormField, "Food"), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, "Food"), "Groceries");
      await tapSave(tester);

      expect(find.widgetWithText(ListTile, "Groceries"), findsOneWidget);
      expect(find.widgetWithText(ListTile, "Food"), findsNothing);
    });

    testWidgets("delete asks first, and Cancel keeps the category", (tester) async {
      await insertCategory(db, name: "Food");
      await openSettings(tester);

      await tester.tap(find.byTooltip("Delete Food"));
      await tester.pumpAndSettle();
      expect(find.text("Delete category?"), findsOneWidget);

      await tester.tap(find.text("Cancel"));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, "Food"), findsOneWidget);

      await tester.tap(find.byTooltip("Delete Food"));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, "Delete"));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, "Food"), findsNothing);
      expect(find.text("Deleted Food"), findsOneWidget);
      expect((await db.categoriesDao.getAll()).single.isDeleted, isTrue);
    });
  });

  group("fixed transactions", () {
    testWidgets("Add Fixed saves a fixed transaction with its category", (tester) async {
      final food = await insertCategory(db, name: "Housing");
      await openSettings(tester);

      await tester.tap(find.widgetWithText(ElevatedButton, "Add Fixed"));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, "Name"), "Rent");
      await tester.enterText(find.widgetWithText(TextFormField, "Amount"), "1200");
      await tester.enterText(find.widgetWithText(TextFormField, "Day of the month"), "31");
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      // NOTE: .last because an open dropdown shows the item in the menu AND in the button
      await tester.tap(find.text("Housing").last);
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(find.widgetWithText(ListTile, "Rent"), findsOneWidget);
      expect(find.text("\$1200.00"), findsOneWidget);
      expect(find.text("Expense · Housing · day 31 of each month"), findsOneWidget);

      final saved = (await db.templatesDao.getAll()).single;
      expect(saved.categoryId, food.id);
      expect(saved.billingDay, 31);
    });

    testWidgets("rejects a day outside 1-31 and a missing category", (tester) async {
      await insertCategory(db, name: "Housing");
      await openSettings(tester);

      await tester.tap(find.widgetWithText(ElevatedButton, "Add Fixed"));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, "Name"), "Rent");
      await tester.enterText(find.widgetWithText(TextFormField, "Amount"), "1200");
      await tester.enterText(find.widgetWithText(TextFormField, "Day of the month"), "40");
      await tapSave(tester);

      expect(find.text("Enter a day from 1 to 31"), findsOneWidget);
      expect(find.text("Pick a category"), findsOneWidget);
      expect(await db.templatesDao.getAll(), isEmpty);
    });

    testWidgets("asks for a category first when there are none", (tester) async {
      await openSettings(tester);

      await tester.tap(find.widgetWithText(ElevatedButton, "Add Fixed"));
      await tester.pumpAndSettle();

      expect(find.text("Add a category first, every fixed transaction needs one."), findsOneWidget);
    });
  });

  testWidgets("Add Goal and Add Investment save their rows", (tester) async {
    await openSettings(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, "Add Goal"));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, "Goal Name"), "Holiday");
    await tester.enterText(find.widgetWithText(TextFormField, "Target Amount"), "2000");
    await tapSave(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, "Add Investment"));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, "Investment Name"), "Index fund");
    await tester.enterText(find.widgetWithText(TextFormField, "Amount"), "500");
    await tapSave(tester);

    expect(find.text("Holiday Goal"), findsOneWidget);
    expect(find.text("\$0.00 saved so far"), findsOneWidget);
    expect(find.widgetWithText(ListTile, "Index fund"), findsOneWidget);
  });
}
