import 'dart:math' as math;

import 'package:flutter/material.dart';


/// 黑白取景引导层，结构对齐 Doka 的 AR 构图：
/// 主体四角框 → 中心四角星 → 虚线目标环 → 对齐后的渐变圆角裁切框。
class GuideOverlay extends StatefulWidget {
  const GuideOverlay({
    super.key,
    required this.subjectBox,
    required this.targetBox,
    this.aligned = false,
    this.analyzing = false,
    this.showGrid = false,
    this.confidence = 0.62,
  });

  final List<double> subjectBox;
  final List<double> targetBox;
  final bool aligned;
  final bool analyzing;
  final bool showGrid;
  final double confidence;

  @override
  State<GuideOverlay> createState() => _GuideOverlayState();
}

class _GuideOverlayState extends State<GuideOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return AnimatedBuilder(
          animation: _scan,
          builder: (context, _) {
            return CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _GuidePainter(
                subjectBox: widget.subjectBox,
                targetBox: widget.targetBox,
                aligned: widget.aligned,
                analyzing: widget.analyzing,
                showGrid: widget.showGrid,
                scan: _scan.value,
                confidence: widget.confidence,
              ),
            );
          },
        );
      },
    );
  }
}

class _GuidePainter extends CustomPainter {
  _GuidePainter({
    required this.subjectBox,
    required this.targetBox,
    required this.aligned,
    required this.analyzing,
    required this.showGrid,
    required this.scan,
    required this.confidence,
  });

  final List<double> subjectBox;
  final List<double> targetBox;
  final bool aligned;
  final bool analyzing;
  final bool showGrid;
  final double scan;
  final double confidence;

  static const List<Offset> _sparkleSpots = [
    Offset(0.09, 0.18),
    Offset(0.20, 0.10),
    Offset(0.34, 0.22),
    Offset(0.47, 0.15),
    Offset(0.63, 0.19),
    Offset(0.78, 0.10),
    Offset(0.91, 0.20),
    Offset(0.12, 0.38),
    Offset(0.29, 0.34),
    Offset(0.71, 0.36),
    Offset(0.88, 0.34),
    Offset(0.18, 0.56),
    Offset(0.84, 0.58),
    Offset(0.07, 0.72),
    Offset(0.92, 0.75),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (showGrid) {
      final grid = Paint()
        ..color = Colors.white.withValues(alpha: 0.05)
        ..strokeWidth = 0.7;
      for (int i = 1; i <= 2; i++) {
        final x = size.width * i / 3;
        final y = size.height * i / 3;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      }
    }

    // 对齐后只保留整块圆角裁切框；主体框、目标环、准星一起退场。
    if (aligned) {
      _paintAlignedFrame(canvas, size);
      return;
    }

    if (analyzing) _paintAnalyzing(canvas, size);

    final center = Offset(size.width / 2, size.height / 2);
    _paintCenterMark(canvas, center);

    final hasSubject = subjectBox.length == 4;
    if (hasSubject) {
      final rect = Rect.fromLTWH(
        subjectBox[0] * size.width,
        subjectBox[1] * size.height,
        subjectBox[2] * size.width,
        subjectBox[3] * size.height,
      );
      _paintSubject(canvas, rect, size);
    }

    final hasTarget = targetBox.length == 4;
    if (hasTarget) {
      final rect = Rect.fromLTWH(
        targetBox[0] * size.width,
        targetBox[1] * size.height,
        targetBox[2] * size.width,
        targetBox[3] * size.height,
      );
      _paintTarget(canvas, size, rect, center);
    }

  }

