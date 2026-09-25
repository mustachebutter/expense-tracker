import 'package:drift/drift.dart' as drift;
import 'dart:typed_data';

import 'package:expense_tracker/daos/base_dao.dart';
import 'package:expense_tracker/services/receipt_images.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database.dart';

// NOTE: How sync works (offline first):
// - The app only ever reads and writes the local Drift DB. Every local change marks
//   the row is_synced = false and bumps updated_at.
// - Sync = PULL server changes since our last pull -> generate fixed transactions -> PUSH
//   every unsynced row.
// - Conflicts are "last write wins" on updated_at: a pulled row only replaces a local
//   unsynced edit if the server's copy is newer (see BaseDao.saveServerRows).
// - Supabase keeps two timestamps per row: updated_at (when a device edited it, sent by
//   us) and server_updated_at (when the server received it, set by a trigger). We pull
//   by server_updated_at, so a device that was offline for a week and uploads old edits
//   still gets them seen by everyone else.

class SyncException implements Exception
{
  final Map<String, Object> errors;

  SyncException(this.errors);

  @override
  String toString() => "Sync failed for ${errors.keys.join(", ")}: ${errors.values.first}";
}

// The server side of sync. SupabaseSyncRemote is the real one, tests use a fake
abstract class SyncRemote
{
  Future<void> upsert(String table, List<Map<String, dynamic>> rows);

  // Rows changed on the server at or after [since] (null = all of them), oldest change first
  Future<List<Map<String, dynamic>>> fetchChanges(String table, String userId, String? since);

  // Receipt photos live in file storage, next to the tables
  Future<void> uploadReceiptImage(String userId, String receiptId, Uint8List bytes);
  Future<Uint8List> downloadReceiptImage(String userId, String receiptId);
  Future<void> removeReceiptImage(String userId, String receiptId);
}

class SupabaseSyncRemote implements SyncRemote
{
  // NOTE: Supabase returns at most 1000 rows per request by default
  static const int _pageSize = 1000;
  // NOTE: Without a limit, a request that never gets an answer (bad signal, captive wifi)
  // would keep the sync "running" forever, and every later sync would wait behind it
  static const Duration _timeout = Duration(seconds: 30);

  // NOTE: A private bucket. Each user's photos are in a folder named after their id, and
  // the storage policies (see the receipts SQL migration) only let them reach that folder
  static const String _receiptBucket = "receipts";

  final SupabaseClient _supabase;

  SupabaseSyncRemote(this._supabase);

  String _receiptImagePath(String userId, String receiptId) => "$userId/$receiptId.jpg";

  @override
  Future<void> uploadReceiptImage(String userId, String receiptId, Uint8List bytes) async
  {
    await _supabase.storage.from(_receiptBucket).uploadBinary(
      _receiptImagePath(userId, receiptId),
      bytes,
      // upsert: re-uploading after an interrupted sync just overwrites the same file
      fileOptions: const FileOptions(upsert: true, contentType: "image/jpeg"),
    ).timeout(_timeout);
  }

  @override
  Future<Uint8List> downloadReceiptImage(String userId, String receiptId)
  {
    return _supabase.storage.from(_receiptBucket).download(_receiptImagePath(userId, receiptId)).timeout(_timeout);
  }

  @override
  Future<void> removeReceiptImage(String userId, String receiptId) async
  {
    await _supabase.storage.from(_receiptBucket).remove([_receiptImagePath(userId, receiptId)]).timeout(_timeout);
  }

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async
  {
    await _supabase.from(table).upsert(rows).timeout(_timeout);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchChanges(String table, String userId, String? since) async
  {
    final changes = <Map<String, dynamic>>[];

    for (var offset = 0; ; offset += _pageSize)
    {
      var query = _supabase.from(table).select().eq("user_id", userId);
      if (since != null) query = query.gte("server_updated_at", since);

      final page = await query
        .order("server_updated_at", ascending: true)
        .range(offset, offset + _pageSize - 1)
        .timeout(_timeout);

      changes.addAll(page);
      if (page.length < _pageSize) return changes;
    }
  }
}

// Everything sync needs to know about one table: how to read its unsynced rows and
// how to convert between a Drift row and a Supabase JSON row
class _SyncTable<D>
{
  final String name;
  final BaseDao<drift.Table, D> dao;
  final Future<List<D>> Function(String userId) getUnsynced;
  final ({String id, DateTime updatedAt}) Function(D row) keyOf;
  final Map<String, dynamic> Function(D row) toJson;
  final drift.Insertable<D> Function(Map<String, dynamic> json) fromJson;

