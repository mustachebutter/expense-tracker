import 'package:drift/drift.dart';
import 'package:expense_tracker/daos/base_dao.dart';
import 'package:expense_tracker/database.dart';
import 'package:uuid/uuid.dart';

part 'transactions_dao.g.dart';

class TransactionWithCategory
{
  final Transaction expense;
  final Category category;

  TransactionWithCategory({
    required this.expense,
    required this.category,
  });
}

// NOTE: A fixed transaction's id is derived from its template and month instead of being random.
// Two offline devices generating "Rent, March 2026" then produce the SAME id, so after
// syncing it's one row instead of a duplicate
const String _fixedTransactionNamespace = "6f1c9a52-3d0b-4e57-9d6e-2b1f8c4a7e10";

String fixedTransactionId(String templateId, int year, int month)
{
  return const Uuid().v5(_fixedTransactionNamespace, "$templateId:$year-$month");
}

typedef DashboardMetrics = ({ double income, double expense, double cashFlow });

@DriftAccessor(tables: [Transactions, Categories, Templates])
class TransactionsDao extends BaseDao<Transactions, Transaction> with _$TransactionsDaoMixin
{
  TransactionsDao(AppDatabase db) : super(db, db.transactions);

  Future<Transaction?> getTransactionById (String id, String userId)
  {
    return (
      select(transactions)
        ..where((t) =>
          t.userId.equals(userId) &
          t.id.equals(id)
        )
    ).getSingleOrNull();
  }

  Future<DateTime?> getEarliestTransactionDate(String userId) async
  {
    final earliestDate = transactions.date.min();

    final query = selectOnly(transactions)
      ..addColumns([earliestDate])
      ..where(
        transactions.userId.equals(userId) &
        transactions.isDeleted.equals(false)
      );
    
    final row = await query.getSingleOrNull();

    return row?.read(earliestDate);
  }

  // Income, spending and cash flow for one month, for the Dashboard's summary cards
  Stream<DashboardMetrics> watchDashboardMetrics(int targetYear, int targetMonth, String userId)
  {
    final incomeSum = transactions.amount.sum(
      filter: transactions.type.equalsValue(TransactionType.income)
    );

    final expenseSum = transactions.amount.sum(
      filter: transactions.type.equalsValue(TransactionType.expense)
    );

    final query = selectOnly(transactions)
      ..addColumns([incomeSum, expenseSum])
      ..where(
        transactions.userId.equals(userId) &
        transactions.isDeleted.equals(false) &
        transactions.date.year.equals(targetYear) &
        transactions.date.month.equals(targetMonth)
      );

    return query.watchSingle().map((row) {
      final income = row.read(incomeSum) ?? 0.0;
      final expense = row.read(expenseSum) ?? 0.0;
      final cashFlow = income - expense;

      return (income: income, expense: expense, cashFlow: cashFlow);
    });
  }

  Future<bool> softDelete(Transaction entity)
  {
    final softDeletedTransaction = entity.copyWith(
      isDeleted: true,
      isSynced: false,
      updatedAt: nextUpdatedAt(entity.updatedAt),
    );

    return updateRow(softDeletedTransaction);
  }

