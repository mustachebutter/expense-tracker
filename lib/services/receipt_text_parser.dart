import 'dart:math' as math;
import 'dart:ui' show Rect;

// One line of text found in a photo, and where it was
typedef TextLineBox = ({String text, Rect box});

// NOTE: OCR often returns the left and right halves of a printed line separately, e.g.
// "TOTAL" and "21.60" as two lines. This puts lines that sit at the same height back
// together, left to right, so the rest of the parser can read "TOTAL 21.60" as one row
List<String> groupIntoRows(List<TextLineBox> lines)
{
  final byHeight = [...lines]..sort((a, b) => a.box.center.dy.compareTo(b.box.center.dy));
  final rows = <List<TextLineBox>>[];

  for (final line in byHeight)
  {
    if (rows.isNotEmpty)
    {
      final anchor = rows.last.first.box;
      // Same row if the centres are closer than about half a line apart
      final tolerance = math.min(anchor.height, line.box.height) * 0.6;
      if ((line.box.center.dy - anchor.center.dy).abs() <= tolerance)
      {
        rows.last.add(line);
        continue;
      }
    }
    rows.add([line]);
  }

  return [
    for (final row in rows)
      (row..sort((a, b) => a.box.left.compareTo(b.box.left))).map((line) => line.text.trim()).join(" "),
  ];
}

class ParsedReceipt
{
  final String? merchant;
  final double? total;
  final DateTime? date;

  const ParsedReceipt({this.merchant, this.total, this.date});

  bool get isEmpty => merchant == null && total == null && date == null;
}

// Pulls the shop, total and date out of a receipt's rows of text. It's a set of rules, not
// AI, so it handles typical receipts and leaves a field empty rather than guess wildly
class ReceiptTextParser
{
  // Whether "03/04/2026" means 3 April (most of the world) or March 4 (US)
  final bool dayFirst;
  // Dates after this are rejected as misreads. A parameter so tests don't depend on today
  final DateTime now;

  ReceiptTextParser({required this.dayFirst, DateTime? now}) : now = now ?? DateTime.now();

  ParsedReceipt parse(List<String> rows)
  {
    final cleanRows = rows.map((row) => row.trim()).where((row) => row.isNotEmpty).toList();
    return ParsedReceipt(merchant: _merchant(cleanRows), total: _total(cleanRows), date: _date(cleanRows));
  }

  // --- Amounts ---------------------------------------------------------------------------

  // "21.60", "1,234.56", "1.234,56", "1 234,56": the last separator before two digits is the
  // decimal point, anything before it is a thousands separator
  static final RegExp _amount = RegExp(r"(\d{1,3}(?:[,.\s]\d{3})+|\d+)[.,](\d{2})(?!\d)");

  static List<double> amountsIn(String row)
  {
    return _amount.allMatches(row).map((match) {
      final whole = match.group(1)!.replaceAll(RegExp(r"[,.\s]"), "");
      return double.parse("$whole.${match.group(2)}");
    }).toList();
  }

  static final RegExp _totalWords = RegExp(
    r"\b(grand\s*total|total|amount\s*(due|payable)|balance\s*(due)?|to\s*pay)\b",
    caseSensitive: false,
  );

  // Rows that mention a total but aren't the amount paid, and payment rows (cash handed over,
  // change) that are often bigger than the total
  static final RegExp _notTheTotal = RegExp(
    r"sub\s*-?\s*total|total\s*(savings?|discounts?|items?|qty|quantity|tax|vat|gst|tip|points)|"
    r"\b(tax|vat|gst|saved|savings|change|tendered|cash|points|tip)\b",
    caseSensitive: false,
  );

  double? _total(List<String> rows)
  {
    final candidates = <double>[];

    for (final (index, row) in rows.indexed)
    {
      if (!_totalWords.hasMatch(row) || _notTheTotal.hasMatch(row)) continue;

      final amounts = amountsIn(row);
      if (amounts.isNotEmpty)
      {
        candidates.add(amounts.last);
      }
      else if (index + 1 < rows.length && !_notTheTotal.hasMatch(rows[index + 1]))
      {
        // The label and the amount ended up on separate rows
        candidates.addAll(amountsIn(rows[index + 1]).take(1));
      }
    }

    if (candidates.isNotEmpty) return candidates.reduce(math.max);

    // No "total" anywhere: the biggest amount that isn't a payment row is the best guess
    final amounts = [
      for (final row in rows)
        if (!_notTheTotal.hasMatch(row)) ...amountsIn(row),
    ];
    return amounts.isEmpty ? null : amounts.reduce(math.max);
  }

