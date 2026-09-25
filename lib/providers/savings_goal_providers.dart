import 'package:expense_tracker/daos/savings_goals_dao.dart';
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/core_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final activeSavingsGoalsProvider = StreamProvider<List<SavingsGoal>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(const []);

  return ref.watch(databaseProvider).savingsGoalsDao.watchActiveSavingsGoals(userId);
});

// See CategoryActions for why changes go through here
class SavingsGoalActions
{
  final Ref _ref;

  SavingsGoalActions(this._ref);

  SavingsGoalsDao get _dao => _ref.read(databaseProvider).savingsGoalsDao;

  Future<void> add({required String name, required double targetAmount, required double currentSavedAmount})
  {
    return _dao.insertRow(SavingsGoalsCompanion.insert(
      name: name,
      targetAmount: targetAmount,
      currentSavedAmount: currentSavedAmount,
      userId: _ref.requireUserId(),
    ));
  }

  Future<void> update(SavingsGoal edited)
  {
    if (edited.userId != _ref.requireUserId()) throw StateError("Can't edit another user's savings goal");

    return _dao.updateRow(edited.copyWith(isSynced: false, updatedAt: nextUpdatedAt(edited.updatedAt)));
  }

  Future<void> delete(String id) => _dao.softDeleteById(id, _ref.requireUserId());
}

final savingsGoalActionsProvider = Provider<SavingsGoalActions>((ref) => SavingsGoalActions(ref));
