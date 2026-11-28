import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Doka 1.3.20 的 AI 构图视觉层。
///
/// 这里的尺寸、颜色、圆角和时长全部来自反编译源码：
/// - `GradientBorderView`：24dp 圆角、1dp 描边、15dp 辉光、6 色渐变、500ms 呼吸。
/// - `CameraMappingView`：30dp 瞄准点、目标环、连接线和对齐进度。
/// - `bg_translucent_panel` / `bg_ai_compose_glass` / `bg_ai_compose_cta`：
///   AI HUD、扫描动作胶囊和方案切换 CTA。
const dokaAiColors = <Color>[
  Color(0xFFFFFFFF),
  Color(0xFFE8FFFC),
  Color(0xFF80EEFF),
  Color(0xFFB1CFFF),
  Color(0xFFFFD2F6),
  Color(0xFFFFC38F),
];

const dokaMappingColors = <Color>[
  Color(0xFFB8F0E0),
  Color(0xFF4FD4E8),
  Color(0xFF7AA8E8),
  Color(0xFFE89ED8),
  Color(0xFFE8A070),
];

/// 全屏预览外圈的 Doka 渐变辉光。控件本身比预览大 36dp，
/// 预览内容由上层 `ClipRRect` 盖住，只留下外圈辉光。
class DokaGradientHalo extends StatefulWidget {
  const DokaGradientHalo({
    super.key,
    required this.visible,
    this.inset = 18,
    this.radius = 24,
  });

  final bool visible;
  final double inset;
  final double radius;

  @override
  State<DokaGradientHalo> createState() => _DokaGradientHaloState();
}

class _DokaGradientHaloState extends State<DokaGradientHalo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _breath,
        builder: (context, _) => CustomPaint(
          painter: _DokaHaloPainter(
            progress: Curves.easeInOut.transform(_breath.value),
            inset: widget.inset,
            radius: widget.radius,
          ),
        ),
      ),
    );
  }
}

class _DokaHaloPainter extends CustomPainter {
  const _DokaHaloPainter({
    required this.progress,
    required this.inset,
    required this.radius,
  });

  final double progress;
  final double inset;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );
    if (rect.width <= 2 || rect.height <= 2) return;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final alpha = 0.4 + 0.6 * progress;
    final shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: dokaAiColors
          .map((color) => color.withValues(alpha: alpha))
          .toList(growable: false),
      stops: const [0, 0.06, 0.27, 0.6, 0.76, 1],
    ).createShader(rect);

    // 15dp 模糊辉光 + 1dp 实线，对应 Doka 的 BlurMaskFilter 双层。
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 15
        ..shader = shader
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant _DokaHaloPainter old) =>
      old.progress != progress || old.inset != inset || old.radius != radius;
}

/// Doka `CameraMappingView` 的显示层：固定瞄准点 + 目标环 + 虚线连接。
/// 只画“该往哪移”，不把主体框画成黄色方块。
class DokaMappingOverlay extends StatefulWidget {
  const DokaMappingOverlay({
    super.key,
    required this.targetBox,
    required this.aligned,
    required this.analyzing,
    required this.progress,
    this.frameRect,
    this.originBox,
    this.showGrid = false,
  });

  final List<double> targetBox;
  final bool aligned;
  final bool analyzing;
  final double progress;
  final Rect? frameRect;

  /// 当前主体框（预览归一化坐标）；连接线从主体中心指向目标环中心，
  /// 对齐 Doka `CameraMappingView` 的“当前位置 → 目标位置”表达。
  final List<double>? originBox;
  final bool showGrid;

  @override
  State<DokaMappingOverlay> createState() => _DokaMappingOverlayState();
}

class _DokaMappingOverlayState extends State<DokaMappingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _spin,
        builder: (context, _) => CustomPaint(
          painter: _DokaMappingPainter(
            targetBox: widget.targetBox,
            aligned: widget.aligned,
            analyzing: widget.analyzing,
            progress: widget.progress,
            frameRect: widget.frameRect,
            originBox: widget.originBox,
            showGrid: widget.showGrid,
            spin: _spin.value,
          ),
        ),
      ),
    );
  }
}

class _DokaMappingPainter extends CustomPainter {
  const _DokaMappingPainter({
    required this.targetBox,
    required this.aligned,
    required this.analyzing,
    required this.progress,
    required this.frameRect,
    required this.originBox,
    required this.showGrid,
    required this.spin,
  });

