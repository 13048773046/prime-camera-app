import 'dart:math' as math;

import 'compose_api.dart';

/// 拍摄场景。通用保留给人像以外的一切画面；街景单独用三分/水平线规则。
enum SceneMode { general, portrait, landscape, street, still }

extension SceneModeX on SceneMode {
  String get label => switch (this) {
    SceneMode.general => '通用',
    SceneMode.portrait => '人像',
    SceneMode.landscape => '风景',
    SceneMode.street => '街景',
    SceneMode.still => '静物',
  };

  String get analyzingText => switch (this) {
    SceneMode.general => '正在读取画面构图',
    SceneMode.portrait => '正在进行人像构图分析',
    SceneMode.landscape => '正在分析风景层次',
    SceneMode.street => '正在分析街景线条',
    SceneMode.still => '正在分析静物主体',
  };

  String get settingText => switch (this) {
    SceneMode.general => '通用构图 · 3:4',
    SceneMode.portrait => '人像构图 · 3:4',
    SceneMode.landscape => '风景 · 三分层次 · 3:4',
    SceneMode.street => '街景 · 右三分 · 3:4',
    SceneMode.still => '静物 · 中心构图 · 3:4',
  };

  /// 没有识别结果时也要先把目标环画出来，用户才知道该往哪挪。
  List<double> get defaultTargetBox => switch (this) {
    SceneMode.general => const [0.34, 0.27, 0.32, 0.32],
    SceneMode.portrait => const [0.30, 0.15, 0.40, 0.40],
    SceneMode.landscape => const [0.34, 0.27, 0.32, 0.32],
    SceneMode.street => const [0.54, 0.22, 0.24, 0.24],
    SceneMode.still => const [0.34, 0.27, 0.32, 0.32],
  };
}

/// 原生相机每帧推上来的识别结果。
/// 坐标已映射到完整 9:16 取景画幅；页面按全屏 cover 的可见矩形再映射一次。
class GuidanceFrame {
  const GuidanceFrame({
    required this.roll,
    required this.pitch,
    required this.frameW,
    required this.frameH,
    required this.hfov,
    required this.ts,
    this.box,
    this.face,
    this.saliency,
    this.action,
    this.actionConfidence = 0,
  });

  final double roll;
  final double pitch;
  final int frameW;
  final int frameH;
  final double hfov;
  final int ts;
  final List<double>? box;
  final List<double>? face;

  /// 非人像场景的显著主体（建筑、树、招牌、静物等）。
  final List<double>? saliency;

  /// 原生 Vision 人体姿态识别出的动作：standing/walking/arms_up/...
  final String? action;
  final double actionConfidence;

  bool get hasSubject => box != null && box!.length == 4;

  String? get actionLabel {
    if (action == null || action!.isEmpty || actionConfidence < 0.22) {
      return null;
    }
    return switch (action) {
      'standing' => '站立',
      'walking' => '行走',
      'arms_up' => '举手',
      'hands_on_hips' => '叉腰',
      'sitting' => '坐姿',
      'leaning' => '倾斜',
      'crouching' => '蹲姿',
      _ => null,
    };
  }

  factory GuidanceFrame.fromMap(Map<String, dynamic> map) {
    List<double>? rect(dynamic value) {
      if (value is! List || value.length != 4) return null;
      final out = value.map((e) => (e as num).toDouble()).toList();
      return out;
    }

    return GuidanceFrame(
      roll: (map['roll'] as num? ?? 0).toDouble(),
      pitch: (map['pitch'] as num? ?? 0).toDouble(),
      frameW: (map['frameW'] as num? ?? 1080).toInt(),
      frameH: (map['frameH'] as num? ?? 1920).toInt(),
      hfov: (map['hfov'] as num? ?? 60).toDouble(),
      ts: (map['ts'] as num? ?? 0).toInt(),
      box: rect(map['box']),
      face: rect(map['face']),
      saliency: rect(map['saliency']),
      action: map['action']?.toString(),
      actionConfidence: (map['actionConfidence'] as num? ?? 0).toDouble(),
    );
  }
}

/// 把实时识别结果翻译成“一句口令”，规则沿用手册：
/// 优先级 距离 > 高度 > 角度 > 焦段；只提示当下最该做的一件事。
class LiveComposer {
  const LiveComposer();

