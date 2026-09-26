import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_receipts.dart';
import '../helpers/fake_sync_remote.dart';
import '../helpers/test_database.dart';

// NOTE: Two "devices" (a phone and a PC), each with its own database and photo folder,
// sharing one pretend Supabase, like the real app on two machines
void main()
{
  late FakeSyncRemote server;
  late AppDatabase phoneDb;
  late AppDatabase pcDb;
  late FakeReceiptImageStore phonePhotos;
  late FakeReceiptImageStore pcPhotos;
  late SyncEngine phone;
  late SyncEngine pc;

  final photo = Uint8List.fromList([0xFF, 0xD8, 1, 2, 3]);

  setUp(() {
    server = FakeSyncRemote();
    phoneDb = createTestDatabase();
    pcDb = createTestDatabase();
    phonePhotos = FakeReceiptImageStore();
    pcPhotos = FakeReceiptImageStore();
    phone = SyncEngine(phoneDb, server, phonePhotos);
    pc = SyncEngine(pcDb, server, pcPhotos);
  });

  tearDown(() async {
    await phoneDb.close();
    await pcDb.close();
  });

  Future<Receipt> addReceiptWithPhoto(AppDatabase db, FakeReceiptImageStore photos, {String? merchant}) async
  {
    final receipt = await insertReceipt(db, merchant: merchant);
    await photos.save(receipt.id, photo);
    return receipt;
  }

  Future<Receipt> getReceipt(AppDatabase db, String id) async => (await db.receiptsDao.getReceiptById(id, userA))!;

  test("a receipt added on one device shows up on the other, with its photo", () async {
    final receipt = await addReceiptWithPhoto(pcDb, pcPhotos, merchant: "Tesco");

    await pc.runSync(userA);

    expect(server.receiptImages["$userA/${receipt.id}"], photo, reason: "the photo went to file storage");
    expect(server.rows("receipts").single["image_uploaded"], isTrue, reason: "and the row says so");
    expect((await getReceipt(pcDb, receipt.id)).isSynced, isTrue);

    await phone.runSync(userA);

    final onPhone = await getReceipt(phoneDb, receipt.id);
    expect(onPhone.merchant, "Tesco");
    expect(onPhone.imageUploaded, isTrue);
    expect(phonePhotos.images[receipt.id], photo, reason: "the phone downloaded the photo");
  });

  test("every field survives the trip, including empty ones", () async {
    final food = await insertCategory(pcDb, name: "Food");
    final full = await insertReceipt(pcDb, merchant: "Full", total: 12.5, date: DateTime(2026, 9, 3), categoryId: food.id,
      isFavorite: true, boardX: 120, boardY: 340, boardZ: 7);
    final empty = await insertReceipt(pcDb);
    await pcDb.receiptsDao.updateRow(full.copyWith(
      scanStatus: ReceiptScanStatus.scanned,
      transactionId: const Value("tx-1"),
      imageQuarterTurns: 3,
      splitPeople: const Value(4),
      cropCorners: const Value("0.1000,0.1000,0.9000,0.1000,0.9000,0.9000,0.1000,0.9000"),
      suburb: const Value("Hoàn Kiếm"),
      city: const Value("Hanoi"),
      state: const Value("Hà Nội"),
      country: const Value("Vietnam"),
      pendingLatitude: const Value(21.03),
      pendingLongitude: const Value(105.85),
    ));
    final customSplit = await insertReceipt(pcDb, total: 20);
    await pcDb.receiptsDao.updateRow(customSplit.copyWith(splitAmount: const Value(7.5)));

    await pc.runSync(userA);
    await phone.runSync(userA);

    final fullOnPhone = await getReceipt(phoneDb, full.id);
    expect(
      (fullOnPhone.merchant, fullOnPhone.total, fullOnPhone.date, fullOnPhone.categoryId, fullOnPhone.transactionId),
      ("Full", 12.5, DateTime(2026, 9, 3), food.id, "tx-1"),
    );
    expect((fullOnPhone.isFavorite, fullOnPhone.boardX, fullOnPhone.boardY, fullOnPhone.boardZ), (true, 120.0, 340.0, 7));
    expect(fullOnPhone.scanStatus, ReceiptScanStatus.scanned);
    expect((fullOnPhone.imageQuarterTurns, fullOnPhone.splitPeople, fullOnPhone.splitAmount), (3, 4, null));
    expect(fullOnPhone.cropCorners, "0.1000,0.1000,0.9000,0.1000,0.9000,0.9000,0.1000,0.9000");
    expect((fullOnPhone.suburb, fullOnPhone.city, fullOnPhone.state, fullOnPhone.country), ("Hoàn Kiếm", "Hanoi", "Hà Nội", "Vietnam"));
    expect((fullOnPhone.pendingLatitude, fullOnPhone.pendingLongitude), (21.03, 105.85), reason: "so the phone can name it");
    expect((await getReceipt(phoneDb, customSplit.id)).splitAmount, 7.5);
    expect(fullOnPhone.createdAt, full.createdAt);

    final emptyOnPhone = await getReceipt(phoneDb, empty.id);
    expect((emptyOnPhone.merchant, emptyOnPhone.total, emptyOnPhone.date, emptyOnPhone.boardX), (null, null, null, null));
  });

  test("a failed photo upload is retried on the next sync", () async {
    final receipt = await addReceiptWithPhoto(pcDb, pcPhotos);
    server.failingTables.add("receipt_images");

    await expectLater(pc.runSync(userA), throwsA(isA<SyncException>()));

    expect((await getReceipt(pcDb, receipt.id)).imageUploaded, isFalse);
    expect(server.receiptImages, isEmpty);

    server.failingTables.clear();
    await pc.runSync(userA);

    expect((await getReceipt(pcDb, receipt.id)).imageUploaded, isTrue);
    expect(server.receiptImages, hasLength(1));
  });

  test("deleting a receipt removes its photo from storage and from every device", () async {
    final receipt = await addReceiptWithPhoto(pcDb, pcPhotos);
    await pc.runSync(userA);
    await phone.runSync(userA);
    expect(phonePhotos.images, hasLength(1));

    await pcDb.receiptsDao.softDeleteById(receipt.id, userA);
    await pc.runSync(userA);

    expect(pcPhotos.images, isEmpty);
    expect(server.receiptImages, isEmpty);

    await phone.runSync(userA);

    expect((await getReceipt(phoneDb, receipt.id)).isDeleted, isTrue);
    expect(phonePhotos.images, isEmpty, reason: "the phone's copy is removed too");
  });

  test("setting image_uploaded doesn't undo an edit made while the photo uploaded", () async {
    final receipt = await addReceiptWithPhoto(pcDb, pcPhotos);
    await pcDb.receiptsDao.updateRow(receipt.copyWith(merchant: const Value("Typed meanwhile")));

    await pcDb.receiptsDao.setImageUploaded(receipt.id, true);

    final saved = await getReceipt(pcDb, receipt.id);
    expect(saved.merchant, "Typed meanwhile");
    expect(saved.imageUploaded, isTrue);
    expect(saved.isSynced, isFalse);
    expect(saved.updatedAt.isAfter(receipt.updatedAt), isTrue);
  });
}
