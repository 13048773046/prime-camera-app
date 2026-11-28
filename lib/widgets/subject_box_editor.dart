import 'package:flutter/material.dart';

/// Doka `SubjectMarkerOverlayView` 的可拖拽版本：
/// 黄色主体框 + 8 个角点/边点，支持整体移动与八向缩放。
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
    if (oldWidget.box != widget.box && _dragHandle == null) {
      _box = List<double>.of(widget.box);
    }
  }

  Rect get _rect => Rect.fromLTWH(
    widget.frameRect.left + _box[0] * widget.frameRect.width,
    widget.frameRect.top + _box[1] * widget.frameRect.height,
    _box[2] * widget.frameRect.width,
    _box[3] * widget.frameRect.height,
  );

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
      final left = handle == 0 || handle == 3 || handle == 6;
      final right = handle == 2 || handle == 5 || handle == 8;
      final top = handle == 0 || handle == 1 || handle == 2;
      final bottom = handle == 6 || handle == 7 || handle == 8;
      if (left) {
        x += dx;
        w -= dx;
      } else if (right) {
        w += dx;
      }
      if (top) {
        y += dy;
        h -= dy;
      } else if (bottom) {
        h += dy;
      }
    }
    w = w.clamp(0.08, 1.0);
    h = h.clamp(0.08, 1.0);
    x = x.clamp(0.0, 1.0 - w);
    y = y.clamp(0.0, 1.0 - h);
    setState(() => _box = [x, y, w, h]);
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final rect = _rect;
    return Stack(
      children: [
        Positioned(
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          child: GestureDetector(
            onPanStart: (_) => _dragHandle = -1,
            onPanUpdate: (d) => _drag(d.delta),
            onPanEnd: (_) => _dragHandle = null,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xFFFFD76A),
                  width: 2.5,
                ),
                color: const Color(0x0AFFD76A),
              ),
              child: const Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    '拍照主体 · 拖动缩放',
                    style: TextStyle(
                      fontSize: 9,
                      color: Color(0xFFFFD76A),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        for (var i = 0; i < 8; i++)
          _handle(i, rect),
        Positioned(
          right: rect.right - 30,
          top: rect.top - 28,
          child: GestureDetector(
            onTap: widget.onClear,
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 14,
                color: Colors.white70,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _handle(int index, Rect rect) {
    final xs = [rect.left, rect.center.dx, rect.right];
    final ys = [rect.top, rect.center.dy, rect.bottom];
    final x = xs[index % 3] - 11;
    final y = ys[index ~/ 3] - 11;
    return Positioned(
      left: x,
      top: y,
      child: GestureDetector(
        onPanStart: (_) => _dragHandle = index,
        onPanUpdate: (d) => _drag(d.delta, handle: index),
        onPanEnd: (_) => _dragHandle = null,
        child: SizedBox(
          width: 22,
          height: 22,
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD76A),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: Colors.black, width: 0.8),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
