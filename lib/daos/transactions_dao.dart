import 'package:drift/drift.dart';
import 'package:expense_tracker/daos/base_dao.dart';
import 'package:expense_tracker/database.dart';

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

typedef DashboardMetrics = ({ double income, double expense, double cashFlow });

@DriftAccessor(tables: [Transactions, Categories, Templates])
class TransactionsDao extends BaseDao<Transactions, Transaction> with _$TransactionsDaoMixin
{
  TransactionsDao(AppDatabase db) : super(db, db.transactions);

  Future<Transaction?> getTransactionById (String id)
  {
    return (
      select(transactions)
        ..where((t) => t.id.equals(id))
    ).getSingleOrNull();
  }

  Future<DateTime?> getEarliestTransactionDate() async
  {
    final earliestDate = transactions.date.min();

    final query = selectOnly(transactions)
      ..addColumns([earliestDate])
      ..where(transactions.isDeleted.equals(false));
    
    final row = await query.getSingleOrNull();

    return row?.read(earliestDate);
  }

  Stream<DashboardMetrics> watchDashboardMetrics()
  {
    final incomeSum = transactions.amount.sum(
      filter: transactions.type.equalsValue(TransactionType.income)
    );

    final expenseSum = transactions.amount.sum(
      filter: transactions.type.equalsValue(TransactionType.expense)
    );

    final query = selectOnly(transactions)
      ..addColumns([incomeSum, expenseSum])
      ..where(transactions.isDeleted.equals(false));

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
    );

    return updateRow(softDeletedTransaction);
  }

  Future<void> generateFixedTransactionsForMonth(int targetYear, int targetMonth, String currentUserId) async
  {
    final allTemplates = await select(templates).get();
    print(allTemplates);
    if (allTemplates.isEmpty) return;

    final startOfMonth = DateTime(targetYear, targetMonth, 1);
    final endOfMonth = DateTime(targetYear, targetMonth + 1, 23, 59, 59);

    final alreadyGeneratedQuery = select(transactions)
      ..where((t) => t.templateId.isNotNull())
      ..where((t) => t.date.isBetweenValues(startOfMonth, endOfMonth));

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
          name: template.name,
          amount: template.amount,
          date: chargeDate,
          type: template.type,
          categoryId: template.categoryId,
          templateId: Value(template.id),
          userId: currentUserId,
        );
      }).toList();

      batch.insertAll(transactions, newTransactions);
    });
  }

  Stream<List<Transaction>> watchAvailableIncomes()
  {
    return (
      select(transactions)
        ..where((t) => t.isDeleted.equals(false))
        ..where((t) => t.type.equalsValue(TransactionType.income))
    ).watch();
  }

  Stream<List<Transaction>> watchAvailableIncomesForMonth(int targetYear, int targetMonth)
  {
    return (
      select(transactions)
        ..where((t) => t.isDeleted.equals(false))
        ..where((t) => t.type.equalsValue(TransactionType.income))
        ..where((t) => t.date.year.equals(targetYear))
        ..where((t) => t.date.month.equals(targetMonth))
    ).watch();
  }

  Stream<List<TransactionWithCategory>> watchVisibleTransactionsWithCategory(int targetYear, int targetMonth)
  {
    final query = select(transactions).join([
      innerJoin(categories, categories.id.equalsExp(transactions.categoryId)),
    ])
      ..where(transactions.isDeleted.equals(false))
      ..where(transactions.date.year.equals(targetYear))
      ..where(transactions.date.month.equals(targetMonth))
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

  Future<List<Transaction>> getUnsynced()
  {
    return (select(transactions)
      ..where((t) => t.isSynced.equals(false))
    ).get();
  }

  Future<bool> markAsSynced(Transaction entity)
  {
    return updateRow(entity.copyWith(isSynced: true));
  }

}