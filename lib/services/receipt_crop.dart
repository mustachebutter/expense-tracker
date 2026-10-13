import 'dart:collection';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

import 'package:image/image.dart' as img;

// NOTE: How cutting a receipt out of a photo works:
// 1. Detect: receipts are bright paper, usually on a darker table. On a small copy of the
//    photo, find the bright pixels (Otsu's threshold picks "bright" automatically), take the
//    biggest connected patch of them, and use its four outermost points as the corners.
// 2. The user checks (and can drag) those corners in the crop editor.
// 3. Warp: map the four corners onto a flat rectangle (a perspective transform), so a
//    receipt photographed at an angle comes out straight, like a scanner would give.
//
// Corners are stored as fractions of the photo's size (0 to 1) in the order top-left,
// top-right, bottom-right, bottom-left, measured on the photo as shown (after rotation).
// The original photo is never changed, each device makes the cropped copy itself.

typedef ReceiptCorners = List<Offset>;

// "0.1,0.05,0.9,0.05,..." for the database, and back
String encodeCorners(ReceiptCorners corners)
{
  return corners.map((c) => "${c.dx.toStringAsFixed(4)},${c.dy.toStringAsFixed(4)}").join(",");
}

ReceiptCorners? decodeCorners(String? text)
{
  if (text == null || text.isEmpty) return null;
  final numbers = text.split(",").map(double.tryParse).toList();
  if (numbers.length != 8 || numbers.contains(null)) return null;
  return [for (var i = 0; i < 8; i += 2) Offset(numbers[i]!, numbers[i + 1]!)];
}

// Where the corners end up when the photo is turned a quarter turn clockwise, so a crop
// still covers the same part of the receipt after rotating it
ReceiptCorners rotateCornersClockwise(ReceiptCorners corners)
{
  Offset turn(Offset point) => Offset(1 - point.dy, point.dx);
  // The old bottom-left corner becomes the new top-left, and so on around
  return [turn(corners[3]), turn(corners[0]), turn(corners[1]), turn(corners[2])];
}

// The photo decoded, with the camera's orientation tag applied and turned upright.
// Everything else here works on this version of the photo
img.Image uprightImage(Uint8List bytes, int quarterTurns)
{
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException("Not an image");
  final oriented = img.bakeOrientation(decoded);
  return quarterTurns % 4 == 0 ? oriented : img.copyRotate(oriented, angle: 90 * (quarterTurns % 4));
}

// --- 1. Detecting the receipt ------------------------------------------------------------

// Finds the receipt's corners, or null when there's no clear receipt-shaped bright patch
// (e.g. a white receipt on a white table). The editor then starts from the whole photo
ReceiptCorners? detectReceiptCorners(img.Image photo)
{
  // NOTE: 300px is plenty to find a receipt's outline, and keeps this fast
  final small = photo.width >= photo.height
    ? img.copyResize(photo, width: math.min(300, photo.width))
    : img.copyResize(photo, height: math.min(300, photo.height));
  final width = small.width;
  final height = small.height;

  final brightness = Uint8List(width * height);
  final histogram = List<int>.filled(256, 0);
  for (var y = 0; y < height; y++)
  {
    for (var x = 0; x < width; x++)
    {
      final pixel = small.getPixel(x, y);
      final value = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).round().clamp(0, 255);
      brightness[y * width + x] = value;
      histogram[value]++;
    }
  }

  final threshold = _otsuThreshold(histogram, width * height);
  final biggest = _largestBrightPatch(brightness, width, height, threshold);

  // Too small to be the receipt, or so big it's the table itself: no confident answer
  final share = biggest.length / (width * height);
  if (share < 0.08 || share > 0.95) return null;

  // NOTE: The outermost points of the patch: top-left has the smallest x + y, bottom-right
  // the largest, top-right the largest x - y, bottom-left the smallest x - y. This works
  // for a receipt that's tilted or photographed at an angle
  var topLeft = biggest.first, topRight = biggest.first, bottomRight = biggest.first, bottomLeft = biggest.first;
  for (final index in biggest)
  {
    final x = index % width, y = index ~/ width;
    int sum(int i) => i % width + i ~/ width;
    int diff(int i) => i % width - i ~/ width;
    if (x + y < sum(topLeft)) topLeft = index;
    if (x + y > sum(bottomRight)) bottomRight = index;
    if (x - y > diff(topRight)) topRight = index;
    if (x - y < diff(bottomLeft)) bottomLeft = index;
  }

  Offset fraction(int index) => Offset((index % width + 0.5) / width, (index ~/ width + 0.5) / height);
  return [fraction(topLeft), fraction(topRight), fraction(bottomRight), fraction(bottomLeft)];
}

// Otsu's method: the brightness that best splits the photo into a dark group and a light group
int _otsuThreshold(List<int> histogram, int total)
{
  var sumAll = 0.0;
  for (var i = 0; i < 256; i++)
  {
    sumAll += i * histogram[i];
  }

  var sumDark = 0.0, countDark = 0, best = 0.0, threshold = 128;
  for (var i = 0; i < 256; i++)
  {
    countDark += histogram[i];
    if (countDark == 0) continue;
    final countLight = total - countDark;
    if (countLight == 0) break;

    sumDark += i * histogram[i];
    final meanDark = sumDark / countDark;
    final meanLight = (sumAll - sumDark) / countLight;
    final between = countDark * countLight * (meanDark - meanLight) * (meanDark - meanLight);
    if (between > best)
    {
      best = between;
      threshold = i;
    }
  }
  return threshold;
}

