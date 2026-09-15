import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'theme.dart';

/// The frame, the two boxes, and the drag that draws a box.
///
/// Everything the callbacks report is in video pixels, converted from where
/// the pointer is on screen. The tracker never sees screen coordinates.
class FrameView extends StatelessWidget {
  const FrameView({
    super.key,
    required this.frame,
    required this.videoSize,
    required this.boxA,
    required this.boxB,
    required this.showBoxes,
    required this.draft,
    required this.active,
    required this.loading,
    required this.enabled,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final FrameImage? frame;
  final Size videoSize;
  final Box? boxA;
  final Box? boxB;
  final bool showBoxes;
  final Box? draft;
  final Fencer active;
  final bool loading;
  final bool enabled;
  final ValueChanged<Offset> onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (videoSize.isEmpty || constraints.biggest.isEmpty) {
        return const SizedBox.shrink();
      }
      final fitted = applyBoxFit(BoxFit.contain, videoSize, constraints.biggest).destination;
      final left = (constraints.maxWidth - fitted.width) / 2;
      final top = (constraints.maxHeight - fitted.height) / 2;
      final scale = fitted.width / videoSize.width;

      Offset toVideo(Offset local) => Offset(
            (local.dx / scale).clamp(0.0, videoSize.width),
            (local.dy / scale).clamp(0.0, videoSize.height),
          );

      return Stack(children: [
        Positioned(
          left: left,
          top: top,
          width: fitted.width,
          height: fitted.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Brand.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Brand.line),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: frame == null
                  ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                  : Image.file(
                      File(frame!.image),
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                    ),
            ),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: fitted.width,
          height: fitted.height,
          child: MouseRegion(
            cursor: enabled ? SystemMouseCursors.precise : SystemMouseCursors.basic,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Without this a pan only reports its start once the pointer has
              // moved past the touch slop, so every box began about 18 pixels
              // from where you actually pressed.
              dragStartBehavior: DragStartBehavior.down,
              onPanStart: enabled ? (d) => onDragStart(toVideo(d.localPosition)) : null,
              onPanUpdate: enabled ? (d) => onDragUpdate(toVideo(d.localPosition)) : null,
              onPanEnd: enabled ? (_) => onDragEnd() : null,
              child: CustomPaint(
                painter: _BoxPainter(
                  scale: scale,
                  boxA: showBoxes ? boxA : null,
                  boxB: showBoxes ? boxB : null,
                  draft: draft,
                  draftColor: Brand.box(active),
                ),
              ),
            ),
          ),
        ),
        if (loading)
          Positioned(
            right: left + 12,
            top: top + 12,
            child: const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
      ]);
    });
  }
}

class _BoxPainter extends CustomPainter {
  _BoxPainter({required this.scale, required this.boxA, required this.boxB, required this.draft, required this.draftColor});

  final double scale;
  final Box? boxA;
  final Box? boxB;
  final Box? draft;
  final Color draftColor;

  Rect _screen(Box b) => Rect.fromLTWH(b.x * scale, b.y * scale, b.w * scale, b.h * scale);

  void _drawBox(Canvas canvas, Box box, Color color, String letter) {
    final r = _screen(box);
    canvas.drawRect(r, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5);
    final text = TextPainter(
      text: TextSpan(text: letter, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout();
    final chip = Rect.fromLTWH(r.left - 1.25, r.top - text.height - 6, text.width + 12, text.height + 6);
    final chipRect = chip.top < 0 ? chip.translate(0, r.height + text.height + 6) : chip;
    canvas.drawRect(chipRect, Paint()..color = color);
    text.paint(canvas, Offset(chipRect.left + 6, chipRect.top + 3));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (boxA != null) _drawBox(canvas, boxA!, Brand.boxA, 'A');
    if (boxB != null) _drawBox(canvas, boxB!, Brand.boxB, 'B');
    if (draft != null) {
      final r = _screen(draft!);
      canvas.drawRect(r, Paint()..color = draftColor.withValues(alpha: 0.16));
      canvas.drawRect(r, Paint()
        ..color = draftColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(covariant _BoxPainter old) =>
      old.scale != scale || old.boxA != boxA || old.boxB != boxB || old.draft != draft || old.draftColor != draftColor;
}
