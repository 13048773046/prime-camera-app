import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Doka `ZoomDialView` 的 Flutter 复刻。
///
/// 关键几何直接取自反编译源码：
/// - 控件高 140dp，铺满预览宽度，圆心在 `width * 0.45 + height`，半径等于控件宽度；
/// - 背景 `#4D000000`，外圈刻度 3dp 白线，红色 5dp 指针；
/// - 倍率范围 1.0–10.0，预设 [1,2,10]，角度 ±35°；
/// - 横向拖动按 `dx / (width * 0.8)` 换算角度。
///
/// PRIME 保留超广角 0.5×，因此最小值延伸为 0.5，其余视觉/手势与 Doka 一致。
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
  double _angle = 0;
  double _startAngle = 0;
  double _dragStartX = 0;

  static const double _maxAngle = 35 * math.pi / 180;
  static const List<double> _presets = [0.5, 1.0, 2.0, 5.0, 10.0];

  double _normalized(double value) =>
      math.log(value / 0.5) / math.log(10.0 / 0.5);

  double _valueFromNormalized(double n) =>
      0.5 * math.pow(10.0 / 0.5, n.clamp(0.0, 1.0));

  double _angleFor(double value) => (_normalized(value) * 2 - 1) * _maxAngle;

  double _valueForAngle(double angle) =>
      _valueFromNormalized(angle / _maxAngle * 0.5 + 0.5);

  @override
  void initState() {
    super.initState();
    _angle = _angleFor(_value);
  }

  @override
  void didUpdateWidget(covariant ZoomDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _value = widget.value.clamp(0.5, 10.0);
      _angle = _angleFor(_value);
    }
  }

  void _onTap(Offset local, double width) {
    // 点按刻度时按水平位置换算，松手吸附到最近预设。
    final normalized = (local.dx / width).clamp(0.0, 1.0);
    final raw = _valueFromNormalized(normalized);
    var snapped = _presets.first;
    var best = double.infinity;
    for (final preset in _presets) {
      final d = (math.log(preset) - math.log(raw)).abs();
      if (d < best) {
        best = d;
        snapped = preset;
      }
    }
    if (best < 0.16) {
      widget.onPreset(snapped);
      return;
    }
    widget.onChanged(raw);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _onTap(details.localPosition, width),
          onHorizontalDragStart: (details) {
            _startAngle = _angle;
            _dragStartX = details.localPosition.dx;
          },
          onHorizontalDragUpdate: (details) {
            final delta =
                (details.localPosition.dx - _dragStartX) /
                math.max(1, width * 0.8) *
                _maxAngle *
                2;
            final next = (_startAngle + delta).clamp(-_maxAngle, _maxAngle);
            final value = _valueForAngle(next);
            if (value == _value) return;
            setState(() {
              _angle = next;
              _value = value;
            });
            widget.onChanged(value);
          },
          child: CustomPaint(
            size: Size(width, 140),
            painter: _ZoomDialPainter(value: _value, angle: _angle),
          ),
        );
      },
    );
  }
}

class _ZoomDialPainter extends CustomPainter {
  const _ZoomDialPainter({required this.value, required this.angle});

  final double value;
  final double angle;

  double _normalized(double value) =>
      math.log(value / 0.5) / math.log(10.0 / 0.5);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, w * 0.45 + h);
    final radius = w;

    // Doka 的大圆背景和内部稍深一层。
    canvas.drawCircle(center, radius, Paint()..color = const Color(0x4D000000));
    canvas.drawCircle(
      center,
      radius - h * 0.35,
      Paint()..color = const Color(0x33000000),
    );

    // 当前倍率：60px（3x 屏约 20dp），白色。
    final label = _label(value);
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          height: 1,
          letterSpacing: 0.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, Offset(w / 2 - text.width / 2, h * 0.5 - 40));

    // 红色指针：5dp 宽、10dp 长，位于数值下方。
    canvas.drawLine(
      Offset(w / 2, h * 0.5),
      Offset(w / 2, h * 0.6),
      Paint()
        ..color = const Color(0xFFFF5A48)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    for (var i = 1; i <= 10; i++) {
      final v = i.toDouble();
      final a = (_normalized(v) * 2 - 1) * (35 * math.pi / 180);
      canvas.save();
      canvas.rotate(a);
      final tickH = i.isEven ? 14.0 : 9.0;
      canvas.drawLine(
        Offset(0, -radius + 7),
        Offset(0, -radius + 7 + tickH),
        Paint()
          ..color = i == 1 || i == 2 || i == 10
              ? Colors.white
              : Colors.white.withValues(alpha: 0.55)
          ..strokeWidth = 1.4,
      );
      final t = TextPainter(
        text: TextSpan(
          text: '$i',
          style: TextStyle(
            color: i == 1 || i == 2 || i == 10
                ? Colors.white
                : Colors.white.withValues(alpha: 0.55),
            fontSize: i == 1 || i == 2 || i == 10 ? 12 : 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      t.paint(canvas, Offset(-t.width / 2, -radius + 7 + tickH + 5));
      canvas.restore();
    }

    // 0.5× 超广角刻度（PRIME 扩展，不影响 Doka 的 1×–10× 主刻度）。
    final halfAngle =
        (math.log(0.5 / 0.5) / math.log(20) * 2 - 1) * (35 * math.pi / 180);
    canvas.save();
    canvas.rotate(halfAngle);
    canvas.drawLine(
      Offset(0, -radius + 7),
      Offset(0, -radius + 20),
      Paint()
        ..color = const Color(0x80FFFFFF)
        ..strokeWidth = 1.4,
    );
    final half = TextPainter(
      text: const TextSpan(
        text: '0.5',
        style: TextStyle(color: Color(0x80FFFFFF), fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    half.paint(canvas, Offset(-half.width / 2, -radius + 27));
    canvas.restore();
    canvas.restore();
  }

  String _label(double v) {
    if (v >= 9.95) return '10x';
    if (v >= 1.0) {
      final fixed = v.toStringAsFixed(1);
      return fixed.endsWith('.0')
          ? '${fixed.substring(0, fixed.length - 2)}x'
          : '${fixed}x';
    }
    return '${v.toStringAsFixed(1)}x';
  }

  @override
  bool shouldRepaint(covariant _ZoomDialPainter old) =>
      old.value != value || old.angle != angle;
}