  ComposeResult compose(
    GuidanceFrame frame, {
    required double zoom,
    SceneMode mode = SceneMode.portrait,
    double targetCenterX = 0.5,
    double targetCenterY = 0.42,
    double targetHeight = 0.58,
    double recommendedDistance = 0,
  }) {
    if (mode == SceneMode.portrait) {
      return _composePortrait(
        frame,
        zoom,
        targetCenterX: targetCenterX,
        targetCenterY: targetCenterY,
        targetHeight: targetHeight,
        planDistance: recommendedDistance,
      );
    }
    return _composeScene(
      frame,
      zoom: zoom,
      mode: mode,
      targetCenterX: targetCenterX,
      targetCenterY: targetCenterY,
      targetHeight: targetHeight,
    );
  }

  /// 把“主体放在哪”变成真实目标框：中心、右三分、左三分都由计划决定，
  /// 宽度按主体的真实长宽比推出来，不再所有场景都用同一个居中大框。
  List<double> _targetBox({
    required List<double>? subjectBox,
    required double centerX,
    required double centerY,
    required double height,
    double fallbackAspect = 0.75,
  }) {
    // 成片始终是一个 3:4 画幅，渐变框也要按 3:4 画；不能再跟着
    // 人物自身的长宽比走，否则会收成一条很窄的竖条，看起来不像取景框。
    final aspect = fallbackAspect;
    final h = height.clamp(0.18, 0.78);
    final w = (h * aspect).clamp(0.16, 0.64);
    final x = (centerX - w / 2).clamp(0.035, 1 - w - 0.035);
    final y = (centerY - h / 2).clamp(0.035, 1 - h - 0.035);
    return [x, y, w, h];
  }

