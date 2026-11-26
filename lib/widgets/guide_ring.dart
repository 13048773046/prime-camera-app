import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// AR 构图环：薄荷虚线目标环 + 主体取景框 + 死区 + 扫描弧。
/// 手册要求：死区 1.2°，收敛 0.25s，引导只做视觉提示，不遮挡主体。
class GuideOverlay extends StatefulWidget {
  const GuideOverlay({
    super.key,
    required this.subjectBox,
    required this.targetBox,
    this.aligned = false,
    this.showGrid = true,
    this.confidence = 0.62,
  });

  final List<double> subjectBox;
  final List<double> targetBox;
  final bool aligned;
  final bool showGrid;
  final double confidence;

  @override
  State<GuideOverlay> createState() => _GuideOverlayState();
}

class _GuideOverlayState extends State<GuideOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _scan = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
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
    required this.showGrid,
    required this.scan,
    required this.confidence,
  });

  final List<double> subjectBox;
  final List<double> targetBox;
  final bool aligned;
  final bool showGrid;
  final double scan;
  final double confidence;

  @override
  void paint(Canvas canvas, Size size) {
    if (showGrid) {
      final grid = Paint()
        ..color = Colors.white.withValues(alpha: 0.09)
        ..strokeWidth = 0.7;
      for (int i = 1; i <= 2; i++) {
        final x = size.width * i / 3;
        final y = size.height * i / 3;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      }
    }

    // 中心十字：极细，克制。
    final cross = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 0.9;
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawLine(c.translate(-7, 0), c.translate(-2.5, 0), cross);
    canvas.drawLine(c.translate(2.5, 0), c.translate(7, 0), cross);
    canvas.drawLine(c.translate(0, -7), c.translate(0, -2.5), cross);
    canvas.drawLine(c.translate(0, 2.5), c.translate(0, 7), cross);

    final hasSubject = subjectBox.length == 4;
    if (hasSubject) {
      final rect = Rect.fromLTWH(
        subjectBox[0] * size.width,
        subjectBox[1] * size.height,
        subjectBox[2] * size.width,
        subjectBox[3] * size.height,
      );
      _paintSubject(canvas, rect);
    }

    final hasTarget = targetBox.length == 4;
    if (hasTarget) {
      final rect = Rect.fromLTWH(
        targetBox[0] * size.width,
        targetBox[1] * size.height,
        targetBox[2] * size.width,
        targetBox[3] * size.height,
      );
      _paintTarget(canvas, size, rect);
    }
  }

  void _paintSubject(Canvas canvas, Rect rect) {
    final len = math.min(rect.width, rect.height) * 0.30;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..color = PrimeColor.mint.withValues(alpha: aligned ? 1.0 : 0.9);

    void corner(Offset p, double sx, double sy) {
      canvas.drawLine(p, p.translate(len * sx, 0), paint);
      canvas.drawLine(p, p.translate(0, len * sy), paint);
    }

    corner(rect.topLeft, 1, 1);
    corner(rect.topRight, -1, 1);
    corner(rect.bottomLeft, 1, -1);
    corner(rect.bottomRight, -1, -1);

  }

  void _paintTarget(Canvas canvas, Size frame, Rect rect) {
    final center = rect.center;
    // 瞄准环：圆形，半径与会话尺寸挂钩，不再拉成椭圆。
    final radius = math.min(frame.width, frame.height) * 0.19;
    final safeCenter = Offset(
      center.dx.clamp(radius + 6, frame.width - radius - 6),
      center.dy.clamp(radius + 22, frame.height - radius - 30),
    );

    // 构图安全区：四角很淡的裁切提示。
    final safe = Rect.fromLTWH(frame.width * 0.07, frame.height * 0.06, frame.width * 0.86, frame.height * 0.70);
    final safePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.white.withValues(alpha: 0.22);
    const safeLen = 14.0;
    for (final corner in [safe.topLeft, safe.topRight, safe.bottomLeft, safe.bottomRight]) {
      final sx = corner.dx < safe.center.dx ? 1.0 : -1.0;
      final sy = corner.dy < safe.center.dy ? 1.0 : -1.0;
      canvas.drawLine(corner, corner.translate(safeLen * sx, 0), safePaint);
      canvas.drawLine(corner, corner.translate(0, safeLen * sy), safePaint);
    }

    // 死区：1.2° 对应的内环。
    final dead = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = PrimeColor.mint.withValues(alpha: aligned ? 0.5 : 0.26);
    canvas.drawCircle(safeCenter, radius * 0.78, dead);

    // 主环：手绘感的短虚线。
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = aligned ? 2.4 : 1.9
      ..strokeCap = StrokeCap.round
      ..color = aligned ? PrimeColor.mint : PrimeColor.mint.withValues(alpha: 0.88);
    if (aligned) {
      canvas.drawCircle(
        safeCenter,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..color = PrimeColor.mint.withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
    }
    _dashedCircle(canvas, safeCenter, radius, ring, dash: aligned ? 7 : 10, gap: aligned ? 3.5 : 7);

    // 四向刻度 + 八个 1.2° 小刻度。
    final tick = Paint()..color = PrimeColor.mint.withValues(alpha: 0.8)..strokeWidth = 1.1;
    for (int i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final p1 = safeCenter + Offset(math.cos(a), math.sin(a)) * (radius - 3);
      final p2 = safeCenter + Offset(math.cos(a), math.sin(a)) * (radius + 2);
      canvas.drawLine(p1, p2, i % 2 == 0 ? tick : (Paint()..color = PrimeColor.mint.withValues(alpha: 0.4)..strokeWidth = 0.9));
    }

    // 扫描弧：模型持续收敛的示意。
    if (!aligned) {
      final sweep = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..color = PrimeColor.mint.withValues(alpha: 0.55);
      final start = scan * math.pi * 2 - math.pi / 2;
      canvas.drawArc(
        Rect.fromCircle(center: safeCenter, radius: radius),
        start,
        0.45,
        false,
        sweep,
      );
      final head = safeCenter + Offset(math.cos(start + 0.45), math.sin(start + 0.45)) * radius;
      canvas.drawCircle(head, 2.2, Paint()..color = Colors.white.withValues(alpha: 0.85));
    }

    // 环心：十字 + 对齐点。
    final core = Paint()..color = aligned ? PrimeColor.mint : Colors.white.withValues(alpha: 0.75);
    canvas.drawCircle(safeCenter, aligned ? 4.2 : 2.6, core);
    final hair = Paint()..color = Colors.white.withValues(alpha: 0.35)..strokeWidth = 0.8;
    canvas.drawLine(safeCenter.translate(-radius * 0.55, 0), safeCenter.translate(-radius * 0.32, 0), hair);
    canvas.drawLine(safeCenter.translate(radius * 0.32, 0), safeCenter.translate(radius * 0.55, 0), hair);
    canvas.drawLine(safeCenter.translate(0, -radius * 0.55), safeCenter.translate(0, -radius * 0.32), hair);
    canvas.drawLine(safeCenter.translate(0, radius * 0.32), safeCenter.translate(0, radius * 0.55), hair);

  }

  void _dashedCircle(Canvas canvas, Offset center, double radius, Paint paint, {required double dash, required double gap}) {
    final circumference = 2 * math.pi * radius;
    final count = (circumference / (dash + gap)).floor();
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

  @override
  bool shouldRepaint(covariant _GuidePainter oldDelegate) =>
      oldDelegate.scan != scan ||
      oldDelegate.aligned != aligned ||
      oldDelegate.targetBox != targetBox ||
      oldDelegate.subjectBox != subjectBox;
}
