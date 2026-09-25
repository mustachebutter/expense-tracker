import 'dart:io';

import 'package:expense_tracker/services/receipt_text_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

// Reads the text in a receipt photo, as printed rows from top to bottom
abstract class ReceiptScanner
{
  // Whether this scanner works on this device at all
  bool get isAvailable;

  Future<List<String>> readRows(File image);
}

// Google ML Kit text recognition. Runs on the phone, offline, and free
class MlKitReceiptScanner implements ReceiptScanner
{
  // NOTE: ML Kit only exists for Android and iOS. On Windows the package is still compiled
  // in, but calling it would fail, so nothing calls it there
  @override
  bool get isAvailable => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Future<List<String>> readRows(File image) async
  {
    // Latin covers English and most European languages, and Vietnamese
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try
    {
      final recognized = await recognizer.processImage(InputImage.fromFilePath(image.path));
      return groupIntoRows([
        for (final block in recognized.blocks)
          for (final line in block.lines)
            (text: line.text, box: line.boundingBox),
      ]);
    }
    finally
    {
      await recognizer.close();
    }
  }
}
