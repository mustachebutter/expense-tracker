import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/services/receipt_images.dart';
import 'package:expense_tracker/services/receipt_scanner.dart';

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
  Future<Uint8List?> read(String receiptId) async => images[receiptId];

  @override
  Future<bool> exists(String receiptId) async => images.containsKey(receiptId);

  @override
  Future<void> delete(String receiptId) async => images.remove(receiptId);
}

// Pretends the user picked [nextImage] (or cancelled, if it's null)
class FakeReceiptImagePicker implements ReceiptImagePicker
{
  @override
  final bool canUseCamera;

  @override
  final bool canScanDocuments;

  Uint8List? nextImage = Uint8List.fromList([1, 2, 3]);
  final List<ReceiptImageSource> requestedSources = [];

  FakeReceiptImagePicker({this.canUseCamera = false, this.canScanDocuments = false});

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

// Pretends to read [rows] off every photo (or to fail, if [failWith] is set).
// [rowsWhenTurned] simulates a sideways photo: the text only makes sense turned that many times
class FakeReceiptScanner implements ReceiptScanner
{
  @override
  final bool isAvailable;

  List<String> rows;
  Map<int, List<String>>? rowsWhenTurned;
  Object? failWith;
  final List<String> scannedPaths = [];
  final List<int> triedTurns = [];

  FakeReceiptScanner({this.isAvailable = true, this.rows = const [], this.rowsWhenTurned});

  @override
  Future<List<String>> readRows(File image, {int quarterTurns = 0}) async
  {
    scannedPaths.add(image.path);
    triedTurns.add(quarterTurns);
    if (failWith != null) throw failWith!;
    if (rowsWhenTurned != null) return rowsWhenTurned![quarterTurns] ?? const ["~~ garbled ~~"];
    return quarterTurns == 0 ? rows : const [];
  }
}
