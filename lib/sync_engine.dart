import 'package:drift/drift.dart' as drift;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database.dart';

class SyncEngine
{
  final AppDatabase _db;
  final SupabaseClient _supabase;

  // NOTE: Created by syncEngineProvider, read it with ref.read(syncEngineProvider)
  SyncEngine(this._db, this._supabase);

  Future<void> _pushTable<T>({
    required String tableName,
    required List<T> unsyncedItems,
    required Map<String, dynamic> Function(T) toSupabaseJson,
    required Future<void> Function(T) markLocalAsSynced,
  }) async
  {
    if (unsyncedItems.isEmpty) return;

    print("Pushing ${unsyncedItems.length} items to $tableName...");

    final payload = unsyncedItems.map((item) {
      final json = toSupabaseJson(item);

      // We need to remove is_synced here because rows pushing to the cloud is synced by default
      // else, we would get an infinite recursion of getting is_synced=False for rows when pulling
      json.remove("is_synced");
      return json;
    }).toList();

    try {
      await _supabase.from(tableName).upsert(payload);

      for (var item in unsyncedItems)
      {
        await markLocalAsSynced(item);
      }
      
      print("Successfully synced $tableName!");
      
    } catch (e) {
      print("Error syncing $tableName: $e");
      // Because we didn't call markLocalAsSynced, the app will just 
      // safely try again the next time they open the app!
    }
  }

  Future<void> _pullTable<T>({
    required String tableName,
    required String userId,
    required Future<List<dynamic>> Function() getLocalUnsyncedItems,
    required Future<void> Function(List<Map<String, dynamic>>) saveLocally,
  }) async
  {
    print("Pulling $tableName from Supabase...");

    try {
      final serverRows = await _supabase.from(tableName).select().eq("user_id", userId);

      if (serverRows.isEmpty) return;

      final unsyncedLocals = await getLocalUnsyncedItems();
      final unsyncedIds = unsyncedLocals.map((item) => item.id).toSet();

      // We don't want to overwrite our local rows, local is newer!
      final safeServerRows = serverRows.where((item) {
        return !unsyncedIds.contains(item["id"]);
      }).toList();

      await saveLocally(safeServerRows);
      print("Successfully pulled ${safeServerRows.length} rows for $tableName!");

    } 
    catch (e) 
    {
      print("Error pulling $tableName: $e");
    }  
  }

  Future<void> pushAllDataToServer(String userId) async
  {
    // Sync Categories
    await _pushTable<Category>(
      tableName: 'categories',
      unsyncedItems: await _db.categoriesDao.getUnsynced(userId),
      markLocalAsSynced: (cat) => _db.categoriesDao.markAsSynced(cat),
      toSupabaseJson: (cat) => {
        'id': cat.id,
        'name': cat.name,
        'color_hex': cat.colorHex,
        'icon_key': cat.iconKey,
        'user_id': cat.userId,
        'is_active': cat.isActive,
        'is_deleted': cat.isDeleted,
      },
    );

    // Sync Transactions
    await _pushTable<Transaction>(
      tableName: 'transactions',
      unsyncedItems: await _db.transactionsDao.getUnsynced(userId),
      markLocalAsSynced: (exp) => _db.transactionsDao.markAsSynced(exp),
      toSupabaseJson: (exp) => {
        'id': exp.id,
        'name': exp.name,
        'amount': exp.amount,
        'date': exp.date.toUtc().toIso8601String(), // Timezone fix applied!
        'type': exp.type.index,
        'category_id': exp.categoryId,
        'user_id': exp.userId,
        'template_id': exp.templateId,
        'is_deleted': exp.isDeleted,
      },
    );

    await _pushTable(
      tableName: 'templates',
      unsyncedItems: await _db.templatesDao.getUnsynced(userId),
      markLocalAsSynced: (entity) => _db.templatesDao.markAsSynced(entity),
      toSupabaseJson: (entity) => {
        'id': entity.id,
        'name': entity.name,
        'amount': entity.amount,
        'start_date': entity.startDate.toUtc().toIso8601String(),
        'billing_day': entity.billingDay,
        'type': entity.type.index,
        'category_id': entity.categoryId,
        'user_id': entity.userId,
        'is_active': entity.isActive,
        'is_deleted': entity.isDeleted,
      },
    );
  }

