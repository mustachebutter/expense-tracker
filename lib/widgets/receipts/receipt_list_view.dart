import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/main.dart';
import 'package:expense_tracker/providers/category_providers.dart';
import 'package:expense_tracker/providers/receipt_providers.dart';
import 'package:expense_tracker/widgets/receipts/receipt_form_dialog.dart';
import 'package:expense_tracker/widgets/receipts/receipt_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// Every receipt as a grid of cards, with a search box and category chips on top
class ReceiptListView extends ConsumerWidget
{
  const ReceiptListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(receiptFilterProvider);
    final receipts = ref.watch(filteredReceiptsProvider).value ?? [];
    final hasAnyReceipts = (ref.watch(receiptsProvider).value ?? []).isNotEmpty;
    final categories = ref.watch(activeCategoriesProvider).value ?? [];
    final categoriesById = {for (final category in categories) category.id: category};

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: "Search by shop",
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: ref.read(receiptFilterProvider.notifier).search,
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text("All"),
                      selected: filter.categoryId == null,
                      onSelected: (_) => ref.read(receiptFilterProvider.notifier).selectCategory(null),
                    ),
                    for (final category in categories)
                      ChoiceChip(
                        label: Text(category.name),
                        selected: filter.categoryId == category.id,
                        onSelected: (_) => ref.read(receiptFilterProvider.notifier).selectCategory(category.id),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),

        if (receipts.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  hasAnyReceipts
                    ? "No receipts match. Try another category or search"
                    : "No receipts yet! Add one with the button below ₍ᐢ•ﻌ•ᐢ₎",
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            sliver: SliverGrid.extent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.72,
              children: [
                for (final receipt in receipts)
                  ReceiptCard(receipt: receipt, category: categoriesById[receipt.categoryId]),
              ],
            ),
          ),
      ],
    );
  }
}

class ReceiptCard extends StatelessWidget
{
  final Receipt receipt;
  final Category? category;

  const ReceiptCard({super.key, required this.receipt, this.category});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final DateTime? date = receipt.date;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: colorScheme.primary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outline),
      ),
      child: InkWell(
        onTap: () => showReceiptFormDialog(context, receipt),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ReceiptImage(receiptId: receipt.id),
                  if (receipt.scanStatus == ReceiptScanStatus.waiting || receipt.scanStatus == ReceiptScanStatus.failed)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: _StatusBadge(status: receipt.scanStatus),
                    ),
                  if (receipt.isFavorite)
                    const Positioned(
                      top: 6,
                      right: 6,
                      child: Icon(Icons.star, color: Colors.amber, shadows: [Shadow(blurRadius: 4)]),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    receipt.merchant ?? "Untitled receipt",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall!.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    [
                      if (receipt.total != null) "\$${receipt.total!.toStringAsFixed(2)}",
                      date == null ? "No date" : DateFormat("MMM d, yyyy").format(date),
                    ].join(" · "),
                    style: textTheme.bodySmall,
                  ),
                  Row(
                    spacing: 4,
                    children: [
                      if (category != null) ...[
                        AppConstants.getIcon(category!.iconKey, color: Colors.grey),
                        Flexible(
                          child: Text(category!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.bodySmall),
                        ),
                      ] else
                        Text("No category", style: textTheme.bodySmall!.copyWith(color: Colors.grey)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// A small label on a card for receipts that haven't been read yet, or couldn't be
class _StatusBadge extends StatelessWidget
{
  final ReceiptScanStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final bool failed = status == ReceiptScanStatus.failed;

    // NOTE: Dark translucent pill with white text, readable on any photo in either theme
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Icon(failed ? Icons.error_outline : Icons.hourglass_top, size: 14, color: Colors.white),
          Text(failed ? "Couldn't read" : "Waiting to scan", style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}
