import 'dart:math' as math;

import 'compose_api.dart';

/// 拍摄场景。通用保留给人像以外的一切画面；街景单独用三分/水平线规则。
enum SceneMode { general, portrait, street }

extension SceneModeX on SceneMode {
  String get label => switch (this) {
    SceneMode.general => '通用',
    SceneMode.portrait => '人像',
    SceneMode.street => '街景',
  };

  String get analyzingText => switch (this) {
    SceneMode.general => '正在读取画面构图',
    SceneMode.portrait => '正在进行人像构图分析',
    SceneMode.street => '正在分析街景线条',
  };

  String get settingText => switch (this) {
    SceneMode.general => '通用构图 · 全屏',
    SceneMode.portrait => '人像构图 · 全屏',
    SceneMode.street => '街景 · 右三分 · 全屏',
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

  bool get hasSubject => box != null && box!.length == 4;

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
  }) {
    if (mode == SceneMode.portrait) return _composePortrait(frame, zoom);
    return _composeScene(frame, zoom: zoom, mode: mode);
  }

  ComposeResult _composePortrait(GuidanceFrame frame, double zoom) {
    final face = frame.face;
    final roll = frame.roll;
    // 人体框偶尔会漏（人物太近、腿出画），但脸还在；用脸扩一个主体框兜底。
    final box = frame.box ?? _boxFromFace(face);

    if (box == null || box.length != 4) {
      return ComposeResult(
        subject: 'person',
        subjectBox: const [],
        targetBox: const [],
        targetZoom: zoom,
        horizonFix: roll,
        hint: '把人物放进取景框',
        reasons: const ['还没有找到主体', '先让人物完整入镜'],
        confidence: 0,
        source: 'vision',
        actionLabel: '找主体',
        distanceMeters: null,
        progress: 0.12,
      );
    }

    // 有脸用脸，脸比人体框更稳；脸太小说明离得远。
    final hasFace = face != null && face.length == 4;
    final metricH = hasFace ? face[3] : box[3];
    final metricTop = hasFace ? face[1] : box[1];
    final targetH = hasFace ? 0.16 : 0.58;
    final farLimit = hasFace ? 0.125 : 0.50;
    final nearLimit = hasFace ? 0.20 : 0.70;
    final topHigh = hasFace ? 0.20 : 0.16;
    final topLow = 0.035;
    final topTarget = hasFace ? 0.12 : 0.10;

    final distance = hasFace ? _estimateDistance(frame, face[2]) : null;

    String hint;
    List<String> reasons;
    String action;
    bool aligned = false;

    if (metricH < farLimit) {
      hint = '再靠近半步，让人物大一点';
      reasons = const ['人物在画面里偏小', '环境占得太多'];
      final delta = distance == null
          ? null
          : math.max(0.2, (distance - 1.5).abs());
      action = delta == null ? '走近' : '再近\n${delta.toStringAsFixed(1)}m';
    } else if (metricH > nearLimit) {
      hint = '再退半步，给头顶留点空间';
      reasons = const ['人物有点太满', '边缘容易切到'];
      final delta = distance == null
          ? null
          : math.max(0.2, (distance - 1.5).abs());
      action = delta == null ? '退后' : '再退\n${delta.toStringAsFixed(1)}m';
    } else if (metricTop > topHigh) {
      hint = '镜头降到胸口';
      reasons = const ['头顶留白偏多', '机位稍微高了'];
      action = '降机位';
    } else if (metricTop < topLow) {
      hint = '镜头抬高一点';
      reasons = const ['头顶快贴边了', '给发梢留点白'];
      action = '抬机位';
    } else if ((box[0] + box[2] / 2 - 0.5).abs() > 0.17) {
      final toLeft = box[0] + box[2] / 2 < 0.5;
      hint = toLeft ? '手机往左带一点，把人物放进环' : '手机往右带一点，把人物放进环';
      reasons = const ['主体还没进瞄准环', '跟着环的方向微移'];
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
      reasons = const ['距离合适', '机位水平都对齐'];
      action = '已对齐';
    }

    final progress = aligned
        ? 1.0
        : (0.15 +
                  0.85 *
                      (0.55 *
                              _near(
                                metricH,
                                targetH,
                                (nearLimit - farLimit) * 0.55,
                              ) +
                          0.25 * _near(metricTop, topTarget, 0.14) +
                          0.20 * _near(roll, 0, 3.0)))
              .clamp(0.15, 0.96);

    return ComposeResult(
      subject: hasFace ? 'face' : 'person',
      subjectBox: box,
      targetBox: const [0.34, 0.08, 0.32, 0.62],
      targetZoom: zoom,
      horizonFix: roll,
      hint: hint,
      reasons: reasons,
      confidence: hasFace ? 0.9 : 0.72,
      source: 'vision',
      actionLabel: action,
      progress: progress,
      distanceMeters: distance,
    );
  }

  /// 通用/街景不依赖人脸：优先使用 Vision 的显著区域。
  ComposeResult _composeScene(
    GuidanceFrame frame, {
    required double zoom,
    required SceneMode mode,
  }) {
    final box = frame.saliency ?? frame.box;
    final roll = frame.roll;
    final isStreet = mode == SceneMode.street;
    final targetBox = isStreet
        ? const [0.54, 0.22, 0.24, 0.30]
        : const [0.34, 0.30, 0.32, 0.32];
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

  /// 以脸为中心扩出半身框：宽约 3 个脸宽，高约 6 个脸高。
  List<double>? _boxFromFace(List<double>? face) {
    if (face == null || face.length != 4) return null;
    final w = (face[2] * 3.2).clamp(0.18, 0.90);
    final h = (face[3] * 3.8).clamp(0.42, 0.82);
    final cx = face[0] + face[2] / 2;
    final top = (face[1] - h * 0.10).clamp(0.0, 1.0 - h);
    final left = (cx - w / 2).clamp(0.0, 1.0 - w);
    return [left.toDouble(), top.toDouble(), w.toDouble(), h.toDouble()];
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
