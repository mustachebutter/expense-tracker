import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Keeps receipt photos in the app's own folder, one file per receipt: receipts/<id>.jpg.
// NOTE: The name is derived from the receipt's id instead of being stored in the database,
// because a full path only makes sense on the device that saved the file
class ReceiptImageStore
{
  final Future<Directory> Function() _directory;

  ReceiptImageStore(this._directory);

  // The real one: a "receipts" folder inside the app's documents folder
  factory ReceiptImageStore.appDocuments()
  {
    return ReceiptImageStore(() async {
      final documents = await getApplicationDocumentsDirectory();
      return Directory(p.join(documents.path, "receipts"));
    });
  }

  Future<Directory> directory() => _directory();

  static File fileIn(Directory directory, String receiptId) => File(p.join(directory.path, "$receiptId.jpg"));

  Future<File> save(String receiptId, Uint8List bytes) async
  {
    final folder = await _directory();
    await folder.create(recursive: true);
    return fileIn(folder, receiptId).writeAsBytes(bytes, flush: true);
  }

  // The photo's file on this device (it may not exist, e.g. not downloaded yet)
  Future<File> fileFor(String receiptId) async => fileIn(await _directory(), receiptId);

  Future<bool> exists(String receiptId) async => (await fileFor(receiptId)).exists();

  // The photo's bytes, or null if it isn't on this device
  Future<Uint8List?> read(String receiptId) async
  {
    final file = await fileFor(receiptId);
    return await file.exists() ? file.readAsBytes() : null;
  }

  // A cached cropped copy, named after the crop so a new crop never shows a stale copy
  Future<File> croppedFileFor(String receiptId, String cropKey) async
  {
    return File(p.join((await _directory()).path, "${receiptId}_crop_$cropKey.jpg"));
  }

  // Saves a cropped copy and removes older crops of the same receipt
  Future<File> saveCropped(String receiptId, String cropKey, Uint8List bytes) async
  {
    await _deleteCroppedCopies(receiptId);
    final file = await croppedFileFor(receiptId, cropKey);
    await file.parent.create(recursive: true);
    return file.writeAsBytes(bytes, flush: true);
  }

  Future<void> _deleteCroppedCopies(String receiptId) async
  {
    final folder = await _directory();
    if (!await folder.exists()) return;
    await for (final entry in folder.list())
    {
      if (entry is File && p.basename(entry.path).startsWith("${receiptId}_crop_")) await entry.delete();
    }
  }

  Future<void> delete(String receiptId) async
  {
    final file = fileIn(await _directory(), receiptId);
    if (await file.exists()) await file.delete();
    await _deleteCroppedCopies(receiptId);
  }
}

enum ReceiptImageSource
{
  // Google's document scanner (Android): finds the receipt's edges, crops away the
  // background and straightens it
  documentScanner,
  camera,
  gallery,
}

// Opens the camera or the photo/file picker and returns the chosen image's bytes
class ReceiptImagePicker
{
  // NOTE: image_picker can only take photos on phones. On Windows and macOS it opens a
  // file picker instead, so the app only offers "Import image" there
  bool get canUseCamera => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // NOTE: ML Kit's document scanner only exists on Android (and needs Google Play services)
  bool get canScanDocuments => !kIsWeb && Platform.isAndroid;

  // Null if the user cancelled
  Future<Uint8List?> pick(ReceiptImageSource source) async
  {
    if (source == ReceiptImageSource.documentScanner) return _scanDocument();

    final image = await ImagePicker().pickImage(
      source: source == ReceiptImageSource.camera ? ImageSource.camera : ImageSource.gallery,
      // NOTE: Phone photos are often 4000px+. This is plenty to read a receipt and keeps
      // files small. Desktop file pickers ignore these and keep the original
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 85,
    );
    return image?.readAsBytes();
  }

  Future<Uint8List?> _scanDocument() async
  {
    final scanner = DocumentScanner(
      // One page, as a JPEG. Its screen also has a button to import from the gallery instead
      options: DocumentScannerOptions(pageLimit: 1, mode: ScannerMode.full, isGalleryImport: true),
    );
    try
    {
      final result = await scanner.scanDocument();
      final images = result.images ?? [];
      return images.isEmpty ? null : File(images.first).readAsBytes();
    }
    on PlatformException catch (e)
    {
      // Backing out of the scanner arrives as an error, treat it like cancelling a picker
      print("Document scanner closed: ${e.message}");
      return null;
    }
    finally
    {
      await scanner.close();
    }
  }
}
