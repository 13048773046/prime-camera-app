import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 黑白取景引导层，结构对齐 Doka 的 AR 构图：
/// 主体四角框 → 虚线目标环 → 对齐后的渐变圆角裁切框。
/// 画面中央不再放固定中心点，避免把「对准中心」误当成唯一构图。
class GuideOverlay extends StatefulWidget {
  const GuideOverlay({
    super.key,
    required this.subjectBox,
    required this.targetBox,
    this.aligned = false,
    this.analyzing = false,
    this.showGrid = false,
    this.confidence = 0.62,
    this.frameRect,
    this.alignedBox,
    this.subjectLabel = '主体',
  });

  final List<double> subjectBox;
  final List<double> targetBox;

  /// 服务端 scan 返回的 `SubAreaRectNorm`。对齐后用它画渐变裁切框，
  /// 对应 Doka 的 AI 构图方案；没有服务端方案时退回 targetBox。
  final List<double>? alignedBox;
  final bool aligned;
  final bool analyzing;
  final bool showGrid;
  final double confidence;

  /// 预览画面在屏幕上的可见矩形（BoxFit.cover 会裁掉一部分画幅）。
  final Rect? frameRect;
  final String subjectLabel;

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
                frameRect: widget.frameRect,
                alignedBox: widget.alignedBox,
                subjectLabel: widget.subjectLabel,
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
    required this.frameRect,
    required this.alignedBox,
    required this.subjectLabel,
  });

  final List<double> subjectBox;
  final List<double> targetBox;
  final bool aligned;
  final bool analyzing;
  final bool showGrid;
  final double scan;
  final double confidence;
  final Rect? frameRect;
  final List<double>? alignedBox;
  final String subjectLabel;

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

    // 对齐后只保留主体周围的渐变圆角框；主体框、目标环一起退场。
    // 不再画整块 3:4 边框——那会让人误以为“满屏居中”就是唯一构图。
    if (aligned) {
      final source = frameRect ?? (Offset.zero & size);
      Rect? target;
      final box = (alignedBox != null && alignedBox!.length == 4)
          ? alignedBox!
          : targetBox;
      if (box.length == 4) {
        target = Rect.fromLTWH(
          source.left + box[0] * source.width,
          source.top + box[1] * source.height,
          box[2] * source.width,
          box[3] * source.height,
        );
      }
      _paintAlignedFrame(
        canvas,
        size,
        target,
        pulse: 0.5 + 0.5 * math.sin(scan * math.pi * 2),
      );
      return;
    }

    if (analyzing) _paintAnalyzing(canvas, size);

    final sourceRect = frameRect ?? (Offset.zero & size);
    final hasSubject = subjectBox.length == 4;
    Rect? subjectRect;
    Rect? targetRect;
    if (hasSubject) {
      subjectRect = Rect.fromLTWH(
        sourceRect.left + subjectBox[0] * sourceRect.width,
        sourceRect.top + subjectBox[1] * sourceRect.height,
        subjectBox[2] * sourceRect.width,
        subjectBox[3] * sourceRect.height,
      );
      _paintSubject(canvas, subjectRect, size);
    }

    final hasTarget = targetBox.length == 4;
    if (hasTarget) {
      targetRect = Rect.fromLTWH(
        sourceRect.left + targetBox[0] * sourceRect.width,
        sourceRect.top + targetBox[1] * sourceRect.height,
        targetBox[2] * sourceRect.width,
        targetBox[3] * sourceRect.height,
      );
      _paintTarget(canvas, size, targetRect);
    }

    // 主体中心到目标环的细虚线：手机移动时主体框会走，这条线也跟着走。
    // 没有识别到主体时只保留目标环，不再让人误以为画面没有反应。
    if (subjectRect != null && targetRect != null) {
      _paintMoveCue(canvas, subjectRect, targetRect);
    }
  }

  void _paintMoveCue(Canvas canvas, Rect subject, Rect target) {
    final from = subject.center;
    final to = target.center;
    if ((to - from).distance < 10) return;
    _dashedLine(
      canvas,
      from,
      to,
      Paint()
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: 0.24),
    );
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
      final radius =
          (i % 4 == 0 ? 3.8 : 2.5) + pulse * (i % 3 == 0 ? 1.0 : 0.4);
      _paintSparkle(
        canvas,
        Offset(p.dx * size.width, p.dy * size.height),
        radius,
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
    }
  }

  void _paintSubject(Canvas canvas, Rect rect, Size frame) {
    final len = (math.min(rect.width, rect.height) * 0.26)
        .clamp(12.0, 26.0)
        .toDouble();
    final shadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round
      ..color = Colors.black.withValues(alpha: 0.34);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFD76A);

    void corner(Offset p, double sx, double sy) {
      canvas.drawLine(p, p.translate(len * sx, 0), shadow);
      canvas.drawLine(p, p.translate(0, len * sy), shadow);
      canvas.drawLine(p, p.translate(len * sx, 0), paint);
      canvas.drawLine(p, p.translate(0, len * sy), paint);
    }

    corner(rect.topLeft, 1, 1);
    corner(rect.topRight, -1, 1);
    corner(rect.bottomLeft, 1, -1);
    corner(rect.bottomRight, -1, -1);

    final label = TextPainter(
      text: TextSpan(
        text: subjectLabel,
        style: const TextStyle(
          fontSize: 10,
          height: 1.1,
          letterSpacing: 0.8,
          color: Color(0xFF16120A),
          fontWeight: FontWeight.w700,
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
    canvas.drawRRect(tagRect, Paint()..color = const Color(0xFFFFD76A));
    label.paint(canvas, Offset(tagRect.left + 6, tagRect.top + 3.5));
  }

  void _paintTarget(Canvas canvas, Size frame, Rect rect) {
    final radius = (math.min(frame.width, frame.height) * 0.165)
        .clamp(38.0, 64.0)
        .toDouble();
    final target = Offset(
      rect.center.dx.clamp(radius + 8, frame.width - radius - 8).toDouble(),
      rect.center.dy.clamp(radius + 28, frame.height - radius - 34).toDouble(),
    );

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
  }

  void _paintAlignedFrame(
    Canvas canvas,
    Size size,
    Rect? target, {
    required double pulse,
  }) {
    final inset = 10.0;
    final rect = (target ?? Offset.zero & size)
        .inflate(target == null ? 0 : 8)
        .intersect(
          Rect.fromLTWH(
            inset,
            inset,
            size.width - inset * 2,
            size.height - inset * 2,
          ),
        );
    if (rect.width < 30 || rect.height < 30) return;
    final radius = math.min(24.0, math.min(rect.width, rect.height) * 0.08);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // Doka 对齐后会压暗主体以外的画面，只留渐变圆角框。
    final hole = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(rrect),
    );
    canvas.drawPath(hole, Paint()..color = const Color(0x66000000));

    final shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFFE8FFFC),
        Color(0xFF80EEFF),
        Color(0xFFB1CFFF),
        Color(0xFFFFD2F6),
        Color(0xFFFFC38F),
      ],
      stops: [0.0, 0.22, 0.48, 0.74, 1.0],
    ).createShader(rect);

    for (final (width, alpha, blur) in [
      (12.0, 0.16, 16.0),
      (5.0, 0.22, 8.0),
      (1.6, 0.72, 0.0),
    ]) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..shader = shader
          ..color = Colors.white.withValues(
            alpha: alpha * (0.55 + 0.45 * pulse),
          )
          ..maskFilter = blur > 0
              ? MaskFilter.blur(BlurStyle.normal, blur)
              : null,
      );
    }

    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.52);
    const len = 14.0;
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
      oldDelegate.showGrid != showGrid ||
      oldDelegate.frameRect != frameRect ||
      oldDelegate.subjectLabel != subjectLabel;
}
