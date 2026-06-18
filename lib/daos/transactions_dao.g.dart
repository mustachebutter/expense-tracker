// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transactions_dao.dart';

// ignore_for_file: type=lint
mixin _$TransactionsDaoMixin on DatabaseAccessor<AppDatabase> {
  $CategoriesTable get categories => attachedDatabase.categories;
  $TemplatesTable get templates => attachedDatabase.templates;
  $TransactionsTable get transactions => attachedDatabase.transactions;
  TransactionsDaoManager get managers => TransactionsDaoManager(this);
}

class TransactionsDaoManager {
  final _$TransactionsDaoMixin _db;
  TransactionsDaoManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$TemplatesTableTableManager get templates =>
      $$TemplatesTableTableManager(_db.attachedDatabase, _db.templates);
  $$TransactionsTableTableManager get transactions =>
      $$TransactionsTableTableManager(_db.attachedDatabase, _db.transactions);
}
