import 'package:flutter/material.dart';
import '../services/compose_api.dart';
import '../theme.dart';
import '../widgets/guide_ring.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key, this.api});

  final ComposeApi? api;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  double _zoom = 1.0;
  bool _aligned = false;
  String _hint = '举起手机，先把主体放进画面';
  List<String> _reasons = const [];
  ComposeResult? _result;
  final String _mode = 'portrait';

  Future<void> _analyzeMock() async {
    await Future.delayed(const Duration(milliseconds: 260));
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
    });
  }

  void _align() {
    setState(() {
      _aligned = true;
      _hint = '位置已对齐，可以拍摄';
    });
  }

  void _capture() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ResultPage()));
  }

  @override
  void initState() {
    super.initState();
    _analyzeMock();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF26332F), Color(0xFF121212)],
                      ),
                    ),
                    child: const Center(
                      child: Icon(Icons.camera_alt_outlined, color: Colors.white24, size: 96),
                    ),
                  ),
                  if (_result != null)
                    GuideRing(targetBox: _result!.targetBox, aligned: _aligned),
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('定焦 PRIME', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        Text(_mode == 'portrait' ? '人像' : '风光', style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 18,
                    left: 20,
                    right: 20,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: PrimeTokens.paper.withValues(alpha: 0.96),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_hint, style: Theme.of(context).textTheme.titleLarge),
                              if (_reasons.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(_reasons.join(' · '), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: PrimeTokens.gray)),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
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
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              color: PrimeTokens.dark,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(onPressed: _analyzeMock, child: const Text('重新构图', style: TextStyle(color: Colors.white))),
                  GestureDetector(
                    onTap: _capture,
                    child: Container(
                      width: 72,
                      height: 72,
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
            ),
          ],
        ),
      ),
    );
  }

  void _setZoom(double value) {
    setState(() => _zoom = value);
    _analyzeMock();
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
          foregroundColor: active ? PrimeTokens.mint : Colors.white70,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }
}

class ResultPage extends StatelessWidget {
  const ResultPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('出片')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 240,
              height: 320,
              decoration: BoxDecoration(
                color: PrimeTokens.nearWhite,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: PrimeTokens.gray, width: 2),
              ),
              child: const Icon(Icons.image_outlined, size: 72, color: PrimeTokens.gray),
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