  final List<double> targetBox;
  final bool aligned;
  final bool analyzing;
  final double progress;
  final Rect? frameRect;
  final List<double>? originBox;
  final bool showGrid;
  final double spin;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = frameRect ?? (Offset.zero & size);
    if (showGrid) {
      final grid = Paint()
        ..color = Colors.white.withValues(alpha: 0.06)
        ..strokeWidth = 0.7;
      for (var i = 1; i <= 2; i++) {
        final x = frame.left + frame.width * i / 3;
        final y = frame.top + frame.height * i / 3;
        canvas.drawLine(Offset(x, frame.top), Offset(x, frame.bottom), grid);
        canvas.drawLine(Offset(frame.left, y), Offset(frame.right, y), grid);
      }
    }
    if (aligned) return;

    var origin = frame.center;
    final originBox = this.originBox;
    if (originBox != null && originBox.length == 4) {
      origin = Offset(
        frame.left + (originBox[0] + originBox[2] / 2) * frame.width,
        frame.top + (originBox[1] + originBox[3] / 2) * frame.height,
      );
    }

    Rect? target;
    if (targetBox.length == 4) {
      target = Rect.fromLTWH(
        frame.left + targetBox[0] * frame.width,
        frame.top + targetBox[1] * frame.height,
        targetBox[2] * frame.width,
        targetBox[3] * frame.height,
      );
    }
    if (target == null) return;
    final targetCenter = Offset(
      target.center.dx.clamp(frame.left + 34, frame.right - 34),
      target.center.dy.clamp(frame.top + 34, frame.bottom - 34),
    );
    _paintConnector(canvas, origin, targetCenter);
    _paintTarget(canvas, targetCenter, analyzing);
  }

  void _paintTarget(Canvas canvas, Offset c, bool pulse) {
    final radius = 24.0 + (pulse ? math.sin(spin * math.pi * 2) * 1.2 : 0);
    canvas.drawCircle(
      c,
      radius + 3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = dokaMappingColors[1].withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = Colors.white.withValues(alpha: 0.95),
    );
    // 五色弧段，绕目标环缓慢旋转，替代当前实现里的星点。
    final shader = SweepGradient(
      colors: [
        dokaMappingColors[0].withValues(alpha: 0.0),
        ...dokaMappingColors,
        dokaMappingColors.last.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.06, 0.2, 0.36, 0.54, 0.72, 1.0],
      transform: GradientRotation(spin * math.pi * 2),
    ).createShader(Rect.fromCircle(center: c, radius: radius + 2));
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: radius + 1.2),
      0,
      math.pi * 1.85,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
  }

  void _paintConnector(Canvas canvas, Offset from, Offset to) {
    // 起点是当前主体的白色圆点，和 Doka 截图里的 14dp 白点一致。
    canvas.drawCircle(from, 7, Paint()..color = Colors.white);
    canvas.drawCircle(
      from,
      7,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    final delta = to - from;
    final distance = delta.distance;
    if (distance < 26) return;
    final unit = delta / distance;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..strokeWidth = 1.4;
    for (double d = 18; d < distance - 18; d += 12) {
      final p1 = from + unit * d;
      final p2 = from + unit * math.min(d + 5, distance - 18);
      canvas.drawLine(p1, p2, paint);
    }
    // 进度小圆点：对齐进度越高，白点越靠近目标环。
    final dotT = progress.clamp(0.0, 1.0);
    final dot = Offset.lerp(from, to, dotT)!;
    canvas.drawCircle(dot, 3.2, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _DokaMappingPainter old) =>
      old.spin != spin ||
      old.aligned != aligned ||
      old.analyzing != analyzing ||
      old.progress != progress ||
      old.targetBox != targetBox ||
      old.originBox != originBox ||
      old.frameRect != frameRect;
}

/// Doka `scanAnimationView` 的近似实现：沿预览边框呼吸的白色粒子 +
/// 缓慢绕行的高光弧。原版是 267 帧 Lottie，节奏同为 2.67s 循环。
class DokaScanOverlay extends StatefulWidget {
  const DokaScanOverlay({super.key, required this.active});

  final bool active;

  @override
  State<DokaScanOverlay> createState() => _DokaScanOverlayState();
}

class _DokaScanOverlayState extends State<DokaScanOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2670),
  )..repeat();

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    return IgnorePointer(child: CustomPaint(painter: _DokaScanPainter(_scan)));
  }
}

