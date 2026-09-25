import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/daos/templates_dao.dart';
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/core_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final activeTemplatesProvider = StreamProvider<List<Template>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(const []);

  return ref.watch(databaseProvider).templatesDao.watchActiveTemplates(userId);
});

// Fixed transactions (templates). See CategoryActions for why changes go through here
class TemplateActions
{
  final Ref _ref;

  TemplateActions(this._ref);

  TemplatesDao get _dao => _ref.read(databaseProvider).templatesDao;

  Future<void> add({
    required String name,
    required double amount,
    required int billingDay,
    required TransactionType type,
    required String categoryId,
  })
  {
    return _dao.insertRow(TemplatesCompanion.insert(
      name: name,
      amount: amount,
      billingDay: billingDay,
      type: type,
      categoryId: categoryId,
      userId: _ref.requireUserId(),
      // NOTE: Starts this month. The next sync generates this month's transaction
      // if the billing day has already passed
      startDate: Value(DateTime.now()),
    ));
  }

  Future<void> update(Template edited)
  {
    if (edited.userId != _ref.requireUserId()) throw StateError("Can't edit another user's fixed transaction");

    return _dao.updateRow(edited.copyWith(isSynced: false, updatedAt: nextUpdatedAt(edited.updatedAt)));
  }

  // Stops future months from being generated. Transactions it already created stay
  Future<void> delete(String id) => _dao.softDeleteById(id, _ref.requireUserId());
}

final templateActionsProvider = Provider<TemplateActions>((ref) => TemplateActions(ref));
