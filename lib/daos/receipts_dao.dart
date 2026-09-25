import 'package:drift/drift.dart';
import 'package:expense_tracker/daos/base_dao.dart';
import 'package:expense_tracker/database.dart';

part 'receipts_dao.g.dart';

@DriftAccessor(tables: [Receipts])
class ReceiptsDao extends BaseDao<Receipts, Receipt> with _$ReceiptsDaoMixin
{
  ReceiptsDao(AppDatabase db) : super(db, db.receipts);

  // Newest first: by the date printed on the receipt, or when it was added if that's unknown
  Stream<List<Receipt>> watchReceipts(String userId)
  {
    return (
      select(receipts)
        ..where((t) =>
          t.userId.equals(userId) &
          t.isDeleted.equals(false)
        )
        ..orderBy([
          (t) => OrderingTerm.desc(coalesce([t.date, t.createdAt])),
          (t) => OrderingTerm.desc(t.createdAt),
        ])
    ).watch();
  }

  Future<Receipt?> getReceiptById(String id, String userId)
  {
    return (
      select(receipts)
        ..where((t) =>
          t.userId.equals(userId) &
          t.id.equals(id)
        )
    ).getSingleOrNull();
  }

  // The highest stacking order on the user's board, so a picked up receipt can go on top
  Future<int> getTopBoardZ(String userId) async
  {
    final topZ = receipts.boardZ.max();
    final query = selectOnly(receipts)
      ..addColumns([topZ])
      ..where(receipts.userId.equals(userId) & receipts.isDeleted.equals(false));

    final row = await query.getSingle();
    return row.read(topZ) ?? 0;
  }

  // Every receipt the user has, deleted ones included. Photo sync needs the deleted ones too,
  // to remove their photos
  Future<List<Receipt>> getAllForUser(String userId)
  {
    return (select(receipts)..where((t) => t.userId.equals(userId))).get();
  }

  // Receipts waiting for the scanner, oldest first
  Future<List<Receipt>> getWaitingToScan(String userId)
  {
    return (
      select(receipts)
        ..where((t) =>
          t.userId.equals(userId) &
          t.isDeleted.equals(false) &
          t.scanStatus.equalsValue(ReceiptScanStatus.waiting)
        )
        ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
    ).get();
  }

  // The category this shop was put in most recently, on a receipt or a transaction, as long
  // as that category still exists. Lets a scanned "Tesco" land in Groceries automatically
  Future<String?> categoryUsedBefore(String merchant, String userId) async
  {
    final db = attachedDatabase;
    final row = await customSelect(
      '''
      SELECT used.category_id FROM (
        SELECT category_id, updated_at AS used_at FROM receipts
        WHERE user_id = ?1 AND is_deleted = 0 AND category_id IS NOT NULL AND lower(merchant) = lower(?2)
        UNION ALL
        SELECT category_id, date AS used_at FROM transactions
        WHERE user_id = ?1 AND is_deleted = 0 AND lower(name) = lower(?2)
      ) AS used
      JOIN categories c ON c.id = used.category_id AND c.is_deleted = 0 AND c.is_active = 1
      ORDER BY used.used_at DESC
      LIMIT 1
      ''',
      variables: [Variable<String>(userId), Variable<String>(merchant.trim())],
      readsFrom: {receipts, db.transactions, db.categories},
    ).getSingleOrNull();

    return row?.read<String>("category_id");
  }

  // NOTE: Only touches image_uploaded (plus the sync columns), so it can't undo an edit
  // the user made to other fields while the photo was uploading
  Future<int> setImageUploaded(String id, bool uploaded)
  {
    return customUpdate(
      "UPDATE receipts SET image_uploaded = ?, is_synced = 0, updated_at = MAX(?, updated_at + 1) WHERE id = ?",
      variables: [Variable<bool>(uploaded), Variable<DateTime>(DateTime.now()), Variable<String>(id)],
      updates: {receipts},
      updateKind: UpdateKind.update,
    );
  }

  Future<List<Receipt>> getUnsynced(String userId)
  {
    return (select(receipts)
      ..where((t) =>
        t.userId.equals(userId) &
        t.isSynced.equals(false)
      )
    ).get();
  }
}
