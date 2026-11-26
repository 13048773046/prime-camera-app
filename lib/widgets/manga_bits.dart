import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// 漫画对白气泡：奶油纸底、墨线边、朝上偏左的小尾巴。
class SpeechBubble extends StatelessWidget {
  const SpeechBubble({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 13, 16, 13),
    this.radius = 16,
    this.tailX = 34,
    this.tailUp = true,
    this.color = PrimeColor.paper,
    this.border = PrimeColor.ink,
    this.borderWidth = 1.3,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final double tailX;
  final bool tailUp;
  final Color color;
  final Color border;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BubblePainter(
        radius: radius,
        tailX: tailX,
        tailUp: tailUp,
        color: color,
        border: border,
        borderWidth: borderWidth,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter({
    required this.radius,
    required this.tailX,
    required this.tailUp,
    required this.color,
    required this.border,
    required this.borderWidth,
  });

  final double radius;
  final double tailX;
  final bool tailUp;
  final Color color;
  final Color border;
  final double borderWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(1.5, 1.5, size.width - 3, size.height - 3);
    final body = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));

    final tail = Path();
    if (tailUp) {
      final x = tailX.clamp(18.0, rect.width - 60);
      tail
        ..moveTo(x, rect.top + 2)
        ..quadraticBezierTo(x - 8, rect.top - 10, x - 20, rect.top - 15)
        ..quadraticBezierTo(x - 4, rect.top - 6, x + 12, rect.top + 2)
        ..close();
    } else {
      final x = tailX.clamp(18.0, rect.width - 60);
      tail
        ..moveTo(x, rect.bottom - 2)
        ..quadraticBezierTo(x - 8, rect.bottom + 10, x - 20, rect.bottom + 15)
        ..quadraticBezierTo(x - 4, rect.bottom + 6, x + 12, rect.bottom - 2)
        ..close();
    }

    final shape = Path.combine(PathOperation.union, body, tail);

    canvas.drawPath(
      shape.shift(const Offset(1.6, 2.6)),
      Paint()
        ..color = const Color(0x26000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(shape, Paint()..color = color);
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..strokeJoin = StrokeJoin.round
        ..color = border,
    );
    // 内层细线，制造二次印刷的手感。
    canvas.drawPath(
      Path.combine(
        PathOperation.union,
        Path()..addRRect(RRect.fromRectAndRadius(rect.deflate(2.6), Radius.circular(radius - 2))),
        tail,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = border.withValues(alpha: 0.22),
    );
  }

  @override
  bool shouldRepaint(covariant _BubblePainter oldDelegate) => oldDelegate.color != color;
}

/// 流萤头像：圆形裁切 + 墨线环 + 小飘带。
class MascotAvatar extends StatelessWidget {
  const MascotAvatar({super.key, this.size = 36, this.showTag = false});

  final double size;
  final bool showTag;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: PrimeColor.paperDeep,
              border: Border.all(color: PrimeColor.ink, width: 1.4),
              boxShadow: const [
                BoxShadow(color: Color(0x22000000), blurRadius: 4, offset: Offset(1, 2)),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/brand/xiaoying_face.png',
                width: size,
                height: size,
                fit: BoxFit.cover,
                alignment: const Alignment(0, -0.12),
              ),
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: PrimeColor.mint,
                shape: BoxShape.circle,
                border: Border.all(color: PrimeColor.paper, width: 1.6),
              ),
            ),
          ),
          if (showTag)
            Positioned(
              left: -4,
              bottom: -14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                color: PrimeColor.ink,
                child: const Text(
                  '流萤',
                  style: TextStyle(
                    fontFamily: PrimeFont.hand,
                    fontFamilyFallback: PrimeFont.handFallback,
                    fontSize: 9,
                    color: PrimeColor.paper,
                    height: 1.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 墨线小标签（贴在取景窗角上的编号）。
class InkTag extends StatelessWidget {
  const InkTag({
    super.key,
    required this.text,
    this.fill = PrimeColor.paper,
    this.textColor = PrimeColor.ink,
    this.angle = 0,
    this.dense = false,
  });

  final String text;
  final Color fill;
  final Color textColor;
  final double angle;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 2 : 3),
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(color: PrimeColor.ink.withValues(alpha: 0.8), width: 1),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: dense ? 8.5 : 9.5,
            height: 1.25,
            letterSpacing: dense ? 1.0 : 1.6,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

/// 墨线按钮：胶囊描边，按下时填充。
class InkButton extends StatelessWidget {
  const InkButton({
    super.key,
    required this.label,
    this.onTap,
    this.filled = false,
    this.icon,
    this.height = 44,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final IconData? icon;
  final double height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final bg = filled ? PrimeColor.ink : PrimeColor.paper;
    final fg = filled ? PrimeColor.paper : PrimeColor.ink;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: height,
        width: expand ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: onTap == null ? bg.withValues(alpha: 0.6) : bg,
          borderRadius: BorderRadius.circular(height / 2),
          border: Border.all(color: PrimeColor.ink.withValues(alpha: onTap == null ? 0.4 : 0.92), width: 1.3),
          boxShadow: filled && onTap != null
              ? const [BoxShadow(color: Color(0x2617332B), blurRadius: 6, offset: Offset(1, 3))]
              : null,
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: PrimeFont.hand,
                fontFamilyFallback: PrimeFont.handFallback,
                fontSize: 16,
                height: 1.2,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 小圆形手绘按钮。
class RoundInkButton extends StatelessWidget {
  const RoundInkButton({
    super.key,
    required this.icon,
    this.size = 46,
    this.onTap,
    this.fill = PrimeColor.paper,
  });

  final IconData icon;
  final double size;
  final VoidCallback? onTap;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: Border.all(color: PrimeColor.ink.withValues(alpha: 0.85), width: 1.3),
        ),
        child: Icon(icon, size: size * 0.44, color: PrimeColor.ink),
      ),
    );
  }
}

/// 心形徽章：手册里唯一允许红色的地方。
class HeartBadge extends StatelessWidget {
  const HeartBadge({super.key, this.count = 12, this.compact = false});

  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.favorite, size: 13, color: PrimeColor.vermilion),
        const SizedBox(width: 3),
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 10,
            color: PrimeColor.inkSoft,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

/// 一格手帐刻度条：距离 / 高度 / 角度。
class MeterBar extends StatelessWidget {
  const MeterBar({
    super.key,
    required this.label,
    required this.value,
    required this.readout,
    this.active = false,
  });

  final String label;
  final double value;
  final String readout;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: PrimeFont.hand,
                fontFamilyFallback: PrimeFont.handFallback,
                fontSize: 11,
                height: 1.1,
                color: active ? PrimeColor.ink : PrimeColor.inkFaint,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const Spacer(),
            Text(
              readout,
              style: TextStyle(
                fontSize: 9,
                height: 1.1,
                color: active ? PrimeColor.ink : PrimeColor.inkFaint,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 8,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: 3,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 3,
                      color: PrimeColor.ink.withValues(alpha: 0.16),
                    ),
                  ),
                  // 刻度：25 / 50 / 75。
                  for (final p in [0.25, 0.5, 0.75])
                    Positioned(
                      left: constraints.maxWidth * p,
                      top: 0,
                      child: Container(width: 1, height: 8, color: PrimeColor.ink.withValues(alpha: 0.25)),
                    ),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => Positioned(
                      top: 2,
                      left: 0,
                      child: Container(
                        height: 4,
                        width: math.max(3, constraints.maxWidth * v),
                        decoration: BoxDecoration(
                          color: active ? PrimeColor.mintDeep : PrimeColor.mint.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
