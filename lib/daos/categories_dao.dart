import 'package:drift/drift.dart';
import 'package:expense_tracker/daos/base_dao.dart';
import 'package:expense_tracker/database.dart';

part 'categories_dao.g.dart';

@DriftAccessor(tables: [Categories])
class CategoriesDao extends BaseDao<Categories, Category> with _$CategoriesDaoMixin
{
  CategoriesDao(AppDatabase db) : super(db, db.categories);
  Future<List<Category>> getCategories(String userId)
  {
    return (
      select(categories)
        ..where((t) => 
          t.userId.equals(userId) & 
          t.isDeleted.equals(false)
        )
    ).get();
  }

  Future<List<Category>> getActiveCategories(String userId)
  {
    return (
      select(categories)
        ..where((t) => 
          t.userId.equals(userId) & 
          t.isDeleted.equals(false) & 
          t.isActive.equals(true)
        )
    ).get();
  }

  Stream<List<Category>> watchCategories(String userId)
  {
    return (
      select(categories)
        ..where((t) => 
          t.userId.equals(userId) & 
          t.isDeleted.equals(false)
        )
        ..orderBy([(t) => OrderingTerm.asc(t.name)])
    ).watch();
  }

  Stream<List<Category>> watchActiveCategories(String userId)
  {
    return (
      select(categories)
        ..where((t) =>
          t.userId.equals(userId) &
          t.isDeleted.equals(false) &
          t.isActive.equals(true)
        )
        ..orderBy([(t) => OrderingTerm.asc(t.name)])
    ).watch();
  }

  Future<List<Category>> getUnsynced(String userId)
  {
    return (select(categories)
      ..where((t) => 
        t.userId.equals(userId) & 
        t.isSynced.equals(false)
      )
    ).get();
  }

}