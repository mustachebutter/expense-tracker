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

    final shrunk = await ReceiptPhotoShrinker().shrink(photo);

    expect(img.decodeImage(shrunk)!.width, 2000);
  });
}
