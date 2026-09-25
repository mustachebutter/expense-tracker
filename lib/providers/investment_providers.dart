import 'package:expense_tracker/daos/investments_dao.dart';
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/core_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final activeInvestmentsProvider = StreamProvider<List<Investment>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(const []);

  return ref.watch(databaseProvider).investmentsDao.watchActiveInvestments(userId);
});

// See CategoryActions for why changes go through here
class InvestmentActions
{
  final Ref _ref;

  InvestmentActions(this._ref);

  InvestmentsDao get _dao => _ref.read(databaseProvider).investmentsDao;

  Future<void> add({required String name, required double amount})
  {
    return _dao.insertRow(InvestmentsCompanion.insert(
      name: name,
      amount: amount,
      userId: _ref.requireUserId(),
    ));
  }

  Future<void> update(Investment edited)
  {
    if (edited.userId != _ref.requireUserId()) throw StateError("Can't edit another user's investment");

    return _dao.updateRow(edited.copyWith(isSynced: false, updatedAt: nextUpdatedAt(edited.updatedAt)));
  }

  Future<void> delete(String id) => _dao.softDeleteById(id, _ref.requireUserId());
}

final investmentActionsProvider = Provider<InvestmentActions>((ref) => InvestmentActions(ref));