  _SyncTable({
    required this.name,
    required this.dao,
    required this.getUnsynced,
    required this.keyOf,
    required this.toJson,
    required this.fromJson,
  });

  Future<void> pull(AppDatabase db, SyncRemote remote, String userId) async
  {
    final scope = "$userId:$name";
    final cursorRow = await (db.select(db.syncCursors)..where((t) => t.scope.equals(scope))).getSingleOrNull();

    final changes = await remote.fetchChanges(name, userId, cursorRow?.cursor);
    if (changes.isEmpty) return;

    final saved = await dao.saveServerRows([
      for (final json in changes)
        (id: json["id"] as String, updatedAt: _parseDate(json["updated_at"]), companion: fromJson(json)),
    ]);
    print("⬇️ Pulled ${changes.length} $name rows, saved $saved (the rest had newer local edits)");

    // NOTE: Only move the cursor once the rows are safely saved. If the app dies before
    // this line, the next sync just downloads the same rows again, which is harmless
    await db.into(db.syncCursors).insertOnConflictUpdate(
      SyncCursorsCompanion.insert(scope: scope, cursor: changes.last["server_updated_at"] as String),
    );
  }

  Future<void> push(SyncRemote remote, String userId) async
  {
    final unsynced = await getUnsynced(userId);
    if (unsynced.isEmpty) return;

    // NOTE: Upload in chunks so a big first sync doesn't become one giant request
    for (var start = 0; start < unsynced.length; start += 500)
    {
      final chunk = unsynced.skip(start).take(500).toList();
      await remote.upsert(name, chunk.map(toJson).toList());

      for (final row in chunk)
      {
        final key = keyOf(row);
        await dao.markAsSynced(key.id, key.updatedAt);
      }
    }
    print("⬆️ Pushed ${unsynced.length} $name rows");
  }
}

DateTime _parseDate(Object? value) => DateTime.parse(value as String).toLocal();
DateTime? _parseOptionalDate(Object? value) => value == null ? null : _parseDate(value);
String? _formatOptionalDate(DateTime? value) => value == null ? null : _formatDate(value);
double? _optionalDouble(Object? value) => (value as num?)?.toDouble();
String _formatDate(DateTime value) => value.toUtc().toIso8601String();

class SyncEngine
{
  final AppDatabase _db;
  final SyncRemote _remote;
  final ReceiptImageStore _receiptImages;

  // NOTE: Created by syncEngineProvider, use it through syncControllerProvider
  SyncEngine(this._db, this._remote, this._receiptImages);

