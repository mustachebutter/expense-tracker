// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'investments_dao.dart';

// ignore_for_file: type=lint
mixin _$InvestmentsDaoMixin on DatabaseAccessor<AppDatabase> {
  $InvestmentsTable get investments => attachedDatabase.investments;
  InvestmentsDaoManager get managers => InvestmentsDaoManager(this);
}

class InvestmentsDaoManager {
  final _$InvestmentsDaoMixin _db;
  InvestmentsDaoManager(this._db);
  $$InvestmentsTableTableManager get investments =>
      $$InvestmentsTableTableManager(_db.attachedDatabase, _db.investments);
}
