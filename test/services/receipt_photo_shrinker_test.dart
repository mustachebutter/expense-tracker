import 'dart:math' as math;
import 'dart:typed_data';

import 'package:expense_tracker/services/receipt_photo_shrinker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// A photo full of random speckles. Unlike a plain color, it doesn't compress to almost
// nothing, so file sizes behave like a real photo's
img.Image speckled(int width, int height)
{
  final random = math.Random(42);
  final photo = img.Image(width: width, height: height);
  for (final pixel in photo)
  {
    pixel.setRgb(random.nextInt(256), random.nextInt(256), random.nextInt(256));
  }
  return photo;
}

bool isJpeg(Uint8List bytes) => bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;

void main()
{
  test("a big photo is shrunk to 2000px on its longest side, as a JPEG", () {
    final photo = img.encodePng(img.Image(width: 4000, height: 3000));

    final shrunk = shrinkReceiptPhoto(photo);

    final decoded = img.decodeImage(shrunk)!;
    expect((decoded.width, decoded.height), (2000, 1500));
    expect(isJpeg(shrunk), isTrue);
  });

  test("a tall receipt keeps its shape", () {
    final photo = img.encodePng(img.Image(width: 1500, height: 5000));

    final decoded = img.decodeImage(shrinkReceiptPhoto(photo))!;

    expect((decoded.width, decoded.height), (600, 2000));
  });

  test("a photo that's already small is kept exactly as it is", () {
    final photo = img.encodeJpg(img.Image(width: 1200, height: 1600), quality: 85);

    expect(shrinkReceiptPhoto(photo), same(photo));
  });

  test("a sideways-tagged photo comes out upright, not turned", () {
    // Stored 3000 wide x 2000 tall, with a tag saying "show this turned a quarter turn"
    final sideways = img.Image(width: 3000, height: 2000);
    sideways.exif.imageIfd.orientation = 6;
    final photo = img.encodeJpg(sideways);

    final decoded = img.decodeImage(shrinkReceiptPhoto(photo))!;

    // Shown upright it's 2000 wide x 3000 tall, so shrunk it's taller than wide
    expect(decoded.height, 2000);
    expect(decoded.width, lessThan(decoded.height));
    expect(decoded.exif.imageIfd.orientation ?? 1, 1, reason: "the turn is in the pixels now, not a tag");
  });

  test("never makes a file bigger", () {
    // Already heavily compressed, and over the "small enough" size: re-encoding at a higher
    // quality would make it bigger, so the original is kept
    final photo = img.encodeJpg(speckled(1500, 1500), quality: 40);
    expect(photo.length, greaterThan(ReceiptPhotoShrinker.smallEnoughBytes));

    expect(shrinkReceiptPhoto(photo), same(photo));
  });

  test("something that isn't an image is saved untouched", () {
    final notAnImage = Uint8List.fromList([1, 2, 3]);

    expect(shrinkReceiptPhoto(notAnImage), same(notAnImage));
  });

  test("the background version gives the same result", () async {
    final photo = img.encodePng(img.Image(width: 4000, height: 3000));

    final prepared = await ReceiptPhotoShrinker().prepare(photo);

    expect(img.decodeImage(prepared.bytes)!.width, 2000);
  });

  group("readPhotoDetails", () {
    // A JPEG with EXIF written the way a phone camera writes it: GPS as degrees, minutes and
    // seconds (each a fraction), plus N/S and E/W, and the date it was taken
    Uint8List photoWithExif({required String taken, required List<List<int>> latitude, required String latitudeRef,
      required List<List<int>> longitude, required String longitudeRef})
    {
      final photo = img.Image(width: 400, height: 300);
      photo.exif.exifIfd[0x9003] = img.IfdValueAscii(taken);
      final gps = photo.exif.gpsIfd;
      gps[0x0001] = img.IfdValueAscii(latitudeRef);
      gps[0x0002] = img.IfdValueRational.list([for (final part in latitude) img.IfdValueRational(part[0], part[1]).toRational()]);
      gps[0x0003] = img.IfdValueAscii(longitudeRef);
      gps[0x0004] = img.IfdValueRational.list([for (final part in longitude) img.IfdValueRational(part[0], part[1]).toRational()]);
      return img.encodeJpg(photo);
    }

    test("reads where and when a photo was taken, down to the suburb", () {
      // Etobicoke, Toronto: 43° 37' 13.8" N, 79° 30' 47.5" W
      final photo = photoWithExif(
        taken: "2026:09:12 14:32:05",
        latitude: [[43, 1], [37, 1], [138, 10]], latitudeRef: "N",
        longitude: [[79, 1], [30, 1], [475, 10]], longitudeRef: "W",
      );

      final details = readPhotoDetails(photo);

      expect(details.takenAt, DateTime(2026, 9, 12, 14, 32, 5));
      // NOTE: image's own gpsLatitude would say 43.0 here, ~70 km out. Minutes and seconds matter
      expect(details.latitude, closeTo(43.6205, 0.0001));
      expect(details.longitude, closeTo(-79.5132, 0.0001), reason: "west is negative");
    });

    test("south of the equator is negative too", () {
      final photo = photoWithExif(
        taken: "2026:01:02 03:04:05",
        latitude: [[33, 1], [52, 1], [0, 1]], latitudeRef: "S",
        longitude: [[151, 1], [12, 1], [0, 1]], longitudeRef: "E",
      );

      final details = readPhotoDetails(photo);

      expect(details.latitude, closeTo(-33.8667, 0.0001));
      expect(details.longitude, closeTo(151.2, 0.0001));
    });

    test("a photo without EXIF, or a camera with an unset clock, gives nothing", () {
      expect(readPhotoDetails(img.encodeJpg(img.Image(width: 10, height: 10))), noPhotoDetails);
      expect(readPhotoDetails(Uint8List.fromList([1, 2, 3])), noPhotoDetails);

      final unsetClock = photoWithExif(
        taken: "0000:00:00 00:00:00",
        latitude: [[0, 1], [0, 1], [0, 1]], latitudeRef: "N",
        longitude: [[0, 1], [0, 1], [0, 1]], longitudeRef: "E",
      );
      expect(readPhotoDetails(unsetClock), noPhotoDetails, reason: "0,0 is a camera without a GPS fix, not the sea off Africa");
    });

    test("prepare reads the details before shrinking removes them", () async {
      final photo = img.Image(width: 4000, height: 3000);
      photo.exif.exifIfd[0x9003] = img.IfdValueAscii("2026:09:12 14:32:05");

      final prepared = await ReceiptPhotoShrinker().prepare(img.encodeJpg(photo));

      expect(prepared.details.takenAt, DateTime(2026, 9, 12, 14, 32, 5));
      expect(img.decodeImage(prepared.bytes)!.width, 2000);
    });
  });
}
