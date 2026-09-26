import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

// NOTE: Receipt photos are stored on every device and in Supabase Storage (1 GB on the free
// plan). A phone photo, a document scan or a file imported on Windows can be several MB,
// while a receipt is perfectly readable (by people and by ML Kit) at 2000px. So every new
// photo is shrunk before it's saved, which makes storage last several times longer
class ReceiptPhotoShrinker
{
  // Longest side of a stored photo, in pixels
  static const int maxSide = 2000;
  static const int jpegQuality = 85;

  // Photos already this small (and small enough in pixels) are kept exactly as they are
  static const int smallEnoughBytes = 700 * 1024;

  Future<Uint8List> shrink(Uint8List photo)
  {
    // NOTE: Decoding and re-encoding a big photo takes a second or two, so it runs in a
    // background isolate instead of freezing the screen
    return Isolate.run(() => shrinkReceiptPhoto(photo));
  }
}

// The photo, at most [maxSide] pixels on its longest side, as a JPEG. Never returns something
// bigger than it was given, and returns the photo untouched when it's already small or when
// it can't be read as an image (the receipt still gets saved, just not shrunk)
Uint8List shrinkReceiptPhoto(
  Uint8List photo, {
  int maxSide = ReceiptPhotoShrinker.maxSide,
  int quality = ReceiptPhotoShrinker.jpegQuality,
  int smallEnoughBytes = ReceiptPhotoShrinker.smallEnoughBytes,
})
{
  final img.Image? decoded;
  try
  {
    decoded = img.decodeImage(photo);
  }
  catch (e)
  {
    // NOTE: The image package throws (rather than returning null) on some data that isn't
    // an image at all
    return photo;
  }
  if (decoded == null) return photo;

  final bool tooManyPixels = math.max(decoded.width, decoded.height) > maxSide;
  if (!tooManyPixels && photo.length <= smallEnoughBytes) return photo;

  // NOTE: Phones often save photos sideways plus an "orientation" tag that viewers apply.
  // Re-encoding drops the tag, so apply it to the pixels first or the photo turns sideways
  var upright = img.bakeOrientation(decoded);
  if (math.max(upright.width, upright.height) > maxSide)
  {
    upright = upright.width >= upright.height
      ? img.copyResize(upright, width: maxSide, interpolation: img.Interpolation.average)
      : img.copyResize(upright, height: maxSide, interpolation: img.Interpolation.average);
  }

  final shrunk = img.encodeJpg(upright, quality: quality);
  // A photo that was already well compressed can come out bigger. Then keep the original,
  // unless it had too many pixels (smaller in pixels is the point then)
  return (shrunk.length < photo.length || tooManyPixels) ? shrunk : photo;
}
