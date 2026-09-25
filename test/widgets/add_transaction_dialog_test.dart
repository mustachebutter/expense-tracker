import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/widgets/add_expense_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';
import '../helpers/test_database.dart';

void main()
{
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() => db.close());

  // NOTE: testWidgets gives us a WidgetTester, a fake screen we can render widgets
  // into, tap, and type on. Time doesn't pass on its own in there: every
  // tester.pump() is "draw the next frame"
  testWidgets("asks for categories when there are none", (tester) async {
    await pumpApp(tester, Scaffold(body: AddTransactionDialog(onTransactionAdded: (_) {}, currentMonth: DateTime.now())), db: db);
    await tester.pumpAndSettle();

    expect(find.text("Please add categories in the settings!"), findsOneWidget);
  });

  testWidgets("sends the entered transaction to onTransactionAdded", (tester) async {
    final food = await insertCategory(db, name: "Food");
    final added = <TransactionsCompanion>[];

    await pumpApp(tester, Scaffold(body: AddTransactionDialog(onTransactionAdded: added.add, currentMonth: DateTime.now())), db: db);
    await tester.pumpAndSettle();

    // NOTE: find.* locates widgets on screen, like a query selector for Flutter
    await tester.enterText(find.widgetWithText(TextField, "Transaction Name"), "Coffee");
    await tester.enterText(find.widgetWithText(TextField, "Amount"), "4.50");
    await tester.tap(find.widgetWithText(ElevatedButton, "Add Transaction"));
    await tester.pump();

    expect(added, hasLength(1));
    expect(added.single.name.value, "Coffee");
    expect(added.single.amount.value, 4.5);
    expect(added.single.categoryId.value, food.id);
    // The dialog no longer decides who owns the row, TransactionActions does
    expect(added.single.userId.present, isFalse);
  });

  testWidgets("does nothing when the name is empty", (tester) async {
    await insertCategory(db, name: "Food");
    final added = <TransactionsCompanion>[];

    await pumpApp(tester, Scaffold(body: AddTransactionDialog(onTransactionAdded: added.add, currentMonth: DateTime.now())), db: db);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, "Amount"), "4.50");
    await tester.tap(find.widgetWithText(ElevatedButton, "Add Transaction"));
    await tester.pump();

    expect(added, isEmpty);
  });
}