  ComposeResult _composePortrait(
    GuidanceFrame frame,
    double zoom, {
    required double targetCenterX,
    required double targetCenterY,
    required double targetHeight,
    required double planDistance,
  }) {
    final face = frame.face;
    final roll = frame.roll;
    // 框必须贴着真实主体：有人体框就用人体框；只有脸时就用脸框，
    // 不再把一张脸硬扩成 3.2×/3.8× 的假“身体框”。
    final box = frame.box ?? ((face != null && face.length == 4) ? face : null);

    if (box == null || box.length != 4) {
      return ComposeResult(
        subject: 'person',
        subjectBox: const [],
        targetBox: _targetBox(
          subjectBox: null,
          centerX: targetCenterX,
          centerY: targetCenterY,
          height: targetHeight,
        ),
        targetZoom: zoom,
        horizonFix: roll,
        hint: '把人物放进取景框',
        reasons: const ['还没有找到主体', '先让人物完整入镜'],
        confidence: 0,
        source: 'vision',
        actionLabel: '找主体',
        distanceMeters: null,
        recommendedDistance: planDistance > 0 ? planDistance : null,
        progress: 0.12,
      );
    }

    // 有身体框时用身体高度判断距离；只有脸时，用脸高反推一个稳定的
    // “等效身体高度”，避免同一张脸在全身/半身计划里来回跳。
    final hasFace = face != null && face.length == 4;
    final hasBody = frame.box != null && frame.box!.length == 4;
    final metricH = hasBody
        ? box[3]
        : (hasFace ? (face[3] * 3.2).clamp(0.18, 0.78) : box[3]);
    final metricTop = hasBody
        ? box[1]
        : (hasFace ? (face[1] - face[3] * 0.45).clamp(0.0, 1.0) : box[1]);
    final targetH = targetHeight.clamp(0.18, 0.78);
    final farLimit = targetH * 0.86;
    final nearLimit = targetH * 1.14;
    final distance = hasFace ? _estimateDistance(frame, face[2]) : null;
    final recommended = planDistance > 0
        ? planDistance
        : (distance == null
              ? null
              : (distance * metricH / targetH).clamp(0.6, 5.0));

    String hint;
    List<String> reasons;
    String action;
    bool aligned = false;
    final placement = targetCenterX < 0.45
        ? '左三分'
        : (targetCenterX > 0.58 ? '右三分' : '中间');

    if (metricH < farLimit) {
      hint = recommended == null
          ? '再靠近一点，让人物大一点'
          : '再靠近半步，站到约 ${recommended.toStringAsFixed(1)} 米';
      reasons = const ['人物在画面里偏小', '环境占得太多'];
      final delta = (distance != null && recommended != null)
          ? (distance - recommended).abs()
          : null;
      action = delta == null || delta < 0.2
          ? '走近'
          : '再近\n${delta.toStringAsFixed(1)}m';
    } else if (metricH > nearLimit) {
      hint = recommended == null
          ? '再退半步，给头顶留点空间'
          : '再退半步，退到约 ${recommended.toStringAsFixed(1)} 米';
      reasons = const ['人物有点太满', '边缘容易切到'];
      final delta = (distance != null && recommended != null)
          ? (distance - recommended).abs()
          : null;
      action = delta == null || delta < 0.2
          ? '退后'
          : '再退\n${delta.toStringAsFixed(1)}m';
    } else if (metricTop > 0.22) {
      hint = '镜头降到胸口';
      reasons = const ['头顶留白偏多', '机位稍微高了'];
      action = '降机位';
    } else if (metricTop < 0.035) {
      hint = '镜头抬高一点，给发梢留白';
      reasons = const ['头顶快贴边了', '给发梢留点白'];
      action = '抬机位';
    } else if ((box[0] + box[2] / 2 - targetCenterX).abs() > 0.10) {
      final toLeft = box[0] + box[2] / 2 < targetCenterX;
      hint = toLeft ? '手机往左带，把人物放到$placement' : '手机往右带，把人物放到$placement';
      reasons = ['现在还没落在$placement', '跟着黄色主体框微移'];
      action = toLeft ? '左移' : '右移';
    } else if (roll.abs() > 2.0) {
      hint = '手机回正，看住水平线';
      reasons = ['地平线有点歪', '慢慢转正手机'];
      action = '回正\n${roll.abs().toStringAsFixed(0)}°';
    } else if (roll.abs() > 1.2) {
      hint = '就快正了，再回一点点';
      reasons = const ['水平差一点', '稳住这一下'];
      action = '微调';
    } else {
      aligned = true;
      hint = '可以拍了，稳住呼吸';
      reasons = ['距离合适', '人物在$placement，机位水平'];
      action = '已对齐';
    }

    final progress = aligned
        ? 1.0
        : (0.15 +
                  0.85 *
                      (0.52 *
                              _near(
                                metricH,
                                targetH,
                                (nearLimit - farLimit) * 0.60,
                              ) +
                          0.20 *
                              _near(box[0] + box[2] / 2, targetCenterX, 0.18) +
                          0.08 * _near(metricTop, 0.12, 0.14) +
                          0.20 * _near(roll, 0, 3.0)))
              .clamp(0.15, 0.96);

    return ComposeResult(
      subject: hasBody ? 'person' : 'face',
      subjectBox: box,
      targetBox: _targetBox(
        subjectBox: box,
        centerX: targetCenterX,
        centerY: targetCenterY,
        height: targetH,
      ),
      targetZoom: zoom,
      horizonFix: roll,
      hint: hint,
      reasons: reasons,
      confidence: hasFace ? 0.9 : 0.72,
      source: 'vision',
      actionLabel: action,
      progress: progress,
      distanceMeters: distance,
      recommendedDistance: recommended,
      nearDistance: recommended == null
          ? null
          : math.max(0.4, recommended - 0.45),
      farDistance: recommended == null ? null : recommended + 0.75,
    );
  }

