import 'dart:ui' show Rect;

import 'package:expense_tracker/services/receipt_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main()
{
  // NOTE: A fixed "today", so date checks don't depend on when the tests run
  final today = DateTime(2026, 9, 26);
  final dayFirst = ReceiptTextParser(dayFirst: true, now: today);
  final monthFirst = ReceiptTextParser(dayFirst: false, now: today);

  group("a whole receipt", () {
    test("a typical supermarket receipt", () {
      final parsed = dayFirst.parse([
        "TESCO EXPRESS",
        "123 High Street, London",
        "Tel 020 7946 0000",
        "MILK 2L            1.45",
        "BREAD              1.10",
        "SUBTOTAL           2.55",
        "VAT 20%            0.51",
        "TOTAL              3.06",
        "CASH              10.00",
        "CHANGE             6.94",
        "12/09/2026  14:32",
      ]);

      expect(parsed.merchant, "Tesco Express");
      expect(parsed.total, 3.06);
      expect(parsed.date, DateTime(2026, 9, 12));
    });

    test("a US style restaurant receipt", () {
      final parsed = monthFirst.parse([
        "Joe's Diner",
        "Server: Amy   Table 12",
        "Burger                 14.50",
        "Fries                   4.25",
        "Subtotal               18.75",
        "Tax                     1.64",
        "Tip                     3.00",
        "Amount Due             23.39",
        "Visa ****1234",
        "09/12/26 7:45 PM",
      ]);

      expect(parsed.merchant, "Joe's Diner");
      expect(parsed.total, 23.39);
      expect(parsed.date, DateTime(2026, 9, 12));
    });

    test("an unreadable photo gives an empty result instead of guesses", () {
      final parsed = dayFirst.parse(["~~", "..", ""]);

      expect(parsed.isEmpty, isTrue);
    });
  });

  group("total", () {
    test("uses the TOTAL row, not the bigger cash or change rows", () {
      expect(dayFirst.parse(["Shop", "TOTAL 21.60", "CASH 50.00", "CHANGE 28.40"]).total, 21.60);
    });

    test("skips subtotal, tax, savings and item counts", () {
      final parsed = dayFirst.parse([
        "Shop",
        "SUBTOTAL 40.00",
        "TOTAL SAVINGS 5.00",
        "TOTAL ITEMS 12",
        "GST 4.00",
        "TOTAL 44.00",
      ]);
      expect(parsed.total, 44.00);
    });

    test("finds the amount on the next row when the label stands alone", () {
      expect(dayFirst.parse(["Shop", "Balance due", "18.20"]).total, 18.20);
    });

    test("falls back to the biggest amount when nothing says total", () {
      expect(dayFirst.parse(["Cafe", "Latte 4.50", "Muffin 3.20", "Card 7.70"]).total, 7.70);
    });

    test("reads thousands separators either way round", () {
      expect(ReceiptTextParser.amountsIn("TOTAL 1,234.56"), [1234.56]);
      expect(ReceiptTextParser.amountsIn("TOTAL 1.234,56"), [1234.56]);
      expect(ReceiptTextParser.amountsIn("TOTAL 1 234,56"), [1234.56]);
      expect(ReceiptTextParser.amountsIn("TOTAL \$12.50"), [12.50]);
    });
  });

  group("date", () {
    test("uses the device's day/month order only when the numbers could be either", () {
      expect(dayFirst.parse(["03/04/2026"]).date, DateTime(2026, 4, 3));
      expect(monthFirst.parse(["03/04/2026"]).date, DateTime(2026, 3, 4));
      // 25 can't be a month, so the order is certain whatever the device says
      expect(monthFirst.parse(["25/04/2026"]).date, DateTime(2026, 4, 25));
      expect(dayFirst.parse(["04/25/2026"]).date, DateTime(2026, 4, 25));
    });

    test("reads ISO dates, month names and 2 digit years", () {
      expect(dayFirst.parse(["2026-09-12 10:00"]).date, DateTime(2026, 9, 12));
      expect(dayFirst.parse(["12 Sep 2026"]).date, DateTime(2026, 9, 12));
      expect(dayFirst.parse(["Sept 12, 2026"]).date, DateTime(2026, 9, 12));
      expect(dayFirst.parse(["1st Aug 26"]).date, DateTime(2026, 8, 1));
      expect(dayFirst.parse(["12.09.26"]).date, DateTime(2026, 9, 12));
    });

    test("rejects impossible or future dates instead of guessing", () {
      expect(dayFirst.parse(["30/02/2026"]).date, isNull, reason: "there's no 30 February");
      expect(dayFirst.parse(["01/01/2030"]).date, isNull, reason: "after today");
      expect(dayFirst.parse(["Ref 12/34/56"]).date, isNull);
    });
  });

  group("shop name", () {
    test("skips header lines that aren't the name", () {
      expect(dayFirst.parse(["TAX INVOICE", "Welcome!", "Blue Bottle Coffee", "Latte 5.00"]).merchant, "Blue Bottle Coffee");
    });

    test("skips addresses, phone numbers and websites", () {
      expect(dayFirst.parse(["www.shop.com", "0412 345 678", "** KMART **", "TOTAL 9.00"]).merchant, "Kmart");
    });

    test("keeps names that aren't all capitals as they are", () {
      expect(dayFirst.parse(["McDonald's", "TOTAL 9.00"]).merchant, "McDonald's");
    });
  });

  group("groupIntoRows", () {
    TextLineBox line(String text, double left, double top) => (text: text, box: Rect.fromLTWH(left, top, 100, 20));

    test("puts the left and right halves of a printed line back together", () {
      final rows = groupIntoRows([
        line("21.60", 300, 102), // the amount comes back first, and slightly lower
        line("TOTAL", 10, 100),
        line("SHOP NAME", 10, 20),
        line("CASH", 10, 140),
        line("50.00", 300, 141),
      ]);

      expect(rows, ["SHOP NAME", "TOTAL 21.60", "CASH 50.00"]);
    });

    test("an empty photo has no rows", () {
      expect(groupIntoRows([]), isEmpty);
    });
  });
}
