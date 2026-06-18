// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'templates_dao.dart';

// ignore_for_file: type=lint
mixin _$TemplatesDaoMixin on DatabaseAccessor<AppDatabase> {
  $CategoriesTable get categories => attachedDatabase.categories;
  $TemplatesTable get templates => attachedDatabase.templates;
  TemplatesDaoManager get managers => TemplatesDaoManager(this);
}

class TemplatesDaoManager {
  final _$TemplatesDaoMixin _db;
  TemplatesDaoManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$TemplatesTableTableManager get templates =>
      $$TemplatesTableTableManager(_db.attachedDatabase, _db.templates);
}
