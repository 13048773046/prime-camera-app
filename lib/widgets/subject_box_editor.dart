import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Doka `SubjectMarkerOverlayView` 的 Flutter 复刻。
///
/// 源码里可见的只有：
/// - 2.5dp 黄色四角括号；
/// - 0.8dp、`#29FFFFFF` 的极细外框；
/// - 底边中心 3dp 圆点 + 10dp 连接线 + 圆角标签；
/// - 8 个 44dp 触摸命中区（不可见），最小边长 64dp，限制在取景框 90% 内。
///
/// 这里不画完整黄色边框，也不把 8 个拖拽点画成可见方块。
class SubjectBoxEditor extends StatefulWidget {
  const SubjectBoxEditor({
    super.key,
    required this.box,
    required this.frameRect,
    required this.onChanged,
    required this.onClear,
  });

  /// 归一化 [x, y, w, h]，相对取景框。
  final List<double> box;
  final Rect frameRect;
  final ValueChanged<List<double>> onChanged;
  final VoidCallback onClear;

  @override
  State<SubjectBoxEditor> createState() => _SubjectBoxEditorState();
}

class _SubjectBoxEditorState extends State<SubjectBoxEditor> {
  late List<double> _box = List<double>.of(widget.box);
  int? _dragHandle;

  @override
  void didUpdateWidget(covariant SubjectBoxEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameBox(oldWidget.box, widget.box) && _dragHandle == null) {
      _box = List<double>.of(widget.box);
    }
  }

  bool _sameBox(List<double> a, List<double> b) {
    if (a.length != 4 || b.length != 4) return false;
    for (var i = 0; i < 4; i++) {
      if ((a[i] - b[i]).abs() > 0.0001) return false;
    }
    return true;
  }

  Rect get _rect => Rect.fromLTWH(
    widget.frameRect.left + _box[0] * widget.frameRect.width,
    widget.frameRect.top + _box[1] * widget.frameRect.height,
    _box[2] * widget.frameRect.width,
    _box[3] * widget.frameRect.height,
  );

  double get _minW => 64 / math.max(1, widget.frameRect.width);
  double get _minH => 64 / math.max(1, widget.frameRect.height);

  void _emit() => widget.onChanged(List<double>.of(_box));

  void _drag(Offset delta, {int? handle}) {
    final dx = delta.dx / widget.frameRect.width;
    final dy = delta.dy / widget.frameRect.height;
    var x = _box[0];
    var y = _box[1];
    var w = _box[2];
    var h = _box[3];

    if (handle == null) {
      x += dx;
      y += dy;
    } else {
      final left = handle == 0 || handle == 3 || handle == 7;
      final right = handle == 1 || handle == 2 || handle == 5;
      final top = handle == 0 || handle == 1 || handle == 4;
      final bottom = handle == 2 || handle == 3 || handle == 6;
      if (left) {
        final nextW = (w - dx).clamp(_minW, 1.0);
        x += w - nextW;
        w = nextW;
      } else if (right) {
        w = (w + dx).clamp(_minW, 1.0);
      }
      if (top) {
        final nextH = (h - dy).clamp(_minH, 1.0);
        y += h - nextH;
        h = nextH;
      } else if (bottom) {
        h = (h + dy).clamp(_minH, 1.0);
      }
    }

    // Doka 的边界限制：不越出取景框的 90% 区域。
    final maxX = 1.0 - w;
    final maxY = 1.0 - h;
    x = x.clamp(0.0, maxX);
    y = y.clamp(0.0, maxY);
    setState(() => _box = [x, y, w, h]);
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final rect = _rect;
    final handle = 44.0;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onClear,
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _DokaSubjectPainter(rect: rect, label: '拍照主体 · 拖动缩放'),
          ),
        ),
        Positioned(
          left: rect.left + 4,
          top: rect.top + 4,
          width: math.max(1, rect.width - 8),
          height: math.max(1, rect.height - 8),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _dragHandle = -1,
            onPanUpdate: (d) => _drag(d.delta),
            onPanEnd: (_) => _dragHandle = null,
            onPanCancel: () => _dragHandle = null,
          ),
        ),
        for (var i = 0; i < 8; i++) _handle(i, rect, handle),
      ],
    );
  }

  Widget _handle(int index, Rect rect, double size) {
    final center = switch (index) {
      0 => rect.topLeft,
      1 => rect.topRight,
      2 => rect.bottomRight,
      3 => rect.bottomLeft,
      4 => Offset(rect.center.dx, rect.top),
      5 => Offset(rect.right, rect.center.dy),
      6 => Offset(rect.center.dx, rect.bottom),
      7 => Offset(rect.left, rect.center.dy),
      _ => rect.center,
    };
    return Positioned(
      left: center.dx - size / 2,
      top: center.dy - size / 2,
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => _dragHandle = index,
        onPanUpdate: (d) => _drag(d.delta, handle: index),
        onPanEnd: (_) => _dragHandle = null,
        onPanCancel: () => _dragHandle = null,
      ),
    );
  }
}

class _DokaSubjectPainter extends CustomPainter {
  const _DokaSubjectPainter({required this.rect, required this.label});

  final Rect rect;
  final String label;

  @override
  void paint(Canvas canvas, Size size) {
    if (rect.width < 1 || rect.height < 1) return;
    final yellow = const Color(0xFFFFD76A);

    // 极细外框：Doka `#29FFFFFF` 0.8dp。
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0x29FFFFFF),
    );

    // 四角括号：18dp 长、2.5dp 粗。
    const arm = 18.0;
    final bracket = Paint()
      ..color = yellow
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.square;
    // 左上
    canvas.drawLine(rect.topLeft, rect.topLeft.translate(arm, 0), bracket);
    canvas.drawLine(rect.topLeft, rect.topLeft.translate(0, arm), bracket);
    // 右上
    canvas.drawLine(rect.topRight, rect.topRight.translate(-arm, 0), bracket);
    canvas.drawLine(rect.topRight, rect.topRight.translate(0, arm), bracket);
    // 右下
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight.translate(-arm, 0),
      bracket,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight.translate(0, -arm),
      bracket,
    );
    // 左下
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft.translate(arm, 0),
      bracket,
    );
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft.translate(0, -arm),
      bracket,
    );

    // 底边中心 3dp 圆点 + 1.5dp 连接线。
    final anchor = Offset(rect.center.dx, rect.bottom);
    canvas.drawCircle(anchor, 3, Paint()..color = yellow);
    canvas.drawLine(
      anchor,
      anchor.translate(0, 10),
      Paint()
        ..color = yellow
        ..strokeWidth = 1.5,
    );

    // 圆角标签：13sp 黑字、黄色底、最大宽 120dp。
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 104);
    final pillWidth = text.width + 18;
    final pillHeight = 24.0;
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        anchor.dx - pillWidth / 2,
        anchor.dy + 17,
        pillWidth,
        pillHeight,
      ),
      const Radius.circular(8),
    );
    canvas.drawRRect(pillRect, Paint()..color = yellow);
    text.paint(
      canvas,
      Offset(pillRect.left + 9, pillRect.top + (pillHeight - text.height) / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _DokaSubjectPainter old) =>
      old.rect != rect || old.label != label;
}
