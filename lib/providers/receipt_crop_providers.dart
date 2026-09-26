import 'dart:io';
import 'dart:typed_data';

import 'package:expense_tracker/providers/core_providers.dart';
import 'package:expense_tracker/services/receipt_crop.dart';
import 'package:expense_tracker/services/receipt_images.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// The heavy image work behind cropping. A class (and a provider) so tests can swap in a
// fake that answers instantly instead of decoding real photos
class ReceiptCropper
{
  Future<CropEditorImage> prepare(Uint8List photo, int quarterTurns) => prepareForCropping(photo, quarterTurns);

  Future<Uint8List> render(Uint8List photo, int quarterTurns, ReceiptCorners corners)
  {
    return renderCroppedReceipt(photo, quarterTurns, corners);
  }
}

final receiptCropperProvider = Provider<ReceiptCropper>((ref) => ReceiptCropper());

// The cropped copy of a receipt's photo: from the cache if it's been made before, otherwise
// made now from the original and cached. Null if the original isn't on this device yet
Future<File?> croppedReceiptFile(
  ReceiptImageStore store,
  ReceiptCropper cropper, {
  required String receiptId,
  required int quarterTurns,
  required String cropCorners,
}) async
{
  final corners = decodeCorners(cropCorners);
  if (corners == null) return null;

  final key = cropCacheKey(quarterTurns, cropCorners);
  final cached = await store.croppedFileFor(receiptId, key);
  if (await cached.exists()) return cached;

  final original = await store.read(receiptId);
  if (original == null) return null;

  return store.saveCropped(receiptId, key, await cropper.render(original, quarterTurns, corners));
}

typedef CroppedImageKey = ({String receiptId, int quarterTurns, String cropCorners});

final croppedReceiptImageProvider = FutureProvider.autoDispose.family<File?, CroppedImageKey>((ref, key) {
  return croppedReceiptFile(
    ref.watch(receiptImageStoreProvider),
    ref.watch(receiptCropperProvider),
    receiptId: key.receiptId,
    quarterTurns: key.quarterTurns,
    cropCorners: key.cropCorners,
  );
});
