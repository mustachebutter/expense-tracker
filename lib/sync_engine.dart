import 'package:expense_tracker/main.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database.dart';

class SyncEngine
{
  final supabase = Supabase.instance.client;
  final AppDatabase localDb;

  SyncEngine(this.localDb);

  Future<void> pushAllDataToServer() async
  {
    // final currentUser = supabase.auth.currentUser;
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
    final unsyncedExpenses = await localDb.getUnsyncedExpenses();

    if (unsyncedExpenses.isEmpty)
    {
      print("Everything is up to date!");
      return;
    }

    for (var expense in unsyncedExpenses)
    {
      try
      {
        await supabase.from('expenses').insert(
          {
            "id": expense.id,
            "name": expense.name,
            "amount": expense.amount,
            "date": expense.date.toIso8601String(),
            "category_id": expense.categoryId,
            "user_id": userId,
          }
        );

        await localDb.markExpenseAsSynced(expense.id);
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
    final unsyncedTemplates = await localDb.getUnsyncedFixedExpenseTemplates();

    for (var template in unsyncedTemplates)
    {
      try
      {
        await supabase.from("fixed_expense_templates").upsert(
          {
            "id": template.id,
            "name": template.name,
            "amount": template.amount,
            "category_id": template.categoryId,
            "user_id": userId,
            "is_active": template.isActive,
          }
        );

        await localDb.markFixedExpenseTemplateAsSynced(template.id);
      }
      catch (e)
      {
        print("Failed to sync template ${template.id}: $e");
      }
    }
  }

  Future<void> _syncFixedExpenses(String userId) async
  {
    final unsyncedFixed = await localDb.getUnsyncedFixedExpenses();

    for (var fixedBill in unsyncedFixed)
    {
      try
      {
        await supabase.from("fixed_expenses").upsert(
          {
            "id": fixedBill.id,
            "name": fixedBill.name,
            "amount": fixedBill.amount,
            "category_id": fixedBill.categoryId,
            "user_id": userId,
            "is_active": fixedBill.isActive,
          }
        );

        await localDb.markFixedExpenseAsSynced(fixedBill.id);
      }
      catch (e)
      {
        print("Failed to sync template ${fixedBill.id}: $e");
      }
    }
  }
}