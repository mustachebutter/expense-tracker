// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'receipts_dao.dart';

// ignore_for_file: type=lint
mixin _$ReceiptsDaoMixin on DatabaseAccessor<AppDatabase> {
  $CategoriesTable get categories => attachedDatabase.categories;
  $TemplatesTable get templates => attachedDatabase.templates;
  $TransactionsTable get transactions => attachedDatabase.transactions;
  $ReceiptsTable get receipts => attachedDatabase.receipts;
  ReceiptsDaoManager get managers => ReceiptsDaoManager(this);
}

class ReceiptsDaoManager {
  final _$ReceiptsDaoMixin _db;
  ReceiptsDaoManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$TemplatesTableTableManager get templates =>
      $$TemplatesTableTableManager(_db.attachedDatabase, _db.templates);
  $$TransactionsTableTableManager get transactions =>
      $$TransactionsTableTableManager(_db.attachedDatabase, _db.transactions);
  $$ReceiptsTableTableManager get receipts =>
      $$ReceiptsTableTableManager(_db.attachedDatabase, _db.receipts);
}