class _DokaScanPainter extends CustomPainter {
  _DokaScanPainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    const count = 26;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      const Radius.circular(24),
    );
    final metric = (Path()..addRRect(rrect)).computeMetrics().first;
    for (var i = 0; i < count; i++) {
      final distance = metric.length * (i / count + t * 0.12) % metric.length;
      final pos = metric.getTangentForOffset(distance)?.position;
      if (pos == null) continue;
      final pulse = 0.5 + 0.5 * math.sin(t * math.pi * 2 + i * 1.7);
      canvas.drawCircle(
        pos,
        1.2 + pulse * 1.6,
        Paint()..color = Colors.white.withValues(alpha: 0.10 + pulse * 0.34),
      );
    }
    final shader = SweepGradient(
      colors: [
        Colors.white.withValues(alpha: 0),
        dokaMappingColors[1].withValues(alpha: 0.55),
        dokaMappingColors[3].withValues(alpha: 0.55),
        Colors.white.withValues(alpha: 0),
      ],
      transform: GradientRotation(t * math.pi * 2),
    ).createShader(Offset.zero & size);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant _DokaScanPainter old) => false;
}

/// Doka `bg_translucent_panel`：20dp 圆角、1dp 六色渐变描边、#B3000000 内底。
class DokaAiHud extends StatelessWidget {
  const DokaAiHud({
    super.key,
    required this.title,
    this.subtitle,
    this.width,
    this.alignment = Alignment.center,
    this.showSparkle = true,
  });

  final String title;
  final String? subtitle;
  final double? width;
  final Alignment alignment;
  final bool showSparkle;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: _DokaPanel(
        width: width,
        maxWidth: 280,
        radius: 20,
        inner: const Color(0xB3000000),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showSparkle) ...[
                  const Icon(
                    Icons.auto_awesome,
                    size: 14,
                    color: Color(0xFFB8F0E0),
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFFD76A),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Doka `tvAiFilterTip`：280dp 宽、20/12 内边距、两行 14sp。
class DokaAiFilterTip extends StatelessWidget {
  const DokaAiFilterTip({super.key, required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return _DokaPanel(
      width: 280,
      radius: 20,
      inner: const Color(0xB3000000),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < lines.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
              child: Text(
                lines[i],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: i == 0 ? Colors.white : const Color(0xFFFFD76A),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Doka `tvSubjectSelectionHint`：28dp 圆角渐变胶囊。
class DokaSubjectHint extends StatelessWidget {
  const DokaSubjectHint({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return _DokaPanel(
      maxWidth: 280,
      radius: 28,
      inner: const Color(0xD012161C),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13,
          height: 1.35,
          color: Color(0xF7FFFFFF),
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

/// Doka `bg_ai_compose_glass`：44dp 高，22dp 圆角，深色玻璃 + 顶部高光。
class DokaScanAction extends StatelessWidget {
  const DokaScanAction({
    super.key,
    required this.text,
    required this.icon,
    this.busy = false,
    this.onTap,
  });

  final String text;
  final Widget icon;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 44,
        child: _DokaPanel(
          radius: 22,
          inner: const Color(0xE012161C),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                )
              else
                icon,
              const SizedBox(width: 6),
              Text(
                text,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Doka `tvAiSwitchPlan`：40dp 高，底部居中，六色渐变玻璃 CTA。
class DokaSwitchPlanCta extends StatelessWidget {
  const DokaSwitchPlanCta({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 40,
        child: _DokaPanel(
          radius: 20,
          inner: const Color(0xE012161C),
          padding: const EdgeInsets.only(left: 8, right: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.keyboard_return_rounded,
                size: 18,
                color: Color(0xFFFFD2F6),
              ),
              const SizedBox(width: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 与 Doka layer-list 一致：外层 1dp 六色渐变，内层深色玻璃。
class _DokaPanel extends StatelessWidget {
  const _DokaPanel({
    required this.radius,
    required this.inner,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.width,
    this.maxWidth,
  });

  final double radius;
  final Color inner;
  final Widget child;
  final EdgeInsets padding;
  final double? width;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final radiusValue = BorderRadius.circular(radius);
    return Container(
      width: width,
      constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        borderRadius: radiusValue,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dokaAiColors.sublist(1),
          stops: const [0, 0.25, 0.55, 0.75, 1],
        ),
      ),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: inner,
          borderRadius: BorderRadius.circular(radius - 1),
        ),
        child: child,
      ),
    );
  }
}

/// Doka 系统 Toast 的轻量复刻：底部居中的黑色半透明胶囊，14sp 白字。
class DokaToast extends StatelessWidget {
  const DokaToast({super.key, required this.text, this.subtitle});

  final String text;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xD90A0A0A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x1FFFFFFF), width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.25,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xB3FFFFFF),
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
