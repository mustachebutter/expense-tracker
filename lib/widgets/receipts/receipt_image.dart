import 'package:expense_tracker/providers/receipt_crop_providers.dart';
import 'package:expense_tracker/providers/receipt_providers.dart';
import 'package:expense_tracker/services/receipt_images.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// A receipt's photo, or a placeholder while it loads or if the file isn't on this device
class ReceiptImage extends ConsumerWidget
{
  final String receiptId;
  final BoxFit fit;
  // Quarter turns clockwise to show the photo upright (the receipt's imageQuarterTurns)
  final int quarterTurns;
  // The receipt's cropCorners: show only the receipt, cut out of the photo
  final String? cropCorners;

  const ReceiptImage({
    super.key,
    required this.receiptId,
    this.fit = BoxFit.cover,
    this.quarterTurns = 0,
    this.cropCorners,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directory = ref.watch(receiptImageDirectoryProvider).value;
    final placeholder = _Placeholder(key: ValueKey("placeholder_$receiptId"));
    if (directory == null) return placeholder;

    if (cropCorners != null)
    {
      final cropped = ref.watch(croppedReceiptImageProvider(
        (receiptId: receiptId, quarterTurns: quarterTurns, cropCorners: cropCorners!),
      )).value;

      // NOTE: The cropped copy is already turned upright. Until it's been made (the first
      // time takes a moment), the whole photo shows below
      if (cropped != null)
      {
        return Image.file(
          cropped,
          fit: fit,
          cacheWidth: fit == BoxFit.cover ? 400 : null,
          errorBuilder: (context, error, stackTrace) => placeholder,
        );
      }
    }

    // NOTE: Rotated for display only, the file on disk (and in the cloud) stays as it was taken
    return RotatedBox(
      quarterTurns: quarterTurns,
      child: Image.file(
        ReceiptImageStore.fileIn(directory, receiptId),
        fit: fit,
        // NOTE: Decode a smaller copy for thumbnails instead of the full 2000px photo
        cacheWidth: fit == BoxFit.cover ? 400 : null,
        errorBuilder: (context, error, stackTrace) => placeholder,
      ),
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
