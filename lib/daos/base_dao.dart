import 'package:drift/drift.dart';
import 'package:expense_tracker/database.dart';

// A row downloaded from Supabase, already converted to a Drift companion
typedef ServerRow<D> = ({String id, DateTime updatedAt, Insertable<D> companion});

abstract class BaseDao<T extends Table, D> extends DatabaseAccessor<AppDatabase>
{
  final TableInfo<T, D> table;

  BaseDao(AppDatabase db, this.table) : super(db);

  Future<int> insertRow(Insertable<D> entity) => into(table).insert(entity);
  Future<bool> updateRow(Insertable<D> entity) => update(table).replace(entity);
  Future<int> hardDeleteRow(Insertable<D> entity) => delete(table).delete(entity);

  // NOTE: Every synced table has id, updated_at and is_synced columns, so these two
  // use plain SQL to work for all of them without repeating the code in each DAO

  // Saves rows pulled from the server, unless we have a newer unsynced edit of the same row.
  // Returns how many server rows were written
  Future<int> saveServerRows(List<ServerRow<D>> serverRows)
  {
    // NOTE: A transaction blocks any other write until we're done, so the user can't
    // edit a row in between us checking it and overwriting it
    return transaction(() async {
      final localChanges = await customSelect(
        "SELECT id, updated_at FROM ${table.actualTableName} WHERE is_synced = 0",
        readsFrom: {table},
      ).get();

      final localUpdatedAtById = {
        for (final row in localChanges) row.read<String>("id"): row.read<DateTime>("updated_at"),
      };

      // Last write wins: keep the local edit if it's the same age or newer than the server's
      final accepted = serverRows.where((serverRow) {
        final localUpdatedAt = localUpdatedAtById[serverRow.id];
        return localUpdatedAt == null || serverRow.updatedAt.isAfter(localUpdatedAt);
      }).toList();

      await batch((batch) {
        batch.insertAll(
          table,
          accepted.map((row) => row.companion),
          mode: InsertMode.insertOrReplace,
        );
      });

      return accepted.length;
    });
  }

  // Marks a row as synced ONLY if it hasn't been edited since we read it for upload.
  // If the user changed it while the upload was in flight, it stays unsynced and goes up next time
  Future<int> markAsSynced(String id, DateTime updatedAt)
  {
    return customUpdate(
      "UPDATE ${table.actualTableName} SET is_synced = 1 WHERE id = ? AND updated_at = ?",
      variables: [Variable<String>(id), Variable<DateTime>(updatedAt)],
      updates: {table},
      updateKind: UpdateKind.update,
    );
  }

  Stream<List<D>> watchAll() => select(table).watch();
  Future<List<D>> getAll() => select(table).get();
}
