import 'package:expense_tracker/daos/transactions_dao.dart';
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/widgets/ledger_list.dart';
import 'package:expense_tracker/widgets/panel.dart';
import 'package:flutter/material.dart';

class StreamLedgerList extends StatelessWidget
{
  final int year;
  final int month;
  final String activeFilter;
  final bool isInitiallyExpanded;
  final Function(String id) onDelete;

  StreamLedgerList({
    super.key,
    required this.year,
    required this.month,
    required this.activeFilter,
    required this.isInitiallyExpanded,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TransactionWithCategory>>(
      stream: AppDatabase.instance.transactionsDao.watchVisibleTransactionsWithCategory(year, month),
      builder: (context, snapshot) {
        final data = snapshot.data ?? [];

        return LedgerList(
          selectedDateTime: DateTime(year, month, 1),
          transactionsWithCategory: data,
          activeFilter: activeFilter,
          onDelete: onDelete,
          isInitiallyExpanded: isInitiallyExpanded,
        );
      }
    );
  }
}
