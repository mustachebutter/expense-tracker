import 'package:drift/drift.dart' as drift;
import 'package:expense_tracker/main.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database.dart';

class SyncEngine
{
  static SyncEngine? _instance;
  
  late final AppDatabase _db;
  late final SupabaseClient _supabase;

  SyncEngine._internal(this._db)
  {
    _supabase = Supabase.instance.client;
  }

  static void initialize(AppDatabase db)
  {
    _instance ??= SyncEngine._internal(db);
  }

  static SyncEngine get instance 
  {
    if (_instance == null)
    {
      throw Exception("SyncEngine must be initialized before use! Call SyncEngine.initialize(db) in main().");
    }

    return _instance!;
  }


  Future<void> pushAllDataToServer() async
  {
    // final currentUser = _supabase.auth.currentUser;
    // if (currentUser == null)
    // {
    //   print("Cannot sync: No user is logged in");
    //   return;
    // } 

    // await _syncExpenses(currentUser.id);
    // await _syncFixedExpenseTemplates(currentUser.id);
    // await _syncFixedExpenses(currentUser.id);
    // DEBUG: Test only!
    await _syncExpenses(AppConstants.testUserId);
    await _syncFixedExpenseTemplates(AppConstants.testUserId);
    await _syncFixedExpenses(AppConstants.testUserId);
  }

  Future<void> _syncExpenses(String userId) async
  {
    final unsyncedExpenses = await _db.getUnsyncedExpenses();

    if (unsyncedExpenses.isEmpty)
    {
      print("Everything is up to date!");
      return;
    }

    for (var expense in unsyncedExpenses)
    {
      try
      {
        await _supabase.from('expenses').insert(
          {
            "id": expense.id,
            "name": expense.name,
            "amount": expense.amount,
            "date": expense.date.toIso8601String(),
            "category_id": expense.categoryId,
            "user_id": userId,
          }
        );

        await _db.markExpenseAsSynced(expense.id);
        print("Successfully synced expense: ${expense.name}");
      }
      catch (e)
      {
        print("Failed to sync expense ${expense.id}: $e");
      }
    }
  }

  Future<void> _syncFixedExpenseTemplates(String userId) async
  {
    final unsyncedTemplates = await _db.getUnsyncedFixedExpenseTemplates();

    for (var template in unsyncedTemplates)
    {
      try
      {
        await _supabase.from("fixed_expense_templates").upsert(
          {
            "id": template.id,
            "name": template.name,
            "amount": template.amount,
            "category_id": template.categoryId,
            "user_id": userId,
            "is_active": template.isActive,
          }
        );

        await _db.markFixedExpenseTemplateAsSynced(template.id);
      }
      catch (e)
      {
        print("Failed to sync template ${template.id}: $e");
      }
    }
  }

  Future<void> _syncFixedExpenses(String userId) async
  {
    final unsyncedFixed = await _db.getUnsyncedFixedExpenses();

    for (var fixedBill in unsyncedFixed)
    {
      try
      {
        await _supabase.from("fixed_expenses").upsert(
          {
            "id": fixedBill.id,
            "name": fixedBill.name,
            "amount": fixedBill.amount,
            "category_id": fixedBill.categoryId,
            "user_id": userId,
            "is_active": fixedBill.isActive,
          }
        );

        await _db.markFixedExpenseAsSynced(fixedBill.id);
      }
      catch (e)
      {
        print("Failed to sync template ${fixedBill.id}: $e");
      }
    }
  }

  Future<void> pullAllDataFromServer() async 
  {
    // final currentUser = _supabase.auth.currentUser;
    // if (currentUser == null)
    // {
    //   print("Cannot sync: No user is logged in");
    //   return;
    // } 

    // DEBUG: Test only!
    await _pullCategories(AppConstants.testUserId);
    await _pullExpenses(AppConstants.testUserId);
    await _pullFixedExpenses(AppConstants.testUserId);
    await _pullFixedExpenseTemplates(AppConstants.testUserId);
  }

