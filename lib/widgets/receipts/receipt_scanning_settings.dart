import 'package:expense_tracker/providers/receipt_scan_providers.dart';
import 'package:expense_tracker/providers/settings_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// The "Receipt scanning" section in Settings: how this device reads receipt photos
class ReceiptScanningSettings extends ConsumerWidget
{
  const ReceiptScanningSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final mode = ref.watch(receiptScanModeProvider);
    final bool scannerWorksHere = ref.watch(receiptScannerProvider).isAvailable;

    final String explanation = switch (mode) {
      ReceiptScanMode.onDevice when scannerWorksHere =>
        "Receipts are read right here on your phone with Google ML Kit. Free, and works offline.",
      ReceiptScanMode.onDevice =>
        "This device can't run ML Kit (it's phones only). Receipts you import here wait until the "
        "app on your phone syncs, and are read there.",
      ReceiptScanMode.selfHosted =>
        "Receipts are sent to the model on your own server or PC.",
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          const Text("Receipt scanning", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SegmentedButton<ReceiptScanMode>(
            segments: const [
              ButtonSegment(
                value: ReceiptScanMode.onDevice,
                icon: Icon(Icons.phone_android),
                label: Text("On-device (ML Kit)"),
              ),
              ButtonSegment(
                value: ReceiptScanMode.selfHosted,
                icon: Icon(Icons.dns_outlined),
                label: Text("Self-hosted model"),
                tooltip: "Coming in the next update",
                // NOTE: Switched on in the next update, together with the Ollama connection
                enabled: false,
              ),
            ],
            selected: {mode},
            onSelectionChanged: (selection) => ref.read(receiptScanModeProvider.notifier).select(selection.single),
          ),
          Text(explanation, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