  // NOTE: Order matters, parents before children, so a transaction is never uploaded
  // before the category/template it points to
  late final List<_SyncTable> _tables = [
    _SyncTable<Category>(
      name: "categories",
      dao: _db.categoriesDao,
      getUnsynced: _db.categoriesDao.getUnsynced,
      keyOf: (row) => (id: row.id, updatedAt: row.updatedAt),
      toJson: (row) => {
        "id": row.id,
        "name": row.name,
        "color_hex": row.colorHex,
        "icon_key": row.iconKey,
        "type": row.type.index,
        "user_id": row.userId,
        "is_active": row.isActive,
        "is_deleted": row.isDeleted,
        "updated_at": _formatDate(row.updatedAt),
      },
      fromJson: (json) => CategoriesCompanion(
        id: drift.Value(json["id"]),
        name: drift.Value(json["name"]),
        colorHex: drift.Value(json["color_hex"]),
        iconKey: drift.Value(json["icon_key"]),
        type: drift.Value(TransactionType.values[json["type"] as int]),
        userId: drift.Value(json["user_id"]),
        isActive: drift.Value(json["is_active"]),
        isDeleted: drift.Value(json["is_deleted"]),
        updatedAt: drift.Value(_parseDate(json["updated_at"])),
        isSynced: const drift.Value(true), // We just pulled it, so it's synced!
      ),
    ),
    _SyncTable<Template>(
      name: "templates",
      dao: _db.templatesDao,
      getUnsynced: _db.templatesDao.getUnsynced,
      keyOf: (row) => (id: row.id, updatedAt: row.updatedAt),
      toJson: (row) => {
        "id": row.id,
        "name": row.name,
        "amount": row.amount,
        "start_date": _formatDate(row.startDate),
        "billing_day": row.billingDay,
        "type": row.type.index,
        "category_id": row.categoryId,
        "user_id": row.userId,
        "is_active": row.isActive,
        "is_deleted": row.isDeleted,
        "updated_at": _formatDate(row.updatedAt),
      },
      fromJson: (json) => TemplatesCompanion(
        id: drift.Value(json["id"]),
        name: drift.Value(json["name"]),
        amount: drift.Value((json["amount"] as num).toDouble()),
        startDate: drift.Value(_parseDate(json["start_date"])),
        billingDay: drift.Value(json["billing_day"]),
        type: drift.Value(TransactionType.values[json["type"] as int]),
        categoryId: drift.Value(json["category_id"]),
        userId: drift.Value(json["user_id"]),
        isActive: drift.Value(json["is_active"]),
        isDeleted: drift.Value(json["is_deleted"]),
        updatedAt: drift.Value(_parseDate(json["updated_at"])),
        isSynced: const drift.Value(true),
      ),
    ),
    _SyncTable<Transaction>(
      name: "transactions",
      dao: _db.transactionsDao,
      getUnsynced: _db.transactionsDao.getUnsynced,
      keyOf: (row) => (id: row.id, updatedAt: row.updatedAt),
      toJson: (row) => {
        "id": row.id,
        "name": row.name,
        "amount": row.amount,
        "date": _formatDate(row.date),
        "type": row.type.index,
        "category_id": row.categoryId,
        "user_id": row.userId,
        "template_id": row.templateId,
        "is_deleted": row.isDeleted,
        "updated_at": _formatDate(row.updatedAt),
      },
      fromJson: (json) => TransactionsCompanion(
        id: drift.Value(json["id"]),
        name: drift.Value(json["name"]),
        amount: drift.Value((json["amount"] as num).toDouble()),
        date: drift.Value(_parseDate(json["date"])),
        type: drift.Value(TransactionType.values[json["type"] as int]),
        categoryId: drift.Value(json["category_id"]),
        userId: drift.Value(json["user_id"]),
        templateId: drift.Value(json["template_id"] as String?),
        isDeleted: drift.Value(json["is_deleted"]),
        updatedAt: drift.Value(_parseDate(json["updated_at"])),
        isSynced: const drift.Value(true),
      ),
    ),
    _SyncTable<SavingsGoal>(
      name: "savings_goals",
      dao: _db.savingsGoalsDao,
      getUnsynced: _db.savingsGoalsDao.getUnsynced,
      keyOf: (row) => (id: row.id, updatedAt: row.updatedAt),
      toJson: (row) => {
        "id": row.id,
        "name": row.name,
        "target_amount": row.targetAmount,
        "current_saved_amount": row.currentSavedAmount,
        "user_id": row.userId,
        "is_active": row.isActive,
        "is_deleted": row.isDeleted,
        "updated_at": _formatDate(row.updatedAt),
      },
      fromJson: (json) => SavingsGoalsCompanion(
        id: drift.Value(json["id"]),
        name: drift.Value(json["name"]),
        targetAmount: drift.Value((json["target_amount"] as num).toDouble()),
        currentSavedAmount: drift.Value((json["current_saved_amount"] as num).toDouble()),
        userId: drift.Value(json["user_id"]),
        isActive: drift.Value(json["is_active"]),
        isDeleted: drift.Value(json["is_deleted"]),
        updatedAt: drift.Value(_parseDate(json["updated_at"])),
        isSynced: const drift.Value(true),
      ),
    ),
    _SyncTable<Investment>(
      name: "investments",
      dao: _db.investmentsDao,
      getUnsynced: _db.investmentsDao.getUnsynced,
      keyOf: (row) => (id: row.id, updatedAt: row.updatedAt),
      toJson: (row) => {
        "id": row.id,
        "name": row.name,
        "amount": row.amount,
        "user_id": row.userId,
        "is_active": row.isActive,
        "is_deleted": row.isDeleted,
        "updated_at": _formatDate(row.updatedAt),
      },
      fromJson: (json) => InvestmentsCompanion(
        id: drift.Value(json["id"]),
        name: drift.Value(json["name"]),
        amount: drift.Value((json["amount"] as num).toDouble()),
        userId: drift.Value(json["user_id"]),
        isActive: drift.Value(json["is_active"]),
        isDeleted: drift.Value(json["is_deleted"]),
        updatedAt: drift.Value(_parseDate(json["updated_at"])),
        isSynced: const drift.Value(true),
      ),
    ),
    // NOTE: After transactions, since a receipt can point at the transaction it became.
    // The photo isn't part of the row, it goes through file storage in _syncReceiptImages
    _SyncTable<Receipt>(
      name: "receipts",
      dao: _db.receiptsDao,
      getUnsynced: _db.receiptsDao.getUnsynced,
      keyOf: (row) => (id: row.id, updatedAt: row.updatedAt),
      toJson: (row) => {
        "id": row.id,
        "user_id": row.userId,
        "merchant": row.merchant,
        "total": row.total,
        "date": _formatOptionalDate(row.date),
        "category_id": row.categoryId,
        "transaction_id": row.transactionId,
        "scan_status": row.scanStatus.index,
        "image_uploaded": row.imageUploaded,
        "image_quarter_turns": row.imageQuarterTurns,
        "crop_corners": row.cropCorners,
        "split_people": row.splitPeople,
        "split_amount": row.splitAmount,
        "is_favorite": row.isFavorite,
        "board_x": row.boardX,
        "board_y": row.boardY,
        "board_z": row.boardZ,
        "created_at": _formatDate(row.createdAt),
        "is_deleted": row.isDeleted,
        "updated_at": _formatDate(row.updatedAt),
      },
      fromJson: (json) => ReceiptsCompanion(
        id: drift.Value(json["id"]),
        userId: drift.Value(json["user_id"]),
        merchant: drift.Value(json["merchant"] as String?),
        total: drift.Value(_optionalDouble(json["total"])),
        date: drift.Value(_parseOptionalDate(json["date"])),
        categoryId: drift.Value(json["category_id"] as String?),
        transactionId: drift.Value(json["transaction_id"] as String?),
        scanStatus: drift.Value(ReceiptScanStatus.values[json["scan_status"] as int]),
        imageUploaded: drift.Value(json["image_uploaded"]),
        imageQuarterTurns: drift.Value(json["image_quarter_turns"] as int),
        cropCorners: drift.Value(json["crop_corners"] as String?),
        splitPeople: drift.Value(json["split_people"] as int?),
        splitAmount: drift.Value(_optionalDouble(json["split_amount"])),
        isFavorite: drift.Value(json["is_favorite"]),
        boardX: drift.Value(_optionalDouble(json["board_x"])),
        boardY: drift.Value(_optionalDouble(json["board_y"])),
        boardZ: drift.Value(json["board_z"] as int),
        createdAt: drift.Value(_parseDate(json["created_at"])),
        isDeleted: drift.Value(json["is_deleted"]),
        updatedAt: drift.Value(_parseDate(json["updated_at"])),
        isSynced: const drift.Value(true),
      ),
    ),
  ];

