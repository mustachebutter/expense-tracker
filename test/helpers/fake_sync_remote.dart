import 'dart:typed_data';

import 'package:expense_tracker/sync_engine.dart';

// NOTE: A pretend Supabase that lives in memory. It behaves like the real tables after
// the offline_sync migration: every write gets a new server_updated_at, and
// fetchChanges returns rows changed since a cursor, oldest first.
// Several AppDatabases (= several devices) can share one FakeSyncRemote
class FakeSyncRemote implements SyncRemote
{
  // table name -> row id -> row
  final Map<String, Map<String, Map<String, dynamic>>> tables = {};

  // Every fetchChanges call, so tests can check the cursor was used
  final List<({String table, String? since})> fetchCalls = [];

  // Tables listed here throw like a network error would. "receipt_images" makes photo
  // uploads and downloads fail
  final Set<String> failingTables = {};

  // Photos in file storage, keyed "<userId>/<receiptId>" like the real bucket
  final Map<String, Uint8List> receiptImages = {};

  // Runs in the middle of the next upsert to [table]. Lets a test do something
  // "while the upload is in flight", like the user editing the same row
  String? _hookTable;
  Future<void> Function()? _hook;

  void runDuringNextUpsert(String table, Future<void> Function() hook)
  {
    _hookTable = table;
    _hook = hook;
  }

  DateTime _serverClock = DateTime.utc(2026, 1, 1);

  String _nextServerTime()
  {
    _serverClock = _serverClock.add(const Duration(seconds: 1));
    return _serverClock.toIso8601String();
  }

  List<Map<String, dynamic>> rows(String table) => (tables[table] ?? {}).values.toList();

  // Pretend another device uploaded this row
  void seed(String table, Map<String, dynamic> row)
  {
    (tables[table] ??= {})[row["id"] as String] = {...row, "server_updated_at": _nextServerTime()};
  }

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async
  {
    if (failingTables.contains(table)) throw Exception("Network error uploading $table");

    if (_hookTable == table && _hook != null)
    {
      final hook = _hook!;
      _hook = null;
      await hook();
    }

    for (final row in rows)
    {
      seed(table, row);
    }
  }

  @override
  Future<void> uploadReceiptImage(String userId, String receiptId, Uint8List bytes) async
  {
    if (failingTables.contains("receipt_images")) throw Exception("Network error uploading a photo");
    receiptImages["$userId/$receiptId"] = bytes;
  }

  @override
  Future<Uint8List> downloadReceiptImage(String userId, String receiptId) async
  {
    if (failingTables.contains("receipt_images")) throw Exception("Network error downloading a photo");
    final bytes = receiptImages["$userId/$receiptId"];
    if (bytes == null) throw Exception("Object not found");
    return bytes;
  }

  @override
  Future<void> removeReceiptImage(String userId, String receiptId) async
  {
    receiptImages.remove("$userId/$receiptId");
  }

  @override
  Future<List<Map<String, dynamic>>> fetchChanges(String table, String userId, String? since) async
  {
    fetchCalls.add((table: table, since: since));
    if (failingTables.contains(table)) throw Exception("Network error downloading $table");

    final changed = rows(table)
      .where((row) => row["user_id"] == userId)
      // NOTE: ISO-8601 strings in the same format sort the same way as the times they represent
      .where((row) => since == null || (row["server_updated_at"] as String).compareTo(since) >= 0)
      .map((row) => Map<String, dynamic>.of(row))
      .toList()
      ..sort((a, b) => (a["server_updated_at"] as String).compareTo(b["server_updated_at"] as String));

    return changed;
  }
}
