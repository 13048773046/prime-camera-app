import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'pages/camera_page.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const PrimeApp());
}

class PrimeApp extends StatelessWidget {
  const PrimeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '定焦 PRIME',
      debugShowCheckedModeBanner: false,
      theme: PrimeTheme.build(),
      builder: (context, child) {
        if (!kIsWeb) return child ?? const SizedBox.shrink();
        return _WebPreviewStage(child: child ?? const SizedBox.shrink());
      },
      home: CameraPage(demo: kIsWeb),
    );
  }
}

/// Web 只用于设计走查：把页面放进 390×844 的手机框里，
/// 避免桌面窗口把布局拉成平板比例。真机 IPA 不经过这一层。
class _WebPreviewStage extends StatelessWidget {
  const _WebPreviewStage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0B0B0B),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          child: AspectRatio(
            aspectRatio: 390 / 844,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: PrimeColor.white12, width: 0.8),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xCC000000),
                    blurRadius: 36,
                    offset: Offset(0, 18),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
