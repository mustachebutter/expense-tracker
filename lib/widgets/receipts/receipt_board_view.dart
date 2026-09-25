import 'dart:math' as math;

import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/receipt_providers.dart';
import 'package:expense_tracker/widgets/receipts/receipt_form_dialog.dart';
import 'package:expense_tracker/widgets/receipts/receipt_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// A big corkboard of pinned (favourite) receipts. Drag the board to look around, pinch or
// scroll to zoom, drag a receipt to move it (it jumps to the top of the pile), tap to open it
class ReceiptBoardView extends ConsumerStatefulWidget
{
  static const Size boardSize = Size(2400, 1600);
  static const Size cardSize = Size(160, 210);

  const ReceiptBoardView({super.key});

  // Where a pinned receipt goes before it's ever been dragged: a loose grid in pin order
  static Offset defaultPosition(int index)
  {
    const columns = 6;
    return Offset(80.0 + (index % columns) * 200, 80.0 + (index ~/ columns) * 250);
  }

  // A slight tilt, between -6 and 6 degrees, so the board looks hand-made. It comes from the
  // receipt's id, so a receipt always has the same tilt on every device without storing it
  static double tiltFor(String receiptId)
  {
    final hash = receiptId.codeUnits.fold(0, (sum, unit) => (sum * 31 + unit) & 0x7fffffff);
    return ((hash % 13) - 6) * math.pi / 180;
  }

  @override
  ConsumerState<ReceiptBoardView> createState() => _ReceiptBoardViewState();
}

class _ReceiptBoardViewState extends ConsumerState<ReceiptBoardView>
{
  final TransformationController _transformation = TransformationController();

  // While a receipt is being dragged it lives here, and is only saved when it's dropped.
  // Saving on every frame of the drag would mean hundreds of database writes
  String? _draggingId;
  Offset _dragPosition = Offset.zero;

  @override
  void dispose() {
    _transformation.dispose();
    super.dispose();
  }

  Offset _positionOf(Receipt receipt, int index)
  {
    if (receipt.id == _draggingId) return _dragPosition;
    if (receipt.boardX != null && receipt.boardY != null) return Offset(receipt.boardX!, receipt.boardY!);
    return ReceiptBoardView.defaultPosition(index);
  }

  Offset _clampToBoard(Offset position)
  {
    const board = ReceiptBoardView.boardSize;
    const card = ReceiptBoardView.cardSize;
    return Offset(
      position.dx.clamp(0, board.width - card.width),
      position.dy.clamp(0, board.height - card.height),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final pinned = ref.watch(boardReceiptsProvider).value ?? [];

    if (pinned.isEmpty)
    {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            "Nothing pinned yet! Open a receipt and switch on \"Pin to board\" ⭐",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // NOTE: Pin order decides the default spot, stacking order decides what's drawn on top.
    // The dragged receipt is always drawn last so it floats above the others
    final pinOrder = {for (final (index, receipt) in pinned.indexed) receipt.id: index};
    final drawOrder = [
      ...pinned.where((r) => r.id != _draggingId),
      ...pinned.where((r) => r.id == _draggingId),
    ];

    return InteractiveViewer(
      transformationController: _transformation,
      constrained: false,
      minScale: 0.3,
      maxScale: 2.5,
      boundaryMargin: const EdgeInsets.all(200),
      child: Container(
        key: const Key("receipt_board"),
        width: ReceiptBoardView.boardSize.width,
        height: ReceiptBoardView.boardSize.height,
        color: colorScheme.secondary,
        child: Stack(
          children: [
            for (final receipt in drawOrder)
              _BoardCard(
                key: ValueKey(receipt.id),
                receipt: receipt,
                position: _positionOf(receipt, pinOrder[receipt.id]!),
                isDragging: receipt.id == _draggingId,
                onTap: () => showReceiptFormDialog(context, receipt),
                onDragStart: () {
                  // NOTE: Read where it is BEFORE marking it as dragged, otherwise _positionOf
                  // returns the (empty) drag position and the card jumps to the corner
                  final startPosition = _positionOf(receipt, pinOrder[receipt.id]!);
                  setState(() {
                    _draggingId = receipt.id;
                    _dragPosition = startPosition;
                  });
                },
                onDragUpdate: (delta) => setState(() {
                  // NOTE: Finger movement is in screen pixels. When zoomed out, one screen pixel
                  // covers more of the board, so divide by the zoom to keep the card under the finger
                  final zoom = _transformation.value.getMaxScaleOnAxis();
                  _dragPosition = _clampToBoard(_dragPosition + delta / zoom);
                }),
                onDragEnd: () async {
                  // NOTE: Whole board pixels. Dividing by the zoom leaves tiny float errors
                  // (220.00000000000003) that would otherwise be saved and synced forever
                  final droppedAt = Offset(_dragPosition.dx.roundToDouble(), _dragPosition.dy.roundToDouble());
                  await ref.read(receiptActionsProvider).moveOnBoard(receipt, droppedAt.dx, droppedAt.dy);
                  // Keep showing it at the drop spot until the saved position arrives from the database
                  if (mounted) setState(() => _draggingId = null);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _BoardCard extends StatelessWidget
{
  final Receipt receipt;
  final Offset position;
  final bool isDragging;
  final VoidCallback onTap;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  const _BoardCard({
    super.key,
    required this.receipt,
    required this.position,
    required this.isDragging,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final String caption = [
      receipt.merchant ?? "Untitled",
      if (receipt.total != null) "\$${receipt.total!.toStringAsFixed(2)}",
    ].join(" · ");

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        // NOTE: The card claims the drag, so dragging a card moves the card and dragging
        // the empty board around it moves the board
        onTap: onTap,
        // NOTE: Count the drag from where the finger went down, so the card doesn't lag
        // behind the finger by the few pixels it takes to recognise a drag
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (_) => onDragStart(),
        onPanUpdate: (details) => onDragUpdate(details.delta),
        onPanEnd: (_) => onDragEnd(),
        child: Transform.rotate(
          angle: isDragging ? 0 : ReceiptBoardView.tiltFor(receipt.id),
          child: AnimatedScale(
            scale: isDragging ? 1.06 : 1,
            duration: const Duration(milliseconds: 120),
            // NOTE: A polaroid stays white in dark mode too, it's a "physical" object
            child: Container(
              width: ReceiptBoardView.cardSize.width,
              height: ReceiptBoardView.cardSize.height,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDragging ? 0.35 : 0.2),
                    blurRadius: isDragging ? 16 : 6,
                    offset: Offset(0, isDragging ? 8 : 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: ReceiptImage(receiptId: receipt.id)),
                  SizedBox(
                    height: 36,
                    child: Center(
                      child: Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
