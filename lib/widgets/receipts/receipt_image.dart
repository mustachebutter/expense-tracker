import 'package:expense_tracker/providers/receipt_providers.dart';
import 'package:expense_tracker/services/receipt_images.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// A receipt's photo, or a placeholder while it loads or if the file isn't on this device
class ReceiptImage extends ConsumerWidget
{
  final String receiptId;
  final BoxFit fit;

  const ReceiptImage({super.key, required this.receiptId, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directory = ref.watch(receiptImageDirectoryProvider).value;
    final placeholder = _Placeholder(key: ValueKey("placeholder_$receiptId"));
    if (directory == null) return placeholder;

    return Image.file(
      ReceiptImageStore.fileIn(directory, receiptId),
      fit: fit,
      // NOTE: Decode a smaller copy for thumbnails instead of the full 2000px photo
      cacheWidth: fit == BoxFit.cover ? 400 : null,
      errorBuilder: (context, error, stackTrace) => placeholder,
    );
  }
}

class _Placeholder extends StatelessWidget
{
  const _Placeholder({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: colorScheme.secondary,
      alignment: Alignment.center,
      child: Icon(Icons.receipt_long, size: 40, color: colorScheme.outline),
    );
  }
}
