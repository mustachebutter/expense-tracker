import 'package:drift/drift.dart';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'database.g.dart'; // Drift will generate this file!
class Categories extends Table
{
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get colorHex => text()();
  TextColumn get userId => text()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Expenses extends Table
{
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get amount => real()();
  DateTimeColumn get date => dateTime()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get userId => text()();

  TextColumn get linkedFixedExpenseId => text().nullable()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  
  @override
  Set<Column> get primaryKey => {id};
}

class FixedExpenses extends Table
{
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get amount => real()();
  IntColumn get billingDay => integer()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get userId => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Incomes extends Table 
{
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get amount => real()();
  DateTimeColumn get date => dateTime()();
  TextColumn get userId => text()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class SavingsGoals extends Table
{
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get targetAmount => real()();
  RealColumn get currentSavedAmount => real()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// Will comeback to this later
class Investments extends Table
{
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get amount => real()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Categories, Expenses, FixedExpenses, Incomes, SavingsGoals, Investments])
class AppDatabase extends _$AppDatabase
{
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  Stream<List<Expense>> watchAllExpenses()
  {
    return (select(expenses)..orderBy([(t) => OrderingTerm.desc(t.date)])).watch();
  }

  Future<int> addExpense(ExpensesCompanion entry)
  {
    return into(expenses).insert(entry);
  }

  Future<bool> updateExpense (ExpensesCompanion entry)
  {
    return update(expenses).replace(entry);
  }

  Future<int> deleteExpense(String id) 
  {
    return (delete(expenses)..where((t) => t.id.equals(id))).go();
  }

  Future<List<Expense>> getUnsyncedExpenses()
  {
    return (select(expenses)..where((t) => t.isSynced.equals(false))).get();
  }

  Future<void> markExpenseAsSynced(String id)
  {
    return (update(expenses)..where((t) => t.id.equals(id)))
      .write(const ExpensesCompanion(isSynced: Value(true)));
  }

}

LazyDatabase _openConnection()
{
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'db.sqlite'));

    return NativeDatabase.createInBackground(file);
  });
}