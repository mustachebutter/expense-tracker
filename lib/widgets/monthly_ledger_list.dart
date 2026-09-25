import 'package:expense_tracker/providers/transaction_providers.dart';
import 'package:expense_tracker/widgets/ledger_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MonthlyLedgerList extends ConsumerWidget
{
  final int year;
  final int month;
  final bool isInitiallyExpanded;
  final Function(String id) onDelete;

  const MonthlyLedgerList({
    super.key,
    required this.year,
    required this.month,
    required this.isInitiallyExpanded,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(monthlyTransactionsProvider((year: year, month: month))).value ?? [];
    final activeFilter = ref.watch(activeFilterProvider);

    return LedgerList(
      selectedDateTime: DateTime(year, month, 1),
      transactionsWithCategory: data,
      activeFilter: activeFilter,
      onDelete: onDelete,
      isInitiallyExpanded: isInitiallyExpanded,
    );
  }
}
