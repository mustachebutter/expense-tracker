import 'package:drift/drift.dart';
import 'package:expense_tracker/daos/base_dao.dart';
import 'package:expense_tracker/database.dart';

part 'investments_dao.g.dart';

@DriftAccessor(tables: [Investments])
class InvestmentsDao extends BaseDao<Investments, Investment> with _$InvestmentsDaoMixin
{
  InvestmentsDao(AppDatabase db) : super(db, db.investments);

  Stream<List<Investment>> watchAvailableInvestments()
  {
    return (
      select(investments)
        ..where((t) => t.isActive.equals(true))
        ..where((t) => t.isDeleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.name)])
    ).watch();
  }

  Future<List<Investment>> getUnsynced()
  {
    return (select(investments)
      ..where((t) => t.isSynced.equals(false))
    ).get();
  }

  Future<bool> markAsSynced(Investment entity)
  {
    return updateRow(entity.copyWith(isSynced: true));
  }

}