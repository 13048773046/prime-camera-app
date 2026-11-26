import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/camera_service.dart';
import '../services/compose_api.dart';
import '../theme.dart';
import '../widgets/film_selector.dart';
import '../widgets/guide_ring.dart';
import '../widgets/manga_bits.dart';
import '../widgets/paper.dart';
import 'result_page.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key, this.camera, this.demo = false});

  final CameraService? camera;
  final bool demo;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with TickerProviderStateMixin {
  late final CameraService _camera =
      widget.camera ?? CameraService(forceDemo: widget.demo);

  CameraStatus _status = CameraStatus.unavailable;
  String? _statusMessage;
  bool _aligned = false;
  double _alignProgress = 0.12;
  int _zoomIndex = 1;
  bool _capturing = false;
  bool _flash = false;
  ComposeResult? _guide;
  Timer? _alignTimer;

  static const List<double> _zoomValues = [0.5, 1.0, 2.0, 3.0];
  static const List<String> _zoomLabels = ['0.5×', '1×', '2×', '3×'];
  static const List<String> _zoomCaptions = ['超广', '标准', '中焦', '长焦'];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _alignTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final init = await _camera.initialize();
    if (!mounted) return;
    setState(() {
      _status = init.status;
      _statusMessage = init.message;
    });
    _startCommandCycle();
  }

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

  void _selectZoom(int index) {
    if (_zoomIndex == index) return;
    setState(() => _zoomIndex = index);
    _camera.setZoom(_zoomValues[index]);
    _startCommandCycle();
  }

  Future<void> _capture() async {
    if (_capturing) return;
    setState(() {
      _capturing = true;
      _flash = true;
    });
    HapticFeedback.mediumImpact();
    final path = await _camera.takePhoto();
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
      final init = await _camera.initialize();
      if (!mounted) return;
      setState(() {
        _status = init.status;
        _statusMessage = init.message;
      });
    } else {
      setState(() {
        _status = CameraStatus.permissionDenied;
        _statusMessage = '还没有相机权限';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PrimeColor.paper,
      body: PaperBackground(
        child: Stack(
          children: [
            // 印在纸上的流萤：像手帐内页的淡彩插画。
            Positioned(
              right: -54,
              bottom: 86,
              child: IgnorePointer(
                child: Transform.rotate(
                  angle: -0.06,
                  child: Opacity(
                    opacity: 0.085,
                    child: Image.asset(
                      'assets/brand/xiaoying_full.png',
                      height: 380,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(child: _buildStage()),
                  _buildMeters(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: FilmStripSelector(
                      labels: _zoomLabels,
                      captions: _zoomCaptions,
                      activeIndex: _zoomIndex,
                      onSelect: _selectZoom,
                    ),
                  ),
                  _buildShutterRow(),
                  _buildFooter(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- header

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 16, 4),
      child: Row(
        children: [
          const SealStamp(text: '定', size: 34, angle: -0.06),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '定焦',
                        style: TextStyle(
                          fontFamily: PrimeFont.hand,
                          fontFamilyFallback: PrimeFont.handFallback,
                          fontSize: 29,
                          height: 1,
                          letterSpacing: 2,
                          color: PrimeColor.ink,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 3),
                        child: Text(
                          'PRIME',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 3.6,
                            color: PrimeColor.inkSoft,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const BrushUnderline(width: 74, height: 7),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'AI 构图相机 · 直出',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: PrimeFont.hand,
                          fontFamilyFallback: PrimeFont.handFallback,
                          fontSize: 9.5,
                          color: PrimeColor.inkFaint,
                          letterSpacing: 0.6,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  const Text(
                    '36',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: PrimeColor.ink,
                      letterSpacing: 0.6,
                    ),
                  ),
                  Text(
                    ' EXP',
                    style: TextStyle(
                      fontSize: 8,
                      height: 1,
                      color: PrimeColor.inkFaint,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'ISO 400 · 35mm',
                style: TextStyle(
                  fontSize: 7.5,
                  height: 1,
                  color: PrimeColor.inkFaint,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(width: 9),
          const MascotAvatar(size: 32),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- stage

  Widget _buildStage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth - 30;
        final maxH = constraints.maxHeight - 12;
        final width = math.min(maxW, maxH * 0.75);
        final height = width * 4 / 3;
        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: InkFrame(
                    radius: 4,
                    strong: true,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildPreview(),
                          IgnorePointer(
                            child: CustomPaint(
                              painter: _ViewfinderGradePainter(),
                            ),
                          ),
                          if (_guide != null)
                            GuideOverlay(
                              subjectBox: _guide!.subjectBox,
                              targetBox: _guide!.targetBox,
                              aligned: _aligned,
                              confidence: _guide!.confidence,
                            ),
                          _buildHud(),
                          _buildVerticalCaption(),
                          _buildDistanceRuler(),
                          Positioned(
                            left: 9,
                            right: 9,
                            bottom: 9,
                            child: _buildBubble(),
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
                ),
                // 贴在分格边上的手写标签。
                Positioned(
                  top: -8,
                  left: 4,
                  child: InkTag(text: 'No.01 取景', angle: -0.02, dense: true),
                ),
                Positioned(
                  top: -8,
                  right: 4,
                  child: InkTag(
                    text: 'PORTRAIT · 3:4',
                    angle: 0.02,
                    dense: true,
                  ),
                ),
              ],
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
          // 原生视频流是 9:16 竖幅，按 cover 填满 3:4 取景窗，裁掉上下多余部分。
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
        return const ColoredBox(color: PrimeColor.dark);
      case CameraStatus.demo:
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/demo/scene.jpg', fit: BoxFit.cover),
            Positioned(
              left: 10,
              top: 42,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: PrimeColor.paper.withValues(alpha: 0.9),
                  border: Border.all(
                    color: PrimeColor.ink.withValues(alpha: 0.7),
                    width: 0.8,
                  ),
                ),
                child: const Text(
                  '演示取景 · 真机为实时画面',
                  style: TextStyle(
                    fontSize: 8,
                    letterSpacing: 0.8,
                    color: PrimeColor.ink,
                  ),
                ),
              ),
            ),
          ],
        );
      case CameraStatus.permissionDenied:
      case CameraStatus.unavailable:
        return Container(
          color: PrimeColor.dark,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                color: Colors.white24,
                size: 40,
              ),
              const SizedBox(height: 10),
              Text(
                _statusMessage ?? '相机未就绪',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildHud() {
    final zoomText = _zoomLabels[_zoomIndex];
    return Positioned(
      top: 10,
      left: 10,
      right: 10,
      child: Row(
        children: [
          _hudChip(zoomText),
          const SizedBox(width: 5),
          _hudChip('f/1.8'),
          const SizedBox(width: 5),
          _hudChip('1/125'),
          const Spacer(),
          _hudChip(
            _status == CameraStatus.demo ? 'DEMO' : 'LIVE',
            accent: _status == CameraStatus.demo,
          ),
        ],
      ),
    );
  }

  Widget _hudChip(String text, {bool accent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.22),
          width: 0.7,
        ),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (accent) ...[
            Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: PrimeColor.mint,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 8,
              height: 1,
              letterSpacing: 1.1,
              color: accent ? PrimeColor.mint : Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalCaption() {
    return Positioned(
      right: 6,
      top: 64,
      child: IgnorePointer(
        child: RotatedBox(
          quarterTurns: 3,
          child: Text(
            '一 格 一 世 界 · 光 落 在 肩 上',
            style: TextStyle(
              fontFamily: PrimeFont.hand,
              fontFamilyFallback: PrimeFont.handFallback,
              fontSize: 8.5,
              letterSpacing: 1.8,
              color: Colors.white.withValues(alpha: 0.42),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDistanceRuler() {
    return Positioned(
      left: 0,
      top: 52,
      child: SizedBox(
        width: 34,
        height: 152,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.black.withValues(alpha: 0.34),
                  Colors.transparent,
                ],
              ),
            ),
            child: CustomPaint(painter: _RulerPainter()),
          ),
        ),
      ),
    );
  }

  Widget _buildBubble() {
    final hint = _aligned ? '可以拍了，稳住呼吸' : (_guide?.hint ?? '举起手机，先把主体放进画面');
    final reasons = _aligned
        ? const ['位置已对齐', '撑住这一下']
        : (_guide?.reasons ?? const ['等待第一次构图']);
    return SpeechBubble(
      tailX: 44,
      padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const MascotAvatar(size: 31),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      _aligned ? '流萤 · 对齐了' : '流萤 · 口令 ①',
                      style: const TextStyle(
                        fontSize: 8.5,
                        letterSpacing: 1.4,
                        color: PrimeColor.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _aligned ? '0.3°' : '距离优先',
                      style: const TextStyle(
                        fontSize: 7.5,
                        letterSpacing: 0.8,
                        color: PrimeColor.inkFaint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  hint,
                  style: TextStyle(
                    fontFamily: PrimeFont.hand,
                    fontFamilyFallback: PrimeFont.handFallback,
                    fontSize: 17,
                    height: 1.25,
                    color: PrimeColor.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  reasons.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: PrimeFont.hand,
                    fontFamilyFallback: PrimeFont.handFallback,
                    fontSize: 10,
                    height: 1.1,
                    color: PrimeColor.inkFaint,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _distanceChip(),
        ],
      ),
    );
  }

  Widget _distanceChip() {
    final text = _aligned ? '已对齐' : '再退\n0.4m';
    return Container(
      width: 42,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: PrimeColor.mint.withValues(alpha: _aligned ? 0.95 : 0.82),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: PrimeColor.ink.withValues(alpha: 0.75),
          width: 0.9,
        ),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 8.5,
          height: 1.25,
          color: PrimeColor.ink,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildPermissionCard() {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.55),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: PrimeColor.paper,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: PrimeColor.ink, width: 1.3),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset(
                    'assets/brand/xiaoying_bust.png',
                    width: 84,
                    height: 96,
                    fit: BoxFit.cover,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '相机还在打盹',
                          style: TextStyle(
                            fontFamily: PrimeFont.hand,
                            fontFamilyFallback: PrimeFont.handFallback,
                            fontSize: 19,
                            height: 1.2,
                            color: PrimeColor.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '允许定焦使用相机，才能看到实时取景和 AR 构图环。',
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.5,
                            color: PrimeColor.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InkButton(
                      label: '允许使用相机',
                      filled: true,
                      height: 40,
                      expand: true,
                      onTap: _requestPermission,
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkButton(
                    label: '去设置',
                    height: 40,
                    onTap: () => _camera.openSettings(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- meters

  Widget _buildMeters() {
    final t = _alignProgress;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Column(
        children: [
          Row(
            children: [
              Container(width: 3, height: 9, color: PrimeColor.mintDeep),
              const SizedBox(width: 5),
              const Text(
                '口令刻度',
                style: TextStyle(
                  fontSize: 8,
                  letterSpacing: 1.6,
                  color: PrimeColor.inkSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              const Text(
                '距离 › 高度 › 角度 › 焦段',
                style: TextStyle(
                  fontSize: 7.5,
                  letterSpacing: 0.8,
                  color: PrimeColor.inkFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: MeterBar(
                  label: '距离',
                  value: 0.25 + 0.7 * t,
                  readout: _aligned ? '0.0m' : '0.4m',
                  active: !_aligned,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MeterBar(
                  label: '高度',
                  value: 0.35 + 0.55 * t,
                  readout: _aligned ? '平视' : '−8cm',
                  active: false,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MeterBar(
                  label: '角度',
                  value: 0.08 + 0.9 * t,
                  readout: _aligned ? '1.2°' : '2.6°',
                  active: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- shutter

  Widget _buildShutterRow() {
    return SizedBox(
      height: 98,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
        child: Row(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _albumTile(),
                const SizedBox(height: 4),
                const Text(
                  '最近',
                  style: TextStyle(
                    fontSize: 8,
                    letterSpacing: 1.2,
                    color: PrimeColor.inkFaint,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _capture,
                  child: AnimatedScale(
                    scale: _capturing ? 0.93 : 1.0,
                    duration: const Duration(milliseconds: 120),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: CustomPaint(
                        painter: _ShutterPainter(
                          progress: _alignProgress,
                          aligned: _aligned,
                          busy: false,
                        ),
                        child: Center(
                          child: Text(
                            '拍',
                            style: TextStyle(
                              fontFamily: PrimeFont.hand,
                              fontFamilyFallback: PrimeFont.handFallback,
                              fontSize: 20,
                              height: 1,
                              color: PrimeColor.ink,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  '按一下 · 直出',
                  style: TextStyle(
                    fontSize: 8,
                    letterSpacing: 1.2,
                    color: PrimeColor.inkFaint,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RoundInkButton(
                  icon: Icons.cameraswitch_outlined,
                  size: 44,
                  onTap: () => _camera.switchCamera(),
                ),
                const SizedBox(height: 4),
                const Text(
                  '翻转',
                  style: TextStyle(
                    fontSize: 8,
                    letterSpacing: 1.2,
                    color: PrimeColor.inkFaint,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _albumTile() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            border: Border.all(
              color: PrimeColor.ink.withValues(alpha: 0.85),
              width: 1.1,
            ),
            color: PrimeColor.paperDeep,
          ),
          child: ClipRect(
            child: Image.asset(
              'assets/demo/scene.jpg',
              fit: BoxFit.cover,
              width: 44,
              height: 44,
            ),
          ),
        ),
        const Positioned(
          left: -6,
          top: -5,
          child: TapeStrip(width: 24, height: 9, angle: -0.4),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- footer

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 4),
      child: Row(
        children: [
          _navTab('取景', active: true),
          const SizedBox(width: 16),
          _navTab('手记', onTap: _openNotebook),
          const SizedBox(width: 16),
          _navTab('设定', onTap: _openNotebook),
          const Spacer(),
          const HeartBadge(count: 12),
        ],
      ),
    );
  }

  Widget _navTab(String label, {bool active = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: PrimeFont.hand,
              fontFamilyFallback: PrimeFont.handFallback,
              fontSize: 13,
              height: 1.2,
              color: active ? PrimeColor.ink : PrimeColor.inkFaint,
            ),
          ),
          const SizedBox(height: 2),
          if (active)
            const BrushUnderline(width: 26, height: 5)
          else
            const SizedBox(width: 26, height: 5),
        ],
      ),
    );
  }

  void _openNotebook() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const _NotebookSheet(),
    );
  }
}

// ---------------------------------------------------------------- painters

class _ViewfinderGradePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // 底部渐变，保证口令气泡压得住画面。
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.55, size.width, size.height * 0.45),
      Paint()
        ..shader =
            const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0x8C000000), Color(0xCC000000)],
              stops: [0.0, 0.55, 1.0],
            ).createShader(
              Rect.fromLTWH(
                0,
                size.height * 0.55,
                size.width,
                size.height * 0.45,
              ),
            ),
    );
    // 暗角。
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 1.05,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.34)],
          stops: const [0.55, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RulerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.38);
    final strongPaint = Paint()..color = Colors.white.withValues(alpha: 0.6);
    final labels = ['3', '2', '1', '0.5'];
    final step = size.height / (labels.length - 1);
    for (int i = 0; i < labels.length; i++) {
      final y = i * step;
      final isCurrent = i == 2;
      canvas.drawLine(
        Offset(size.width - 12, y),
        Offset(size.width, y),
        isCurrent ? strongPaint : paint,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            fontSize: 6.5,
            color: Colors.white.withValues(alpha: 0.5),
            letterSpacing: 0.4,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(size.width - 12 - tp.width - 3, y - tp.height / 2),
      );
      if (i < labels.length - 1) {
        for (int j = 1; j < 4; j++) {
          final ty = y + step * j / 4;
          canvas.drawLine(
            Offset(size.width - 6, ty),
            Offset(size.width, ty),
            paint,
          );
        }
      }
    }
    // 当前距离的小三角。
    canvas.drawPath(
      Path()
        ..moveTo(size.width - 2, step * 2 - 3)
        ..lineTo(size.width + 4, step * 2)
        ..lineTo(size.width - 2, step * 2 + 3)
        ..close(),
      Paint()..color = PrimeColor.mint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ShutterPainter extends CustomPainter {
  _ShutterPainter({
    required this.progress,
    required this.aligned,
    required this.busy,
  });

  final double progress;
  final bool aligned;
  final bool busy;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 2;
    final outer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = PrimeColor.ink;
    canvas.drawCircle(center, r, Paint()..color = PrimeColor.paper);
    canvas.drawCircle(center, r, outer);
    canvas.drawCircle(
      center,
      r - 4.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = PrimeColor.ink.withValues(alpha: 0.4),
    );

    // 六叶光圈：对齐时开合更大。
    final iris = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = PrimeColor.ink.withValues(alpha: 0.28);
    final innerR = aligned ? r - 13 : r - 20;
    for (int i = 0; i < 6; i++) {
      final a = i * math.pi / 3;
      canvas.drawLine(
        center + Offset(math.cos(a), math.sin(a)) * (r - 6),
        center + Offset(math.cos(a), math.sin(a)) * innerR,
        iris,
      );
    }

    // 对齐进度：薄荷弧。
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r - 7),
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..color = aligned
            ? PrimeColor.mintDeep
            : PrimeColor.mint.withValues(alpha: 0.85),
    );

    if (aligned) {
      canvas.drawCircle(
        center,
        r - 10,
        Paint()..color = PrimeColor.mint.withValues(alpha: 0.22),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ShutterPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.aligned != aligned ||
      oldDelegate.busy != busy;
}

// ------------------------------------------------------------- notebook

class _NotebookSheet extends StatelessWidget {
  const _NotebookSheet();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.42,
      maxChildSize: 0.9,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: PrimeColor.paper,
            borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
          ),
          child: PaperBackground(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 3,
                    decoration: BoxDecoration(
                      color: PrimeColor.inkFaint,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '构图手记 · 第 01 页',
                            style: TextStyle(
                              fontFamily: PrimeFont.hand,
                              fontFamilyFallback: PrimeFont.handFallback,
                              fontSize: 22,
                              color: PrimeColor.ink,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '口诀一次只说一句，先站对位置，再按快门。',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.7,
                              color: PrimeColor.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Image.asset(
                      'assets/brand/xiaoying_bust.png',
                      width: 74,
                      height: 86,
                      fit: BoxFit.cover,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const DottedRule(),
                const SizedBox(height: 14),
                _tip('01', '距离', '先退到主体刚好占画面 1/3 的位置。'),
                _tip('02', '高度', '镜头降到胸口，头顶留白不超过一拳。'),
                _tip('03', '角度', '手机竖平，别仰拍，地平线压在下方一格。'),
                _tip('04', '焦段', '最后才动焦段，1× 先拍一张，再决定要不要 2×。'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tip(String no, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(
                color: PrimeColor.ink.withValues(alpha: 0.6),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              no,
              style: const TextStyle(fontSize: 9, color: PrimeColor.ink),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: PrimeFont.hand,
                    fontFamilyFallback: PrimeFont.handFallback,
                    fontSize: 14,
                    color: PrimeColor.ink,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.6,
                    color: PrimeColor.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
