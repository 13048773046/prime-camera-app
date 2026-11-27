import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

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
import '../widgets/guide_ring.dart';
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

enum CaptureRatio { threeFour, oneOne, sixteenNine }

extension CaptureRatioX on CaptureRatio {
  String get label => switch (this) {
    CaptureRatio.threeFour => '3:4',
    CaptureRatio.oneOne => '1:1',
    CaptureRatio.sixteenNine => '16:9',
  };

  /// 预览高 / 宽。
  double get heightOverWidth => switch (this) {
    CaptureRatio.threeFour => 4 / 3,
    CaptureRatio.oneOne => 1,
    CaptureRatio.sixteenNine => 9 / 16,
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
  bool _capturing = false;
  bool _flash = false;
  bool _flashOn = false;
  bool _ultraWideAvailable = true;
  bool _gridOn = false;
  bool _planSheetOpen = false;
  ComposeResult? _guide;
  Timer? _alignTimer;
  Timer? _analyzeTimer;
  Timer? _frameWatchdog;
  Timer? _promptTimer;
  Timer? _distanceTimer;
  bool _distanceCardOpen = false;
  bool _distanceCardDismissed = false;
  StreamSubscription<GuidanceFrame>? _guidanceSub;
  StreamSubscription<CameraFrameTick>? _frameSub;
  final LiveComposer _composer = const LiveComposer();
  final ScanApi _scanApi = ScanApi();
  Timer? _scanTimer;
  bool _scanInFlight = false;
  List<double>? _serverCrop;
  List<double>? _lockedSubjectBox;
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

  static const List<double> _zoomValues = [0.5, 1.0, 2.0, 5.0];
  static const List<String> _zoomLabels = ['.5', '1x', '2', '5'];

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
    _distanceTimer?.cancel();
    _exposureTimer?.cancel();
    _alignConfirmTimer?.cancel();
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
    for (final plan in _currentPlans) {
      if (plan.index == _zoomIndex) return plan;
    }
    return _currentPlans.first;
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
      _analyzing =
          init.status == CameraStatus.ready || init.status == CameraStatus.demo;
      _guide = null;
      _lockedSubjectBox = null;
      _aligned = false;
      _alignProgress = 0.12;
    });
    if (_live) {
      _startLiveGuidance();
    } else if (init.status == CameraStatus.demo) {
      _startDemoAnalysis();
    } else if (init.status == CameraStatus.unavailable) {
      setState(() => _analyzing = false);
    }
  }

  void _startDemoAnalysis() {
    _alignTimer?.cancel();
    _resetDistanceCard();
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
    _showPrompt('你好，我是流小萤', '正在看你的画面和光线', 2400);
    _analyzeTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _analyzing = false);
      _showPrompt('看好了', '选一个拍法，我带你对准主体', 2000);
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

  void _resetDistanceCard() {
    _distanceTimer?.cancel();
    _distanceCardOpen = false;
    _distanceCardDismissed = false;
  }

  void _maybeShowDistanceCard(ComposeResult guide) {
    if (!mounted || _distanceCardOpen || _distanceCardDismissed) return;
    if (_analyzing || guide.distanceMeters == null || guide.confidence <= 0) {
      return;
    }
    if (_status != CameraStatus.ready && _status != CameraStatus.demo) return;
    setState(() => _distanceCardOpen = true);
    _distanceTimer?.cancel();
    _distanceTimer = Timer(const Duration(seconds: 7), () {
      if (mounted) setState(() => _distanceCardOpen = false);
    });
  }

  void _dismissDistanceCard({bool start = false}) {
    _distanceTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _distanceCardOpen = false;
      _distanceCardDismissed = true;
    });
    if (start) {
      final plan = _activePlan;
      final placement = plan.targetCenterX < 0.45
          ? '左三分'
          : (plan.targetCenterX > 0.58 ? '右三分' : '中间');
      _showPrompt('开始构图', '把主体放进$placement的黄色目标环', 2200);
    }
  }

  void _startLiveGuidance() {
    _resetDistanceCard();
    _guidanceSub?.cancel();
    _frameSub?.cancel();
    _scanTimer?.cancel();
    _frameWatchdog?.cancel();
    _alignTimer?.cancel();
    _analyzeTimer?.cancel();
    _lastGuidanceTs = 0;
    _lastFrameTs = 0;
    _restartAttempts = 0;
    _serverCrop = null;
    _scanInFlight = false;
    _wasAligned = false;
    setState(() {
      _composeEnabled = true;
      _analyzing = true;
      _guide = null;
      _lockedSubjectBox = null;
      _aligned = false;
      _alignProgress = 0.12;
      _lastActionLabel = null;
    });
    _showPrompt('你好，我是流小萤', '正在看你的画面和光线', 2500);
    _startScanLoop();
    _guidanceSub = _camera.guidanceStream.listen(_onGuidanceFrame);
    _frameSub = _camera.frameStream.listen((tick) {
      _lastFrameTs = tick.ts;
    });
    _startFrameWatchdog();
    // 原生首帧约 100–300ms；先留 1.8 秒“稳住手机”的分析态。
    _analyzeTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _analyzing = false);
      if (_guide == null || !_isAlignedGuide(_guide!)) {
        _showPrompt('看好了', '选一个拍法，我带你对准主体', 2000);
      }
    });
  }

  /// Doka 是“客户端抓帧 → 服务端 scan 给方案 → 客户端跟踪”。
  /// 这里保留同样的时序，但只有配置了 PRIME_API_BASE 才发请求；
  /// 没有后端时端侧 Vision 仍然独立工作，不会出现空转或卡顿。
  void _startScanLoop() {
    _scanTimer?.cancel();
    _serverCrop = null;
    _lastServerReason = '';
    if (!_scanApi.enabled) return;
    _scanTimer = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      _scanCurrentFrame();
    });
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
        zoom: _zoomValues[_zoomIndex],
        tilt: _lastPitch,
        roll: _lastRoll,
        subjectBox: _lockedSubjectBox ?? _guide?.subjectBox,
        subjectKind: _scene == SceneMode.portrait ? 'person' : 'object',
      );
      if (!mounted || plan == null) return;
      final rect = plan.cropRect;
      if (rect.length != 4 || rect[2] <= 0 || rect[3] <= 0) return;
      setState(() {
        _serverCrop = rect;
        _recommendedFilterName = plan.filterName;
        _recommendedFilterId = plan.filterId;
      });
      if (!_aligned && plan.reason.isNotEmpty && plan.reason != _lastServerReason) {
        _lastServerReason = plan.reason;
        _showPrompt('小萤看过画面', plan.reason, 1900);
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

  void _onGuidanceFrame(GuidanceFrame frame) {
    if (!mounted || !_live || !_composeEnabled) return;
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
      zoom: _zoomValues[_zoomIndex],
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
      _alignProgress = newlyAligned ? 1.0 : guide.progress;
      if (!newlyAligned) _aligned = false;
    });
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
    _maybeShowDistanceCard(guide);
    if (newlyAligned && !_wasAligned) {
      HapticFeedback.lightImpact();
      _showPrompt('构图已锁定', '可以按快门', 1500);
    } else if (!_analyzing &&
        guide.confidence > 0 &&
        guide.actionLabel != _lastActionLabel) {
      _showPrompt('小萤建议', guide.hint, 1700);
    }
    _lastActionLabel = guide.actionLabel;
    _wasAligned = newlyAligned;
  }

  bool _isAlignedGuide(ComposeResult guide) =>
      guide.actionLabel == '已对齐' || guide.hint.startsWith('可以拍了');

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
    final preset = _presetFor(_zoomIndex, _scene);
    setState(() {
      _guide = preset;
      _alignProgress = 0.12;
      _aligned = false;
    });
    _maybeShowDistanceCard(preset);
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
    _distanceTimer?.cancel();
    setState(() {
      _composeEnabled = false;
      _analyzing = false;
      _guide = null;
      _lockedSubjectBox = null;
      _aligned = false;
      _alignProgress = 0.12;
      _distanceCardOpen = false;
      _distanceCardDismissed = true;
      _lastActionLabel = null;
    });
    _showPrompt('已退出构图', '自由取景，随时可以再进 AI 构图', 1700);
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
    if (nearest != _zoomIndex) setState(() => _zoomIndex = nearest);
  }

  Future<void> _selectZoom(int index) async {
    if (index == 0 && !_ultraWideAvailable) return;
    _resetDistanceCard();
    if (_zoomIndex == index) return;
    setState(() => _zoomIndex = index);
    // 先让演示口令立刻跟手，再等原生回报实际可用倍率。
    if (!_live && _status == CameraStatus.demo) _startCommandCycle();
    final actual = await _camera.setZoom(_zoomValues[index]);
    if (!mounted || actual == null) return;
    final nearest = _nearestZoomIndex(actual);
    if (nearest != _zoomIndex) setState(() => _zoomIndex = nearest);
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
      exposure: _exposure,
    );
    await Future.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    if (path != null && path.isNotEmpty) {
      _recentPhotos.insert(0, path);
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
        onSelect: (id, label) {
          Navigator.of(sheetContext).pop();
          if (id == _filterId) return;
          if (filterById(id).pro && !CameraPrefs.instance.isPro) {
            _showPrompt('Doka Pro 胶片', '$label 需要 Pro；在“我的 → 兑换码”输入 PRIME2026', 2600);
            return;
          }
          setState(() => _filterId = id);
          _showPrompt('滤镜 · $label', '已套用到取景与下一张照片', 1800);
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
        selectedIndex: _zoomIndex,
        sceneTitle: switch (_scene) {
          SceneMode.portrait => '小萤的 3 种拍法',
          SceneMode.street => '街道的 3 种拍法',
          SceneMode.landscape => '风景的 3 种拍法',
          SceneMode.still => '静物的 3 种拍法',
          SceneMode.general => '这个场景的 3 种拍法',
        },
        sceneAsset: _status == CameraStatus.demo
            ? 'assets/demo/scene.jpg'
            : null,
        onSelect: (index) {
          Navigator.of(sheetContext).pop();
          _selectZoom(index);
        },
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _planSheetOpen = false);
    });
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
    if (!mounted) return;
    final changed = _scene != CameraPrefs.instance.scene;
    setState(() {
      _scene = CameraPrefs.instance.scene;
      _sceneLocked = _scene != SceneMode.general;
      _gridOn = CameraPrefs.instance.grid;
      _flashOn = CameraPrefs.instance.flash;
    });
    if (changed) {
      _resetDistanceCard();
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

  /// 照着 Doka 相机页的结构重排：
  /// 3:4 圆角取景窗 → 48dp 固定选项行 → 96dp 功能行 → 52dp 玻璃三栏导航。
  /// 取景窗和功能行之间不再留一大块空白，也不再在画面里放品牌标题。
  Widget _buildFramedLayout() {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final maxHeight = constraints.maxHeight;
          const bottomReserve = 238.0;
          final maxStageHeight = math.max(220.0, maxHeight - bottomReserve);
          final fullWidthHeight = maxWidth * _ratio.heightOverWidth;
          double stageHeight = math.min(fullWidthHeight, maxStageHeight);
          double stageWidth = stageHeight / _ratio.heightOverWidth;
          if (stageWidth > maxWidth) {
            stageWidth = maxWidth;
            stageHeight = stageWidth * _ratio.heightOverWidth;
          }

          return Column(
            children: [
              SizedBox(
                width: maxWidth,
                height: stageHeight,
                child: Center(
                  child: SizedBox(
                    width: stageWidth,
                    height: stageHeight,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildStage(),
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: 104,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.50),
                                      Colors.black.withValues(alpha: 0.14),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: _buildTopBar(),
                          ),
                          if (_promptTitle != null)
                            Positioned(
                              top: 58,
                              left: 18,
                              right: 18,
                              child: _buildPromptChip(),
                            ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 10,
                            child: _buildFocalPill(),
                          ),
                          Positioned(
                            right: 12,
                            bottom: 10,
                            child: _buildAiFilterEntry(),
                          ),
                          if (_recommendedFilterId != 'none' &&
                              _recommendedFilterId != _filterId)
                            Positioned(
                              right: 10,
                              bottom: 56,
                              child: _buildAiRecommendationChip(),
                            ),
                          if (_distanceCardOpen && _guide != null)
                            Positioned(
                              left: 30,
                              right: 30,
                              bottom: 58,
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: 1),
                                duration: const Duration(milliseconds: 340),
                                curve: Curves.easeOutCubic,
                                builder: (context, value, child) => Opacity(
                                  opacity: value,
                                  child: Transform.translate(
                                    offset: Offset(0, 18 * (1 - value)),
                                    child: Transform.scale(
                                      scale: 0.96 + 0.04 * value,
                                      child: child,
                                    ),
                                  ),
                                ),
                                child: _DistanceCard(
                                  guide: _guide!,
                                  plan: _activePlan,
                                  scene: _scene,
                                  onStart: () =>
                                      _dismissDistanceCard(start: true),
                                  onClose: _dismissDistanceCard,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              _buildDokaOptionRow(),
              _buildDokaFunctionRow(),
              const Spacer(),
              _buildDokaTabBar(),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------- header

  /// Doka 顶栏只有左上「主体选择」和右上「设置」，没有品牌字和三个工具图标。
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Row(
        children: [
          _glassTopButton(
            Icons.visibility_off_outlined,
            _startAi,
            tooltip: '重新识别主体',
          ),
          const Spacer(),
          _glassTopButton(
            Icons.settings_outlined,
            _openSettings,
            tooltip: '设置',
          ),
        ],
      ),
    );
  }

  Widget _glassTopButton(IconData icon, VoidCallback onTap, {String? tooltip}) {
    final button = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.10),
          border: Border.all(color: PrimeColor.white12, width: 0.8),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 21, color: PrimeColor.white70),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
  // ----------------------------------------------------------------- stage

  Widget _buildStage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final previewRect = _coverRect(viewport, const Size(1080, 1920));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final x = ((details.localPosition.dx - previewRect.left) /
                    previewRect.width)
                .clamp(0.0, 1.0);
            final y = ((details.localPosition.dy - previewRect.top) /
                    previewRect.height)
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
            final next = (_exposure - details.delta.dy / 90)
                .clamp(-2.0, 2.0);
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
          onDoubleTap: () {
            if (_lockedSubjectBox == null) return;
            setState(() => _lockedSubjectBox = null);
            _showPrompt('已解除主体锁定', 'AI 会重新判断画面主体', 1600);
          },
          onLongPressStart: (details) {
            if (!CameraPrefs.instance.subjectGuide) return;
            final x = ((details.localPosition.dx - previewRect.left) /
                    previewRect.width)
                .clamp(0.0, 1.0);
            final y = ((details.localPosition.dy - previewRect.top) /
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
            });
            _showPrompt('主体已锁定', 'AI 会优先分析框内的人或物；长按可重新框选，双击解除', 2200);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildPreview(),
              IgnorePointer(
                child: CustomPaint(painter: _ViewfinderGradePainter()),
              ),
              IgnorePointer(
                child: GuideOverlay(
                  subjectBox: _lockedSubjectBox ?? _guide?.subjectBox ?? const [],
                  targetBox: (_guide?.targetBox.isNotEmpty ?? false)
                      ? _guide!.targetBox
                      : _scene.defaultTargetBox,
                  aligned: _aligned,
                  analyzing: _analyzing,
                  showGrid: _gridOn,
                  frameRect: previewRect,
                  alignedBox: _serverCrop,
                  subjectLabel: _lockedSubjectBox != null
                      ? '已锁定主体'
                      : _subjectLabel == '主体'
                          ? '拍照主体'
                          : '拍照主体 · $_subjectLabel',
                ),
              ),
              if (CameraPrefs.instance.level)
                IgnorePointer(
                  child: CustomPaint(
                    painter: _LevelPainter(
                      roll: _lastRoll,
                      pitch: _lastPitch,
                    ),
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
          return ColorFiltered(
            colorFilter: _activeFilter.colorFilter,
            child: texture,
          );
        }
        return const ColoredBox(color: PrimeColor.black);
      case CameraStatus.demo:
        final image = Image.asset('assets/demo/scene.jpg', fit: BoxFit.cover);
        return ColorFiltered(
          colorFilter: _activeFilter.colorFilter,
          child: image,
        );
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

  /// 顶部阶段性小提示：出现 2–3 秒后自动消失，不占常驻版面。
  Widget _buildPromptChip() {
    final title = _promptTitle ?? '';
    final subtitle = _promptSubtitle;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
              decoration: BoxDecoration(
                color: const Color(0xE60A0A0A),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: PrimeColor.white12, width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _SparkleMark(size: 14, color: PrimeColor.white70),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.1,
                            color: PrimeColor.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PrimeType.caption.copyWith(
                              color: PrimeColor.white54,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFocalPill() {
    return Center(
      child: Container(
        height: 38,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0x99000000),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: PrimeColor.white12, width: 0.8),
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
                  width: i == _zoomIndex ? 42 : 34,
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
    );
  }

  Widget _buildAiRecommendationChip() {
    return GestureDetector(
      onTap: () {
        setState(() => _filterId = _recommendedFilterId);
        _showPrompt('AI 推荐 · $_recommendedFilterName', '已套用到取景与下一张照片', 1800);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 5, 10, 5),
        decoration: BoxDecoration(
          color: const Color(0xE60A0A0A),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFF7ECFC8).withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SparkleMark(size: 10, color: Color(0xFF7ECFC8)),
            const SizedBox(width: 5),
            Text(
              'AI 推荐 $_recommendedFilterName',
              style: const TextStyle(fontSize: 9, color: PrimeColor.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiFilterEntry() {
    return GestureDetector(
      onTap: _openFilterSheet,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.32),
          border: Border.all(color: PrimeColor.white24, width: 0.8),
        ),
        alignment: Alignment.center,
        child: const _SparkleMark(size: 18, color: PrimeColor.white70),
      ),
    );
  }

  // --------------------------------------------------------------- controls

  Widget _buildDokaOptionRow() {
    final composing = _guide != null && !_analyzing;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        height: 48,
        child: composing
            ? Row(
                children: [
                  SizedBox(
                    width: 70,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _multiComposeOption(),
                    ),
                  ),
                  Expanded(child: Center(child: _buildSwitchPlanCapsule())),
                  SizedBox(
                    width: 70,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _ratioOption(),
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _multiComposeOption(),
                  _subjectOption(),
                  _ratioOption(),
                  _flipOption(),
                ],
              ),
      ),
    );
  }

  Widget _multiComposeOption() {
    return GestureDetector(
      onTap: _openPlanSheet,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Align(
              child: Icon(
                Icons.auto_awesome_mosaic_outlined,
                size: 24,
                color: PrimeColor.white38,
              ),
            ),
            Positioned(
              top: 2,
              right: -10,
              child: Container(
                height: 12,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: PrimeColor.white12,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: PrimeColor.white12, width: 0.6),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Beta',
                  style: TextStyle(fontSize: 7, color: PrimeColor.white70),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _subjectOption() {
    return GestureDetector(
      onTap: _startAi,
      behavior: HitTestBehavior.opaque,
      child: const SizedBox(
        width: 48,
        height: 48,
        child: Icon(
          Icons.center_focus_weak_rounded,
          size: 24,
          color: PrimeColor.white70,
        ),
      ),
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
        child: Center(
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: PrimeColor.white54, width: 1),
            ),
            alignment: Alignment.center,
            child: Text(
              _ratio.label,
              style: const TextStyle(
                fontSize: 8,
                height: 1,
                color: PrimeColor.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _flipOption() {
    return GestureDetector(
      onTap: _switchCamera,
      behavior: HitTestBehavior.opaque,
      child: const SizedBox(
        width: 48,
        height: 48,
        child: Icon(
          Icons.cameraswitch_outlined,
          size: 24,
          color: PrimeColor.white70,
        ),
      ),
    );
  }

  Widget _buildSwitchPlanCapsule() {
    return GestureDetector(
      key: const ValueKey('plan-button'),
      onTap: _openPlanSheet,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 36,
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            colors: [
              Color(0xFFE8FFFC),
              Color(0xFFB1CFFF),
              Color(0xFFFFD2F6),
              Color(0xFFFFC38F),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xE612161C),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.crop_free_rounded,
                size: 14,
                color: Color(0xFFFFD2F6),
              ),
              const SizedBox(width: 7),
              Text(
                '切换构图方案',
                style: PrimeType.caption.copyWith(
                  color: PrimeColor.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: PrimeColor.white54,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDokaFunctionRow() {
    return SizedBox(
      height: 96,
      child: Stack(
        children: [
          Positioned(
            left: 12,
            top: 10,
            child: _functionAction(
              icon: Icons.camera_alt_outlined,
              label: '相机滤镜',
              onTap: _openFilterSheet,
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [_buildShutterButton()],
            ),
          ),
          Positioned(
            right: 12,
            top: 10,
            child: _functionAction(
              icon: _composeEnabled && _guide != null && !_analyzing
                  ? Icons.close_rounded
                  : Icons.auto_awesome,
              label: _analyzing
                  ? '分析中'
                  : (_composeEnabled && _guide != null ? '退出构图' : 'AI 构图'),
              onTap: _composeEnabled && _guide != null && !_analyzing
                  ? _exitCompose
                  : _startAi,
              active: _analyzing || (_composeEnabled && _guide != null),
            ),
          ),
        ],
      ),
    );
  }

  Widget _functionAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 66,
        height: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 32,
              color: active ? PrimeColor.white : PrimeColor.white70,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                height: 1,
                color: active ? PrimeColor.white : PrimeColor.white70,
                fontWeight: FontWeight.w500,
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
          width: 76,
          height: 76,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(76, 76),
                painter: _ShutterProgressPainter(
                  progress: _alignProgress,
                  aligned: _aligned,
                ),
              ),
              Container(
                width: 72,
                height: 72,
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const SweepGradient(
                    colors: [
                      Color(0xFFE8FFFC),
                      Color(0xFF80EEFF),
                      Color(0xFFB1CFFF),
                      Color(0xFFFFD2F6),
                      Color(0xFFFFC38F),
                      Color(0xFFE8FFFC),
                    ],
                  ),
                  boxShadow: _aligned
                      ? [
                          BoxShadow(
                            color: const Color(0xFFFFD2F6)
                                .withValues(alpha: 0.24),
                            blurRadius: 22,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: ClipOval(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/ai/liuxiaoying_face.png',
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const ColoredBox(color: Color(0xFF17171A)),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 5,
                        child: Text(
                          '流小萤',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 7.5,
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.92),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            shadows: const [
                              Shadow(
                                color: Color(0xCC000000),
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDokaTabBar() {
    return Center(
      child: Container(
        width: 310,
        height: 52,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: PrimeColor.white12, width: 0.8),
        ),
        child: Row(
          children: [
            Expanded(child: _tabItem('相机', active: true)),
            Expanded(child: _tabItem('相册', onTap: _openGallery)),
            Expanded(child: _tabItem('我的', onTap: _openMine)),
          ],
        ),
      ),
    );
  }

  Widget _tabItem(String label, {bool active = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: active ? PrimeColor.white12 : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            height: 1,
            color: active ? PrimeColor.white : const Color(0xFFBFBFBF),
            fontWeight: FontWeight.w600,
          ),
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
class _DistanceCard extends StatelessWidget {
  const _DistanceCard({
    required this.guide,
    required this.plan,
    required this.scene,
    required this.onStart,
    required this.onClose,
  });

  final ComposeResult guide;
  final _ShotPlan plan;
  final SceneMode scene;
  final VoidCallback onStart;
  final VoidCallback onClose;

  double get _distance => guide.distanceMeters ?? plan.recommendedDistance;
  double get _recommended =>
      guide.recommendedDistance ??
      (plan.recommendedDistance > 0 ? plan.recommendedDistance : _distance);
  double get _near => guide.nearDistance ?? math.max(0.4, _recommended - 0.45);
  double get _far => guide.farDistance ?? _recommended + 0.75;

  bool get _isPortrait => scene == SceneMode.portrait;

  String get _title {
    if (!_isPortrait || _recommended <= 0) return '把主体放进目标环';
    if (_distance < _recommended - 0.55) return '再退一点';
    if (_distance > _recommended + 0.75) return '再近一点';
    return '距离合适';
  }

  String get _subtitle {
    if (!_isPortrait || _recommended <= 0) {
      return '约 ${_distance.toStringAsFixed(1)} 米 · 跟着黄色主体框微移';
    }
    if (_distance < _recommended - 0.55) {
      return '约 ${_distance.toStringAsFixed(1)} 米 · 可继续后退，人物会更完整';
    }
    if (_distance > _recommended + 0.75) {
      return '约 ${_distance.toStringAsFixed(1)} 米 · 再靠近，人物会更突出';
    }
    return '约 ${_distance.toStringAsFixed(1)} 米 · 位置刚好，按开始构图锁定';
  }

  bool get _good => _isPortrait && (_distance - _recommended).abs() <= 0.65;

  @override
  Widget build(BuildContext context) {
    final progress = ((_distance - _near) / math.max(0.01, _far - _near)).clamp(
      0.05,
      0.95,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            color: const Color(0xF20C0C0E),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: PrimeColor.white12, width: 0.8),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _AiAvatar(size: 42),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '流小萤 · 构图导演',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1,
                            color: PrimeColor.white54,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _title,
                          style: const TextStyle(
                            fontSize: 19,
                            height: 1.05,
                            color: PrimeColor.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _statusPill(),
                  GestureDetector(
                    onTap: onClose,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8, top: 2, bottom: 2),
                      child: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: PrimeColor.white38,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                _subtitle,
                maxLines: 2,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: PrimeColor.white54,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '最近建议距离\n人物更突出',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: PrimeColor.white38,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '最远建议距离\n环境更完整',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: PrimeColor.white38,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 18,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final x = width * progress;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 8,
                          child: Container(
                            height: 2,
                            color: PrimeColor.white24,
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: 8,
                          width: x,
                          child: Container(height: 2, color: PrimeColor.white),
                        ),
                        Positioned(
                          left: x - 5,
                          top: 2,
                          child: const Icon(
                            Icons.arrow_drop_down_rounded,
                            size: 18,
                            color: PrimeColor.white,
                          ),
                        ),
                        const Positioned(left: 0, top: 5, child: _TickMark()),
                        const Positioned(right: 0, top: 5, child: _TickMark()),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: onStart,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  height: 44,
                  width: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F1F6),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    '开始构图',
                    style: TextStyle(
                      fontSize: 15,
                      color: Color(0xFF3A3540),
                      fontWeight: FontWeight.w600,
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

  Widget _statusPill() {
    final good = _good;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: good ? const Color(0xFF14351F) : const Color(0xFF2A2313),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            good ? Icons.check_rounded : Icons.arrow_upward_rounded,
            size: 13,
            color: good ? const Color(0xFF8BE0A6) : const Color(0xFFFFD76A),
          ),
          const SizedBox(width: 4),
          Text(
            good ? '距离合适' : '继续调整',
            style: TextStyle(
              fontSize: 11,
              color: good ? const Color(0xFF8BE0A6) : const Color(0xFFFFD76A),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TickMark extends StatelessWidget {
  const _TickMark();

  @override
  Widget build(BuildContext context) {
    return Container(width: 2, height: 8, color: PrimeColor.white38);
  }
}

class _AiAvatar extends StatelessWidget {
  const _AiAvatar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          colors: [
            Color(0xFF80EEFF),
            Color(0xFFB1CFFF),
            Color(0xFFFFD2F6),
            Color(0xFFFFC38F),
            Color(0xFF80EEFF),
          ],
        ),
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/ai/liuxiaoying_face.png',
          width: size - 4,
          height: size - 4,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            color: const Color(0xFF111114),
            alignment: Alignment.center,
            child: const _SparkleMark(size: 16, color: PrimeColor.white),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- painters

class _SparkleMark extends StatelessWidget {
  const _SparkleMark({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _SparklePainter(color: color),
    );
  }
}

class _SparklePainter extends CustomPainter {
  _SparklePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + r * 0.17, c.dy - r * 0.17, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + r * 0.17, c.dy + r * 0.17, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - r * 0.17, c.dy + r * 0.17, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - r * 0.17, c.dy - r * 0.17, c.dx, c.dy - r);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ViewfinderGradePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final top = Rect.fromLTWH(0, 0, size.width, size.height * 0.34);
    canvas.drawRect(
      top,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xB3000000), Color(0x00000000)],
        ).createShader(top),
    );

    final bottom = Rect.fromLTWH(
      0,
      size.height * 0.58,
      size.width,
      size.height * 0.42,
    );
    canvas.drawRect(
      bottom,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0x99000000)],
        ).createShader(bottom),
    );

    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 1.08,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.28)],
          stops: const [0.52, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ShutterProgressPainter extends CustomPainter {
  _ShutterProgressPainter({required this.progress, required this.aligned});

  final double progress;
  final bool aligned;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 1;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = aligned ? 1.8 : 1.2
        ..color = aligned ? PrimeColor.white70 : PrimeColor.white24,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 4),
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..color = aligned ? PrimeColor.white : PrimeColor.white54,
    );
  }

  @override
  bool shouldRepaint(covariant _ShutterProgressPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.aligned != aligned;
}

// ---------------------------------------------------------------- sheets

/// Doka 式滤镜托盘：横向缩略图，选中项用白框和白色文字。
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.selected, required this.onSelect});

  final String selected;
  final void Function(String id, String label) onSelect;

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
              Row(
                children: [
                  for (final ratio in CaptureRatio.values) ...[
                    Expanded(
                      child: GestureDetector(
                        key: ValueKey('ratio-${ratio.name}'),
                        onTap: () => onSelect(ratio),
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          height: 100,
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
                                width: 38,
                                height: 38 * ratio.heightOverWidth,
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
                              const SizedBox(height: 9),
                              Text(
                                ratio.label,
                                style: TextStyle(
                                  fontSize: 12,
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
                    ),
                    if (ratio != CaptureRatio.values.last)
                      const SizedBox(width: 10),
                  ],
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
            value >= 0 ? '+${value.toStringAsFixed(1)}' : value.toStringAsFixed(1),
            style: const TextStyle(fontSize: 9, color: PrimeColor.white70, fontWeight: FontWeight.w600),
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
          const Text('EV', style: TextStyle(fontSize: 8, color: PrimeColor.white38)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _LevelPainter extends CustomPainter {
  _LevelPainter({required this.roll, required this.pitch});

  final double roll;
  final double pitch;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final line = Paint()
      ..color = const Color(0x99FFFFFF)
      ..strokeWidth = 1.0;
    final angle = (roll.clamp(-1.0, 1.0)) * 0.18;
    final half = size.width * 0.16;
    final dx = math.cos(angle) * half;
    final dy = math.sin(angle) * half;
    canvas.drawLine(center.translate(-dx, -dy), center.translate(dx, dy), line);
    canvas.drawCircle(center, 2.2, Paint()..color = const Color(0xCC7ECFC8));

    final bubble = center.translate(
      (pitch.clamp(-1.0, 1.0)) * size.width * 0.12,
      0,
    );
    canvas.drawCircle(
      bubble,
      4.0,
      Paint()
        ..color = const Color(0xCCFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    final label = TextPainter(
      text: TextSpan(
        text: (roll.abs() < 0.02 ? '水平' : 'ROLL ${(roll * 18).toStringAsFixed(0)}°'),
        style: const TextStyle(fontSize: 9, color: Color(0x99FFFFFF)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, center.translate(-label.width / 2, 12));
  }

  @override
  bool shouldRepaint(covariant _LevelPainter old) =>
      old.roll != roll || old.pitch != pitch;
}
