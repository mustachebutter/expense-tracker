import 'dart:async';

import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/main.dart';
import 'package:expense_tracker/theme/money_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

// WCAG contrast ratio between two colors, from 1:1 (identical) to 21:1 (black on white)
double contrastRatio(Color a, Color b)
{
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (lighter, darker) = la > lb ? (la, lb) : (lb, la);
  return (lighter + 0.05) / (darker + 0.05);
}

void main()
{
  // NOTE: Google Fonts looks up the app's bundled assets, which needs Flutter's test
  // binding. testWidgets sets it up automatically, plain test() doesn't
  TestWidgetsFlutterBinding.ensureInitialized();

  late ThemeData lightTheme;
  late ThemeData darkTheme;

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;

    // NOTE: The app's themes use Google Fonts, which starts loading the font files in the
    // background as soon as the themes are built. Tests have no fonts or network, so those
    // loads fail. This test only checks colors, so catch exactly those errors and let
    // anything else still fail the test
    runZonedGuarded(() {
      final app = TransactionApp();
      lightTheme = app.lightTheme;
      darkTheme = app.darkTheme;
    }, (error, stackTrace) {
      final isFontLoadError = error.toString().contains("GoogleFonts") || error.toString().contains("google_fonts");
      if (!isFontLoadError) Error.throwWithStackTrace(error, stackTrace);
    });
  });

  for (final name in ["light", "dark"])
  {
    test("income and expense colors are readable on the $name theme", () {
      final theme = name == "light" ? lightTheme : darkTheme;
      final money = theme.extension<MoneyColors>();
      expect(money, isNotNull, reason: "the $name theme must register MoneyColors");

      // The ledger draws amounts on both of these
      final backgrounds = {"surface": theme.colorScheme.surface, "primary": theme.colorScheme.primary};

      for (final background in backgrounds.entries)
      {
        for (final (label, color) in [("income", money!.income), ("expense", money.expense)])
        {
          // NOTE: 4.5:1 is the WCAG AA minimum for normal sized text
          expect(
            contrastRatio(color, background.value),
            greaterThanOrEqualTo(4.5),
            reason: "$label on ${background.key} in the $name theme",
          );
        }
      }
    });
  }

  for (final name in ["light", "dark"])
  {
    test("tab labels are readable on the $name theme", () {
      final theme = name == "light" ? lightTheme : darkTheme;
      final background = theme.colorScheme.surface; // what the AppBar and Scaffold are drawn on

      // NOTE: Regression check, the selected tab used to be drawn in colorScheme.primary,
      // which is the background color in these themes (white on white / black on black)
      expect(contrastRatio(theme.tabBarTheme.labelColor!, background), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(theme.tabBarTheme.unselectedLabelColor!, background), greaterThanOrEqualTo(4.5));
    });
  }

  for (final name in ["light", "dark"])
  {
    test("switches, checkboxes, spinners, the cursor and the date picker are visible on the $name theme", () {
      final theme = name == "light" ? lightTheme : darkTheme;
      // Dialogs and screens are drawn on the surface color
      final background = theme.colorScheme.surface;
      const on = {WidgetState.selected};
      const off = <WidgetState>{};

      // NOTE: Regression check. These used colorScheme.primary, which is the background
      // color in these themes, so a ticked checkbox or an "on" switch was invisible.
      // 3:1 is the WCAG minimum for controls, 4.5:1 for text
      final checkboxFill = theme.checkboxTheme.fillColor!.resolve(on)!;
      expect(contrastRatio(checkboxFill, background), greaterThanOrEqualTo(3), reason: "ticked checkbox");
      expect(contrastRatio(theme.checkboxTheme.checkColor!.resolve(on)!, checkboxFill), greaterThanOrEqualTo(4.5), reason: "the tick");
      expect(contrastRatio(theme.checkboxTheme.side!.color, background), greaterThanOrEqualTo(3), reason: "empty checkbox");

      final switchTrack = theme.switchTheme.trackColor!.resolve(on)!;
      expect(contrastRatio(switchTrack, background), greaterThanOrEqualTo(3), reason: "switch that's on");
      expect(contrastRatio(theme.switchTheme.thumbColor!.resolve(on)!, switchTrack), greaterThanOrEqualTo(3), reason: "its knob");
      expect(contrastRatio(theme.switchTheme.thumbColor!.resolve(off)!, background), greaterThanOrEqualTo(3), reason: "switch that's off");

      expect(contrastRatio(theme.progressIndicatorTheme.color!, background), greaterThanOrEqualTo(3), reason: "spinner");
      expect(contrastRatio(theme.textSelectionTheme.cursorColor!, background), greaterThanOrEqualTo(3), reason: "text cursor");

      final selectedDay = theme.datePickerTheme.dayBackgroundColor!.resolve(on)!;
      expect(contrastRatio(selectedDay, background), greaterThanOrEqualTo(3), reason: "picked date");
      expect(contrastRatio(theme.datePickerTheme.dayForegroundColor!.resolve(on)!, selectedDay), greaterThanOrEqualTo(4.5), reason: "picked date's number");
    });
  }

  test("plain Colors.green would NOT have been readable on the light theme", () {
    // This is why the theme uses darker shades instead of the obvious choice
    expect(contrastRatio(Colors.green, lightTheme.colorScheme.primary), lessThan(4.5));
  });

  test("signedAmount shows which way the money went", () {
    expect(signedAmount(1200, TransactionType.income), "+\$1200.00");
    expect(signedAmount(4.5, TransactionType.expense), "-\$4.50");
  });

  group("AppConstants", () {
    test("has 20 category icons, and every one resolves to a real icon", () {
      expect(AppConstants.iconKeys, hasLength(20));
      for (final key in AppConstants.iconKeys)
      {
        expect(AppConstants.getIcon(key).icon, isNot(Icons.help_outline), reason: key);
      }
      expect(AppConstants.iconKeys.last, "more_horiz");
    });

    test("colorToHex is the reverse of getColorFromHex", () {
      for (final hex in ["4CAF50", "000000", "FFFFFF", "0A1B2C"])
      {
        expect(AppConstants.colorToHex(AppConstants.getColorFromHex(hex)), hex);
      }
    });

    test("onColor picks a readable icon color for any category color", () {
      expect(AppConstants.onColor(const Color(0xFF0D47A1)), Colors.white);
      expect(AppConstants.onColor(const Color(0xFFFFEB3B)), Colors.black);
    });
  });
}
