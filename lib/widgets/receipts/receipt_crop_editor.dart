import 'dart:typed_data';

import 'package:expense_tracker/providers/receipt_crop_providers.dart';
import 'package:expense_tracker/services/receipt_crop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// What the user chose in the crop editor. [corners] is null for "use the whole photo"
class CropChoice
{
  final ReceiptCorners? corners;

  const CropChoice(this.corners);
}

// Opens the crop editor on [photo] (shown turned by [quarterTurns]), starting from the
// [current] crop if there is one. Returns null if the user backed out without choosing
Future<CropChoice?> showReceiptCropEditor(
  BuildContext context, {
  required Uint8List photo,
  required int quarterTurns,
  ReceiptCorners? current,
})
{
  return Navigator.push<CropChoice>(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ReceiptCropEditor(photo: photo, quarterTurns: quarterTurns, current: current),
    ),
  );
}

class ReceiptCropEditor extends ConsumerStatefulWidget
{
  final Uint8List photo;
  final int quarterTurns;
  final ReceiptCorners? current;

  const ReceiptCropEditor({super.key, required this.photo, required this.quarterTurns, this.current});

  @override
  ConsumerState<ReceiptCropEditor> createState() => _ReceiptCropEditorState();
}

class _ReceiptCropEditorState extends ConsumerState<ReceiptCropEditor>
{
  static const double _handleSize = 32;

  // When nothing was detected: most of the photo, with room to grab each corner
  static const ReceiptCorners _nearlyWholePhoto = [Offset(0.05, 0.05), Offset(0.95, 0.05), Offset(0.95, 0.95), Offset(0.05, 0.95)];

  CropEditorImage? _image;
  ReceiptCorners? _corners;
  Object? _error;

  @override
  void initState() {
    super.initState();
    ref.read(receiptCropperProvider).prepare(widget.photo, widget.quarterTurns).then(
      (image) {
        if (!mounted) return;
        setState(() {
          _image = image;
          _corners = widget.current ?? image.detected ?? _nearlyWholePhoto;
        });
      },
      onError: (Object error) {
        if (mounted) setState(() => _error = error);
      },
    );
  }

  void _moveCorner(int index, Offset delta, Size shown)
  {
    setState(() {
      final corners = [..._corners!];
      final moved = corners[index] + Offset(delta.dx / shown.width, delta.dy / shown.height);
      corners[index] = Offset(moved.dx.clamp(0.0, 1.0), moved.dy.clamp(0.0, 1.0));
      _corners = corners;
    });
  }

  Widget _editor(BuildContext context, CropEditorImage image)
  {
    return LayoutBuilder(builder: (context, constraints) {
      // Where the photo sits on screen when it's fitted inside the available space
      // NOTE: Leave room around the photo so a corner handle at the very edge can still be grabbed
      final available = Size(constraints.maxWidth - _handleSize * 2, constraints.maxHeight - _handleSize * 2);
      final fitted = applyBoxFit(BoxFit.contain, image.size, available).destination;
      final photoRect = Alignment.center.inscribe(fitted, Offset.zero & Size(constraints.maxWidth, constraints.maxHeight));
      final screenCorners = [for (final c in _corners!) photoRect.topLeft + Offset(c.dx * photoRect.width, c.dy * photoRect.height)];

      return Stack(
        children: [
          Positioned.fromRect(rect: photoRect, child: Image.memory(image.preview, fit: BoxFit.fill, gaplessPlayback: true)),
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _CropPainter(screenCorners)))),
          for (final (index, corner) in screenCorners.indexed)
            Positioned(
              left: corner.dx - _handleSize / 2,
              top: corner.dy - _handleSize / 2,
              child: GestureDetector(
                key: Key("crop_corner_$index"),
                onPanUpdate: (details) => _moveCorner(index, details.delta, photoRect.size),
                child: Container(
                  width: _handleSize,
                  height: _handleSize,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.lightBlue, width: 3),
                    boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Crop receipt"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, const CropChoice(null)),
            child: const Text("Whole photo"),
          ),
          TextButton(
            onPressed: _corners == null ? null : () => Navigator.pop(context, CropChoice(_corners)),
            child: const Text("Done"),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _error != null
                ? const Center(child: Text("Couldn't open this photo"))
                : image == null
                  ? const Center(child: CircularProgressIndicator())
                  : _editor(context, image),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      image != null && image.detected == null
                        ? "Couldn't find the receipt's edges. Drag the corners onto them."
                        : "Drag the corners onto the receipt's edges.",
                    ),
                  ),
                  if (image?.detected != null)
                    TextButton.icon(
                      onPressed: () => setState(() => _corners = image!.detected),
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text("Auto-detect"),
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

// Dims everything outside the crop and outlines it
class _CropPainter extends CustomPainter
{
  final List<Offset> corners;

  _CropPainter(this.corners);

  @override
  void paint(Canvas canvas, Size size)
  {
    final crop = Path()..addPolygon(corners, true);
    final outside = Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), crop);
    canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.55));
    canvas.drawPath(crop, Paint()
      ..color = Colors.lightBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) => oldDelegate.corners != corners;
}
