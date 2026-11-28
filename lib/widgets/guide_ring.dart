import 'package:flutter/material.dart';

import 'doka_ai_overlay.dart';

/// AI 构图映射层。
///
/// Doka 1.3.20 的取景层里没有“8 点主体框常驻 + 星点 + 虚线圆环 + 内部裁切框”
/// 这一套自定义 UI。实际显示的是：
/// - `scanAnimationView`：分析期沿取景框呼吸的 Lottie 粒子；
/// - `CameraMappingView`：固定 `ic_sight` 瞄准点、目标环、虚线连接；
/// - 对齐后仅由 `previewGlowBorder` 给整个 3:4 预览描六色渐变边。
///
/// 主体框只在用户手动指定主体时由 `SubjectBoxEditor` 单独绘制，
/// 因此这里不再接收/绘制 subjectBox。
class GuideOverlay extends StatelessWidget {
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
    this.showMapping = true,
  });

  final List<double> subjectBox;
  final List<double> targetBox;
  final List<double>? alignedBox;
  final bool aligned;
  final bool analyzing;
  final bool showGrid;
  final double confidence;
  final Rect? frameRect;
  final String subjectLabel;
  final bool showMapping;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DokaScanOverlay(active: analyzing),
        if (showMapping)
          DokaMappingOverlay(
            targetBox: targetBox,
            aligned: aligned,
            analyzing: false,
            progress: confidence,
            frameRect: frameRect,
            originBox: subjectBox.length == 4 ? subjectBox : null,
            showGrid: showGrid,
          ),
      ],
    );
  }
}
