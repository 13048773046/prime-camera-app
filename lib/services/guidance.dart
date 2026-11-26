import 'dart:math' as math;

import 'compose_api.dart';

/// 原生相机每帧推上来的识别结果（坐标已映射到 3:4 可见取景窗）。
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
  });

  final double roll;
  final double pitch;
  final int frameW;
  final int frameH;
  final double hfov;
  final int ts;
  final List<double>? box;
  final List<double>? face;

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
    );
  }
}

/// 把实时识别结果翻译成“一句口令”，规则沿用手册：
/// 优先级 距离 > 高度 > 角度 > 焦段；只提示当下最该做的一件事。
class LiveComposer {
  const LiveComposer();

  ComposeResult compose(GuidanceFrame frame, {required double zoom}) {
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
      final delta = distance == null ? null : math.max(0.2, (distance - 1.5).abs());
      action = delta == null ? '走近' : '再近\n${delta.toStringAsFixed(1)}m';
    } else if (metricH > nearLimit) {
      hint = '再退半步，给头顶留点空间';
      reasons = const ['人物有点太满', '边缘容易切到'];
      final delta = distance == null ? null : math.max(0.2, (distance - 1.5).abs());
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
                    (0.55 * _near(metricH, targetH, (nearLimit - farLimit) * 0.55) +
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