  Future<void> generateFixedTransactionsForMonth(int targetYear, int targetMonth, String userId) async
  {
    final allTemplates = await (
      select(templates)
        ..where((t) =>
          t.userId.equals(userId) &
          t.isDeleted.equals(false) &
          t.isActive.equals(true)
        )
    ).get();
    print(allTemplates);
    if (allTemplates.isEmpty) return;

    final startOfMonth = DateTime(targetYear, targetMonth, 1);
    // NOTE: Day 0 of next month is the last day of this month (Dart rolls it back),
    // so endOfMonth.day is also the number of days in this month
    final endOfMonth = DateTime(targetYear, targetMonth + 1, 0, 23, 59, 59);

    final alreadyGeneratedQuery = select(transactions)
      ..where((t) =>
        t.userId.equals(userId) &
        t.templateId.isNotNull() &
        t.date.isBetweenValues(startOfMonth, endOfMonth)
      );

    final alreadyGeneratedRows = await alreadyGeneratedQuery.get();

    final alreadyGeneratedTemplateIds = alreadyGeneratedRows
      .map((row) => row.templateId)
      .toSet();

    final targetMonthDate = DateTime(targetYear, targetMonth, 1);

    DateTime _getChargeDate(int billingDay)
    {
        int targetDay = billingDay;
        int maxDayInMonth = endOfMonth.day;
        // If billingDay is 31st, we wanna use the last day of the month
        // for Feb (28/29) or May (30)
        if (targetDay > maxDayInMonth) targetDay = maxDayInMonth;

        return DateTime(targetYear, targetMonth, targetDay);
    }
    // Filter out the templates we HAVENT generated yet
    final templatesToGenerate = allTemplates.where((element) {
      if (alreadyGeneratedTemplateIds.contains(element.id)) return false;

      final templateStartMonth = DateTime(element.startDate.year, element.startDate.month, 1);

      // If the template got added AFTER the currently processed date
      // We don't retroactively stamp the past with the templates
      if (templateStartMonth.isAfter(targetMonthDate)) return false;

      final chargeDate = _getChargeDate(element.billingDay);

      if (chargeDate.isAfter(DateTime.now())) return false;

      return true;
    }).toList();

    print(templatesToGenerate);
    if (templatesToGenerate.isEmpty) return;

    await batch((batch) {
      final newTransactions = templatesToGenerate.map((template) {
        final chargeDate = _getChargeDate(template.billingDay);

        return TransactionsCompanion.insert(
          id: Value(fixedTransactionId(template.id, targetYear, targetMonth)),
          name: template.name,
          amount: template.amount,
          date: chargeDate,
          type: template.type,
          categoryId: template.categoryId,
          templateId: Value(template.id),
          userId: userId,
        );
      }).toList();

      // NOTE: insertOrIgnore in case another device's copy was already pulled with the same id
      batch.insertAll(transactions, newTransactions, mode: InsertMode.insertOrIgnore);
    });
  }

  Stream<List<Transaction>> watchIncomes(String userId)
  {
    return (
      select(transactions)
        ..where((t) =>
          t.userId.equals(userId) &
          t.isDeleted.equals(false) &
          t.type.equalsValue(TransactionType.income)
        )
    ).watch();
  }

  Stream<List<Transaction>> watchIncomesForMonth(int targetYear, int targetMonth, String userId)
  {
    return (
      select(transactions)
        ..where((t) =>
          t.userId.equals(userId) &
          t.isDeleted.equals(false) &
          t.type.equalsValue(TransactionType.income) &
          t.date.year.equals(targetYear) &
          t.date.month.equals(targetMonth)
        )
    ).watch();
  }

  Stream<List<TransactionWithCategory>> watchVisibleTransactionsWithCategory(int targetYear, int targetMonth, String userId)
  {
    final query = select(transactions).join([
      innerJoin(categories, categories.id.equalsExp(transactions.categoryId)),
    ])
      ..where(
        transactions.userId.equals(userId) &
        transactions.isDeleted.equals(false) &
        transactions.date.year.equals(targetYear) &
        transactions.date.month.equals(targetMonth)
      )
      ..orderBy([OrderingTerm.desc(transactions.date)]);

    return query.watch().map((rows) {
      return rows.map((row) {
        return TransactionWithCategory(
          expense: row.readTable(transactions),
          category: row.readTable(categories),
        );
      }).toList();
    });    
  }

  Future<List<Transaction>> getUnsynced(String userId)
  {
    return (select(transactions)
      ..where((t) =>
        t.userId.equals(userId) &
        t.isSynced.equals(false)
      )
    ).get();
  }


}