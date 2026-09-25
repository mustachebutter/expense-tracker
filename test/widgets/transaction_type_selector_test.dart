import 'dart:math';

import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/main.dart';
import 'package:expense_tracker/widgets/forms/form_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main()
{
  // NOTE: Tests have no internet, so don't let google_fonts try to download Public Sans.
  // Text falls back to the default font, which is fine for checking colors
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // NOTE: WCAG contrast ratio, from 1 (same color) to 21 (black on white).
  // 4.5 is the usual minimum for normal sized text to count as readable
  double contrast(Color a, Color b)
  {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
  }

  // How readable a segment's label is: its painted text color against the segment's
  // background, with see-through backgrounds blended over the page behind them
  double labelContrast(WidgetTester tester, String label)
  {
    final textColor = tester.renderObject<RenderParagraph>(find.text(label)).text.style!.color!;
    final segment = tester.widget<Material>(
      find.ancestor(of: find.text(label), matching: find.byType(Material)).first,
    );
    final page = Theme.of(tester.element(find.text(label))).scaffoldBackgroundColor;
    final background = Color.alphaBlend(segment.color ?? Colors.transparent, page);
    return contrast(textColor, background);
  }

  Future<void> pumpSelector(WidgetTester tester, ThemeData theme) async
  {
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: TransactionTypeSelector(value: TransactionType.income, onChanged: (_) {}),
      ),
    ));
  }

  testWidgets("dark mode: selected and unselected segments are readable", (tester) async {
    await pumpSelector(tester, TransactionApp().darkTheme);

    // Income is the selected one
    expect(labelContrast(tester, "Income"), greaterThanOrEqualTo(4.5));
    expect(labelContrast(tester, "Expense"), greaterThanOrEqualTo(4.5));
  });

  testWidgets("light mode: selected and unselected segments are readable", (tester) async {
    await pumpSelector(tester, TransactionApp().lightTheme);

    expect(labelContrast(tester, "Income"), greaterThanOrEqualTo(4.5));
    expect(labelContrast(tester, "Expense"), greaterThanOrEqualTo(4.5));
  });
}
