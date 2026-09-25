import 'package:drift/drift.dart';
import 'package:expense_tracker/daos/base_dao.dart';
import 'package:expense_tracker/database.dart';

part 'savings_goals_dao.g.dart';

@DriftAccessor(tables: [SavingsGoals])
class SavingsGoalsDao extends BaseDao<SavingsGoals, SavingsGoal> with _$SavingsGoalsDaoMixin
{
  SavingsGoalsDao(AppDatabase db) : super(db, db.savingsGoals);

  Stream<List<SavingsGoal>> watchActiveSavingsGoals(String userId)
  {
    return (
      select(savingsGoals)
        ..where((t) =>
          t.userId.equals(userId) & 
          t.isActive.equals(true) &
          t.isDeleted.equals(false)
        )
        ..orderBy([(t) => OrderingTerm.asc(t.name)])
    ).watch();
  }
  Future<List<SavingsGoal>> getUnsynced(String userId)
  {
    return (select(savingsGoals)
      ..where((t) =>
        t.userId.equals(userId) &
        t.isSynced.equals(false)
      )
    ).get();
  }


}