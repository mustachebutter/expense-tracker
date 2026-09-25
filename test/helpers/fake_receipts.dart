import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/services/receipt_images.dart';

import 'test_database.dart';

// NOTE: Keeps "saved" photos in a map instead of on disk. Real file writes don't finish
// inside widget tests (their clock is fake), and tests shouldn't leave files behind anyway
class FakeReceiptImageStore extends ReceiptImageStore
{
  final Map<String, Uint8List> images = {};

  FakeReceiptImageStore() : super(() async => Directory.systemTemp);

  @override
  Future<File> save(String receiptId, Uint8List bytes) async
  {
    images[receiptId] = bytes;
    return ReceiptImageStore.fileIn(Directory.systemTemp, receiptId);
  }

  @override
  Future<void> delete(String receiptId) async => images.remove(receiptId);
}

// Pretends the user picked [nextImage] (or cancelled, if it's null)
class FakeReceiptImagePicker implements ReceiptImagePicker
{
  @override
  final bool canUseCamera;

  Uint8List? nextImage = Uint8List.fromList([1, 2, 3]);
  final List<ReceiptImageSource> requestedSources = [];

  FakeReceiptImagePicker({this.canUseCamera = false});

  @override
  Future<Uint8List?> pick(ReceiptImageSource source) async
  {
    requestedSources.add(source);
    return nextImage;
  }
}

Future<Receipt> insertReceipt(
  AppDatabase db, {
  String? merchant,
  double? total,
  DateTime? date,
  String? categoryId,
  String userId = userA,
  bool isFavorite = false,
  double? boardX,
  double? boardY,
  int boardZ = 0,
  bool isDeleted = false,
  DateTime? createdAt,
}) async
{
  return db.into(db.receipts).insertReturning(
    ReceiptsCompanion.insert(
      userId: userId,
      merchant: Value(merchant),
      total: Value(total),
      date: Value(date),
      categoryId: Value(categoryId),
      isFavorite: Value(isFavorite),
      boardX: Value(boardX),
      boardY: Value(boardY),
      boardZ: Value(boardZ),
      isDeleted: Value(isDeleted),
      createdAt: createdAt == null ? const Value.absent() : Value(createdAt),
    ),
  );
}
