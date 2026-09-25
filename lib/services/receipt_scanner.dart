import 'dart:io';
import 'dart:isolate';

import 'package:expense_tracker/services/receipt_text_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

// Reads the text in a receipt photo, as printed rows from top to bottom
abstract class ReceiptScanner
{
  // Whether this scanner works on this device at all
  bool get isAvailable;

  // [quarterTurns] turns the photo clockwise before reading, for sideways receipts
  Future<List<String>> readRows(File image, {int quarterTurns = 0});
}

// Writes a copy of [image] turned [quarterTurns] clockwise to a temporary file.
// NOTE: Runs in a background isolate, decoding and re-encoding a 2000px photo takes about a
// second and would otherwise freeze the screen
Future<File> rotatedCopy(File image, int quarterTurns) async
{
  final bytes = await image.readAsBytes();
  final rotated = await Isolate.run(() {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw const FormatException("Not an image");
    // NOTE: Phones often save photos sideways plus an "orientation" tag that viewers apply.
    // Apply the tag first, so turns are counted from how the photo actually looks
    final upright = img.bakeOrientation(decoded);
    return img.encodeJpg(img.copyRotate(upright, angle: 90 * quarterTurns), quality: 90);
  });

  final name = "receipt_scan_${DateTime.now().microsecondsSinceEpoch}.jpg";
  return File(p.join(Directory.systemTemp.path, name)).writeAsBytes(rotated);
}

// Google ML Kit text recognition. Runs on the phone, offline, and free
class MlKitReceiptScanner implements ReceiptScanner
{
  // NOTE: ML Kit only exists for Android and iOS. On Windows the package is still compiled
  // in, but calling it would fail, so nothing calls it there
  @override
  bool get isAvailable => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Future<List<String>> readRows(File image, {int quarterTurns = 0}) async
  {
    final File source = quarterTurns % 4 == 0 ? image : await rotatedCopy(image, quarterTurns);
    // Latin covers English and most European languages, and Vietnamese
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try
    {
      final recognized = await recognizer.processImage(InputImage.fromFilePath(source.path));
      return groupIntoRows([
        for (final block in recognized.blocks)
          for (final line in block.lines)
            (text: line.text, box: line.boundingBox),
      ]);
    }
    finally
    {
      await recognizer.close();
      if (source != image) await source.delete();
    }
  }
}