  // --- Dates -----------------------------------------------------------------------------

  static const List<String> _months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
  static const String _monthName = r"(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?";

  static final RegExp _isoDate = RegExp(r"\b(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\b");
  static final RegExp _numericDate = RegExp(r"\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{4}|\d{2})\b");
  static final RegExp _dayMonthName = RegExp("\\b(\\d{1,2})(?:st|nd|rd|th)?[\\s-]*$_monthName[\\s,-]*(\\d{4}|\\d{2})\\b", caseSensitive: false);
  static final RegExp _monthNameDay = RegExp("\\b$_monthName\\s*(\\d{1,2})(?:st|nd|rd|th)?,?\\s*(\\d{4}|\\d{2})\\b", caseSensitive: false);

  DateTime? _date(List<String> rows)
  {
    for (final row in rows)
    {
      for (final match in _isoDate.allMatches(row))
      {
        final date = _validDate(match.group(1)!, match.group(2)!, match.group(3)!);
        if (date != null) return date;
      }
      for (final match in _dayMonthName.allMatches(row))
      {
        final month = _months.indexOf(match.group(2)!.toLowerCase().substring(0, 3)) + 1;
        final date = _validDate(match.group(3)!, "$month", match.group(1)!);
        if (date != null) return date;
      }
      for (final match in _monthNameDay.allMatches(row))
      {
        final month = _months.indexOf(match.group(1)!.toLowerCase().substring(0, 3)) + 1;
        final date = _validDate(match.group(3)!, "$month", match.group(2)!);
        if (date != null) return date;
      }
      for (final match in _numericDate.allMatches(row))
      {
        final first = int.parse(match.group(1)!);
        final second = int.parse(match.group(2)!);
        // A number above 12 can only be the day, so the order is only a guess when both fit
        final bool firstIsDay = first > 12 || (second <= 12 && dayFirst);
        final date = firstIsDay
          ? _validDate(match.group(3)!, "$second", "$first")
          : _validDate(match.group(3)!, "$first", "$second");
        if (date != null) return date;
      }
    }
    return null;
  }

  // Null for impossible dates (Feb 30), and for anything before 2000 or after tomorrow,
  // which on a receipt means the numbers were something else (or were misread)
  DateTime? _validDate(String year, String month, String day)
  {
    var y = int.parse(year);
    final m = int.parse(month);
    final d = int.parse(day);
    if (y < 100) y += 2000;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;

    final date = DateTime(y, m, d);
    // NOTE: DateTime rolls invalid days over (Feb 30 -> Mar 2), so check nothing moved
    if (date.month != m || date.day != d) return null;
    if (date.isBefore(DateTime(2000)) || date.isAfter(now.add(const Duration(days: 1)))) return null;
    return date;
  }

  // --- Shop name -------------------------------------------------------------------------

  // Typical header lines that aren't the shop's name
  static final RegExp _notAName = RegExp(
    r"receipt|invoice|welcome|thank|order|table|server|cashier|date|time|\babn\b|\bgst\b|\bvat\b|"
    r"\btel\b|phone|www\.|https?:|@|\.com|store\s*#|reg\s*#|trans|copy",
    caseSensitive: false,
  );

  String? _merchant(List<String> rows)
  {
    // The name is almost always in the first few lines
    for (final row in rows.take(6))
    {
      final letters = RegExp(r"[A-Za-zÀ-ÿ]").allMatches(row).length;
      final digits = RegExp(r"\d").allMatches(row).length;
      if (letters < 3 || digits > letters || _notAName.hasMatch(row)) continue;

      final name = row
        .replaceAll(RegExp(r"^[^A-Za-z0-9À-ÿ]+|[^A-Za-z0-9À-ÿ.!)']+$"), "")
        .replaceAll(RegExp(r"\s+"), " ")
        .trim();
      if (name.length < 3) continue;

      return _tidyCase(name.length > 40 ? name.substring(0, 40).trim() : name);
    }
    return null;
  }

  // "TESCO EXPRESS" -> "Tesco Express". Mixed case names are left as the shop wrote them
  static String _tidyCase(String name)
  {
    if (name != name.toUpperCase()) return name;
    return name.split(" ").map((word) {
      if (word.length <= 1) return word;
      return word[0] + word.substring(1).toLowerCase();
    }).join(" ");
  }
}
