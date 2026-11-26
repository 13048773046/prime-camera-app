import 'package:flutter/material.dart';
import '../services/camera_service.dart';
import '../services/compose_api.dart';
import '../theme.dart';
import '../widgets/guide_ring.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key, this.camera});

  final CameraService? camera;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  late final CameraService _camera = widget.camera ?? CameraService();

  double _zoom = 1.0;
  bool _aligned = false;
  bool _busy = false;
  String _hint = '举起手机，先把主体放进画面';
  List<String> _reasons = const [];
  ComposeResult? _result;
  CameraStatus _status = CameraStatus.unavailable;
  final String _mode = 'portrait';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final status = await _camera.initialize();
    if (!mounted) return;
    setState(() => _status = status);
    await _analyze();
  }

  Future<void> _analyze() async {
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    setState(() {
      _result = ComposeResult(
        subject: 'person',
        subjectBox: const [0.34, 0.24, 0.32, 0.64],
        targetBox: const [0.33, 0.22, 0.34, 0.68],
        targetZoom: _zoom,
        horizonFix: 0,
        hint: '后退半步，镜头降到胸口',
        reasons: const ['头顶留白偏多', '主体略偏近'],
        confidence: 0.62,
        source: 'rule',
      );
      _hint = _result!.hint;
      _reasons = _result!.reasons;
      _aligned = false;
      _busy = false;
    });
  }

  void _align() {
    setState(() {
      _aligned = true;
      _hint = '位置已对齐，可以拍摄';
    });
  }

  Future<void> _capture() async {
    final path = await _camera.takePhoto();
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResultPage(photoPath: path)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PrimeTokens.dark,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildViewfinder(context)),
            _buildBottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildViewfinder(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _CameraPreview(status: _status),
        if (_result != null) GuideRing(targetBox: _result!.targetBox, aligned: _aligned),
        Positioned(top: 16, left: 18, right: 18, child: _buildTopBar()),
        Positioned(bottom: 18, left: 20, right: 20, child: _buildGuideCard()),
      ],
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white24),
          ),
          child: const Text('定焦 PRIME', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        ),
        const Spacer(),
        Text(_mode == 'portrait' ? '人像构图' : '风光构图', style: const TextStyle(color: Colors.white70)),
      ],
    );
  }

  Widget _buildGuideCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: PrimeTokens.paper.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: PrimeTokens.line),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset('assets/ai/xiaoying.png', width: 34, height: 34, fit: BoxFit.cover),
              const SizedBox(width: 10),
              Expanded(child: Text(_hint, style: Theme.of(context).textTheme.titleLarge)),
            ],
          ),
          if (_reasons.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 44),
              child: Text(_reasons.join(' · '), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6B7570))),
            ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ZoomButton(label: '0.5x', active: _zoom == 0.5, onTap: () => _setZoom(0.5)),
              _ZoomButton(label: '1x', active: _zoom == 1, onTap: () => _setZoom(1)),
              _ZoomButton(label: '2x', active: _zoom == 2, onTap: () => _setZoom(2)),
              _ZoomButton(label: '3x', active: _zoom == 3, onTap: () => _setZoom(3)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 22),
      color: PrimeTokens.dark,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          TextButton(onPressed: _busy ? null : _analyze, child: const Text('重新构图', style: TextStyle(color: Colors.white))),
          GestureDetector(
            onTap: _capture,
            child: Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
                color: _aligned ? PrimeTokens.mint : Colors.white24,
              ),
              child: const Icon(Icons.camera_alt, color: Colors.white),
            ),
          ),
          TextButton(onPressed: _align, child: const Text('对齐', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  void _setZoom(double value) {
    setState(() => _zoom = value);
    _camera.setZoom(value);
    _analyze();
  }
}

class _CameraPreview extends StatelessWidget {
  const _CameraPreview({required this.status});

  final CameraStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF26332F), Color(0xFF0E0F0E)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_outlined, color: Colors.white24, size: 86),
            const SizedBox(height: 12),
            Text(
              switch (status) {
                CameraStatus.ready => '实时取景已连接',
                CameraStatus.permissionDenied => '相机权限未开启',
                CameraStatus.unavailable => '原生相机内核待接入，当前为取景窗占位',
              },
              style: const TextStyle(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: active ? PrimeTokens.deepGreen : const Color(0xFF6B7570),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }
}

class ResultPage extends StatelessWidget {
  const ResultPage({super.key, this.photoPath});

  final String? photoPath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PrimeTokens.paper,
      appBar: AppBar(title: const Text('出片')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 250,
              height: 330,
              decoration: BoxDecoration(
                color: PrimeTokens.nearWhite,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: PrimeTokens.gray, width: 2),
              ),
              child: photoPath == null
                  ? const Icon(Icons.image_outlined, size: 72, color: PrimeTokens.gray)
                  : const Icon(Icons.check_circle_outline, size: 72, color: PrimeTokens.mint),
            ),
            const SizedBox(height: 24),
            const Text('成片已生成，可保存或分享', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(onPressed: () {}, child: const Text('保存相册')),
                const SizedBox(width: 16),
                OutlinedButton(onPressed: () {}, child: const Text('分享')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
