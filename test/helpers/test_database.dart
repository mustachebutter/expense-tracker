import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:expense_tracker/database.dart';

const String userA = "user-a";
const String userB = "user-b";

// NOTE: A brand new, empty SQLite database that only lives in RAM.
// Every test gets its own, so tests can never affect each other.
// closeStreamsSynchronously stops widget tests from complaining about pending timers
AppDatabase createTestDatabase()
{
  return AppDatabase.forTesting(
    DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
  );
}

// Small helpers so each test only spells out the fields it actually cares about

Future<Category> insertCategory(
  AppDatabase db, {
  required String name,
  String? id,
  TransactionType type = TransactionType.expense,
  String userId = userA,
  bool isActive = true,
  bool isDeleted = false,
  bool isSynced = false,
  DateTime? updatedAt,
}) async
{
  return db.into(db.categories).insertReturning(
    CategoriesCompanion.insert(
      id: id == null ? const Value.absent() : Value(id),
      name: name,
      colorHex: "4CAF50",
      iconKey: "restaurant",
      type: type,
      userId: userId,
      isActive: Value(isActive),
      isDeleted: Value(isDeleted),
      isSynced: Value(isSynced),
      updatedAt: updatedAt == null ? const Value.absent() : Value(updatedAt),
    ),
  );
}

Future<Template> insertTemplate(
  AppDatabase db, {
  required String name,
  required String categoryId,
  required int billingDay,
  required DateTime startDate,
  String? id,
  double amount = 10.0,
  String userId = userA,
  bool isActive = true,
  bool isDeleted = false,
}) async
{
  return db.into(db.templates).insertReturning(
    TemplatesCompanion.insert(
      id: id == null ? const Value.absent() : Value(id),
      name: name,
      amount: amount,
      billingDay: billingDay,
      type: TransactionType.expense,
      userId: userId,
      categoryId: categoryId,
      startDate: Value(startDate),
      isActive: Value(isActive),
      isDeleted: Value(isDeleted),
    ),
  );
}

Future<Transaction> insertTransaction(
  AppDatabase db, {
  required String name,
  required String categoryId,
  required DateTime date,
  double amount = 10.0,
  TransactionType type = TransactionType.expense,
  String userId = userA,
  bool isDeleted = false,
}) async
{
  return db.into(db.transactions).insertReturning(
    TransactionsCompanion.insert(
      name: name,
      amount: amount,
      date: date,
      type: type,
      categoryId: categoryId,
      userId: userId,
      isDeleted: Value(isDeleted),
    ),
  );
}
