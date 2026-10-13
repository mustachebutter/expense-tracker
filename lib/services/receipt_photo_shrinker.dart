import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

// What a photo's EXIF data says about it, if the camera recorded it
typedef PhotoDetails = ({DateTime? takenAt, double? latitude, double? longitude});

const PhotoDetails noPhotoDetails = (takenAt: null, latitude: null, longitude: null);

// The photo to save, and what its EXIF said before shrinking removed it
typedef PreparedPhoto = ({Uint8List bytes, PhotoDetails details});

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

  // Reads the photo's EXIF details, then shrinks it
  // NOTE: In that order, because re-encoding the photo drops the EXIF data
  Future<PreparedPhoto> prepare(Uint8List photo)
  {
    // NOTE: Decoding and re-encoding a big photo takes a second or two, so it runs in a
    // background isolate instead of freezing the screen
    return Isolate.run(() {
      // Decoded once and used for both, decoding is the slow part
      final decoded = _tryDecode(photo);
      // NOTE: Details first, shrinking turns the photo upright and that edits its EXIF
      final details = readPhotoDetails(photo, decoded: decoded);
      return (bytes: shrinkReceiptPhoto(photo, decoded: decoded), details: details);
    });
  }
}

// When and where the photo was taken, from its EXIF data. Anything the camera didn't record
// (or the phone removed, Android often strips GPS from gallery photos) comes back null
PhotoDetails readPhotoDetails(Uint8List photo, {img.Image? decoded})
{
  final image = decoded ?? _tryDecode(photo);
  if (image == null || !image.hasExif) return noPhotoDetails;
  final exif = image.exif;

  // "2026:09:12 14:32:05", when the photo was taken (DateTime is when the file was last changed)
  final taken = exif.exifIfd[0x9003]?.toString() ?? exif.imageIfd[0x0132]?.toString();

  final gps = exif.gpsIfd;
  final latitude = _gpsCoordinate(gps[0x0002], gps[0x0001]?.toString(), negative: "S");
  final longitude = _gpsCoordinate(gps[0x0004], gps[0x0003]?.toString(), negative: "W");
  final bothKnown = latitude != null && longitude != null && !(latitude == 0 && longitude == 0);

  return (
    takenAt: _parseExifDate(taken),
    latitude: bothKnown ? latitude : null,
    longitude: bothKnown ? longitude : null,
  );
}

// EXIF stores a coordinate as degrees, minutes and seconds, plus N/S or E/W
// NOTE: image's own gpsLatitude getter only returns the whole degrees, up to ~100 km off
double? _gpsCoordinate(img.IfdValue? value, String? reference, {required String negative})
{
  if (value == null || value.length == 0) return null;
  double part(int index) => index < value.length ? value.toDouble(index) : 0;
  final degrees = part(0) + part(1) / 60 + part(2) / 3600;
  if (degrees.isNaN || degrees.isInfinite) return null;
  return (reference ?? "").toUpperCase().contains(negative) ? -degrees : degrees;
}

DateTime? _parseExifDate(String? text)
{
  final match = RegExp(r"(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})").firstMatch(text ?? "");
  if (match == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  // Cameras with an unset clock write zeros
  if (parts[0] < 2000 || parts[1] == 0 || parts[2] == 0) return null;
  return DateTime(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
}

// The photo, at most [maxSide] pixels on its longest side, as a JPEG. Never returns something
// bigger than it was given, and returns the photo untouched when it's already small or when
// it can't be read as an image (the receipt still gets saved, just not shrunk)
// The photo decoded, or null if it isn't one
img.Image? _tryDecode(Uint8List photo)
{
  try
  {
    return img.decodeImage(photo);
  }
  catch (e)
  {
    // NOTE: The image package throws (rather than returning null) on some data that isn't
    // an image at all
    return null;
  }
}

Uint8List shrinkReceiptPhoto(
  Uint8List photo, {
  img.Image? decoded,
  int maxSide = ReceiptPhotoShrinker.maxSide,
  int quality = ReceiptPhotoShrinker.jpegQuality,
  int smallEnoughBytes = ReceiptPhotoShrinker.smallEnoughBytes,
})
{
  final image = decoded ?? _tryDecode(photo);
  if (image == null) return photo;

  final bool tooManyPixels = math.max(image.width, image.height) > maxSide;
  if (!tooManyPixels && photo.length <= smallEnoughBytes) return photo;

  // NOTE: Phones often save photos sideways plus an "orientation" tag that viewers apply.
  // Re-encoding drops the tag, so apply it to the pixels first or the photo turns sideways
  var upright = img.bakeOrientation(image);
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
