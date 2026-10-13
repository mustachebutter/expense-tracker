import 'dart:ui' show Offset;

import 'package:expense_tracker/services/receipt_crop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// A dark "table" with a light "receipt" drawn as the four-sided shape [corners] (in pixels)
img.Image photoOfReceipt(int width, int height, List<Offset> corners)
{
  final photo = img.Image(width: width, height: height);
  img.fill(photo, color: img.ColorRgb8(70, 55, 45));
  img.fillPolygon(
    photo,
    vertices: [for (final c in corners) img.Point(c.dx, c.dy)],
    color: img.ColorRgb8(245, 242, 235),
  );
  return photo;
}

void expectCloseTo(List<Offset> actual, List<Offset> expected, {double within = 0.03})
{
  for (var i = 0; i < 4; i++)
  {
    expect((actual[i] - expected[i]).distance, lessThan(within), reason: "corner $i: ${actual[i]} vs ${expected[i]}");
  }
}

void main()
{
  group("detectReceiptCorners", () {
    test("finds a receipt lying straight on a dark table", () {
      final photo = photoOfReceipt(600, 800, const [Offset(150, 100), Offset(450, 100), Offset(450, 700), Offset(150, 700)]);

      final corners = detectReceiptCorners(photo)!;

      expectCloseTo(corners, const [Offset(0.25, 0.125), Offset(0.75, 0.125), Offset(0.75, 0.875), Offset(0.25, 0.875)]);
    });

    test("finds the corners of a receipt photographed at an angle", () {
      // Narrower at the top, like a receipt photographed from below
      final photo = photoOfReceipt(600, 800, const [Offset(200, 80), Offset(400, 100), Offset(500, 720), Offset(90, 700)]);

      final corners = detectReceiptCorners(photo)!;

      expectCloseTo(corners, const [Offset(200 / 600, 0.1), Offset(400 / 600, 0.125), Offset(500 / 600, 0.9), Offset(90 / 600, 0.875)]);
    });

    test("gives up when there's no clear receipt, e.g. white on white", () {
      final plain = img.Image(width: 400, height: 400);
      img.fill(plain, color: img.ColorRgb8(240, 240, 240));

      expect(detectReceiptCorners(plain), isNull);
    });
  });

  group("cropToCorners", () {
    test("keeps only the receipt, as a flat rectangle", () {
      final photo = photoOfReceipt(600, 800, const [Offset(150, 100), Offset(450, 100), Offset(450, 700), Offset(150, 700)]);
      const corners = [Offset(0.25, 0.125), Offset(0.75, 0.125), Offset(0.75, 0.875), Offset(0.25, 0.875)];

      final receipt = cropToCorners(photo, corners);

      expect((receipt.width, receipt.height), (300, 600));
      // Every edge of the result is receipt paper, none of the table is left
      for (final (x, y) in [(2, 2), (297, 2), (297, 597), (2, 597), (150, 300)])
      {
        expect(receipt.getPixel(x, y).r, greaterThan(200), reason: "pixel ($x, $y)");
      }
    });

    test("straightens a receipt photographed at an angle", () {
      const skewed = [Offset(200, 80), Offset(400, 100), Offset(500, 720), Offset(90, 700)];
      final photo = photoOfReceipt(600, 800, skewed);

      final receipt = cropToCorners(photo, [for (final c in skewed) Offset(c.dx / 600, c.dy / 800)]);

      // Corners of the flattened result land inside the paper, not on the table
      final w = receipt.width, h = receipt.height;
      for (final (x, y) in [(3, 3), (w - 4, 3), (w - 4, h - 4), (3, h - 4)])
      {
        expect(receipt.getPixel(x, y).r, greaterThan(200), reason: "pixel ($x, $y)");
      }
    });

    test("never makes a huge image, whatever the photo's size", () {
      final photo = photoOfReceipt(3000, 4000, const [Offset(0, 0), Offset(3000, 0), Offset(3000, 4000), Offset(0, 4000)]);

      final receipt = cropToCorners(photo, const [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)], maxSide: 800);

      expect((receipt.width, receipt.height), (600, 800));
    });
  });

  group("corners", () {
    test("survive the trip to the database and back", () {
      const corners = [Offset(0.1, 0.05), Offset(0.9, 0.06), Offset(0.88, 0.97), Offset(0.12, 0.95)];

      expect(decodeCorners(encodeCorners(corners)), corners);
      expect(decodeCorners(null), isNull);
      expect(decodeCorners("garbage"), isNull);
    });

    test("rotating a cropped photo keeps the crop on the same part of the receipt", () {
      // A crop covering the left half of the photo
      const leftHalf = [Offset(0, 0), Offset(0.5, 0), Offset(0.5, 1), Offset(0, 1)];

      // Turned clockwise, the left half of the photo becomes the top half
      expect(rotateCornersClockwise(leftHalf), const [Offset(0, 0), Offset(1, 0), Offset(1, 0.5), Offset(0, 0.5)]);

      // Four quarter turns is back where it started
      var corners = leftHalf;
      for (var i = 0; i < 4; i++)
      {
        corners = rotateCornersClockwise(corners);
      }
      expect(corners, leftHalf);
    });
  });
}
