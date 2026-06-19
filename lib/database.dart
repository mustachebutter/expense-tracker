import 'package:drift/drift.dart';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:expense_tracker/daos/categories_dao.dart';
import 'package:expense_tracker/daos/transactions_dao.dart';
import 'package:expense_tracker/daos/templates_dao.dart';
import 'package:expense_tracker/daos/investments_dao.dart';
import 'package:expense_tracker/daos/savings_goals_dao.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

part 'database.g.dart'; // Drift will generate this file!

enum TransactionType
{
  income,
  expense,
}

class Categories extends Table
{
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get name => text()();
  TextColumn get colorHex => text()();
  TextColumn get iconKey => text()();
  IntColumn get type => intEnum<TransactionType>()();

  TextColumn get userId => text()();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Transactions extends Table
{
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get name => text()();
  RealColumn get amount => real()();
  DateTimeColumn get date => dateTime()();
  IntColumn get type => intEnum<TransactionType>()();
  
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get userId => text()();
  TextColumn get templateId => text()
    .nullable()
    .references(Templates, #id)();

  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  
  @override
  Set<Column> get primaryKey => {id};
}

class Templates extends Table
{
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get name => text()();
  RealColumn get amount => real()();
  DateTimeColumn get startDate => dateTime().clientDefault(() => DateTime.now())();
  IntColumn get billingDay => integer()();
  IntColumn get type => intEnum<TransactionType>()();

  TextColumn get userId => text()();
  TextColumn get categoryId => text().references(Categories, #id)();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class SavingsGoals extends Table
{
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get name => text()();
  RealColumn get targetAmount => real()();
  RealColumn get currentSavedAmount => real()();
  TextColumn get userId => text()();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// Will comeback to this later
class Investments extends Table
{
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get name => text()();
  RealColumn get amount => real()();
  TextColumn get userId => text()();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [Categories, Transactions, Templates, SavingsGoals, Investments],
  daos: [CategoriesDao, TransactionsDao, TemplatesDao, SavingsGoalsDao, InvestmentsDao]
)
class AppDatabase extends _$AppDatabase
{
  static AppDatabase? _instance;

  AppDatabase._internal() : super(_openConnection());

  static AppDatabase get instance
  {
    _instance ??= AppDatabase._internal();
    return _instance!;
  }

  @override
  int get schemaVersion => 1;
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