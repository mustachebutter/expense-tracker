import 'package:expense_tracker/providers/receipt_providers.dart';
import 'package:expense_tracker/services/receipt_images.dart';
import 'package:expense_tracker/widgets/receipts/receipt_board_view.dart';
import 'package:expense_tracker/widgets/receipts/receipt_form_dialog.dart';
import 'package:expense_tracker/widgets/receipts/receipt_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReceiptsScreen extends ConsumerWidget
{
  const ReceiptsScreen({super.key});

  Future<void> _addReceipt(BuildContext context, WidgetRef ref) async
  {
    final picker = ref.read(receiptImagePickerProvider);

    // NOTE: On a phone, ask how. Desktops can only import a file
    final ReceiptImageSource? source = picker.canUseCamera
      ? await showModalBottomSheet<ReceiptImageSource>(
          context: context,
          builder: (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (picker.canScanDocuments)
                  ListTile(
                    leading: const Icon(Icons.document_scanner),
                    title: const Text("Scan receipt"),
                    subtitle: const Text("Crops out the background and straightens it"),
                    onTap: () => Navigator.pop(sheetContext, ReceiptImageSource.documentScanner),
                  ),
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: Text(picker.canScanDocuments ? "Take a plain photo" : "Take a photo"),
                  onTap: () => Navigator.pop(sheetContext, ReceiptImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text("Choose from gallery"),
                  onTap: () => Navigator.pop(sheetContext, ReceiptImageSource.gallery),
                ),
              ],
            ),
          ),
        )
      : ReceiptImageSource.gallery;
    if (source == null) return;

    final bytes = await picker.pick(source);
    if (bytes == null) return;

    final receipt = await ref.read(receiptActionsProvider).addFromImage(bytes);

    // Straight into the details, while the receipt is still in hand
    if (context.mounted) await showReceiptFormDialog(context, receipt);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool canUseCamera = ref.watch(receiptImagePickerProvider).canUseCamera;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Receipts"),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.grid_view), text: "All receipts"),
              Tab(icon: Icon(Icons.push_pin), text: "Board"),
            ],
          ),
        ),
        body: const TabBarView(
          // NOTE: Swiping would fight with dragging receipts around the board
          physics: NeverScrollableScrollPhysics(),
          children: [
            ReceiptListView(),
            ReceiptBoardView(),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _addReceipt(context, ref),
          icon: Icon(canUseCamera ? Icons.add_a_photo : Icons.upload_file),
          label: Text(canUseCamera ? "Add receipt" : "Import receipt"),
        ),
      ),
    );
  }
}
