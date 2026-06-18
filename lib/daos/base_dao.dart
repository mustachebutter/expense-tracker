import 'package:drift/drift.dart';
import 'package:expense_tracker/database.dart';

abstract class BaseDao<T extends Table, D> extends DatabaseAccessor<AppDatabase>
{
  final TableInfo<T, D> table;

  BaseDao(AppDatabase db, this.table) : super(db);

  Future<int> insertRow(Insertable<D> entity) => into(table).insert(entity);
  Future<bool> updateRow(Insertable<D> entity) => update(table).replace(entity);
  Future<int> hardDeleteRow(Insertable<D> entity) => delete(table).delete(entity);

  Future<void> saveServerData(List<Insertable<D>> serverRows) async
  {
    await batch((batch) {
      batch.insertAll(
        table,
        serverRows,
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  Stream<List<D>> watchAll() => select(table).watch();
  Future<List<D>> getAll() => select(table).get(); 
}