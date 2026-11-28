import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/camera_service.dart';
import '../services/compose_api.dart';
import '../services/scan_api.dart';
import '../services/guidance.dart';
import '../data/filters.dart';
import '../services/camera_prefs.dart';
import 'settings_page.dart';
import '../theme.dart';
import '../widgets/filter_detail_sheet.dart';
import '../widgets/palette_sheet.dart';
import '../widgets/subject_box_editor.dart';
import '../widgets/zoom_dial.dart';
import '../widgets/guide_ring.dart';
import '../widgets/doka_ai_overlay.dart';
import 'gallery_page.dart';
import 'mine_page.dart';
import 'result_page.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({
    super.key,
    this.camera,
    this.demo = false,
    this.initialScene = SceneMode.general,
  });

  final CameraService? camera;
  final bool demo;
  final SceneMode initialScene;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

enum CaptureRatio {
  threeFour,
  fourThree,
  oneOne,
  sixteenNine,
  nineSixteen,
  twoThree,
  threeTwo,
  fourFive,
  fiveFour,
  sixtyFiveTwentyFour,
}

extension CaptureRatioX on CaptureRatio {
  String get label => switch (this) {
    CaptureRatio.threeFour => '3:4',
    CaptureRatio.fourThree => '4:3',
    CaptureRatio.oneOne => '1:1',
    CaptureRatio.sixteenNine => '16:9',
    CaptureRatio.nineSixteen => '9:16',
    CaptureRatio.twoThree => '2:3',
    CaptureRatio.threeTwo => '3:2',
    CaptureRatio.fourFive => '4:5',
    CaptureRatio.fiveFour => '5:4',
    CaptureRatio.sixtyFiveTwentyFour => '65:24',
  };

  /// 预览高 / 宽。
  double get heightOverWidth => switch (this) {
    CaptureRatio.threeFour => 4 / 3,
    CaptureRatio.fourThree => 3 / 4,
    CaptureRatio.oneOne => 1,
    CaptureRatio.sixteenNine => 9 / 16,
    CaptureRatio.nineSixteen => 16 / 9,
    CaptureRatio.twoThree => 3 / 2,
    CaptureRatio.threeTwo => 2 / 3,
    CaptureRatio.fourFive => 5 / 4,
    CaptureRatio.fiveFour => 4 / 5,
    CaptureRatio.sixtyFiveTwentyFour => 24 / 65,
  };
}

class _ShotPlan {
  const _ShotPlan({
    required this.index,
    required this.title,
    required this.zoomLabel,
    required this.framing,
    required this.alignment,
    required this.targetHeight,
    required this.recommendedDistance,
    required this.description,
  });

  final int index;
  final String title;
  final String zoomLabel;
  final String framing;
  final Alignment alignment;

  /// 目标主体高度（占取景框高度）。拍法不是一句口号：它会直接决定
  /// 画面里的黄色主体框要多大、人物应该站在哪里。
  final double targetHeight;
  final double recommendedDistance;
  final String description;

  double get targetCenterX => switch (alignment) {
    Alignment.centerLeft => 0.34,
    Alignment.centerRight => 0.66,
    _ => 0.5,
  };

  double get targetCenterY => switch (alignment) {
    Alignment.topCenter => 0.38,
    _ => 0.44,
  };
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  late final CameraService _camera =
      widget.camera ?? CameraService(forceDemo: widget.demo);

  CameraStatus _status = CameraStatus.unavailable;
  String? _statusMessage;
  bool _aligned = false;
  double _alignProgress = 0.12;
  SceneMode _scene = SceneMode.general;
  bool _sceneLocked = false;
  CaptureRatio _ratio = CaptureRatio.threeFour;
  int _zoomIndex = 1;
  double _zoom = 1.0;
  double _zoomAtScaleStart = 1.0;
  bool _zoomDialOpen = false;
  Timer? _zoomDialTimer;
  Timer? _zoomSendTimer;
  double? _pendingZoom;
  bool _capturing = false;
  bool _flash = false;
  bool _flashOn = false;
  bool _ultraWideAvailable = true;
  bool _gridOn = false;
  bool _planSheetOpen = false;
  int _planIndex = 0;
  bool _subjectHintVisible = false;
  bool _showAiFilterTip = false;
  Timer? _aiFilterTipTimer;
  Timer? _subjectHintTimer;
  ComposeResult? _guide;
  Timer? _alignTimer;
  Timer? _analyzeTimer;
  Timer? _frameWatchdog;
  Timer? _promptTimer;
  StreamSubscription<GuidanceFrame>? _guidanceSub;
  StreamSubscription<CameraFrameTick>? _frameSub;
  final LiveComposer _composer = const LiveComposer();
  final ScanApi _scanApi = ScanApi();
  Timer? _scanTimer;
  bool _scanInFlight = false;
  List<double>? _serverCrop;
  List<double>? _lockedSubjectBox;
  List<double>? _stableSubjectBox;
  int _stableSubjectTs = 0;
  double _exposure = 0.0;
  bool _showExposure = false;
  Timer? _exposureTimer;
  Timer? _alignConfirmTimer;
  String _lastServerReason = '';
  double _lastRoll = 0;
  double _lastPitch = 0;
  bool _live = false;
  bool _analyzing = false;
  bool _restarting = false;
  int _restartAttempts = 0;
  bool _composeEnabled = true;
  String _filterId = 'none';
  String _recommendedFilterName = '';
  String _recommendedFilterId = 'none';
  final List<String> _recentPhotos = [];
  int _lastGuidanceTs = 0;
  int _lastFrameTs = 0;
  bool _wasAligned = false;
  String? _promptTitle;
  String? _promptSubtitle;
  String? _lastActionLabel;
  String? _actionLabel;
  DateTime? _lastAutoZoomAt;
  bool _autoZoomBusy = false;

  static const List<double> _zoomValues = [0.5, 1.0, 2.0, 5.0, 10.0];
  static const List<String> _zoomLabels = ['.5x', '1x', '2x', '5x', '10x'];

  static const List<_ShotPlan> _plans = [
    _ShotPlan(
      index: 1,
      title: '全身',
      zoomLabel: '1×',
      framing: '居中',
      alignment: Alignment.center,
      targetHeight: 0.60,
      recommendedDistance: 2.2,
      description: '全身入镜，头顶留一拳，脚底留一点',
    ),
    _ShotPlan(
      index: 2,
      title: '七分身',
      zoomLabel: '2×',
      framing: '右三分',
      alignment: Alignment.centerRight,
      targetHeight: 0.42,
      recommendedDistance: 1.5,
      description: '卡到膝盖以上，人物放在右三分',
    ),
    _ShotPlan(
      index: 3,
      title: '九分身',
      zoomLabel: '5×',
      framing: '居中',
      alignment: Alignment.topCenter,
      targetHeight: 0.28,
      recommendedDistance: 0.9,
      description: '卡到胸以上，眼睛放在上三分',
    ),
  ];

  static const List<_ShotPlan> _streetPlans = [
    _ShotPlan(
      index: 1,
      title: '街道全景',
      zoomLabel: '1×',
      framing: '右三分',
      alignment: Alignment.centerRight,
      targetHeight: 0.34,
      recommendedDistance: 0,
      description: '把街道消失点放进右三分',
    ),
    _ShotPlan(
      index: 2,
      title: '门洞框景',
      zoomLabel: '2×',
      framing: '居中',
      alignment: Alignment.center,
      targetHeight: 0.42,
      recommendedDistance: 0,
      description: '让门洞成为画框，主体放在里面',
    ),
    _ShotPlan(
      index: 3,
      title: '局部细节',
      zoomLabel: '5×',
      framing: '居中',
      alignment: Alignment.topCenter,
      targetHeight: 0.34,
      recommendedDistance: 0,
      description: '走近拍纹理，让画面只有一个重点',
    ),
  ];

  static const List<_ShotPlan> _generalPlans = [
    _ShotPlan(
      index: 1,
      title: '环境居中',
      zoomLabel: '1×',
      framing: '居中',
      alignment: Alignment.center,
      targetHeight: 0.44,
      recommendedDistance: 0,
      description: '主体居中，四周留出环境',
    ),
    _ShotPlan(
      index: 2,
      title: '三分留白',
      zoomLabel: '1×',
      framing: '右三分',
      alignment: Alignment.centerRight,
      targetHeight: 0.40,
      recommendedDistance: 0,
      description: '主体放右三分，左侧留呼吸空间',
    ),
    _ShotPlan(
      index: 3,
      title: '主体特写',
      zoomLabel: '2×',
      framing: '居中',
      alignment: Alignment.center,
      targetHeight: 0.30,
      recommendedDistance: 0,
      description: '让主体占满画面，裁掉干扰',
    ),
  ];

