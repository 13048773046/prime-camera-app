import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/camera_service.dart';
import '../services/compose_api.dart';
import '../services/guidance.dart';
import '../theme.dart';
import '../widgets/guide_ring.dart';
import 'result_page.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key, this.camera, this.demo = false});

  final CameraService? camera;
  final bool demo;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _ShotPlan {
  const _ShotPlan({
    required this.index,
    required this.title,
    required this.zoomLabel,
    required this.framing,
    required this.alignment,
  });

  final int index;
  final String title;
  final String zoomLabel;
  final String framing;
  final Alignment alignment;
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  late final CameraService _camera =
      widget.camera ?? CameraService(forceDemo: widget.demo);

  CameraStatus _status = CameraStatus.unavailable;
  String? _statusMessage;
  bool _aligned = false;
  double _alignProgress = 0.12;
  int _zoomIndex = 1;
  bool _capturing = false;
  bool _flash = false;
  bool _flashOn = false;
  bool _gridOn = false;
  bool _planSheetOpen = false;
  ComposeResult? _guide;
  Timer? _alignTimer;
  Timer? _analyzeTimer;
  StreamSubscription<GuidanceFrame>? _guidanceSub;
  final LiveComposer _composer = const LiveComposer();
  bool _live = false;
  bool _analyzing = false;
  int _lastGuidanceTs = 0;
  bool _wasAligned = false;

  static const List<double> _zoomValues = [0.5, 1.0, 2.0, 3.0];
  static const List<String> _zoomLabels = ['.5', '1x', '2', '3'];

  static const List<_ShotPlan> _plans = [
    _ShotPlan(
      index: 1,
      title: '全身',
      zoomLabel: '1×',
      framing: '居中',
      alignment: Alignment.center,
    ),
    _ShotPlan(
      index: 2,
      title: '七分身',
      zoomLabel: '2×',
      framing: '右三分',
      alignment: Alignment.centerRight,
    ),
    _ShotPlan(
      index: 3,
      title: '九分身',
      zoomLabel: '3×',
      framing: '居中',
      alignment: Alignment.topCenter,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alignTimer?.cancel();
    _analyzeTimer?.cancel();
    _guidanceSub?.cancel();
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
    for (final plan in _plans) {
      if (plan.index == _zoomIndex) return plan;
    }
    return _plans.first;
  }

  Future<void> _bootstrap() async {
    final init = await _camera.initialize();
    if (!mounted) return;
    setState(() {
      _status = init.status;
      _statusMessage = init.message;
      _live = init.status == CameraStatus.ready;
      _analyzing =
          init.status == CameraStatus.ready || init.status == CameraStatus.demo;
      _guide = null;
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
    _analyzeTimer?.cancel();
    setState(() {
      _analyzing = true;
      _guide = null;
      _aligned = false;
      _alignProgress = 0.12;
    });
    _analyzeTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      setState(() => _analyzing = false);
      _startCommandCycle();
    });
  }

  void _startLiveGuidance() {
    _guidanceSub?.cancel();
    _alignTimer?.cancel();
    _analyzeTimer?.cancel();
    _lastGuidanceTs = 0;
    _wasAligned = false;
    setState(() {
      _analyzing = true;
      _guide = null;
      _aligned = false;
      _alignProgress = 0.12;
    });
    _guidanceSub = _camera.guidanceStream.listen(_onGuidanceFrame);
    // 原生首帧约 100–300ms；先留一秒“稳住手机”的分析态。
    _analyzeTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() => _analyzing = false);
    });
  }

  void _onGuidanceFrame(GuidanceFrame frame) {
    if (!mounted || !_live) return;
    // UI 最高 4fps 更新，避免识别帧率带着整页抖动。
    if (frame.ts - _lastGuidanceTs < 240) return;
    _lastGuidanceTs = frame.ts;
    final guide = _composer.compose(frame, zoom: _zoomValues[_zoomIndex]);
    final newlyAligned = guide.confidence > 0 && _isAlignedGuide(guide);
    setState(() {
      _guide = guide;
      _aligned = newlyAligned;
      _alignProgress = newlyAligned ? 1.0 : guide.progress;
    });
    if (newlyAligned && !_wasAligned) HapticFeedback.lightImpact();
    _wasAligned = newlyAligned;
  }

  bool _isAlignedGuide(ComposeResult guide) =>
      guide.actionLabel == '已对齐' || guide.hint.startsWith('可以拍了');

  ComposeResult _presetFor(int index) {
    switch (index) {
      case 0:
        return const ComposeResult(
          subject: 'person',
          subjectBox: [0.32, 0.34, 0.28, 0.40],
          targetBox: [0.28, 0.26, 0.26, 0.22],
          targetZoom: 0.5,
          horizonFix: -0.4,
          hint: '退到墙角，让街道进来',
          reasons: ['主体占比过大', '需要更多环境'],
          confidence: 0.58,
          source: 'rule',
        );
      case 2:
        return const ComposeResult(
          subject: 'person',
          subjectBox: [0.38, 0.32, 0.25, 0.36],
          targetBox: [0.40, 0.26, 0.20, 0.16],
          targetZoom: 2.0,
          horizonFix: 0.2,
          hint: '再靠近半步，肩膀切出画面',
          reasons: ['两侧留白过多', '主体可以更满'],
          confidence: 0.64,
          source: 'rule',
        );
      case 3:
        return const ComposeResult(
          subject: 'person',
          subjectBox: [0.44, 0.34, 0.18, 0.24],
          targetBox: [0.42, 0.30, 0.16, 0.13],
          targetZoom: 3.0,
          horizonFix: 0.0,
          hint: '手肘夹紧，对准眼睛',
          reasons: ['长焦易抖', '对焦点在眼部'],
          confidence: 0.66,
          source: 'rule',
        );
      default:
        return const ComposeResult(
          subject: 'person',
          subjectBox: [0.35, 0.36, 0.27, 0.40],
          targetBox: [0.33, 0.28, 0.26, 0.20],
          targetZoom: 1.0,
          horizonFix: 0.0,
          hint: '后退半步，镜头降到胸口',
          reasons: ['头顶留白偏多', '主体略偏近'],
          confidence: 0.62,
          source: 'rule',
        );
    }
  }

  void _startCommandCycle() {
    if (_live || _status != CameraStatus.demo) return;
    _alignTimer?.cancel();
    final preset = _presetFor(_zoomIndex);
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

  void _startAi() {
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
    HapticFeedback.mediumImpact();
    final path = await _camera.takePhoto(flash: _flashOn);
    await Future.delayed(const Duration(milliseconds: 160));
    if (!mounted) return;
    setState(() {
      _flash = false;
      _capturing = false;
    });
    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (context, animation, secondary) => ResultPage(
          photoPath: path,
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

  void _toggleFlash() {
    setState(() => _flashOn = !_flashOn);
  }

  void _toggleGrid() {
    setState(() => _gridOn = !_gridOn);
  }

  void _openPlanSheet() {
    if (_planSheetOpen) return;
    setState(() => _planSheetOpen = true);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _PlanSheet(
        plans: _plans,
        selectedIndex: _zoomIndex,
        sceneAsset: _status == CameraStatus.demo ? 'assets/demo/scene.jpg' : null,
        onSelect: (index) {
          Navigator.of(sheetContext).pop();
          _selectZoom(index);
        },
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _planSheetOpen = false);
    });
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SettingsSheet(),
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
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(child: _buildStage()),
              _buildBottomControls(),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- header

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 14, 4),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '定焦',
                style: TextStyle(
                  fontSize: 18,
                  height: 1,
                  color: PrimeColor.white,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'PRIME',
                style: PrimeType.overline.copyWith(
                  color: PrimeColor.white24,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
          const Spacer(),
          _topIcon(
            _flashOn ? Icons.bolt : Icons.bolt_outlined,
            _toggleFlash,
            active: _flashOn,
          ),
          _topIcon(Icons.tune_rounded, _openSettings),
        ],
      ),
    );
  }

  Widget _topIcon(IconData icon, VoidCallback onTap, {bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 38,
        height: 38,
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? PrimeColor.white12 : Colors.transparent,
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 19,
          color: active ? PrimeColor.white : PrimeColor.white54,
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- stage

  Widget _buildStage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth - 24;
        final maxH = constraints.maxHeight - 8;
        final width = math.min(maxW, maxH * 0.75);
        final height = width * 4 / 3;
        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildPreview(),
                  IgnorePointer(
                    child: CustomPaint(painter: _ViewfinderGradePainter()),
                  ),
                  IgnorePointer(
                    child: GuideOverlay(
                      subjectBox: _guide?.subjectBox ?? const [],
                      targetBox: _guide?.targetBox ?? const [],
                      aligned: _aligned,
                      analyzing: _analyzing,
                      showGrid: _gridOn,
                    ),
                  ),
                  Positioned(
                    left: 10,
                    right: 10,
                    top: 10,
                    child: _buildGuideCard(),
                  ),
                  if (!_planSheetOpen)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 10,
                      child: _buildFocalPill(),
                    ),
                  if (_status == CameraStatus.permissionDenied)
                    Positioned.fill(child: _buildPermissionCard()),
                  if (_flash)
                    const Positioned.fill(
                      child: ColoredBox(color: Color(0xF2FFFFFF)),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPreview() {
    switch (_status) {
      case CameraStatus.ready:
        final id = _camera.textureId;
        if (id != null) {
          return ClipRect(
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
        }
        return const ColoredBox(color: PrimeColor.black);
      case CameraStatus.demo:
        return Image.asset('assets/demo/scene.jpg', fit: BoxFit.cover);
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

  Widget _buildGuideCard() {
    final label = _analyzing
        ? 'PRIME · AI'
        : _aligned
            ? '构图已锁定'
            : 'PRIME · AI 构图';
    final title = _analyzing
        ? '正在进行人像构图分析'
        : _aligned
            ? '对齐了 · 可以按快门'
            : (_guide?.hint ?? '把主体放进画面');
    final subtitle = _analyzing
        ? '请稳住手机，不要移动'
        : _aligned
            ? '双环重合 · 直接出片'
            : '${_activePlan.title} · ${_activePlan.zoomLabel} · ${_activePlan.framing}';

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          decoration: BoxDecoration(
            color: const Color(0xE60A0A0A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: PrimeColor.white12, width: 0.8),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: PrimeColor.white12),
                ),
                alignment: Alignment.center,
                child: const _SparkleMark(size: 17, color: PrimeColor.white70),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: PrimeType.overline.copyWith(
                        color: PrimeColor.white38,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        height: 1.3,
                        color: PrimeColor.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PrimeType.caption.copyWith(
                        color: PrimeColor.white54,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (_analyzing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.2,
                    color: PrimeColor.white54,
                  ),
                )
              else if (_aligned)
                const Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: PrimeColor.white,
                )
              else
                const Icon(
                  Icons.auto_awesome,
                  size: 15,
                  color: PrimeColor.white24,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFocalPill() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xB3000000),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: PrimeColor.white12, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < _zoomLabels.length; i++)
              GestureDetector(
                key: ValueKey('zoom-$i'),
                onTap: () => _selectZoom(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  width: i == _zoomIndex ? 44 : 36,
                  height: 32,
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
                          : PrimeColor.white38,
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

  // --------------------------------------------------------------- controls

  Widget _buildBottomControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _guide != null && !_analyzing
                ? _buildPlanPill()
                : const SizedBox(height: 34),
          ),
          const SizedBox(height: 4),
          _buildUtilityRow(),
          const SizedBox(height: 2),
          _buildShutterRow(),
          const SizedBox(height: 2),
          _buildBottomNav(),
        ],
      ),
    );
  }

  Widget _buildUtilityRow() {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          _utilityIcon(
            Icons.grid_view_rounded,
            _toggleGrid,
            active: _gridOn,
          ),
          const Spacer(),
          Text(
            '3:4',
            style: PrimeType.overline.copyWith(
              color: PrimeColor.white38,
              letterSpacing: 1.4,
            ),
          ),
          const Spacer(),
          _utilityIcon(
            Icons.cameraswitch_outlined,
            _switchCamera,
          ),
        ],
      ),
    );
  }

  Widget _utilityIcon(IconData icon, VoidCallback onTap, {bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(
          icon,
          size: 18,
          color: active ? PrimeColor.white : PrimeColor.white38,
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Center(
      child: Container(
        height: 44,
        width: 250,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: PrimeColor.white06,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: PrimeColor.white12, width: 0.8),
        ),
        child: Row(
          children: [
            _navItem('相机', active: true),
            _navItem('相册'),
            _navItem('我的', onTap: _openSettings),
          ],
        ),
      ),
    );
  }

  Widget _navItem(String label, {bool active = false, VoidCallback? onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: active ? PrimeColor.white12 : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: active ? PrimeColor.white : PrimeColor.white38,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlanPill() {
    return GestureDetector(
      onTap: _openPlanSheet,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: PrimeColor.white06,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: PrimeColor.white12, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.grid_view_rounded,
              size: 14,
              color: PrimeColor.white38,
            ),
            const SizedBox(width: 8),
            Text(
              '切换构图方案',
              style: PrimeType.caption.copyWith(
                color: PrimeColor.white54,
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: PrimeColor.white38,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShutterRow() {
    return SizedBox(
      height: 92,
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _bottomAction(
                label: '相册',
                child: _buildAlbumButton(),
              ),
            ),
          ),
          _buildShutterButton(),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: _bottomAction(
                label: 'AI 构图',
                child: _buildAiButton(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomAction({required String label, required Widget child}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        const SizedBox(height: 5),
        Text(
          label,
          style: PrimeType.overline.copyWith(
            color: PrimeColor.white38,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildAlbumButton() {
    return Container(
      width: 44,
      height: 44,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: PrimeColor.surfaceLift,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PrimeColor.white12, width: 0.8),
      ),
      child: Image.asset(
        'assets/demo/scene.jpg',
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.photo_library_outlined,
          size: 20,
          color: PrimeColor.white38,
        ),
      ),
    );
  }

  Widget _buildAiButton() {
    return GestureDetector(
      onTap: _startAi,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: PrimeColor.white12, width: 0.8),
        ),
        alignment: Alignment.center,
        child: _SparkleMark(
          size: 18,
          color: _analyzing ? PrimeColor.white38 : PrimeColor.white70,
        ),
      ),
    );
  }

  Widget _buildShutterButton() {
    return GestureDetector(
      key: const ValueKey('shutter'),
      onTap: _capture,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _capturing ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: SizedBox(
          width: 78,
          height: 78,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(78, 78),
                painter: _ShutterProgressPainter(
                  progress: _alignProgress,
                  aligned: _aligned,
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: _capturing ? 46 : 58,
                height: _capturing ? 46 : 58,
                decoration: BoxDecoration(
                  color: PrimeColor.white,
                  shape: BoxShape.circle,
                  boxShadow: _aligned
                      ? [
                          BoxShadow(
                            color: PrimeColor.white.withValues(alpha: 0.18),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
              ),
            ],
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
                  Expanded(
                    child: _primaryButton('允许使用相机', _requestPermission),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _outlineButton(
                      '去设置',
                      () => _camera.openSettings(),
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

class _PlanSheet extends StatelessWidget {
  const _PlanSheet({
    required this.plans,
    required this.selectedIndex,
    required this.sceneAsset,
    required this.onSelect,
  });

  final List<_ShotPlan> plans;
  final int selectedIndex;
  final String? sceneAsset;
  final ValueChanged<int> onSelect;

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
                'PRIME 的 3 种拍法',
                style: TextStyle(
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
                              padding: const EdgeInsets.symmetric(horizontal: 5),
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
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              child: Text(
                                '${plan.zoomLabel} · ${plan.framing}',
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

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet();

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
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '设置',
                  style: TextStyle(
                    fontSize: 20,
                    color: PrimeColor.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _row('构图网格', '关闭'),
              _row('保存水印', '开启'),
              _row('版本', '0.2.0'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: PrimeColor.white70),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 12, color: PrimeColor.white38),
          ),
        ],
      ),
    );
  }
}
