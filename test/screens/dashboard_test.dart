import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/screens/dashboard.dart';
import 'package:expense_tracker/widgets/summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';
import '../helpers/test_database.dart';

void main()
{
  late AppDatabase db;
  late Category food;
  late Category travel;

  setUp(() async {
    db = createTestDatabase();
    food = await insertCategory(db, name: "Food");
    travel = await insertCategory(db, name: "Travel");
  });
  tearDown(() => db.close());

  testWidgets("shows totals and this month's transactions for the signed in user only", (tester) async {
    final now = DateTime.now();
    await insertTransaction(db, name: "Salary", categoryId: food.id, date: now, amount: 1000, type: TransactionType.income);
    await insertTransaction(db, name: "Lunch", categoryId: food.id, date: now, amount: 25);
    await insertTransaction(db, name: "Someone else's", categoryId: food.id, date: now, amount: 999, userId: userB);

    await pumpApp(tester, const Dashboard(), db: db);
    await tester.pumpAndSettle();

    // NOTE: $1000.00 is also shown in the ledger's income list, so only look inside the cards
    expect(find.widgetWithText(SummaryCard, "\$1000.00"), findsOneWidget); // Monthly Income
    expect(find.widgetWithText(SummaryCard, "\$975.00"), findsOneWidget);  // Cash Flow
    expect(find.text("Lunch"), findsOneWidget);
    expect(find.text("Someone else's"), findsNothing);
  });

  testWidgets("adding a transaction makes it appear in the ledger", (tester) async {
    await pumpApp(tester, const Dashboard(), db: db);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, "Transaction Name"), "Coffee");
    await tester.enterText(find.widgetWithText(TextField, "Amount"), "4.50");
    await tester.tap(find.widgetWithText(ElevatedButton, "Add Transaction"));
    // NOTE: pumpAndSettle keeps drawing frames until nothing is changing anymore,
    // which gives the DB insert -> stream -> provider -> rebuild chain time to finish
    await tester.pumpAndSettle();

    // NOTE: "Coffee" is also still typed in the text field, so look for the ledger row
    expect(find.widgetWithText(ListTile, "Coffee"), findsOneWidget);
    final saved = await db.transactionsDao.getAll();
    expect(saved.single.userId, userA);
  });

  testWidgets("category chips filter the ledger", (tester) async {
    final now = DateTime.now();
    await insertTransaction(db, name: "Lunch", categoryId: food.id, date: now);
    await insertTransaction(db, name: "Train", categoryId: travel.id, date: now);

    await pumpApp(tester, const Dashboard(), db: db);
    await tester.pumpAndSettle();

    expect(find.text("Lunch"), findsOneWidget);
    expect(find.text("Train"), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, "Travel"));
    await tester.pumpAndSettle();

    expect(find.text("Lunch"), findsNothing);
    expect(find.text("Train"), findsOneWidget);
  });
}
