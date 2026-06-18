import 'package:drift/drift.dart';
import 'package:expense_tracker/daos/base_dao.dart';
import 'package:expense_tracker/database.dart';

part 'templates_dao.g.dart';

@DriftAccessor(tables: [Templates])
class TemplatesDao extends BaseDao<Templates, Template> with _$TemplatesDaoMixin
{
  TemplatesDao(AppDatabase db) : super(db, db.templates);

  Stream<List<Template>> watchAllTemplates()
  {
    return (
      select(templates)
        ..where((t) => t.isDeleted.equals(false))
    ).watch();
  }

  Future<List<Template>> getUnsynced()
  {
    return (select(templates)
      ..where((t) => t.isSynced.equals(false))
    ).get();
  }

  Future<bool> markAsSynced(Template entity)
  {
    return updateRow(entity.copyWith(isSynced: true));
  }

}