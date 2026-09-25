import 'package:expense_tracker/daos/categories_dao.dart';
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/core_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final activeCategoriesProvider = StreamProvider<List<Category>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(const []);

  return ref.watch(databaseProvider).categoriesDao.watchActiveCategories(userId);
});

// NOTE: Every change goes through these actions so the offline-sync rules are always
// followed: new rows belong to the signed in user, edits move updatedAt forward and
// mark the row unsynced, and deletes are soft so they can sync to other devices
class CategoryActions
{
  final Ref _ref;

  CategoryActions(this._ref);

  CategoriesDao get _dao => _ref.read(databaseProvider).categoriesDao;

  Future<void> add({
    required String name,
    required String colorHex,
    required String iconKey,
    required TransactionType type,
  })
  {
    return _dao.insertRow(CategoriesCompanion.insert(
      name: name,
      colorHex: colorHex,
      iconKey: iconKey,
      type: type,
      userId: _ref.requireUserId(),
    ));
  }

  // [edited] is the original row with the user's changes applied through copyWith
  Future<void> update(Category edited)
  {
    if (edited.userId != _ref.requireUserId()) throw StateError("Can't edit another user's category");

    return _dao.updateRow(edited.copyWith(isSynced: false, updatedAt: nextUpdatedAt(edited.updatedAt)));
  }

  Future<void> delete(String id) => _dao.softDeleteById(id, _ref.requireUserId());
}

final categoryActionsProvider = Provider<CategoryActions>((ref) => CategoryActions(ref));
