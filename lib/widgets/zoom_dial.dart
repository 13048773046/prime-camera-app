import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Doka `ZoomDialView` 的 Flutter 版：
/// 0.5×–10× 对数刻度、固定 1×/2×/10× 停靠点、左右 ±35° 的指针。
class ZoomDial extends StatefulWidget {
  const ZoomDial({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onPreset,
    required this.onClose,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onPreset;
  final VoidCallback onClose;

  @override
  State<ZoomDial> createState() => _ZoomDialState();
}

class _ZoomDialState extends State<ZoomDial> {
  late double _value = widget.value.clamp(0.5, 10.0);

  double _normalized(double value) =>
      math.log(value / 0.5) / math.log(10.0 / 0.5);

  double _valueFromNormalized(double n) =>
      0.5 * math.pow(10.0 / 0.5, n.clamp(0.0, 1.0));

  void _setFromDx(double dx, double width) {
    final delta = dx / width;
    final next = _valueFromNormalized(_normalized(_value) + delta * 0.85);
    _value = next.clamp(0.5, 10.0);
    widget.onChanged(_value);
  }

  @override
  Widget build(BuildContext context) {
    final angle = (_normalized(_value) * 2 - 1) * 35 * math.pi / 180;
    return GestureDetector(
      onHorizontalDragUpdate: (details) =>
          _setFromDx(details.delta.dx, 220),
      child: Container(
        width: 240,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: const Color(0xEE080A0D),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x22FFFFFF)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  '${_value.toStringAsFixed(_value < 2 ? 1 : 0)}×',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: widget.onClose,
                  child: const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: Colors.white38,
                  ),
                ),
              ],
            ),
            SizedBox(
              height: 52,
              child: CustomPaint(
                painter: _DialPainter(normalized: _normalized(_value)),
                child: Align(
                  alignment: Alignment(angle / 1.2, 0.92),
                  child: Container(
                    width: 2,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF6B6B),
                      borderRadius: BorderRadius.all(Radius.circular(2)),
                    ),
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final preset in <double>[0.5, 1, 2, 10])
                  GestureDetector(
                    onTap: () {
                      _value = preset;
                      widget.onPreset(preset);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: (widget.value - preset).abs() < 0.01
                            ? Colors.white12
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        preset == 0.5 ? '.5' : '${preset.toStringAsFixed(0)}×',
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  const _DialPainter({required this.normalized});
  final double normalized;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height + 18);
    final radius = size.height * 1.8;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..color = const Color(0x33FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawArc(rect, math.pi * 1.18, math.pi * 0.64, false, paint);
    for (var i = 0; i <= 10; i++) {
      final t = i / 10.0;
      final angle = math.pi * 1.18 + math.pi * 0.64 * t;
      final inner = Offset(
        center.dx + (radius - 6) * math.cos(angle),
        center.dy + (radius - 6) * math.sin(angle),
      );
      final outer = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      final active = (t - normalized).abs() < 0.035;
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = active ? const Color(0xFFFF6B6B) : const Color(0x44FFFFFF)
          ..strokeWidth = active ? 1.6 : 0.8,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DialPainter oldDelegate) =>
      oldDelegate.normalized != normalized;
}
