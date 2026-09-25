import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
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

  Future<void> delete(String receiptId) async
  {
    final file = fileIn(await _directory(), receiptId);
    if (await file.exists()) await file.delete();
  }
}

enum ReceiptImageSource { camera, gallery }

// Opens the camera or the photo/file picker and returns the chosen image's bytes
class ReceiptImagePicker
{
  // NOTE: image_picker can only take photos on phones. On Windows and macOS it opens a
  // file picker instead, so the app only offers "Import image" there
  bool get canUseCamera => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // Null if the user cancelled
  Future<Uint8List?> pick(ReceiptImageSource source) async
  {
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
}
