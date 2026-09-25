import 'package:expense_tracker/database.dart';
import 'package:flutter/material.dart';

// Green for money in, red for money out, in a shade that's readable on each theme.
// NOTE: A ThemeExtension is how you add your own colors to ThemeData. The light and dark
// themes in main.dart each register their own set, and widgets ask for "whatever the
// current theme uses" with MoneyColors.of(context), just like Theme.of(context).colorScheme
@immutable
class MoneyColors extends ThemeExtension<MoneyColors>
{
  final Color income;
  final Color expense;

  const MoneyColors({required this.income, required this.expense});

  // NOTE: Darker shades on light backgrounds, lighter ones on dark backgrounds. Each passes
  // the WCAG AA contrast ratio for text (4.5:1) on every background the ledger draws them
  // on, which test/theme/money_colors_test.dart checks. Plain Colors.green/red don't
  // (Colors.green on white is only ~2.5:1)
  static const MoneyColors light = MoneyColors(
    income: Color(0xFF2E7D32),  // Green 800
    expense: Color(0xFFC62828), // Red 800
  );

  static const MoneyColors dark = MoneyColors(
    income: Color(0xFF81C784),  // Green 300
    expense: Color(0xFFEF9A9A), // Red 200
  );

  static MoneyColors of(BuildContext context)
  {
    final theme = Theme.of(context);
    // Falls back to the right set if a theme was built without the extension (e.g. in tests)
    return theme.extension<MoneyColors>() ?? (theme.brightness == Brightness.dark ? dark : light);
  }

  Color forType(TransactionType type) => type == TransactionType.income ? income : expense;

  // Positive is money in (green), negative is money out (red). For totals like cash flow
  Color forBalance(double amount) => amount < 0 ? expense : income;

  @override
  MoneyColors copyWith({Color? income, Color? expense})
  {
    return MoneyColors(income: income ?? this.income, expense: expense ?? this.expense);
  }

  // Blends between the two sets while the app animates from light to dark theme
  @override
  MoneyColors lerp(MoneyColors? other, double t)
  {
    if (other == null) return this;
    return MoneyColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
    );
  }
}

// "+$12.00" for income, "-$12.00" for an expense. The sign means the amount still reads
// correctly for anyone who can't tell the green and red apart
String signedAmount(double amount, TransactionType type)
{
  final sign = type == TransactionType.income ? "+" : "-";
  return "$sign\$${amount.toStringAsFixed(2)}";
}
