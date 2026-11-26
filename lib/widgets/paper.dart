import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// 手帐纸底：奶油纸 + 淡点阵 + 细颗粒 + 边缘微微发暖。
/// 所有纹理都画在一次性栅格化的图层上，避免每帧重绘。
class PaperBackground extends StatelessWidget {
  const PaperBackground({super.key, this.child, this.dense = false});

  final Widget? child;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _PaperPainter(dense: dense),
        child: child,
      ),
    );
  }
}

class _PaperPainter extends CustomPainter {
  _PaperPainter({required this.dense});

  final bool dense;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFDFAF4), PrimeColor.paper, Color(0xFFF7F0E3)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(rect),
    );

    // 手帐点阵：22px 一格，非常淡。
    final dot = Paint()..color = const Color(0x2E9C8B6E);
    const step = 22.0;
    for (double y = step / 2; y < size.height; y += step) {
      for (double x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 0.9, dot);
      }
    }

    // 纸纤维颗粒。
    final rnd = math.Random(20261126);
    final count = dense ? 900 : 520;
    for (int i = 0; i < count; i++) {
      final dx = rnd.nextDouble() * size.width;
      final dy = rnd.nextDouble() * size.height;
      final warm = rnd.nextBool();
      final paint = Paint()
        ..color = (warm ? const Color(0xFF9A8463) : const Color(0xFF54655C))
            .withValues(alpha: 0.03 + rnd.nextDouble() * 0.06);
      canvas.drawCircle(Offset(dx, dy), 0.35 + rnd.nextDouble() * 1.05, paint);
    }

    // 四角轻微暖影。
    final vignette = Paint()
      ..shader = RadialGradient(
        radius: 1.15,
        colors: [Colors.transparent, const Color(0x141C1206)],
        stops: const [0.62, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);
  }

  @override
  bool shouldRepaint(covariant _PaperPainter oldDelegate) => oldDelegate.dense != dense;
}

/// 手绘墨线框：双层描边 + 四角裁切记号，模拟印刷/漫画分格。
class InkFrame extends StatelessWidget {
  const InkFrame({
    super.key,
    required this.child,
    this.radius = 12,
    this.padding = EdgeInsets.zero,
    this.color = PrimeColor.ink,
    this.strong = true,
    this.corners = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final Color color;
  final bool strong;
  final bool corners;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _InkFramePainter(
        radius: radius,
        color: color,
        strong: strong,
        corners: corners,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _InkFramePainter extends CustomPainter {
  _InkFramePainter({
    required this.radius,
    required this.color,
    required this.strong,
    required this.corners,
  });

  final double radius;
  final Color color;
  final bool strong;
  final bool corners;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0.8, 0.8, size.width - 1.6, size.height - 1.6);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // 纸面上的淡投影，让分格像贴在纸上。
    canvas.drawRRect(
      rrect.shift(const Offset(1.4, 2.2)),
      Paint()
        ..color = const Color(0x1A1F2A22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strong ? 2.0 : 1.0
        ..color = color.withValues(alpha: strong ? 0.92 : 0.62),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(3.2), Radius.circular(radius - 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = color.withValues(alpha: 0.34),
    );

    if (corners) {
      final tick = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = color.withValues(alpha: 0.55);
      const len = 9.0;
      const gap = 6.0;
      final corners4 = <Offset>[
        Offset(rect.left - gap, rect.top - gap),
        Offset(rect.right + gap, rect.top - gap),
        Offset(rect.right + gap, rect.bottom + gap),
        Offset(rect.left - gap, rect.bottom + gap),
      ];
      for (final corner in corners4) {
        final sx = corner.dx < rect.center.dx ? 1 : -1;
        final sy = corner.dy < rect.center.dy ? 1 : -1;
        canvas.drawLine(corner, corner.translate(len * sx, 0), tick);
        canvas.drawLine(corner, corner.translate(0, len * sy), tick);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _InkFramePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strong != strong;
}

/// 印章：墨绿方章，边角有崩口。
class SealStamp extends StatelessWidget {
  const SealStamp({super.key, this.text = '定', this.size = 34, this.angle = -0.05});

  final String text;
  final double size;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: PrimeColor.ink,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: PrimeColor.paper, width: 1.4),
          boxShadow: const [
            BoxShadow(color: Color(0x2A17332B), blurRadius: 2, offset: Offset(1, 2)),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: TextStyle(
            fontFamily: PrimeFont.hand,
            fontFamilyFallback: PrimeFont.handFallback,
            color: PrimeColor.paper,
            fontSize: size * 0.52,
            height: 1,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

/// 胶带：贴在照片/卡片角上的半透明奶油纸条。
class TapeStrip extends StatelessWidget {
  const TapeStrip({super.key, this.width = 54, this.height = 16, this.angle = -0.32});

  final double width;
  final double height;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFF6EEDC).withValues(alpha: 0.86),
          border: Border.all(color: const Color(0x33A08C68), width: 0.8),
          boxShadow: const [
            BoxShadow(color: Color(0x141A1408), blurRadius: 2, offset: Offset(0, 1)),
          ],
        ),
      ),
    );
  }
}

/// 手绘下划线：两笔叠压，粗细不均。
class BrushUnderline extends StatelessWidget {
  const BrushUnderline({super.key, this.width = 92, this.height = 8, this.color = PrimeColor.ink});

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: _BrushPainter(color: color)),
    );
  }
}

class _BrushPainter extends CustomPainter {
  _BrushPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(1, size.height * 0.55)
      ..quadraticBezierTo(size.width * 0.35, size.height * 0.15, size.width - 2, size.height * 0.42);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.85),
    );
    final path2 = Path()
      ..moveTo(4, size.height * 0.85)
      ..quadraticBezierTo(size.width * 0.45, size.height * 0.5, size.width * 0.9, size.height * 0.72);
    canvas.drawPath(
      path2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(covariant _BrushPainter oldDelegate) => oldDelegate.color != color;
}

/// 虚线分隔（手帐内页的分栏线）。
class DottedRule extends StatelessWidget {
  const DottedRule({super.key, this.height = 1, this.color = PrimeColor.rule, this.dash = 3.0, this.gap = 3.0});

  final double height;
  final Color color;
  final double dash;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _DashLinePainter(color: color, dash: dash, gap: gap)),
    );
  }
}

class _DashLinePainter extends CustomPainter {
  _DashLinePainter({required this.color, required this.dash, required this.gap});

  final Color color;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double x = 0; x < size.width; x += dash + gap) {
      canvas.drawRect(Rect.fromLTWH(x, 0, dash, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashLinePainter oldDelegate) => false;
}
