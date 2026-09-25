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