  // Moves receipt photos between this device and file storage. Runs after the pull (so it
  // knows about other devices' receipts) and before the push (so image_uploaded goes up now)
  Future<void> _syncReceiptImages(String userId, Future<void> Function(String step, Future<void> Function() action) attempt) async
  {
    final receipts = await _db.receiptsDao.getAllForUser(userId);

    for (final receipt in receipts)
    {
      // NOTE: Each photo is its own step, so one bad photo doesn't stop the rest
      await attempt("receipt photo ${receipt.id}", () async {
        if (receipt.isDeleted)
        {
          // Deleted on any device: remove the photo everywhere
          await _receiptImages.delete(receipt.id);
          if (receipt.imageUploaded)
          {
            await _remote.removeReceiptImage(userId, receipt.id);
            await _db.receiptsDao.setImageUploaded(receipt.id, false);
          }
          return;
        }

        final localBytes = await _receiptImages.read(receipt.id);

        if (!receipt.imageUploaded && localBytes != null)
        {
          // Taken on this device, not uploaded yet
          await _remote.uploadReceiptImage(userId, receipt.id, localBytes);
          await _db.receiptsDao.setImageUploaded(receipt.id, true);
        }
        else if (receipt.imageUploaded && localBytes == null)
        {
          // Taken on another device
          await _receiptImages.save(receipt.id, await _remote.downloadReceiptImage(userId, receipt.id));
        }
      });
    }
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

  // Runs a full sync. One table failing doesn't stop the others, but if anything
  // failed it throws a SyncException at the end so the caller can show it
  Future<void> runSync(String userId) async
  {
    final errors = <String, Object>{};

    Future<void> attempt(String step, Future<void> Function() action) async
    {
      try
      {
        await action();
      }
      catch (e)
      {
        print("❌ Sync step '$step' failed: $e");
        errors[step] = e;
      }
    }

    print("🔄 1. Pulling changes from Supabase...");
    for (final table in _tables)
    {
      await attempt("pull ${table.name}", () => table.pull(_db, _remote, userId));
    }

    print("⚙️ 2. Generating missing fixed transactions locally...");
    await attempt("generate fixed transactions", () => syncAllTransactionsFromTemplates(userId));

    print("🧾 3. Syncing receipt photos...");
    await attempt("receipt photos", () => _syncReceiptImages(userId, attempt));

    print("☁️ 4. Pushing local changes to Supabase...");
    for (final table in _tables)
    {
      await attempt("push ${table.name}", () => table.push(_remote, userId));
    }

    if (errors.isNotEmpty) throw SyncException(errors);
  }
}
