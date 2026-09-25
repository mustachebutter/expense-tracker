import 'package:drift/drift.dart' as drift;
import 'package:expense_tracker/daos/transactions_dao.dart';
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/core_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef YearMonth = ({int year, int month});

// NOTE: The summary cards are for one month, like the ledger. They used to add up every
// transaction ever, so "Monthly Income" really showed all-time income
final dashboardMetricsProvider = StreamProvider.autoDispose
  .family<DashboardMetrics, YearMonth>((ref, yearMonth) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return Stream.value((income: 0.0, expense: 0.0, cashFlow: 0.0));

    return ref.watch(databaseProvider).transactionsDao
      .watchDashboardMetrics(yearMonth.year, yearMonth.month, userId);
  });

// NOTE: One stream per month. autoDispose closes the query once no ledger list is showing it
final monthlyTransactionsProvider = StreamProvider.autoDispose
  .family<List<TransactionWithCategory>, YearMonth>((ref, yearMonth) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return Stream.value(const []);

    return ref.watch(databaseProvider).transactionsDao
      .watchVisibleTransactionsWithCategory(yearMonth.year, yearMonth.month, userId);
  });

class ActiveFilterNotifier extends Notifier<String>
{
  static const String all = "All";

  @override
  String build() => all;

  void select(String filter) => state = filter;
}

final activeFilterProvider = NotifierProvider<ActiveFilterNotifier, String>(ActiveFilterNotifier.new);

class TransactionActions
{
  final Ref _ref;

  TransactionActions(this._ref);

  TransactionsDao get _dao => _ref.read(databaseProvider).transactionsDao;

  Future<void> add(TransactionsCompanion transaction)
  {
    // NOTE: The signed in user always owns new rows, the UI doesn't need to know the id
    return _dao.insertRow(
      transaction.copyWith(userId: drift.Value(_ref.requireUserId())),
    );
  }

  // Returns the deleted transaction so the UI can show its name, null if not found
  Future<Transaction?> softDeleteById(String id) async
  {
    final transaction = await _dao.getTransactionById(id, _ref.requireUserId());
    if (transaction == null) return null;

    await _dao.softDelete(transaction);
    return transaction;
  }
}

final transactionActionsProvider = Provider<TransactionActions>((ref) => TransactionActions(ref));