  List<_ShotPlan> get _currentPlans => switch (_scene) {
    SceneMode.portrait => _plans,
    SceneMode.street => _streetPlans,
    SceneMode.general ||
    SceneMode.landscape ||
    SceneMode.still => _generalPlans,
  };

  @override
  void initState() {
    super.initState();
    _scene = widget.initialScene;
    CameraPrefs.instance.scene = widget.initialScene;
    _sceneLocked = widget.initialScene != SceneMode.general;
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alignTimer?.cancel();
    _analyzeTimer?.cancel();
    _frameWatchdog?.cancel();
    _guidanceSub?.cancel();
    _frameSub?.cancel();
    _scanTimer?.cancel();
    _promptTimer?.cancel();
    _exposureTimer?.cancel();
    _alignConfirmTimer?.cancel();
    _zoomDialTimer?.cancel();
    _zoomSendTimer?.cancel();
    _aiFilterTipTimer?.cancel();
    _subjectHintTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _status == CameraStatus.permissionDenied) {
      _bootstrap();
    }
  }

  _ShotPlan get _activePlan {
    final plans = _currentPlans;
    return plans[_planIndex.clamp(0, plans.length - 1)];
  }

  String get _subjectLabel {
    if (_scene == SceneMode.street) return '街景';
    if (_scene == SceneMode.general ||
        _scene == SceneMode.landscape ||
        _scene == SceneMode.still) {
      return '重点';
    }
    final guide = _guide;
    if (guide == null) return '主体';
    if (guide.subject == 'face') return '人脸';
    if (guide.subject == 'person') {
      final height = guide.subjectBox.length == 4 ? guide.subjectBox[3] : 0.0;
      if (height >= 0.52) return '全身';
      if (height >= 0.30) return '半身';
      return '人物';
    }
    return '主体';
  }

  Future<void> _bootstrap() async {
    final init = await _camera.initialize();
    if (!mounted) return;
    setState(() {
      _status = init.status;
      _statusMessage = init.message;
      _ultraWideAvailable = init.ultraWide;
      _live = init.status == CameraStatus.ready;
      _composeEnabled = false;
      _analyzing = false;
      _guide = null;
      _lockedSubjectBox = null;
      _aligned = false;
      _alignProgress = 0.12;
    });
    if (_live) {
      _startPreviewStreams();
    } else if (init.status == CameraStatus.unavailable) {
      setState(() => _analyzing = false);
    }
  }

  /// Doka 相机空闲态不扫描、不显示目标环；只保持预览与帧心跳。
  void _startPreviewStreams() {
    _guidanceSub?.cancel();
    _frameSub?.cancel();
    _lastFrameTs = 0;
    _guidanceSub = _camera.guidanceStream.listen(_onGuidanceFrame);
    _frameSub = _camera.frameStream.listen((tick) {
      _lastFrameTs = tick.ts;
    });
    _startFrameWatchdog();
  }

  void _startDemoAnalysis() {
    _alignTimer?.cancel();
    _analyzeTimer?.cancel();
    setState(() {
      _composeEnabled = true;
      _analyzing = true;
      _guide = null;
      _lockedSubjectBox = null;
      _aligned = false;
      _alignProgress = 0.12;
      _lastActionLabel = null;
    });
    _analyzeTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _analyzing = false);
      _showPrompt('请对准彩色圆环', '跟随引导线移动手机', 2200);
      _startCommandCycle();
    });
  }

  /// 顶部只做阶段性小提示，2–3 秒自动收走，不再常驻一张大卡。
  void _showPrompt(String title, String? subtitle, int milliseconds) {
    _promptTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _promptTitle = title;
      _promptSubtitle = subtitle;
    });
    _promptTimer = Timer(Duration(milliseconds: milliseconds), () {
      if (!mounted) return;
      setState(() {
        _promptTitle = null;
        _promptSubtitle = null;
      });
    });
  }

  void _startLiveGuidance() {
    _scanTimer?.cancel();
    _alignTimer?.cancel();
    _analyzeTimer?.cancel();
    _subjectHintTimer?.cancel();
    _lastGuidanceTs = 0;
    _restartAttempts = 0;
    _serverCrop = null;
    _scanInFlight = false;
    _wasAligned = false;
    _stableSubjectBox = null;
    _stableSubjectTs = 0;
    setState(() {
      _composeEnabled = true;
      _analyzing = true;
      _guide = null;
      _lockedSubjectBox = null;
      _subjectHintVisible = false;
      _aligned = false;
      _alignProgress = 0.12;
      _lastActionLabel = null;
      _planIndex = 0;
      _showAiFilterTip = false;
    });
    if (_guidanceSub == null) _startPreviewStreams();
    _startScanLoop();
    // Doka 的分析态：HUD 由 `_analyzing` 驱动，分析期间不显示拍法提示。
    _analyzeTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      if (_guide != null) {
        setState(() => _analyzing = false);
        return;
      }
      // 扫描请求还没回来时继续显示分析 HUD / 扫描动画；
      // 4 秒兜底，避免网络卡住后界面永远停在“分析中”。
      _analyzeTimer = Timer(const Duration(milliseconds: 2200), () {
        if (!mounted) return;
        setState(() => _analyzing = false);
        _showPrompt('请对准彩色圆环', '跟随引导线移动手机', 2200);
      });
    });
  }

  /// Doka 是“客户端抓帧 → 服务端 scan 给方案 → 客户端跟踪”。
  /// AI 构图只抓一帧分析；分析结束后不再每 1.6 秒重复请求。
  void _startScanLoop() {
    _scanTimer?.cancel();
    _serverCrop = null;
    _lastServerReason = '';
    if (!_scanApi.enabled) return;
    _scanTimer = Timer(const Duration(milliseconds: 500), _scanCurrentFrame);
  }

  /// 原生 Vision / 后端返回的是完整 9:16 画幅坐标，Flutter 只显示中间
  /// 3:4 预览。这里把全画幅框映射到预览归一化坐标；否则主体框/目标环会
  /// 整体偏上，出现“框不跟着人走”的错觉。
  List<double> _toPreviewBox(List<double> box) {
    if (box.length != 4) return box;
    final visibleY = 0.5625 * _ratio.heightOverWidth;
    if (visibleY >= 0.999) return box;
    final offsetY = (1 - visibleY) / 2;
    final x = box[0].clamp(0.0, 1.0);
    final y = ((box[1] - offsetY) / visibleY).clamp(0.0, 1.0);
    final w = box[2].clamp(0.0, 1.0 - x);
    final h = (box[3] / visibleY).clamp(0.0, 1.0 - y);
    return [x, y, w, h];
  }

  List<double> _previewToFullBox(List<double> box) {
    final visibleY = 0.5625 * _ratio.heightOverWidth;
    if (visibleY >= 0.999) return List<double>.of(box);
    final offsetY = (1 - visibleY) / 2;
    return [
      box[0],
      (offsetY + box[1] * visibleY).clamp(0.0, 1.0),
      box[2],
      (box[3] * visibleY).clamp(0.02, 1.0),
    ];
  }

  /// 服务端拿到的 scan 帧是完整 9:16 画幅，手动主体框却是 3:4 预览坐标；
  /// 这里做一次 cover 映射，避免后端按错位置裁主体。
  List<double>? _subjectBoxForServer() {
    final locked = _lockedSubjectBox;
    if (locked == null || locked.length != 4) return _guide?.subjectBox;
    return _previewToFullBox(locked);
  }

  Future<void> _scanCurrentFrame() async {
    if (!mounted || !_live || !_composeEnabled || _scanInFlight) return;
    _scanInFlight = true;
    try {
      final jpeg = await _camera.capturePreviewJpeg();
      if (!mounted || jpeg == null) return;
      final plan = await _scanApi.scan(
        jpeg: jpeg,
        scene: _scene.name,
        zoom: _zoom,
        tilt: _lastPitch,
        roll: _lastRoll,
        subjectBox: _subjectBoxForServer(),
        subjectKind: _scene == SceneMode.portrait ? 'person' : 'object',
        aiFilterPreferences: jsonEncode({
          'scenes': CameraPrefs.instance.preferredScenes,
          'series': CameraPrefs.instance.preferredSeries,
        }),
        aspect: _ratio.label,
      );
      if (!mounted || plan == null) return;
      final rect = plan.cropRect;
      if (rect.length != 4 || rect[2] <= 0 || rect[3] <= 0) return;
      setState(() {
        _serverCrop = rect;
        _recommendedFilterName = plan.filterName;
        _recommendedFilterId = plan.filterId;
      });
      // Doka `tvAiFilterTip`：扫完给 AI 滤镜建议，3.2 秒后收起。
      if (plan.filterName.isNotEmpty && plan.filterId != 'none') {
        _aiFilterTipTimer?.cancel();
        setState(() => _showAiFilterTip = true);
        _aiFilterTipTimer = Timer(const Duration(milliseconds: 3200), () {
          if (mounted) setState(() => _showAiFilterTip = false);
        });
      }
      if (!_aligned &&
          plan.reason.isNotEmpty &&
          plan.reason != _lastServerReason) {
        _lastServerReason = plan.reason;
        _showPrompt('请对准彩色圆环', plan.reason, 2200);
      }
    } finally {
      _scanInFlight = false;
    }
  }

  /// 取景纹理停住时，页面看不出任何“移动手机”的反馈。这里用心跳
  /// 做兜底：超过 1.6s 没有新帧就轻量重启一次 session，最多三次。
  void _startFrameWatchdog() {
    _frameWatchdog?.cancel();
    _frameWatchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_live || _restarting) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_lastFrameTs > 0 && now - _lastFrameTs < 1600) return;
      if (_restartAttempts >= 3) {
        _frameWatchdog?.cancel();
        return;
      }
      _restartAttempts++;
      _restarting = true;
      _camera.restart().whenComplete(() {
        if (mounted) _restarting = false;
      });
    });
  }

  /// 原生已经做了连续性选人；这里再补一层“手动主体优先 + 时间平滑”，
  /// 避免同一帧里换人、或 5–6fps 的人体框带着目标环抖动。
  GuidanceFrame _stableGuidance(GuidanceFrame raw) {
    var box = raw.box;
    final locked = _lockedSubjectBox;
    final lockedFull = locked == null ? null : _previewToFullBox(locked);
    if (lockedFull != null) {
      // 用户手动指定的主体优先；原生检测到的人只在框内/附近时才接管，
      // 否则长按一个物体后主体框会被旁边的人抢走。
      box = lockedFull;
    }
    if (locked != null && raw.candidates.isNotEmpty) {
      final visibleY = 0.5625 * _ratio.heightOverWidth;
      final offsetY = (1 - visibleY) / 2;
      final lx = locked[0] + locked[2] / 2;
      final ly = offsetY + (locked[1] + locked[3] / 2) * visibleY;
      List<double>? best;
      var bestDistance = double.infinity;
      for (final candidate in raw.candidates) {
        if (candidate.length != 4) continue;
        final cx = candidate[0] + candidate[2] / 2;
        final cy = candidate[1] + candidate[3] / 2;
        final d = math.pow(cx - lx, 2) + math.pow(cy - ly, 2);
        if (d < bestDistance) {
          bestDistance = d.toDouble();
          best = candidate;
        }
      }
      if (best != null) {
        final cx = best[0] + best[2] / 2;
        final cy = best[1] + best[3] / 2;
        final inside =
            lockedFull != null &&
            cx >= lockedFull[0] &&
            cx <= lockedFull[0] + lockedFull[2] &&
            cy >= lockedFull[1] &&
            cy <= lockedFull[1] + lockedFull[3];
        // bestDistance 是归一化平方距离：0.008 约等于 0.09 的画幅距离，
        // 只允许离手动框很近的人接管，避免长按物体后被旁边的人抢走。
        if (inside || bestDistance < 0.008) box = best;
      }
    }

    if (box != null && box.length == 4) {
      final previous = _stableSubjectBox;
      final fresh = raw.ts - _stableSubjectTs > 700;
      final next = (previous == null || fresh || previous.length != 4)
          ? List<double>.of(box)
          : _lerpRect(previous, box, 0.38);
      _stableSubjectBox = next;
      _stableSubjectTs = raw.ts;
      return raw.copyWith(box: next);
    }

    // 短暂丢失（<650ms）时保留上一帧，避免目标环瞬间消失又跳回来。
    if (_stableSubjectBox != null && raw.ts - _stableSubjectTs < 650) {
      return raw.copyWith(box: _stableSubjectBox);
    }
    return raw;
  }

  List<double> _lerpRect(List<double> a, List<double> b, double t) {
    return [
      a[0] + (b[0] - a[0]) * t,
      a[1] + (b[1] - a[1]) * t,
      a[2] + (b[2] - a[2]) * t,
      a[3] + (b[3] - a[3]) * t,
    ];
  }

  void _onGuidanceFrame(GuidanceFrame rawFrame) {
    if (!mounted || !_live || !_composeEnabled) return;
    final frame = _stableGuidance(rawFrame);
    _lastFrameTs = math.max(_lastFrameTs, frame.ts);
    _lastRoll = frame.roll;
    _lastPitch = frame.pitch;
    // UI 最高 4fps 更新，避免识别帧率带着整页抖动。
    if (frame.ts - _lastGuidanceTs < 240) return;
    _lastGuidanceTs = frame.ts;
    // 没有手动锁场景时，先让 AI 自己判断：画面里有人就进人像流程，
    // 只有显著物就继续用通用/风景构图。这样用户不需要先选一个胶囊。
    var mode = _scene;
    if (!_sceneLocked) {
      if (frame.box != null || frame.face != null) {
        mode = SceneMode.portrait;
      } else if (frame.saliency != null && frame.saliency![2] > 0.42) {
        mode = SceneMode.landscape;
      } else {
        mode = SceneMode.general;
      }
      if (mode != _scene) {
        setState(() => _scene = mode);
      }
    }
    final guide = _composer.compose(
      frame,
      zoom: _zoom,
      mode: mode,
      targetCenterX: _activePlan.targetCenterX,
      targetCenterY: _activePlan.targetCenterY,
      targetHeight: _activePlan.targetHeight,
      recommendedDistance: _activePlan.recommendedDistance,
    );
    final newlyAligned = guide.confidence > 0 && _isAlignedGuide(guide);
    final confirm = CameraPrefs.instance.alignmentConfirm;
    setState(() {
      _guide = guide;
      if (guide.confidence > 0 || guide.subjectBox.length == 4) {
        _analyzing = false;
      }
      _alignProgress = newlyAligned ? 1.0 : guide.progress;
      if (!newlyAligned) _aligned = false;
    });

    // 动作识别仍保留给调试/辅助信息，但不再用 Doka 没有的“动作 chip”打扰取景。
    final nextAction = CameraPrefs.instance.actionRecognition
        ? frame.actionLabel
        : null;
    if (nextAction != _actionLabel) {
      setState(() {
        _actionLabel = nextAction;
      });
    }

    if (CameraPrefs.instance.autoZoom) {
      _maybeAutoZoom(frame, guide);
    }
    if (newlyAligned && confirm) {
      _alignConfirmTimer?.cancel();
      _alignConfirmTimer = Timer(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        if (_guide != null && _isAlignedGuide(_guide!)) {
          setState(() => _aligned = true);
        }
      });
    } else if (!confirm) {
      _alignConfirmTimer?.cancel();
      setState(() => _aligned = newlyAligned);
    }
    if (newlyAligned && !_wasAligned) {
      HapticFeedback.lightImpact();
      _showPrompt('已对准，保持稳定', '构图锁定后按快门', 1800);
    } else if (!_analyzing &&
        guide.confidence > 0 &&
        guide.actionLabel != _lastActionLabel) {
      _showPrompt('请对准彩色圆环', '跟随引导线移动手机', 1600);
    }
    _lastActionLabel = guide.actionLabel;
    _wasAligned = newlyAligned;
  }

  bool _isAlignedGuide(ComposeResult guide) =>
      guide.actionLabel == '已对齐' || guide.hint.startsWith('可以拍了');

  /// Doka 的 AI 构图不是只给框：主体在画面里太小/太大时，镜头要
  /// 跟着换焦段。这里用人体框高度和目标高度的比例做一次迟滞变焦，
  /// 避免 1×↔2× 来回跳；真正按下快门仍保留用户选择的焦段。
  Future<void> _maybeAutoZoom(GuidanceFrame frame, ComposeResult guide) async {
    if (!_live ||
        _analyzing ||
        guide.confidence <= 0.05 ||
        _autoZoomBusy ||
        _scene == SceneMode.landscape ||
        frame.box == null ||
        frame.box!.length != 4) {
      return;
    }
    final subjectH = frame.box![3];
    if (subjectH < 0.05 || subjectH > 0.98) return;
    final targetH = _activePlan.targetHeight.clamp(0.18, 0.78);
    final ratio = targetH / subjectH;
    final currentZoom = _zoom;
    final desired = (currentZoom * ratio).clamp(0.5, 10.0);
    var nearest = _nearestZoomIndex(desired);
    if (nearest == 0 && !_ultraWideAvailable) nearest = 1;
    if (nearest == _zoomIndex) return;

    // 只有明显偏小/偏大才切；0.72–1.35 的误差留在原地，靠走位解决。
    if (ratio > 1.35 && nearest > _zoomIndex) {
      // 继续拉近。
    } else if (ratio < 0.72 && nearest < _zoomIndex) {
      // 退一点，给主体留出环境。
    } else {
      return;
    }
    final now = DateTime.now();
    final last = _lastAutoZoomAt;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 3200)) {
      return;
    }
    _lastAutoZoomAt = now;
    _autoZoomBusy = true;
    try {
      await _selectZoom(nearest);
      if (mounted) {
        _showPrompt(
          'AI 自动变焦',
          '主体占比 ${(subjectH * 100).round()}% · 切到 ${_zoomLabels[nearest]}',
          1700,
        );
      }
    } finally {
      _autoZoomBusy = false;
    }
  }

  ComposeResult _presetFor(int index, SceneMode mode) {
    if (mode != SceneMode.portrait) return _scenePreset(index, mode);
    switch (index) {
      case 0:
        return const ComposeResult(
          subject: 'person',
          subjectBox: [0.32, 0.22, 0.28, 0.66],
          targetBox: [0.16, 0.18, 0.68, 0.68],
          targetZoom: 0.5,
          horizonFix: -0.4,
          hint: '退到墙角，让街道进来',
          reasons: ['主体占比过大', '需要更多环境'],
          confidence: 0.58,
          distanceMeters: 1.7,
          recommendedDistance: 2.2,
          source: 'rule',
        );
      case 2:
        return const ComposeResult(
          subject: 'person',
          subjectBox: [0.40, 0.24, 0.26, 0.48],
          targetBox: [0.44, 0.26, 0.40, 0.40],
          targetZoom: 2.0,
          horizonFix: 0.2,
          hint: '再靠近半步，肩膀切出画面',
          reasons: ['两侧留白过多', '主体可以更满'],
          confidence: 0.64,
          distanceMeters: 1.7,
          recommendedDistance: 2.2,
          source: 'rule',
        );
      case 3:
        return const ComposeResult(
          subject: 'person',
          subjectBox: [0.44, 0.28, 0.18, 0.34],
          targetBox: [0.34, 0.30, 0.32, 0.32],
          targetZoom: 3.0,
          horizonFix: 0.0,
          hint: '手肘夹紧，对准眼睛',
          reasons: ['长焦易抖', '对焦点在眼部'],
          confidence: 0.66,
          distanceMeters: 1.7,
          recommendedDistance: 2.2,
          source: 'rule',
        );
      default:
        return const ComposeResult(
          subject: 'person',
          subjectBox: [0.34, 0.22, 0.28, 0.66],
          targetBox: [0.18, 0.18, 0.64, 0.64],
          targetZoom: 1.0,
          horizonFix: 0.0,
          hint: '后退半步，镜头降到胸口',
          reasons: ['头顶留白偏多', '主体略偏近'],
          confidence: 0.62,
          distanceMeters: 1.7,
          recommendedDistance: 2.2,
          source: 'rule',
        );
    }
  }

  ComposeResult _scenePreset(int index, SceneMode mode) {
    final street = mode == SceneMode.street;
    final target = street
        ? const [0.54, 0.22, 0.24, 0.24]
        : const [0.34, 0.27, 0.32, 0.32];
    final subject = street
        ? const [0.16, 0.30, 0.30, 0.34]
        : const [0.34, 0.30, 0.26, 0.30];
    return ComposeResult(
      subject: 'scene',
      subjectBox: subject,
      targetBox: target,
      targetZoom: _zoomValues[index],
      horizonFix: 0.0,
      hint: street ? '把街道消失点放进右边瞄准环' : '把画面重点放进中心环',
      reasons: street
          ? const ['街道重点在右三分', '先看消失点']
          : const ['先找画面重点', '再稳住水平线'],
      confidence: 0.58,
      source: 'rule',
      actionLabel: street ? '右移' : '对准',
      progress: 0.46,
    );
  }

  void _startCommandCycle() {
    if (_live || _status != CameraStatus.demo) return;
    _alignTimer?.cancel();
    final preset = _presetFor(_planIndex, _scene);
    setState(() {
      _guide = preset;
      _alignProgress = 0.12;
      _aligned = false;
    });
    int step = 0;
    const stops = [0.34, 0.6, 0.84, 1.0];
    _alignTimer = Timer.periodic(const Duration(milliseconds: 950), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      step++;
      setState(() {
        _alignProgress = stops[math.min(step, stops.length - 1)];
        _aligned = _alignProgress >= 1.0;
      });
      if (_aligned) HapticFeedback.lightImpact();
      if (step >= stops.length - 1) timer.cancel();
    });
  }

  void _exitCompose() {
    _alignTimer?.cancel();
    _analyzeTimer?.cancel();
    setState(() {
      _composeEnabled = false;
      _analyzing = false;
      _guide = null;
      _lockedSubjectBox = null;
      _aligned = false;
      _alignProgress = 0.12;
      _lastActionLabel = null;
      _showAiFilterTip = false;
      _subjectHintVisible = false;
    });
    _showPrompt('AI构图已退出', '自由取景，随时可以再进 AI 构图', 1700);
  }

  void _startAi() {
    _composeEnabled = true;
    if (_live) {
      _startLiveGuidance();
    } else if (_status == CameraStatus.demo) {
      _startDemoAnalysis();
    }
  }

  Future<void> _switchCamera() async {
    final actual = await _camera.switchCamera();
    if (!mounted || actual == null) return;
    final nearest = _nearestZoomIndex(actual);
    setState(() {
      _zoomIndex = nearest;
      _zoom = actual;
    });
  }

  Future<void> _selectZoom(int index) async {
    if (index == 0 && !_ultraWideAvailable) return;
    if (_zoomIndex == index && (_zoom - _zoomValues[index]).abs() < 0.01) {
      return;
    }
    setState(() => _zoomIndex = index);
    // 先让演示口令立刻跟手，再等原生回报实际可用倍率。
    if (!_live && _status == CameraStatus.demo) _startCommandCycle();
    final actual = await _camera.setZoom(_zoomValues[index]);
    if (!mounted) return;
    if (actual == null) {
      setState(() => _zoom = _zoomValues[index]);
      return;
    }
    final nearest = _nearestZoomIndex(actual);
    setState(() {
      _zoomIndex = nearest;
      _zoom = actual;
    });
  }

  void _scheduleZoom(double value) {
    _pendingZoom = value.clamp(0.5, 10.0);
    _zoomSendTimer?.cancel();
    _zoomSendTimer = Timer(const Duration(milliseconds: 90), () async {
      final target = _pendingZoom;
      if (target == null) return;
      final actual = await _camera.setZoom(target);
      if (!mounted) return;
      setState(() {
        _zoom = actual ?? target;
        _zoomIndex = _nearestZoomIndex(_zoom);
      });
    });
  }

  void _onZoomGesture(double next) {
    final value = next.clamp(_ultraWideAvailable ? 0.5 : 1.0, 10.0);
    setState(() {
      _zoom = value;
      _zoomIndex = _nearestZoomIndex(value);
    });
    _scheduleZoom(value);
  }

  void _openZoomDial() {
    setState(() => _zoomDialOpen = true);
    _zoomDialTimer?.cancel();
    _zoomDialTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _zoomDialOpen = false);
    });
  }

  int _nearestZoomIndex(double actual) {
    var best = 0;
    var distance = double.infinity;
    for (var i = 0; i < _zoomValues.length; i++) {
      final d = (_zoomValues[i] - actual).abs();
      if (d < distance) {
        distance = d;
        best = i;
      }
    }
    return best;
  }

  Future<void> _capture() async {
    if (_capturing ||
        (_status != CameraStatus.ready && _status != CameraStatus.demo)) {
      return;
    }
    final activeFilter = filterById(_filterId);
    if (activeFilter.pro &&
        !CameraPrefs.instance.filterUnlocked(activeFilter)) {
      _showPrompt(
        'Pro 滤镜未解锁',
        '${activeFilter.name} 可试用取景；保存需开通 Pro，或用其他滤镜拍摄 ${activeFilter.unlockShots} 张解锁',
        2800,
      );
      return;
    }
    setState(() {
      _capturing = true;
      _flash = true;
    });
    // 按下快门立刻给声/触/白闪，不等原生照片回调。
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.mediumImpact();
    final path = await _camera.takePhoto(
      flash: _flashOn,
      filter: _filterId,
      ratio: _ratio.name,
      livePhoto: CameraPrefs.instance.livePhoto,
      saveRaw: CameraPrefs.instance.saveRaw,
      selfieMirror: CameraPrefs.instance.selfieMirror,
      noiseReduction: CameraPrefs.instance.noiseReduction,
      watermark: CameraPrefs.instance.watermark,
      watermarkStyle: CameraPrefs.instance.watermarkStyle,
      border: CameraPrefs.instance.borderStyle,
      exposure: _exposure,
    );
    await Future.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    if (path == null || path.isEmpty) {
      setState(() {
        _flash = false;
        _capturing = false;
      });
      _showPrompt('拍摄失败', '相机没有返回照片，请重试', 2400);
      return;
    }
    _recentPhotos.insert(0, path);
    if (_filterId != 'none') {
      CameraPrefs.instance.recordFilterShot(_filterId);
    }
    setState(() {
      _flash = false;
      _capturing = false;
    });
    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (context, animation, secondary) => ResultPage(
          photoPath: path,
          camera: _camera,
          onSave: () => _camera.saveToAlbum(path),
          onShare: () => _camera.share(path),
          onRetake: () => Navigator.of(context).pop(),
        ),
        transitionsBuilder: (context, animation, secondary, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween(begin: 0.96, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  Future<void> _requestPermission() async {
    final granted = await _camera.requestPermission();
    if (!mounted) return;
    if (granted) {
      await _bootstrap();
    } else {
      setState(() {
        _status = CameraStatus.permissionDenied;
        _statusMessage = '还没有相机权限';
      });
    }
  }

  void _openGallery() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GalleryPage(
          photos: List<String>.of(_recentPhotos),
          camera: _camera,
          onMine: _openMine,
        ),
      ),
    );
  }

  void _openMine() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MinePage(
          photoCount: _recentPhotos.length,
          camera: _camera,
          gridOn: _gridOn,
          flashOn: _flashOn,
          onGrid: (value) => setState(() {
            _gridOn = value;
            CameraPrefs.instance.grid = value;
          }),
          onFlash: (value) => setState(() {
            _flashOn = value;
            CameraPrefs.instance.flash = value;
          }),
          onGallery: () {
            Navigator.of(context).pop();
            _openGallery();
          },
          onCamera: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  void _openFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _FilterSheet(
        selected: _filterId,
        recommended: _recommendedFilterId,
        recommendedName: _recommendedFilterName,
        displayStyle: CameraPrefs.instance.aiFilterDisplayStyle,
        onSelect: (id, label) {
          Navigator.of(sheetContext).pop();
          _applyFilterPreset(filterById(id));
        },
        onDetail: (filter) => _openFilterDetail(filter),
      ),
    );
  }

  void _applyFilterPreset(FilterPreset filter) {
    if (filter.id == _filterId) return;
    final unlocked = CameraPrefs.instance.filterUnlocked(filter);
    setState(() => _filterId = filter.id);
    if (filter.pro && !unlocked) {
      _showPrompt(
        '试用 · ${filter.name}',
        '取景可预览；拍摄保存前需要 Pro 或拍摄 ${filter.unlockShots} 张解锁',
        2600,
      );
      return;
    }
    _showPrompt('滤镜 · ${filter.name}', '已套用到取景与下一张照片', 1800);
  }

  void _openFilterDetail(FilterPreset filter) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (detailContext) => FilterDetailSheet(
        filter: filter,
        onApply: () {
          Navigator.of(detailContext).pop();
          _applyFilterPreset(filter);
        },
        onBuyPro: () {
          Navigator.of(detailContext).pop();
          _openMine();
        },
      ),
    );
  }

  void _openPlanSheet() {
    if (_planSheetOpen) return;
    setState(() => _planSheetOpen = true);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _PlanSheet(
        plans: _currentPlans,
        selectedIndex: _planIndex,
        sceneTitle: switch (_scene) {
          SceneMode.portrait => '构图方案',
          SceneMode.street => '街道构图方案',
          SceneMode.landscape => '风景构图方案',
          SceneMode.still => '静物构图方案',
          SceneMode.general => '构图方案',
        },
        sceneAsset: _status == CameraStatus.demo
            ? 'assets/demo/scene.jpg'
            : null,
        onSelect: (index) {
          Navigator.of(sheetContext).pop();
          setState(() {
            _planIndex = index.clamp(0, _currentPlans.length - 1);
            _aligned = false;
            _alignProgress = 0.12;
          });
          if (!_live && _status == CameraStatus.demo) _startCommandCycle();
        },
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _planSheetOpen = false);
    });
  }

  Future<void> _openSettings() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsPage()));
    if (!mounted) return;
    final changed = _scene != CameraPrefs.instance.scene;
    setState(() {
      _scene = CameraPrefs.instance.scene;
      _sceneLocked = _scene != SceneMode.general;
      _gridOn = CameraPrefs.instance.grid;
      _flashOn = CameraPrefs.instance.flash;
    });
    if (changed) {
      if (_live) {
        _startLiveGuidance();
      } else if (_status == CameraStatus.demo) {
        _startDemoAnalysis();
      }
    }
  }

  void _openRatioSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _RatioSheet(
        selected: _ratio,
        onSelect: (ratio) {
          Navigator.of(sheetContext).pop();
          if (ratio == _ratio) return;
          setState(() => _ratio = ratio);
          _showPrompt('比例已切换', '${ratio.label} · 宽度铺满取景', 1600);
          if (_live) {
            _startLiveGuidance();
          } else if (_status == CameraStatus.demo) {
            _startDemoAnalysis();
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: PrimeColor.black,
      ),
      child: Scaffold(
        backgroundColor: PrimeColor.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildFramedLayout(),
            if (_flash)
              const Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(color: Color(0xF2FFFFFF)),
                ),
              ),
            if (_status == CameraStatus.permissionDenied)
              Positioned.fill(child: _buildPermissionCard()),
          ],
        ),
      ),
    );
  }

  /// 照着 Doka 1.3.20 `fragment_camera.xml` 的结构：
  /// 3:4 圆角取景窗 → 48dp 固定选项行 → 96dp 功能行 → 70dp 底部留白。
  /// 没有底部三栏导航；空闲态 5 个选项，AI 构图态按 Doka 收成 3 个。
  Widget _buildFramedLayout() {
    return SafeArea(
      top: true,
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final maxHeight = constraints.maxHeight;
          // Doka fragment_camera：option 48 + function 96 + bottom padding 70。
          final bottomReserve = 48.0 + 96.0 + 12.0 + 70.0;
          final maxPreviewHeight = math.max(180.0, maxHeight - bottomReserve);
          // CameraMaskView：左右各留 12dp，3:4 预览在剩余区域内居中。
          final availableWidth = math.max(120.0, maxWidth - 24);
          var previewWidth = availableWidth;
          var previewHeight = previewWidth * _ratio.heightOverWidth;
          if (previewHeight > maxPreviewHeight) {
            previewHeight = maxPreviewHeight;
            previewWidth = previewHeight / _ratio.heightOverWidth;
          }

          return Column(
            children: [
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: previewWidth,
                    height: previewHeight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (_aligned)
                          Positioned(
                            left: -18,
                            top: -18,
                            right: -18,
                            bottom: -18,
                            child: const DokaGradientHalo(visible: true),
                          ),
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _buildStage(),
                                if (!_showAiFilterTip &&
                                    (_analyzing ||
                                        (_guide != null && !_aligned)))
                                  Positioned(
                                    top: 12,
                                    left: 48,
                                    right: 48,
                                    child: DokaAiHud(
                                      title: _analyzing
                                          ? 'AI正在分析画面'
                                          : '请对准彩色圆环',
                                      subtitle: _analyzing
                                          ? '请稳住手机，不要移动'
                                          : null,
                                    ),
                                  ),
                                if (!_analyzing && _showAiFilterTip)
                                  Positioned(
                                    top: 12,
                                    left: 0,
                                    right: 0,
                                    child: Center(
                                      child: DokaAiFilterTip(
                                        lines: [
                                          'AI推荐滤镜 · $_recommendedFilterName',
                                          '已为你匹配当前画面光线',
                                        ],
                                      ),
                                    ),
                                  ),
                                if (_subjectHintVisible && !_analyzing)
                                  Positioned(
                                    top: 28,
                                    left: 0,
                                    right: 0,
                                    child: Center(
                                      child: DokaSubjectHint(
                                        text: _lockedSubjectBox == null
                                            ? '长按取景框，标记你想拍的对象'
                                            : '已指定为本次 AI 构图主体\n拖动四角可调整范围',
                                      ),
                                    ),
                                  ),
                                if (!_analyzing &&
                                    _guide == null &&
                                    !_showAiFilterTip &&
                                    _promptTitle != null)
                                  Positioned(
                                    left: 24,
                                    right: 24,
                                    bottom: 86,
                                    child: Center(
                                      child: DokaToast(
                                        text: _promptTitle!,
                                        subtitle: _promptSubtitle,
                                      ),
                                    ),
                                  ),
                                if (!_analyzing && !_showAiFilterTip)
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    child: IgnorePointer(
                                      child: Container(
                                        height: 96,
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Color(0x4D000000),
                                              Colors.transparent,
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (!_analyzing && !_showAiFilterTip)
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    child: _buildTopBar(),
                                  ),
                                if (_guide != null &&
                                    !_analyzing &&
                                    _currentPlans.length > 1 &&
                                    !_aligned)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 62,
                                    child: Center(
                                      child: DokaSwitchPlanCta(
                                        label: '切换构图方案',
                                        onTap: _switchNextPlan,
                                      ),
                                    ),
                                  ),
                                if (!_zoomDialOpen &&
                                    (_analyzing || _guide != null))
                                  Positioned(
                                    left: 14,
                                    bottom: 12,
                                    child: _buildSingleZoomPill(),
                                  ),
                                if (!_zoomDialOpen &&
                                    !_analyzing &&
                                    _guide == null)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 12,
                                    child: _buildFocalPill(),
                                  ),
                                if (_zoomDialOpen)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: ZoomDial(
                                      value: _zoom,
                                      onChanged: (value) {
                                        _openZoomDial();
                                        _onZoomGesture(value);
                                      },
                                      onPreset: (value) {
                                        _zoomDialTimer?.cancel();
                                        _selectZoom(_nearestZoomIndex(value));
                                        setState(() => _zoomDialOpen = false);
                                      },
                                      onClose: () =>
                                          setState(() => _zoomDialOpen = false),
                                    ),
                                  ),
                                if (_guide != null && !_analyzing)
                                  Positioned(
                                    right: 10,
                                    bottom: 10,
                                    child: _buildAiFilterEntry(),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 48,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: 0.94,
                        end: 1,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(_analyzing || _guide != null),
                    child: _buildDokaOptionRow(),
                  ),
                ),
              ),
              _buildDokaFunctionRow(),
              const SizedBox(height: 70),
            ],
          );
        },
      ),
    );
  }

  void _switchNextPlan() {
    if (_currentPlans.length < 2) return;
    setState(() {
      _planIndex = (_planIndex + 1) % _currentPlans.length;
      _aligned = false;
      _alignProgress = 0.12;
    });
    _showPrompt('构图方案 ${_planIndex + 1}', '跟随引导线对准新的目标环', 1600);
    if (!_live && _status == CameraStatus.demo) _startCommandCycle();
  }

  // ---------------------------------------------------------------- header

  /// Doka 顶栏只有左上 `ivLivePhotoToggle` 48×48 与右上 `ivSetting` 48×48，
  /// 都是 24dp 白色图标 + 12dp 内边距，没有玻璃圆底、品牌字或动作 chip。
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: GestureDetector(
              onTap: () {
                setState(
                  () => CameraPrefs.instance.livePhoto =
                      !CameraPrefs.instance.livePhoto,
                );
                _showPrompt(
                  CameraPrefs.instance.livePhoto ? '实况照片已开启' : '实况照片已关闭',
                  CameraPrefs.instance.livePhoto
                      ? '快门前会同时录制 1.5 秒动态'
                      : '下一张只保存静态照片',
                  1800,
                );
              },
              behavior: HitTestBehavior.opaque,
              child: Center(
                child: CustomPaint(
                  size: const Size(24, 24),
                  painter: _LivePhotoGlyph(on: CameraPrefs.instance.livePhoto),
                ),
              ),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 48,
            height: 48,
            child: GestureDetector(
              onTap: _openSettings,
              behavior: HitTestBehavior.opaque,
              child: Center(child: _dokaAssetIcon('ic_setting', size: 24)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dokaAssetIcon(
    String name, {
    double size = 24,
    double opacity = 1.0,
    bool tintWhite = true,
  }) {
    final image = Image.asset(
      'assets/doka/$name.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, _, _) => SizedBox(width: size, height: size),
    );
    return Opacity(
      opacity: opacity,
      child: tintWhite
          ? ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
              child: image,
            )
          : image,
    );
  }

  // ----------------------------------------------------------------- stage

  Widget _buildStage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final focusRect = _coverRect(viewport, const Size(1080, 1920));
        final previewRect = Offset.zero & viewport;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final x =
                ((details.localPosition.dx - focusRect.left) / focusRect.width)
                    .clamp(0.0, 1.0);
            final y =
                ((details.localPosition.dy - focusRect.top) / focusRect.height)
                    .clamp(0.0, 1.0);
            _camera.focusAt(x, y);
            if (CameraPrefs.instance.touchShot) {
              _capture();
            }
          },
          onVerticalDragStart: (details) {
            if (details.localPosition.dx > previewRect.width * 0.3) return;
            _exposureTimer?.cancel();
            setState(() => _showExposure = true);
          },
          onVerticalDragUpdate: (details) {
            if (!_showExposure) return;
            final next = (_exposure - details.delta.dy / 90).clamp(-2.0, 2.0);
            if ((next - _exposure).abs() < 0.001) return;
            setState(() => _exposure = next);
            _camera.setExposure(next);
          },
          onVerticalDragEnd: (_) {
            _exposureTimer?.cancel();
            _exposureTimer = Timer(const Duration(milliseconds: 1400), () {
              if (mounted) setState(() => _showExposure = false);
            });
          },
          onScaleStart: (details) {
            if (details.pointerCount < 2) return;
            _zoomAtScaleStart = _zoom;
          },
          onScaleUpdate: (details) {
            if (details.pointerCount < 2) return;
            _onZoomGesture(_zoomAtScaleStart * details.scale);
          },
          onScaleEnd: (_) {
            if (_zoomDialOpen) _openZoomDial();
          },
          onDoubleTap: () {
            if (_lockedSubjectBox == null) return;
            setState(() {
              _lockedSubjectBox = null;
              _subjectHintVisible = false;
            });
            _showPrompt('已解除主体锁定', 'AI 会重新判断画面主体', 1600);
          },
          onLongPressStart: (details) {
            if (!CameraPrefs.instance.subjectGuide) return;
            final x =
                ((details.localPosition.dx - previewRect.left) /
                        previewRect.width)
                    .clamp(0.0, 1.0);
            final y =
                ((details.localPosition.dy - previewRect.top) /
                        previewRect.height)
                    .clamp(0.0, 1.0);
            const w = 0.34;
            const h = 0.50;
            setState(() {
              _lockedSubjectBox = <double>[
                (x - w / 2).clamp(0.0, 1.0 - w),
                (y - h / 2).clamp(0.0, 1.0 - h),
                w,
                h,
              ];
              _subjectHintVisible = true;
            });
            _showPrompt('已指定为本次 AI 构图主体', '拖动四角可调整范围，双击解除', 2200);
            _subjectHintTimer?.cancel();
            _subjectHintTimer = Timer(const Duration(seconds: 5), () {
              if (mounted) setState(() => _subjectHintVisible = false);
            });
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildPreview(),
              if (_analyzing || _guide != null || _lockedSubjectBox != null)
                GuideOverlay(
                  subjectBox:
                      _lockedSubjectBox ??
                      (_guide?.subjectBox.length == 4
                          ? _toPreviewBox(_guide!.subjectBox)
                          : const []),
                  targetBox: _serverCrop != null
                      ? _toPreviewBox(_serverCrop!)
                      : ((_guide?.targetBox.isNotEmpty ?? false)
                            ? _guide!.targetBox
                            : _planTargetBox(_activePlan)),
                  aligned: _aligned,
                  analyzing: _analyzing,
                  showMapping: _guide != null,
                  showGrid: _gridOn,
                  frameRect: previewRect,
                  alignedBox: _serverCrop != null
                      ? _toPreviewBox(_serverCrop!)
                      : null,
                  confidence: _guide?.progress ?? _alignProgress,
                  subjectLabel: _lockedSubjectBox != null
                      ? '已锁定主体'
                      : _subjectLabel == '主体'
                      ? '拍照主体'
                      : '拍照主体 · $_subjectLabel',
                ),
              if (_lockedSubjectBox != null)
                Positioned.fill(
                  child: SubjectBoxEditor(
                    box: _lockedSubjectBox!,
                    frameRect: previewRect,
                    onChanged: (box) => setState(() {
                      _lockedSubjectBox = box;
                      _subjectHintVisible = true;
                    }),
                    onClear: () => setState(() {
                      _lockedSubjectBox = null;
                      _subjectHintVisible = false;
                    }),
                  ),
                ),
              if (_showExposure)
                Positioned(
                  left: 14,
                  top: previewRect.height / 2 - 70,
                  child: _ExposureBar(value: _exposure),
                ),
            ],
          ),
        );
      },
    );
  }

  List<double> _planTargetBox(_ShotPlan plan) {
    final h = plan.targetHeight.clamp(0.16, 0.80);
    final w = math.min(0.56, h * 0.78);
    return [
      (plan.targetCenterX - w / 2).clamp(0.02, 0.98 - w),
      (plan.targetCenterY - h / 2).clamp(0.02, 0.98 - h),
      w,
      h,
    ];
  }

  Rect _coverRect(Size viewport, Size source) {
    final scale = math.max(
      viewport.width / source.width,
      viewport.height / source.height,
    );
    final width = source.width * scale;
    final height = source.height * scale;
    return Rect.fromLTWH(
      (viewport.width - width) / 2,
      (viewport.height - height) / 2,
      width,
      height,
    );
  }

  FilterPreset get _activeFilter => filterById(_filterId);

  Widget _applyPreviewColor(Widget child) {
    Widget result = ColorFiltered(
      colorFilter: _activeFilter.colorFilter,
      child: child,
    );
    final prefs = CameraPrefs.instance;
    if (!prefs.paletteEnabled) return result;
    result = ColorFiltered(
      colorFilter: ColorFilter.mode(
        prefs.paletteColor.withValues(
          alpha: 0.10 + prefs.paletteStrength * 0.35,
        ),
        BlendMode.softLight,
      ),
      child: result,
    );
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(paletteToneMatrix(prefs.paletteTone)),
      child: result,
    );
  }

  Widget _buildPreview() {
    switch (_status) {
      case CameraStatus.ready:
        final id = _camera.textureId;
        if (id != null) {
          final texture = ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: 1080,
                height: 1920,
                child: Texture(textureId: id),
              ),
            ),
          );
          return _applyPreviewColor(texture);
        }
        return const ColoredBox(color: PrimeColor.black);
      case CameraStatus.demo:
        final image = Image.asset('assets/demo/scene.jpg', fit: BoxFit.cover);
        return _applyPreviewColor(image);
      case CameraStatus.permissionDenied:
      case CameraStatus.unavailable:
        return ColoredBox(
          color: PrimeColor.surface,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _status == CameraStatus.permissionDenied
                      ? Icons.no_photography_outlined
                      : Icons.camera_outlined,
                  color: PrimeColor.white24,
                  size: 40,
                ),
                const SizedBox(height: 12),
                Text(
                  _statusMessage ?? '相机未就绪',
                  style: PrimeType.caption.copyWith(
                    color: PrimeColor.white38,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }

  /// Doka `tvSingleZoomRatio`：36dp 白色 iOS 小圆，黑色 12sp 粗体，
  /// 只在 AI 构图态出现，替代底部的多档倍率胶囊。
  Widget _buildSingleZoomPill() {
    final label = _zoom < 10
        ? '${_zoom.toStringAsFixed(1)}x'
        : '${_zoom.toStringAsFixed(0)}x';
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF333333),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }

  Widget _buildFocalPill() {
    return GestureDetector(
      onLongPress: _openZoomDial,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Container(
          height: 40,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xB3000000),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < _zoomLabels.length; i++)
                GestureDetector(
                  key: ValueKey('zoom-$i'),
                  onTap: i == 0 && !_ultraWideAvailable
                      ? null
                      : () => _selectZoom(i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    width: i == _zoomIndex ? 40 : 31,
                    height: 30,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == _zoomIndex
                          ? PrimeColor.white
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      _zoomLabels[i],
                      style: TextStyle(
                        fontSize: 11,
                        height: 1,
                        letterSpacing: 0.2,
                        color: i == _zoomIndex
                            ? PrimeColor.black
                            : (i == 0 && !_ultraWideAvailable
                                  ? PrimeColor.white24
                                  : PrimeColor.white54),
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAiFilterEntry() {
    return GestureDetector(
      onTap: _openFilterSheet,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0x66000000),
          border: Border.all(color: const Color(0x33FFFFFF), width: 1),
        ),
        alignment: Alignment.center,
        child: _dokaAssetIcon('ic_ai_filter_recom', size: 24, tintWhite: false),
      ),
    );
  }

  // --------------------------------------------------------------- controls

  /// Doka `cameraOptionFixed`：48dp 高、左右 20dp、5 个 24dp 图标。
  /// 分析时只保留多景别/比例，中间换成扫描状态；对齐后不改成 3 图标布局。
  Widget _buildDokaOptionRow() {
    // Doka 的固定选项行是 5 个等宽图标：# / 主体 / 3:4 / 前后摄 / 调色盘。
    // AI 构图态收起为主体、比例、前后摄 3 个，和 1.3.20 截图一致。
    if (_analyzing || _guide != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              Expanded(child: Center(child: _multiComposeOption())),
              Expanded(child: Center(child: _ratioOption())),
              Expanded(child: Center(child: _flipOption())),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(child: Center(child: _multiComposeOption())),
            Expanded(child: Center(child: _subjectOption())),
            Expanded(child: Center(child: _ratioOption())),
            Expanded(child: Center(child: _flipOption())),
            Expanded(child: Center(child: _paletteOption())),
          ],
        ),
      ),
    );
  }

  Widget _multiComposeOption() {
    return GestureDetector(
      key: const ValueKey('plan-button'),
      onTap: _openPlanSheet,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(child: _dokaAssetIcon('ic_multi_compose', size: 24)),
      ),
    );
  }

  Widget _subjectOption() {
    return GestureDetector(
      onTap: _beginSubjectSelection,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: _dokaAssetIcon(
            'ic_subject_selection',
            size: 24,
            opacity: _lockedSubjectBox == null ? 0.72 : 1.0,
          ),
        ),
      ),
    );
  }

  Widget _paletteOption() {
    final active = CameraPrefs.instance.paletteEnabled;
    return GestureDetector(
      onTap: _openPalette,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: _dokaAssetIcon(
            'ic_palette',
            size: 26,
            opacity: active ? 1.0 : 0.72,
          ),
        ),
      ),
    );
  }

  void _beginSubjectSelection() {
    setState(() => _subjectHintVisible = true);
    _subjectHintTimer?.cancel();
    _subjectHintTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _subjectHintVisible = false);
    });
    if (!_analyzing && _live) _startAi();
    _showPrompt('指定 AI 构图主体', '长按取景框里的人或物，出现黄色四角框即为锁定', 2200);
  }

  void _openPalette() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => PaletteSheet(onChanged: () => setState(() {})),
    );
  }

  Widget _ratioOption() {
    return GestureDetector(
      key: const ValueKey('ratio-button'),
      onTap: _openRatioSheet,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(child: _dokaAssetIcon('ic_ratio_3_4', size: 24)),
      ),
    );
  }

  Widget _flipOption() {
    return GestureDetector(
      onTap: _switchCamera,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(child: _dokaAssetIcon('ic_switch', size: 24)),
      ),
    );
  }

  /// Doka `cameraFunction`：96dp 高、左右 10dp、底部 12dp；
  /// 滤镜 60、快门 70、AI 扫描切换 60，分布在 25% / 50% / 75%。
  Widget _buildDokaFunctionRow() {
    final composing = _analyzing || _guide != null;
    return Container(
      height: 96,
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 12),
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: _openFilterSheet,
                behavior: HitTestBehavior.opaque,
                child: _buildFilterThumb(),
              ),
            ),
          ),
          Expanded(child: Center(child: _buildShutterButton())),
          Expanded(
            child: Center(
              child: GestureDetector(
                key: const ValueKey('ai-compose'),
                onTap: _analyzing || composing ? _exitCompose : _startAi,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 60,
                  height: 64,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _dokaAssetIcon(
                        composing ? 'ic_close' : 'ic_ai_scan',
                        size: 28,
                      ),
                      if (composing) ...[
                        const SizedBox(height: 5),
                        const Text(
                          '取消',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1,
                            color: Colors.white,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Doka `cameraFilter` 的 60dp 滤镜缩略图：当前滤镜渲染后的小图 +
  /// 左上角两行白色滤镜名，不再是单独的“无滤镜”相机图标。
  Widget _buildFilterThumb() {
    final name = _activeFilter.id == 'none' ? '原片' : _activeFilter.name;
    final words = name.replaceAll(' ', '\n');
    return SizedBox(
      width: 58,
      height: 74,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColorFiltered(
              colorFilter: _activeFilter.colorFilter,
              child: Image.asset('assets/demo/scene.jpg', fit: BoxFit.cover),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(5, 14, 5, 4),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xCC000000)],
                  ),
                ),
                child: Text(
                  words,
                  maxLines: 2,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    height: 1.05,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24, width: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShutterButton() {
    return GestureDetector(
      key: const ValueKey('shutter'),
      onTapDown: (_) => _capture(),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _capturing ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: SizedBox(
          width: 70,
          height: 70,
          child: Center(child: _dokaAssetIcon('ic_capture', size: 64)),
        ),
      ),
    );
  }

  Widget _buildPermissionCard() {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.6),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(18),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            color: const Color(0xF20A0A0A),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: PrimeColor.white12, width: 0.8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.camera_outlined,
                size: 28,
                color: PrimeColor.white54,
              ),
              const SizedBox(height: 12),
              const Text(
                '需要相机权限',
                style: TextStyle(
                  fontSize: 17,
                  height: 1.2,
                  color: PrimeColor.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '允许定焦使用相机，才能看到实时取景和构图引导。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: PrimeColor.white54,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _primaryButton('允许使用相机', _requestPermission)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _outlineButton('去设置', () => _camera.openSettings()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _primaryButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: PrimeColor.white,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: PrimeColor.black,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _outlineButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: PrimeColor.white24, width: 0.8),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: PrimeColor.white54,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ distance card

/// Doka 式“距离导演”卡：不是泛泛一句“走近一点”，而是给出约数、
/// 最近/最远建议距离，并让用户按「开始构图」进入对位。
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.selected,
    required this.onSelect,
    required this.onDetail,
    this.recommended = 'none',
    this.recommendedName = '',
    this.displayStyle = 'panel',
  });

  final String selected;
  final void Function(String id, String label) onSelect;
  final void Function(FilterPreset filter) onDetail;
  final String recommended;
  final String recommendedName;
  final String displayStyle;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String _selected = widget.selected;
  FilterCategory? _category = FilterCategory.base;

  @override
  void initState() {
    super.initState();
    final current = filterById(widget.selected);
    _category = current.category;
  }

  @override
  Widget build(BuildContext context) {
    final items = filtersByCategory(_category);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: const BoxDecoration(
          color: Color(0xFF0B0B0B),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Color(0x22FFFFFF))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '相机滤镜',
                  style: TextStyle(
                    fontSize: 17,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Doka 胶片库',
                  style: TextStyle(fontSize: 10, color: Colors.white38),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: Colors.white38,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (widget.displayStyle == 'full' &&
                widget.recommended != 'none' &&
                widget.recommendedName.isNotEmpty)
              GestureDetector(
                onTap: () => widget.onDetail(filterById(widget.recommended)),
                child: Container(
                  height: 104,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF1B3B42),
                        const Color(0xFF0E1518).withValues(alpha: 0.9),
                      ],
                    ),
                    border: Border.all(
                      color: const Color(0xFF7ECFC8).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.white10,
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.auto_awesome,
                            color: Color(0xFF7ECFC8),
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'AI 推荐',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF7ECFC8),
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              widget.recommendedName,
                              style: const TextStyle(
                                fontSize: 18,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '点开查看原片 / 滤镜两联样片',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white38,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white38,
                      ),
                    ],
                  ),
                ),
              ),
            SizedBox(
              height: 30,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final category in FilterCategory.values) ...[
                    GestureDetector(
                      onTap: () => setState(() => _category = category),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: category == _category
                              ? Colors.white
                              : Colors.white10,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          category.label,
                          style: TextStyle(
                            fontSize: 11,
                            color: category == _category
                                ? Colors.black
                                : Colors.white60,
                            fontWeight: category == _category
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 112,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final filter = items[index];
                  final active = filter.id == _selected;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selected = filter.id);
                      widget.onSelect(filter.id, filter.name);
                    },
                    onLongPress: () => widget.onDetail(filter),
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: 72,
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: active
                                        ? Colors.white
                                        : Colors.white12,
                                    width: active ? 1.6 : 0.8,
                                  ),
                                ),
                                child: ColorFiltered(
                                  colorFilter: filter.colorFilter,
                                  child: Image.asset(
                                    'assets/demo/scene.jpg',
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              if (filter.pro)
                                Positioned(
                                  right: 5,
                                  top: 5,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFC9A86A),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'PRO',
                                      style: TextStyle(
                                        fontSize: 7,
                                        color: Colors.black,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Text(
                            filter.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: active ? Colors.white : Colors.white54,
                              fontWeight: active
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _category == FilterCategory.base
                  ? '原片与基础调色；继续左滑切换胶片系列。'
                  : '${_category?.label ?? '全部'} · ${items.length} 款；带 PRO 标记的滤镜属于 Doka Pro 胶片库。',
              style: const TextStyle(fontSize: 10, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanSheet extends StatelessWidget {
  const _PlanSheet({
    required this.plans,
    required this.selectedIndex,
    required this.sceneAsset,
    required this.onSelect,
    required this.sceneTitle,
  });

  final List<_ShotPlan> plans;
  final int selectedIndex;
  final String? sceneAsset;
  final ValueChanged<int> onSelect;
  final String sceneTitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: PrimeColor.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 3,
                  decoration: BoxDecoration(
                    color: PrimeColor.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                sceneTitle,
                style: const TextStyle(
                  fontSize: 20,
                  height: 1.2,
                  color: PrimeColor.white,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                '可以逐个试拍，多拍几种更容易出片',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: PrimeColor.white54,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 190,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: plans.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final plan = plans[index];
                    final selected = plan.index == selectedIndex;
                    return GestureDetector(
                      onTap: () => onSelect(plan.index),
                      behavior: HitTestBehavior.opaque,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 126,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: PrimeColor.white06,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? PrimeColor.white54
                                : PrimeColor.white12,
                            width: selected ? 1.2 : 0.8,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(9),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (sceneAsset != null)
                                      Image.asset(
                                        sceneAsset!,
                                        fit: BoxFit.cover,
                                        alignment: plan.alignment,
                                      )
                                    else
                                      const ColoredBox(
                                        color: PrimeColor.surfaceLift,
                                      ),
                                    const DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Color(0x00000000),
                                            Color(0x99000000),
                                          ],
                                          stops: [0.55, 1.0],
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: 8,
                                      right: 8,
                                      bottom: 7,
                                      child: Text(
                                        '${index + 1}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: PrimeColor.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              child: Text(
                                '${index + 1}  ${plan.title}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.2,
                                  color: PrimeColor.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              child: Text(
                                plan.recommendedDistance > 0
                                    ? '${plan.zoomLabel} · ${plan.framing} · 约 ${plan.recommendedDistance.toStringAsFixed(1)} 米'
                                    : '${plan.zoomLabel} · ${plan.framing}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  height: 1.2,
                                  color: PrimeColor.white54,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RatioSheet extends StatelessWidget {
  const _RatioSheet({required this.selected, required this.onSelect});

  final CaptureRatio selected;
  final ValueChanged<CaptureRatio> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: PrimeColor.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 3,
                  decoration: BoxDecoration(
                    color: PrimeColor.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '取景比例',
                style: TextStyle(
                  fontSize: 20,
                  height: 1.2,
                  color: PrimeColor.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                '宽度铺满屏幕，高度由比例决定',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: PrimeColor.white54,
                ),
              ),
              const SizedBox(height: 18),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 5,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.78,
                children: [
                  for (final ratio in CaptureRatio.values)
                    GestureDetector(
                      key: ValueKey('ratio-${ratio.name}'),
                      onTap: () => onSelect(ratio),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        decoration: BoxDecoration(
                          color: PrimeColor.white06,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: ratio == selected
                                ? PrimeColor.white70
                                : PrimeColor.white12,
                            width: ratio == selected ? 1.2 : 0.8,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 32,
                              height: (32 * ratio.heightOverWidth).clamp(
                                18,
                                48,
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(
                                    color: PrimeColor.white38,
                                    width: 0.8,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              ratio.label,
                              style: TextStyle(
                                fontSize: 11,
                                color: ratio == selected
                                    ? PrimeColor.white
                                    : PrimeColor.white54,
                                fontWeight: ratio == selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExposureBar extends StatelessWidget {
  const _ExposureBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final t = (value + 2) / 4;
    return Container(
      width: 34,
      height: 140,
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: PrimeColor.white12, width: 0.8),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(
            value >= 0
                ? '+${value.toStringAsFixed(1)}'
                : value.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 9,
              color: PrimeColor.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(width: 2, color: PrimeColor.white24),
                  Align(
                    alignment: Alignment(0, 1 - t * 2),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Color(0xFF7ECFC8),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Text(
            'EV',
            style: TextStyle(fontSize: 8, color: PrimeColor.white38),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Doka `selector_camera_live_photo` 的白点环实况图标。
class _LivePhotoGlyph extends CustomPainter {
  const _LivePhotoGlyph({required this.on});

  final bool on;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: on ? 0.95 : 0.62)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final dot = Paint()
      ..color = Colors.white.withValues(alpha: on ? 0.95 : 0.62);
    const count = 30;
    final radius = size.width * 0.43;
    for (var i = 0; i < count; i++) {
      final a = i * math.pi * 2 / count;
      canvas.drawCircle(
        c + Offset(math.cos(a), math.sin(a)) * radius,
        0.85,
        dot,
      );
    }
    canvas.drawCircle(c, size.width * 0.22, paint..strokeWidth = 2.2);
    if (!on) {
      final slash = Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(c + const Offset(-6, 6), c + const Offset(6, -6), slash);
    }
  }

  @override
  bool shouldRepaint(covariant _LivePhotoGlyph old) => old.on != on;
}