  /// 通用/街景不依赖人脸：优先使用 Vision 的显著区域。
  ComposeResult _composeScene(
    GuidanceFrame frame, {
    required double zoom,
    required SceneMode mode,
    required double targetCenterX,
    required double targetCenterY,
    required double targetHeight,
  }) {
    final box = frame.saliency ?? frame.box;
    final roll = frame.roll;
    final isStreet = mode == SceneMode.street;
    final targetBox = _targetBox(
      subjectBox: box,
      centerX: targetCenterX,
      centerY: targetCenterY,
      height: targetHeight,
    );
    final targetCx = targetBox[0] + targetBox[2] / 2;
    final targetCy = targetBox[1] + targetBox[3] / 2;

    if (box == null || box.length != 4) {
      return ComposeResult(
        subject: 'scene',
        subjectBox: const [],
        targetBox: targetBox,
        targetZoom: zoom,
        horizonFix: roll,
        hint: isStreet ? '找街道消失点，放进右边瞄准环' : '把画面重点放进中心环',
        reasons: isStreet
            ? const ['还没有找到街道重点', '先找消失点或最亮的地方']
            : const ['还没有找到画面重点', '先找主体或最亮的地方'],
        confidence: 0,
        source: 'vision',
        actionLabel: '找重点',
        distanceMeters: null,
        progress: 0.12,
      );
    }

    final cx = box[0] + box[2] / 2;
    final cy = box[1] + box[3] / 2;
    String hint;
    List<String> reasons;
    String action;
    bool aligned = false;

    if (roll.abs() > 2.0) {
      hint = '手机回正，让街道线保持水平';
      reasons = ['地平线有点歪', '先把手机转正'];
      action = '回正\n${roll.abs().toStringAsFixed(0)}°';
    } else if (isStreet && cx < 0.50) {
      hint = '手机往右带，把消失点放进右环';
      reasons = const ['街道重点还没到右三分', '沿着街道方向微移'];
      action = '右移';
    } else if (isStreet && cx > 0.84) {
      hint = '手机往左带，给街道留一点前景';
      reasons = const ['重点太靠右', '左侧需要街道环境'];
      action = '左移';
    } else if (!isStreet && cx < 0.32) {
      hint = '手机往左带，把重点移进中心环';
      reasons = const ['画面重点偏右', '向中心微移'];
      action = '左移';
    } else if (!isStreet && cx > 0.68) {
      hint = '手机往右带，把重点移进中心环';
      reasons = const ['画面重点偏左', '向中心微移'];
      action = '右移';
    } else if (box[1] > (isStreet ? 0.50 : 0.58)) {
      hint = '镜头抬高一点，多收一点环境';
      reasons = const ['主体偏低', '上方环境占比不够'];
      action = '抬机位';
    } else if (box[3] < 0.18) {
      hint = '再走近一点，让重点更清楚';
      reasons = const ['画面重点偏小', '环境占得有点多'];
      action = '走近';
    } else if (roll.abs() > 1.2) {
      hint = '就快正了，再回一点点';
      reasons = const ['水平差一点', '稳住这一下'];
      action = '微调';
    } else {
      aligned = true;
      hint = isStreet ? '可以拍了，等一束光' : '可以拍了，画面稳了';
      reasons = isStreet
          ? const ['消失点在右三分', '街道线已水平']
          : const ['重点在画面中心', '机位水平'];
      action = '已对齐';
    }

    final centerScore = _near(cx, targetCx, isStreet ? 0.30 : 0.30);
    final verticalScore = _near(cy, targetCy, 0.30);
    final rollScore = _near(roll, 0, 3.0);
    final progress = aligned
        ? 1.0
        : (0.15 +
                  0.85 *
                      (0.5 * centerScore +
                          0.3 * verticalScore +
                          0.2 * rollScore))
              .clamp(0.15, 0.96);

    return ComposeResult(
      subject: 'scene',
      subjectBox: box,
      targetBox: targetBox,
      targetZoom: zoom,
      horizonFix: roll,
      hint: hint,
      reasons: reasons,
      confidence: 0.76,
      source: 'vision',
      actionLabel: action,
      progress: progress,
    );
  }

  double _near(double value, double target, double tolerance) {
    if (tolerance <= 0) return 0;
    return (1 - (value - target).abs() / tolerance).clamp(0.0, 1.0);
  }

  /// 用脸宽反推距离：0.14m 平均脸宽 + 由视场角换算的焦距；只作“约”值。
  double? _estimateDistance(GuidanceFrame frame, double faceWidthRatio) {
    if (faceWidthRatio <= 0.01) return null;
    final fov = frame.hfov * math.pi / 180;
    final focalPx = (frame.frameW / 2) / math.tan(fov / 2);
    final facePx = faceWidthRatio * frame.frameW;
    if (facePx < 6) return null;
    final meters = 0.14 * focalPx / facePx;
    if (meters < 0.4 || meters > 9) return null;
    return meters;
  }
}
