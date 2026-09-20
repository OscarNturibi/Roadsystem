import 'package:flutter/material.dart';
import '../models/detection_model.dart';

enum VisualizationMode { bbox, heatmap, both }

class DetectionPainter extends CustomPainter {
  final List<Detection> detections;
  final double imageWidth;
  final double imageHeight;
  final VisualizationMode mode;

  const DetectionPainter({
    required this.detections,
    required this.imageWidth,
    required this.imageHeight,
    this.mode = VisualizationMode.bbox,
  });

  /// Computes the actual painted rect of the image inside the widget when
  /// BoxFit.contain is used. Handles both letterbox and pillarbox cases.
  Rect _computeImageRect(Size size) {
    final widgetAspect = size.width / size.height;
    final imageAspect = imageWidth / imageHeight;

    if (imageAspect > widgetAspect) {
      // Wider image → top & bottom bars (letterbox)
      final scale = size.width / imageWidth;
      final paintedH = imageHeight * scale;
      final offsetY = (size.height - paintedH) / 2;
      return Rect.fromLTWH(0, offsetY, size.width, paintedH);
    } else {
      // Taller image → left & right bars (pillarbox)
      final scale = size.height / imageHeight;
      final paintedW = imageWidth * scale;
      final offsetX = (size.width - paintedW) / 2;
      return Rect.fromLTWH(offsetX, 0, paintedW, size.height);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    final imgRect = _computeImageRect(size);
    final scaleX = imgRect.width / imageWidth;
    final scaleY = imgRect.height / imageHeight;

    // Clip all drawing to image bounds so labels never bleed into letterbox bars
    canvas.save();
    canvas.clipRect(imgRect);

    for (final det in detections) {
      final rect = Rect.fromLTWH(
        imgRect.left + det.x1 * scaleX,
        imgRect.top + det.y1 * scaleY,
        det.width * scaleX,
        det.height * scaleY,
      );

      if (mode == VisualizationMode.heatmap || mode == VisualizationMode.both) {
        _drawHeatBlob(canvas, rect, det);
      }

      if (mode == VisualizationMode.bbox || mode == VisualizationMode.both) {
        _drawBoundingBox(canvas, rect, det);
        _drawLabel(canvas, rect, det, imgRect);
      }
    }

    canvas.restore();
  }

  // Fixed: uses drawOval directly instead of canvas.scale() hack
  void _drawHeatBlob(Canvas canvas, Rect rect, Detection det) {
    final heatRect = Rect.fromCenter(
      center: rect.center,
      width: rect.width * 1.5,
      height: rect.height * 1.5,
    );

    final gradient = RadialGradient(
      colors: [
        det.severityColor.withValues(alpha: 0.65),
        det.severityColor.withValues(alpha: 0.30),
        det.severityColor.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.55, 1.0],
    );

    canvas.drawOval(
      heatRect,
      Paint()..shader = gradient.createShader(heatRect),
    );
  }

  void _drawBoundingBox(Canvas canvas, Rect rect, Detection det) {
    // Thin full-perimeter ghost border
    canvas.drawRect(
      rect,
      Paint()
        ..color = det.severityColor.withValues(alpha: 0.45)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    // Corner brackets — length scales with box size, clamped between 6–16px
    final cornerPaint = Paint()
      ..color = det.severityColor
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final cLen = (rect.shortestSide * 0.20).clamp(6.0, 16.0);

    final corners = <List<Offset>>[
      [rect.topLeft,     Offset(cLen, 0),  Offset(0, cLen)],
      [rect.topRight,    Offset(-cLen, 0), Offset(0, cLen)],
      [rect.bottomLeft,  Offset(cLen, 0),  Offset(0, -cLen)],
      [rect.bottomRight, Offset(-cLen, 0), Offset(0, -cLen)],
    ];

    for (final c in corners) {
      final o = c[0];
      final h = c[1];
      final v = c[2];
      canvas.drawPath(
        Path()
          ..moveTo(o.dx + h.dx, o.dy + h.dy)
          ..lineTo(o.dx, o.dy)
          ..lineTo(o.dx + v.dx, o.dy + v.dy),
        cornerPaint,
      );
    }
  }

  void _drawLabel(Canvas canvas, Rect rect, Detection det, Rect imgBounds) {
    final label = '${det.className.toUpperCase()}  ${det.confidencePct}';

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const hPad = 7.0;
    const vPad = 3.5;
    const chipH = 20.0;
    final chipW = tp.width + hPad * 2;

    // Place above box, fall back to below if it clips the image top edge
    final labelTop = rect.top - chipH >= imgBounds.top
        ? rect.top - chipH
        : rect.bottom;

    // Keep chip within image horizontal bounds
    final chipLeft = rect.left.clamp(imgBounds.left, imgBounds.right - chipW);

    final chipRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(chipLeft, labelTop, chipW, chipH),
      const Radius.circular(5),
    );

    canvas.drawRRect(chipRRect, Paint()..color = det.severityColor);
    tp.paint(canvas, Offset(chipLeft + hPad, labelTop + vPad));
  }

  @override
  bool shouldRepaint(DetectionPainter old) =>
      old.detections != detections ||
      old.mode != mode ||
      old.imageWidth != imageWidth ||
      old.imageHeight != imageHeight;
}