  void _paintAnalyzing(Canvas canvas, Size size) {
    // 四角细括号：正在读取画面。
    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.24);
    const inset = 12.0;
    const len = 16.0;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );
    for (final c in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      final sx = c.dx < rect.center.dx ? 1.0 : -1.0;
      final sy = c.dy < rect.center.dy ? 1.0 : -1.0;
      canvas.drawLine(c, c.translate(len * sx, 0), corner);
      canvas.drawLine(c, c.translate(0, len * sy), corner);
    }

    // Doka 的分析态是满屏星点；黑白版只保留少量白色星火。
    for (int i = 0; i < _sparkleSpots.length; i++) {
      final p = _sparkleSpots[i];
      final phase = scan * math.pi * 2 + i * 1.31;
      final pulse = 0.5 + 0.5 * math.sin(phase);
      final opacity = 0.14 + 0.30 * pulse;
      final radius = (i % 4 == 0 ? 3.8 : 2.5) +
          pulse * (i % 3 == 0 ? 1.0 : 0.4);
      _paintSparkle(
        canvas,
        Offset(p.dx * size.width, p.dy * size.height),
        radius,
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
    }
  }

  void _paintCenterMark(Canvas canvas, Offset c) {
    final shadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..color = Colors.black.withValues(alpha: 0.32);
    _paintSparklePath(canvas, c, aligned ? 12.8 : 10.8, shadow);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = aligned ? 1.6 : 1.2
      ..color = Colors.white.withValues(alpha: aligned ? 0.95 : 0.72);
    _paintSparklePath(canvas, c, aligned ? 11.5 : 9.5, paint);

    if (aligned) {
      canvas.drawCircle(
        c,
        16,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = Colors.white.withValues(alpha: 0.10)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    canvas.drawCircle(
      c,
      aligned ? 2.8 : 2.1,
      Paint()..color = Colors.white.withValues(alpha: aligned ? 0.95 : 0.62),
    );
  }

  void _paintSubject(Canvas canvas, Rect rect, Size frame) {
    final len = (math.min(rect.width, rect.height) * 0.26)
        .clamp(12.0, 26.0)
        .toDouble();
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: aligned ? 0.92 : 0.72);

    void corner(Offset p, double sx, double sy) {
      canvas.drawLine(p, p.translate(len * sx, 0), paint);
      canvas.drawLine(p, p.translate(0, len * sy), paint);
    }

    corner(rect.topLeft, 1, 1);
    corner(rect.topRight, -1, 1);
    corner(rect.bottomLeft, 1, -1);
    corner(rect.bottomRight, -1, -1);

    final label = TextPainter(
      text: const TextSpan(
        text: '主体',
        style: TextStyle(
          fontSize: 9,
          height: 1.1,
          letterSpacing: 1.2,
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final tagLeft = rect.left
        .clamp(2.0, math.max(2.0, frame.width - label.width - 14))
        .toDouble();
    final tagTop = (rect.bottom + 5)
        .clamp(2.0, math.max(2.0, frame.height - label.height - 7))
        .toDouble();
    final tagRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(tagLeft, tagTop, label.width + 12, label.height + 7),
      const Radius.circular(4),
    );
    canvas.drawRRect(tagRect, Paint()..color = Colors.black.withValues(alpha: 0.72));
    canvas.drawRRect(
      tagRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: 0.18),
    );
    label.paint(canvas, Offset(tagRect.left + 6, tagRect.top + 3.5));
  }

  void _paintTarget(Canvas canvas, Size frame, Rect rect, Offset center) {
    final radius = (math.min(frame.width, frame.height) * 0.165)
        .clamp(38.0, 64.0)
        .toDouble();
    final target = Offset(
      rect.center.dx.clamp(radius + 8, frame.width - radius - 8).toDouble(),
      rect.center.dy.clamp(radius + 28, frame.height - radius - 34).toDouble(),
    );

    // 中心 → 目标环的虚线，方向感来自 Doka 的虚线引导。
    if (!aligned) {
      _dashedLine(
        canvas,
        center,
        target,
        Paint()
          ..strokeWidth = 0.8
          ..color = Colors.white.withValues(alpha: 0.24),
      );
      canvas.drawCircle(
        center + (target - center) * 0.34,
        1.8,
        Paint()..color = Colors.white.withValues(alpha: 0.34),
      );
    }

    final dead = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.white.withValues(alpha: aligned ? 0.28 : 0.12);
    canvas.drawCircle(target, radius * 0.76, dead);

    final shadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..color = Colors.black.withValues(alpha: 0.30);
    _dashedCircle(canvas, target, radius, shadow, dash: 7, gap: 6);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = aligned ? 1.9 : 1.4
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: aligned ? 0.92 : 0.68);
    if (aligned) {
      canvas.drawCircle(
        target,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..color = Colors.white.withValues(alpha: 0.13)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawCircle(target, radius, ring);
    } else {
      _dashedCircle(canvas, target, radius, ring, dash: 7, gap: 6);
    }

    final tick = Paint()
      ..color = Colors.white.withValues(alpha: aligned ? 0.9 : 0.55)
      ..strokeWidth = 1;
    for (int i = 0; i < 4; i++) {
      final a = i * math.pi / 2;
      final p1 = target + Offset(math.cos(a), math.sin(a)) * (radius - 4);
      final p2 = target + Offset(math.cos(a), math.sin(a)) * (radius + 3);
      canvas.drawLine(p1, p2, tick);
    }

    if (!aligned && analyzing) {
      final sweep = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.32);
      final start = scan * math.pi * 2 - math.pi / 2;
      canvas.drawArc(
        Rect.fromCircle(center: target, radius: radius + 2),
        start,
        0.5,
        false,
        sweep,
      );
    }

    canvas.drawCircle(
      target,
      aligned ? 3.2 : 2.2,
      Paint()..color = Colors.white.withValues(alpha: aligned ? 0.95 : 0.7),
    );
  }

  void _paintAlignedFrame(Canvas canvas, Size size) {
    const inset = 12.0;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(22));
    final shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xE6FFFFFF),
        Color(0x33FFFFFF),
        Color(0xCCFFFFFF),
        Color(0x22FFFFFF),
      ],
      stops: [0.0, 0.38, 0.72, 1.0],
    ).createShader(rect);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..color = const Color(0x12FFFFFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = const Color(0x1FFFFFFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = shader,
    );

    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.42);
    const len = 16.0;
    for (final c in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      final sx = c.dx < rect.center.dx ? 1.0 : -1.0;
      final sy = c.dy < rect.center.dy ? 1.0 : -1.0;
      canvas.drawLine(c, c.translate(len * sx, 0), corner);
      canvas.drawLine(c, c.translate(0, len * sy), corner);
    }
  }

  void _paintSparkle(Canvas canvas, Offset center, double radius, Paint paint) {
    _paintSparklePath(canvas, center, radius, paint);
  }

  void _paintSparklePath(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + r * 0.18, c.dy - r * 0.18, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + r * 0.18, c.dy + r * 0.18, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - r * 0.18, c.dy + r * 0.18, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - r * 0.18, c.dy - r * 0.18, c.dx, c.dy - r);
    canvas.drawPath(path, paint);
  }

  void _dashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    final count = (2 * math.pi * radius / (dash + gap)).floor();
    final step = 2 * math.pi / count;
    for (int i = 0; i < count; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * step,
        step * (dash / (dash + gap)),
        false,
        paint,
      );
    }
  }

  void _dashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    final delta = to - from;
    final distance = delta.distance;
    if (distance < 12) return;
    final unit = delta / distance;
    const dash = 6.0;
    const gap = 6.0;
    for (double d = 18; d < distance - 18; d += dash + gap) {
      canvas.drawLine(
        from + unit * d,
        from + unit * math.min(d + dash, distance - 18),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GuidePainter oldDelegate) =>
      oldDelegate.scan != scan ||
      oldDelegate.aligned != aligned ||
      oldDelegate.analyzing != analyzing ||
      oldDelegate.targetBox != targetBox ||
      oldDelegate.subjectBox != subjectBox ||
      oldDelegate.showGrid != showGrid;
}