// The biggest group of touching bright pixels, as pixel indexes
List<int> _largestBrightPatch(Uint8List brightness, int width, int height, int threshold)
{
  final visited = Uint8List(width * height);
  var biggest = <int>[];

  for (var start = 0; start < brightness.length; start++)
  {
    if (visited[start] == 1 || brightness[start] <= threshold) continue;

    final patch = <int>[];
    final queue = Queue<int>()..add(start);
    visited[start] = 1;
    while (queue.isNotEmpty)
    {
      final index = queue.removeFirst();
      patch.add(index);
      final x = index % width, y = index ~/ width;
      for (final next in [
        if (x > 0) index - 1,
        if (x < width - 1) index + 1,
        if (y > 0) index - width,
        if (y < height - 1) index + width,
      ])
      {
        if (visited[next] == 0 && brightness[next] > threshold)
        {
          visited[next] = 1;
          queue.add(next);
        }
      }
    }
    if (patch.length > biggest.length) biggest = patch;
  }
  return biggest;
}

// --- 3. Straightening the receipt ----------------------------------------------------------

// Cuts the area inside [corners] out of [photo] and flattens it into a rectangle
img.Image cropToCorners(img.Image photo, ReceiptCorners corners, {int maxSide = 1600})
{
  final points = [for (final c in corners) Offset(c.dx * photo.width, c.dy * photo.height)];
  double distance(Offset a, Offset b) => (a - b).distance;

  // The flat receipt is as wide and tall as its longest edges
  var outWidth = math.max(distance(points[0], points[1]), distance(points[3], points[2]));
  var outHeight = math.max(distance(points[0], points[3]), distance(points[1], points[2]));
  final scale = math.min(1.0, maxSide / math.max(outWidth, outHeight));
  outWidth = math.max(1, outWidth * scale);
  outHeight = math.max(1, outHeight * scale);

  final w = outWidth.round(), h = outHeight.round();
  final transform = _perspectiveTransform(
    [Offset.zero, Offset(w.toDouble(), 0), Offset(w.toDouble(), h.toDouble()), Offset(0, h.toDouble())],
    points,
  );

  final result = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++)
  {
    for (var x = 0; x < w; x++)
    {
      // Where this pixel of the flat receipt comes from in the photo
      final source = transform(x + 0.5, y + 0.5);
      final pixel = photo.getPixelInterpolate(source.dx - 0.5, source.dy - 0.5, interpolation: img.Interpolation.linear);
      result.setPixelRgb(x, y, pixel.r, pixel.g, pixel.b);
    }
  }
  return result;
}

// The perspective transform (homography) that maps each point in [from] to the matching
// point in [to]. Solves the 8 equations the 4 point pairs give
Offset Function(double x, double y) _perspectiveTransform(List<Offset> from, List<Offset> to)
{
  final a = List.generate(8, (_) => List<double>.filled(9, 0));
  for (var i = 0; i < 4; i++)
  {
    final (x, y, u, v) = (from[i].dx, from[i].dy, to[i].dx, to[i].dy);
    a[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u];
    a[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v];
  }

  // Gaussian elimination with partial pivoting
  for (var col = 0; col < 8; col++)
  {
    var pivot = col;
    for (var row = col + 1; row < 8; row++)
    {
      if (a[row][col].abs() > a[pivot][col].abs()) pivot = row;
    }
    final swap = a[col]; a[col] = a[pivot]; a[pivot] = swap;
    if (a[col][col].abs() < 1e-12) throw const FormatException("The corners don't make a shape");

    for (var row = 0; row < 8; row++)
    {
      if (row == col) continue;
      final factor = a[row][col] / a[col][col];
      for (var k = col; k < 9; k++)
      {
        a[row][k] -= factor * a[col][k];
      }
    }
  }
  final h = [for (var i = 0; i < 8; i++) a[i][8] / a[i][i]];

  return (x, y) {
    final d = h[6] * x + h[7] * y + 1;
    return Offset((h[0] * x + h[1] * y + h[2]) / d, (h[3] * x + h[4] * y + h[5]) / d);
  };
}

// A short, stable name for one crop of one photo (the rotation matters too, the corners are
// measured on the rotated photo). Used to name the cached cropped copy
String cropCacheKey(int quarterTurns, String corners)
{
  // NOTE: FNV-1a, a tiny hash that gives the same answer on every device and every run
  var hash = 0x811c9dc5;
  for (final unit in "$quarterTurns|$corners".codeUnits)
  {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16);
}

// --- The work, off the main thread ---------------------------------------------------------

// What the crop editor needs: a small upright copy to show, its size, and a first guess
typedef CropEditorImage = ({Uint8List preview, Size size, ReceiptCorners? detected});

Future<CropEditorImage> prepareForCropping(Uint8List photoBytes, int quarterTurns)
{
  // NOTE: Decoding a 2000px photo takes a moment, so it runs in a background isolate
  return Isolate.run(() {
    final upright = uprightImage(photoBytes, quarterTurns);
    final preview = upright.width >= upright.height
      ? img.copyResize(upright, width: math.min(1200, upright.width))
      : img.copyResize(upright, height: math.min(1200, upright.height));
    return (
      preview: img.encodeJpg(preview, quality: 85),
      size: Size(preview.width.toDouble(), preview.height.toDouble()),
      detected: detectReceiptCorners(upright),
    );
  });
}

// The cropped, straightened receipt as a JPEG
Future<Uint8List> renderCroppedReceipt(Uint8List photoBytes, int quarterTurns, ReceiptCorners corners)
{
  return Isolate.run(() => img.encodeJpg(cropToCorners(uprightImage(photoBytes, quarterTurns), corners), quality: 88));
}
