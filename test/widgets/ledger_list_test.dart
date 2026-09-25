import 'package:expense_tracker/daos/transactions_dao.dart';
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/theme/money_colors.dart';
import 'package:expense_tracker/widgets/ledger_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 10);

final _category = Category(
  id: "c1", name: "Food", colorHex: "4CAF50", iconKey: "restaurant", type: TransactionType.expense,
  userId: "user-a", isActive: true, isSynced: true, isDeleted: false, updatedAt: _now,
);

TransactionWithCategory _row(String name, double amount, TransactionType type)
{
  return TransactionWithCategory(
    expense: Transaction(
      id: name, name: name, amount: amount, date: _now, type: type, categoryId: "c1",
      userId: "user-a", isSynced: true, isDeleted: false, updatedAt: _now,
    ),
    category: _category,
  );
}

void main()
{
  Future<void> pumpLedger(WidgetTester tester, Brightness brightness, List<TransactionWithCategory> rows) async
  {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        extensions: [brightness == Brightness.dark ? MoneyColors.dark : MoneyColors.light],
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: LedgerList(
            selectedDateTime: DateTime(2026, 9),
            transactionsWithCategory: rows,
            activeFilter: "All",
            isInitiallyExpanded: true,
            onDelete: (_) {},
          ),
        ),
      ),
    ));
  }

  // The color a Text widget with exactly this text is drawn in
  Color? colorOf(WidgetTester tester, String text)
  {
    final widget = tester.widget<Text>(find.text(text));
    return widget.style?.color ?? widget.textSpan?.style?.color;
  }

  for (final (brightness, money) in [(Brightness.light, MoneyColors.light), (Brightness.dark, MoneyColors.dark)])
  {
    testWidgets("income is green and expenses are red on the ${brightness.name} theme", (tester) async {
      await pumpLedger(tester, brightness, [
        _row("Salary", 2000, TransactionType.income),
        _row("Lunch", 25, TransactionType.expense),
      ]);

      expect(colorOf(tester, "+\$2000.00"), money.income);
      expect(colorOf(tester, "-\$25.00"), money.expense);
    });
  }

  testWidgets("cash flow turns red once spending is higher than income", (tester) async {
    await pumpLedger(tester, Brightness.light, [
      _row("Salary", 100, TransactionType.income),
      _row("Rent", 300, TransactionType.expense),
    ]);

    // NOTE: The summary is a Text.rich, label and amount are two spans in one widget
    final summary = tester.widgetList<Text>(find.byType(Text))
      .where((t) => t.textSpan?.toPlainText().startsWith("Cash Flow: ") ?? false)
      .single;
    final amountSpan = (summary.textSpan! as TextSpan).children!.single as TextSpan;

    expect(amountSpan.text, "\$-200.00");
    expect(amountSpan.style?.color, MoneyColors.light.expense);
  });
}
