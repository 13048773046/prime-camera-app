import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

class GuideRing extends StatelessWidget {
  const GuideRing({
    super.key,
    required this.targetBox,
    required this.aligned,
  });

  final List<double> targetBox;
  final bool aligned;

  @override
  Widget build(BuildContext context) {
    if (targetBox.length != 4) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final x = targetBox[0] * constraints.maxWidth;
        final y = targetBox[1] * constraints.maxHeight;
        final w = targetBox[2] * constraints.maxWidth;
        final h = targetBox[3] * constraints.maxHeight;
        return Stack(
          children: [
            Positioned(
              left: x,
              top: y,
              width: w,
              height: h,
              child: CustomPaint(painter: _RingPainter(aligned: aligned)),
            ),
          ],
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.aligned});

  final bool aligned;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = aligned ? PrimeTokens.mint : PrimeTokens.amber;

    final arc1 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = PrimeTokens.deepGreen;
    final arc2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = PrimeTokens.red;

    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(28)), paint);
    canvas.drawArc(rect, math.pi * 0.15, math.pi * 0.55, false, arc1);
    canvas.drawArc(rect, math.pi * 1.15, math.pi * 0.55, false, arc2);

    final center = Offset(size.width / 2, size.height / 2);
    final core = Paint()..color = aligned ? PrimeTokens.mint : PrimeTokens.amber;
    canvas.drawCircle(center, 10, core);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => oldDelegate.aligned != aligned;
}
