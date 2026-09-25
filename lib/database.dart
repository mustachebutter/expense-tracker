import 'package:drift/drift.dart';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:expense_tracker/daos/categories_dao.dart';
import 'package:expense_tracker/daos/transactions_dao.dart';
import 'package:expense_tracker/daos/templates_dao.dart';
import 'package:expense_tracker/daos/investments_dao.dart';
import 'package:expense_tracker/daos/savings_goals_dao.dart';
import 'package:expense_tracker/daos/receipts_dao.dart';
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
  // NOTE: When this row was last changed locally. Inserts get it for free, updates
  // must set it (see nextUpdatedAt). Sync uses it to decide which edit wins
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();

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
  // NOTE: When this row was last changed locally. Inserts get it for free, updates
  // must set it (see nextUpdatedAt). Sync uses it to decide which edit wins
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
  
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
  // NOTE: When this row was last changed locally. Inserts get it for free, updates
  // must set it (see nextUpdatedAt). Sync uses it to decide which edit wins
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();

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
  // NOTE: When this row was last changed locally. Inserts get it for free, updates
  // must set it (see nextUpdatedAt). Sync uses it to decide which edit wins
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();

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
  // NOTE: When this row was last changed locally. Inserts get it for free, updates
  // must set it (see nextUpdatedAt). Sync uses it to decide which edit wins
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}

enum ReceiptScanStatus
{
  // Receipts added before scanning existed. They're filled in by hand
  notScanned,
  // Queued for the scanner. On a device that can't scan (e.g. Windows with ML Kit), it waits
  // until a device that can (the phone) syncs, downloads the photo and reads it
  waiting,
  scanned,
  failed,
}

class Receipts extends Table
{
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get userId => text()();

  // NOTE: No image path column. The photo is always saved as receipts/<id>.jpg (see
  // ReceiptImageStore), because a file path only means something on the device that saved it
  TextColumn get merchant => text().nullable()();
  RealColumn get total => real().nullable()();
  DateTimeColumn get date => dateTime().nullable()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  // Set once the receipt has been turned into a transaction, so it isn't added twice
  TextColumn get transactionId => text().nullable().references(Transactions, #id)();
  IntColumn get scanStatus => intEnum<ReceiptScanStatus>().withDefault(const Constant(0))();
  // True once the photo is in Supabase Storage. Other devices download it when they see this
  BoolColumn get imageUploaded => boolean().withDefault(const Constant(false))();
  // Quarter turns clockwise (0-3) to show the photo upright. The photo file itself is never
  // changed, so rotating syncs as a number instead of re-uploading the whole photo
  IntColumn get imageQuarterTurns => integer().withDefault(const Constant(0))();
  // The receipt's four corners in the photo (see receipt_crop.dart), to cut it out of the
  // background. Like the rotation, the photo itself is never changed, every device makes
  // its own cropped copy from these. Null shows the whole photo
  TextColumn get cropCorners => text().nullable()();

  // Splitting the bill with friends. An equal split stores how many people (you included),
  // a custom split stores your own amount. Both empty: you paid all of it
  IntColumn get splitPeople => integer().nullable()();
  RealColumn get splitAmount => real().nullable()();

  // Favourites are the receipts pinned on the board
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  // Position on the board. Null until the receipt is pinned and placed for the first time
  RealColumn get boardX => real().nullable()();
  RealColumn get boardY => real().nullable()();
  // Stacking order on the board, the highest is drawn on top
  IntColumn get boardZ => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();

  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}

// NOTE: Remembers how far each table has been pulled from Supabase, so the next
// sync only downloads rows that changed after that point
class SyncCursors extends Table
{
  // "<userId>:<table>", each user on this device has their own position per table
  TextColumn get scope => text()();
  // The server's server_updated_at of the newest row we've pulled, kept as the raw
  // string so no precision is lost (Drift would round a DateTime to whole seconds)
  TextColumn get cursor => text()();

  @override
  Set<Column> get primaryKey => {scope};
}

@DriftDatabase(
  tables: [Categories, Transactions, Templates, SavingsGoals, Investments, SyncCursors, Receipts],
  daos: [CategoriesDao, TransactionsDao, TemplatesDao, SavingsGoalsDao, InvestmentsDao, ReceiptsDao]
)
class AppDatabase extends _$AppDatabase
{
  static AppDatabase? _instance;

  AppDatabase._internal() : super(_openConnection());

  // NOTE: Tests pass an in-memory database here so they never touch the real db.sqlite
  AppDatabase.forTesting(super.executor);

  static AppDatabase get instance
  {
    _instance ??= AppDatabase._internal();
    return _instance!;
  }

  @override
  // v3 changes no tables, it only runs _repairTransactionTypes once. v4 adds receipts,
  // v5 adds receipts.image_uploaded, v6 adds receipt rotation and splitting, v7 cropping
  int get schemaVersion => 7;

  // NOTE: The Add Transaction form used to save every transaction as an expense, even in an
  // income category. This gives those rows their category's type. Fixed transactions
  // (template_id set) always had the right type, so they're left alone. Repaired rows are
  // marked unsynced with a newer updated_at, so the fix uploads and wins over the old copy
  Future<void> _repairTransactionTypes() async
  {
    await customStatement("""
      UPDATE transactions
      SET type = (SELECT c.type FROM categories c WHERE c.id = transactions.category_id),
          is_synced = 0,
          updated_at = MAX(CAST(strftime('%s', 'now') AS INTEGER), updated_at + 1)
      WHERE template_id IS NULL
        AND EXISTS (
          SELECT 1 FROM categories c
          WHERE c.id = transactions.category_id AND c.type <> transactions.type
        )
    """);
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2)
      {
        // NOTE: SQLite can't ADD COLUMN with a "now" default, so alterTable rebuilds
        // each table and fills updatedAt for existing rows with the current time
        for (final table in <TableInfo>[categories, transactions, templates, savingsGoals, investments])
        {
          final updatedAt = table.columnsByName["updated_at"]!;
          await m.alterTable(TableMigration(
            table,
            newColumns: [updatedAt],
            columnTransformer: {updatedAt: currentDateAndTime},
          ));
        }
        await m.createTable(syncCursors);
      }

      if (from < 3)
      {
        await _repairTransactionTypes();
      }

      if (from < 4)
      {
        // NOTE: Created with today's columns, so a v3 database skips the receipt steps below
        await m.createTable(receipts);
      }
      else
      {
        if (from < 5)
        {
          await m.addColumn(receipts, receipts.imageUploaded);
        }
        if (from < 6)
        {
          await m.addColumn(receipts, receipts.imageQuarterTurns);
          await m.addColumn(receipts, receipts.splitPeople);
          await m.addColumn(receipts, receipts.splitAmount);
        }
        if (from < 7)
        {
          await m.addColumn(receipts, receipts.cropCorners);
        }
      }
    },
  );
}

// NOTE: Drift stores DateTime in whole seconds, so two edits within the same second
// would get the same updatedAt and sync couldn't tell them apart. This always moves
// updatedAt forward by at least a second. Use it for every local UPDATE
DateTime nextUpdatedAt(DateTime previous)
{
  final now = DateTime.now();
  final minimum = previous.add(const Duration(seconds: 1));
  return now.isAfter(minimum) ? now : minimum;
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