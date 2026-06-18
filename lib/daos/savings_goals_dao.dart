import 'package:drift/drift.dart';
import 'package:expense_tracker/daos/base_dao.dart';
import 'package:expense_tracker/database.dart';

part 'savings_goals_dao.g.dart';

@DriftAccessor(tables: [SavingsGoals])
class SavingsGoalsDao extends BaseDao<SavingsGoals, SavingsGoal> with _$SavingsGoalsDaoMixin
{
  SavingsGoalsDao(AppDatabase db) : super(db, db.savingsGoals);

  Stream<List<SavingsGoal>> watchAvailableSavingsGoals()
  {
    return (
      select(savingsGoals)
        ..where((t) => t.isActive.equals(true))
        ..where((t) => t.isDeleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.name)])
    ).watch();
  }
  Future<List<SavingsGoal>> getUnsynced()
  {
    return (select(savingsGoals)
      ..where((t) => t.isSynced.equals(false))
    ).get();
  }

  Future<bool> markAsSynced(SavingsGoal entity)
  {
    return updateRow(entity.copyWith(isSynced: true));
  }

}