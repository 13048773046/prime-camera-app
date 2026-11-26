import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// 胶片条：焦段切换器的外壳。
/// 上下两排片孔 + 四格片框，当前焦段像被墨色填满的一格胶片。
class FilmStripSelector extends StatelessWidget {
  const FilmStripSelector({
    super.key,
    required this.labels,
    required this.captions,
    required this.activeIndex,
    required this.onSelect,
  });

  final List<String> labels;
  final List<String> captions;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 74,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _FilmStripPainter(
                    count: labels.length,
                    activeIndex: activeIndex,
                  ),
                ),
              ),
              Row(
                children: [
                  for (int i = 0; i < labels.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelect(i),
                        child: SizedBox(
                          height: 60,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                labels[i],
                                style: TextStyle(
                                  fontSize: 15,
                                  height: 1.1,
                                  letterSpacing: 0.4,
                                  fontWeight: FontWeight.w700,
                                  color: i == activeIndex ? PrimeColor.paper : PrimeColor.ink,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                captions[i],
                                style: TextStyle(
                                  fontFamily: PrimeFont.hand,
                                  fontFamilyFallback: PrimeFont.handFallback,
                                  fontSize: 9.5,
                                  height: 1.1,
                                  color: i == activeIndex
                                      ? PrimeColor.paper.withValues(alpha: 0.72)
                                      : PrimeColor.inkFaint,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilmStripPainter extends CustomPainter {
  _FilmStripPainter({required this.count, required this.activeIndex});

  final int count;
  final int activeIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, 60);
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(3));

    canvas.drawRRect(
      rr,
      Paint()..color = const Color(0xFFF4ECDC),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = PrimeColor.ink.withValues(alpha: 0.9),
    );

    // 片孔。
    final hole = Paint()..color = PrimeColor.paper;
    final holeEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = PrimeColor.ink.withValues(alpha: 0.5);
    const holeW = 7.0;
    const holeH = 4.4;
    for (double x = 6; x < size.width - 6; x += 13) {
      for (final y in [2.2, 53.4]) {
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, holeW, holeH), const Radius.circular(1.2));
        canvas.drawRRect(r, hole);
        canvas.drawRRect(r, holeEdge);
      }
    }

    final cellW = size.width / count;
    for (int i = 0; i < count; i++) {
      final cell = Rect.fromLTWH(i * cellW, 9.5, cellW, 41);
      if (i == activeIndex) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(cell.deflate(2), const Radius.circular(2)),
          Paint()..color = PrimeColor.ink,
        );
        // 墨色里透出的一点薄荷高光。
        canvas.drawLine(
          Offset(cell.left + 6, cell.bottom - 6),
          Offset(cell.right - 6, cell.bottom - 6),
          Paint()..color = PrimeColor.mint.withValues(alpha: 0.5)..strokeWidth = 1,
        );
      } else {
        final dashed = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = PrimeColor.ink.withValues(alpha: 0.35);
        for (double y = cell.top; y < cell.bottom; y += 5) {
          canvas.drawLine(Offset(cell.left, y), Offset(cell.left, math.min(y + 2.6, cell.bottom)), dashed);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FilmStripPainter oldDelegate) =>
      oldDelegate.activeIndex != activeIndex;
}
