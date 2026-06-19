import 'package:drift/drift.dart';
import 'package:expense_tracker/daos/base_dao.dart';
import 'package:expense_tracker/database.dart';

part 'categories_dao.g.dart';

@DriftAccessor(tables: [Categories])
class CategoriesDao extends BaseDao<Categories, Category> with _$CategoriesDaoMixin
{
  CategoriesDao(AppDatabase db) : super(db, db.categories);
  Future<List<Category>> getAllCategories()
  {
    return (
      select(categories)
        ..where((t) => t.isDeleted.equals(false))
    ).get();
  }

  Future<List<Category>> getAllActiveCategories()
  {
    return (
      select(categories)
        ..where((t) => t.isDeleted.equals(false))
        ..where((t) => t.isActive.equals(true))
    ).get();
  }

  Stream<List<Category>> watchAllCategories()
  {
    return (
      select(categories)
        ..where((t) => t.isDeleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.name)])
    ).watch();
  }

  Stream<List<Category>> watchAllActiveCategories()
  {
    return (
      select(categories)
        ..where((t) => t.isDeleted.equals(false))
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm.asc(t.name)])
    ).watch();
  }

  Future<List<Category>> getUnsynced()
  {
    return (select(categories)
      ..where((t) => t.isSynced.equals(false))
    ).get();
  }

  Future<bool> markAsSynced(Category entity)
  {
    return updateRow(entity.copyWith(isSynced: true));
  }
}