  Future<void> pullAllDataFromServer(String userId) async
  {
    // Pull Categories
    await _pullTable(
      tableName: 'categories',
      userId: userId,
      getLocalUnsyncedItems: () => _db.categoriesDao.getUnsynced(userId),
      saveLocally: (safeServerRows) async {
        final companions = safeServerRows.map((row) => CategoriesCompanion(
          id: drift.Value(row['id']),
          name: drift.Value(row['name']),
          colorHex: drift.Value(row['color_hex']),
          iconKey: drift.Value(row['icon_key']),
          type: drift.Value(TransactionType.values[row['type'] as int]),
          userId: drift.Value(row['user_id']),
          isActive: drift.Value(row['is_active']),
          isDeleted: drift.Value(row['is_deleted']),
          isSynced: const drift.Value(true), // We just pulled it, so it's synced!
        )).toList();
        
        await _db.categoriesDao.saveServerData(companions);
      },
    );

    // Pull Transactions
    await _pullTable(
      tableName: 'transactions',
      userId: userId,
      getLocalUnsyncedItems: () => _db.transactionsDao.getUnsynced(userId),
      saveLocally: (safeServerRows) async {
        final companions = safeServerRows.map((row) => TransactionsCompanion(
          id: drift.Value(row['id']),
          name: drift.Value(row['name']),
          // Parse the Supabase number to a double
          amount: drift.Value((row['amount'] as num).toDouble()), 
          // Parse the UTC string and convert it back to local timezone!
          date: drift.Value(DateTime.parse(row['date'].toString()).toLocal()),
          type: drift.Value(TransactionType.values[row["type"] as int]),
          categoryId: drift.Value(row['category_id']),
          userId: drift.Value(row['user_id']),
          templateId: drift.Value(row['template_id']),
          isDeleted: drift.Value(row['is_deleted']),
          isSynced: const drift.Value(true),
        )).toList();
        
        await _db.transactionsDao.saveServerData(companions);
      },
    );

    await _pullTable(
      tableName: 'templates',
      userId: userId,
      getLocalUnsyncedItems: () => _db.templatesDao.getUnsynced(userId),
      saveLocally: (safeServerRows) async {
        final companions = safeServerRows.map((row) => TemplatesCompanion(
          id: drift.Value(row["id"]),
          name: drift.Value(row["name"]),
          amount: drift.Value((row["amount"] as num).toDouble()),
          startDate: drift.Value(DateTime.parse(row["start_date"].toString())),
          billingDay: drift.Value(row["billing_day"]),
          type: drift.Value(TransactionType.values[row["type"] as int]),
          categoryId: drift.Value(row["category_id"]),
          userId: drift.Value(row["user_id"]),
          isActive: drift.Value(row["is_active"]),
          isSynced: const drift.Value(true), // Pull from cloud so it is already synced
        )).toList();
        
        await _db.templatesDao.saveServerData(companions);
      },
    );    
  }

  Future<void> syncAllTransactionsFromTemplates(String userId) async
  {
    DateTime? earliestDate = await _db.transactionsDao.getEarliestTransactionDate(userId);

    final now = DateTime.now();
    earliestDate ??= now;

    DateTime currentDate = DateTime(earliestDate.year, earliestDate.month, 1);
    

    while (!currentDate.isAfter(now))
    {
      await _db.transactionsDao.generateFixedTransactionsForMonth(currentDate.year, currentDate.month, userId);
      
      currentDate = DateTime(currentDate.year, currentDate.month + 1, currentDate.day);
    }

  }

  Future<void> runStartUpSync(String userId) async
  {
    try
    {
      print("🔄 1. Pulling latest data from Supabase...");
      await pullAllDataFromServer(userId);
      print("⚙️ 2. Generating missing fixed expenses locally...");
      await syncAllTransactionsFromTemplates(userId);
      print("☁️ 3. Pushing local changes (and new generations) to Supabase...");
      await pushAllDataToServer(userId);
    }
    catch (e)
    {
      print("❌ Sync Failed: $e");
    }
  }
}