  Future<void> _pullCategories(String userId) async
  {
    try
    {
      final data = await _supabase.from("categories").select().eq("user_id", userId);

      for (var row in data)
      {
        await _db.into(_db.categories).insertOnConflictUpdate(
          CategoriesCompanion(
            id: drift.Value(row["id"]),
            name: drift.Value(row["name"]),
            colorHex: drift.Value(row["color_hex"]),
            iconKey: drift.Value(row["icon_key"]),
            userId: drift.Value(row["user_id"]),
            isActive: drift.Value(row["is_active"]),
            isSynced: drift.Value(true), // Pull from cloud so it is already synced
          )
        );
      }

      await _db.updateCategoryCache();
      print("SyncEngine: Synchronized ${data.length} categories.");
    }
    catch (e)
    {
      print("SyncEngine: Error pulling categories: $e");
      rethrow;
    }
  }


  Future<void> _pullExpenses(String userId) async
  {
    try
    {
      final data = await _supabase.from("expenses").select().eq("user_id", userId);

      for (var row in data)
      {
        await _db.into(_db.expenses).insertOnConflictUpdate(
          ExpensesCompanion(
            id: drift.Value(row["id"]),
            name: drift.Value(row["name"]),
            amount: drift.Value((row["amount"] as num).toDouble()),
            date: drift.Value(DateTime.parse(row["date"].toString())),
            categoryId: drift.Value(row["category_id"]),
            userId: drift.Value(row["user_id"]),
            isSynced: drift.Value(true), // Pull from cloud so it is already synced
          )
        );
      }

      print("SyncEngine: Synchronized ${data.length} expenses.");
    }
    catch (e)
    {
      print("SyncEngine: Error pulling expenses: $e");
      rethrow;
    }
  }


  Future<void> _pullFixedExpenses(String userId) async
  {
    try
    {
      final data = await _supabase.from("fixed_expenses").select().eq("user_id", userId);

      for (var row in data)
      {
        await _db.into(_db.fixedExpenses).insertOnConflictUpdate(
          FixedExpensesCompanion(
            id: drift.Value(row["id"]),
            name: drift.Value(row["name"]),
            amount: drift.Value((row["amount"] as num).toDouble()),
            categoryId: drift.Value(row["category_id"]),
            userId: drift.Value(row["user_id"]),
            date: drift.Value(DateTime.parse(row["date"].toString())),
            templateId: drift.Value(row["template_id"]),
            isActive: drift.Value(row["is_active"]),
            isSynced: drift.Value(true), // Pull from cloud so it is already synced
          )
        );
      }

      print("SyncEngine: Synchronized ${data.length} fixed expenses");
    }
    catch (e)
    {
      print("SyncEngine: Error pulling fixed expenses: $e");
      rethrow;
    }
  }

  
  Future<void> _pullFixedExpenseTemplates(String userId) async
  {
    try
    {
      final data = await _supabase.from("fixed_expense_templates").select().eq("user_id", userId);

      for (var row in data)
      {
        await _db.into(_db.fixedExpenseTemplates).insertOnConflictUpdate(
          FixedExpenseTemplatesCompanion(
            id: drift.Value(row["id"]),
            name: drift.Value(row["name"]),
            amount: drift.Value((row["amount"] as num).toDouble()),
            categoryId: drift.Value(row["category_id"]),
            userId: drift.Value(row["user_id"]),
            billingDay: drift.Value(row["billing_day"]),
            isActive: drift.Value(row["is_active"]),
            isSynced: drift.Value(true), // Pull from cloud so it is already synced
          )
        );
      }

      print("SyncEngine: Synchronized ${data.length} fixed expense templates.");
    }
    catch (e)
    {
      print("SyncEngine: Error pulling fixed expense templates: $e");
      rethrow;
    }
  }
}