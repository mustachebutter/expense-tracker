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
  TextColumn get iconKey => text()();
  TextColumn get userId => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
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
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get userId => text()();

  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  
  @override
  Set<Column> get primaryKey => {id};
}

class FixedExpenseTemplates extends Table
{
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get amount => real()();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get userId => text()();
  IntColumn get billingDay => integer()();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class FixedExpenses extends Table
{
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get amount => real()();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get userId => text()();
  DateTimeColumn get date => dateTime()();
  TextColumn get templateId => text().references(FixedExpenseTemplates, #id)();


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
  TextColumn get userId => text()();

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
  TextColumn get userId => text()();

  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Categories, Expenses, FixedExpenseTemplates, FixedExpenses, Incomes, SavingsGoals, Investments])
class AppDatabase extends _$AppDatabase
{
  static AppDatabase? _instance;
  List<Category> _cachedCategories = [];
  Map<String, Category> _categoryMap = {};

  AppDatabase._internal() : super(_openConnection())
  {
    updateCategoryCache();
  }

  static AppDatabase get instance
  {
    _instance ??= AppDatabase._internal();
    return _instance!;
  }

  @override
  int get schemaVersion => 1;

  Future<void> updateCategoryCache() async
  {
    _cachedCategories = await (select(categories)
      ..where((t) => t.isActive.equals(true)))
      .get();
    _categoryMap = { for (var c in _cachedCategories) c.id : c };
    print("Database Cache: Loaded ${_cachedCategories.length} categories in memory.");
  }

  Map<String, Category> get categoryMap => _categoryMap;
  List<Category> get categoryList => _cachedCategories;

  Stream<List<Expense>> watchAllExpenses()
  {
    return (select(expenses)..orderBy([(t) => OrderingTerm.desc(t.date)])).watch();
  }

  Stream<List<FixedExpense>> watchAllFixedExpenses()
  {
    return (select(fixedExpenses)..orderBy([(t) => OrderingTerm.desc(t.date)])).watch();
  }

  Stream<List<Category>> watchAllCategories()
  {
    return (select(categories)..orderBy([(t) => OrderingTerm.desc(t.name)])).watch();
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

  Future<List<FixedExpenseTemplate>> getUnsyncedFixedExpenseTemplates()
  {
    return (select(fixedExpenseTemplates)..where((t) => t.isSynced.equals(false))).get();
  }

  Future<void> markFixedExpenseTemplateAsSynced(String id)
  {
    return (update(fixedExpenseTemplates)..where((t) => t.id.equals(id)))
      .write(const FixedExpenseTemplatesCompanion(isSynced: Value(true)));
  }

  Future<List<FixedExpense>> getUnsyncedFixedExpenses()
  {
    return (select(fixedExpenses)..where((t) => t.isSynced.equals(false))).get();
  }

  Future<void> markFixedExpenseAsSynced(String id)
  {
    return (update(fixedExpenses)..where((t) => t.id.equals(id)))
      .write(const FixedExpensesCompanion(isSynced: Value(true)));
  }

}

LazyDatabase _openConnection()
{
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'db.sqlite'));
    // ADD THIS LINE TEMPORARILY:
    print("🚀 EXTREMELY IMPORTANT - DRIFT IS SAVING HERE: ${file.path}");
    return NativeDatabase.createInBackground(file);
  });
}