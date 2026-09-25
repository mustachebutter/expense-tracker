import 'package:drift/drift.dart';
import 'package:expense_tracker/daos/base_dao.dart';
import 'package:expense_tracker/database.dart';

part 'templates_dao.g.dart';

@DriftAccessor(tables: [Templates])
class TemplatesDao extends BaseDao<Templates, Template> with _$TemplatesDaoMixin
{
  TemplatesDao(AppDatabase db) : super(db, db.templates);

  Stream<List<Template>> watchTemplates(String userId)
  {
    return (
      select(templates)
        ..where((t) => 
          t.userId.equals(userId) &
          t.isDeleted.equals(false)
        )
    ).watch();
  }
  Stream<List<Template>> watchActiveTemplates(String userId)
  {
    return (
      select(templates)
        ..where((t) => 
          t.userId.equals(userId) &
          t.isDeleted.equals(false) &
          t.isActive.equals(true)
        )
    ).watch();
  }

  Future<List<Template>> getUnsynced(String userId)
  {
    return (select(templates)
      ..where((t) => 
        t.userId.equals(userId) &
        t.isSynced.equals(false)
      )
    ).get();
  }


}