import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prime_camera/pages/camera_page.dart';
import 'package:prime_camera/services/camera_service.dart';
import 'package:prime_camera/services/guidance.dart';
import 'package:prime_camera/widgets/guide_ring.dart';

/// 端到端（Dart 侧）验证：原生 guidance 消息 → CameraService 流 → Doka 覆盖层。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('原生推送识别帧后主体框跟随，移动手机时目标环原点同步移动', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const channel = MethodChannel('prime/camera_test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initialize' || call.method == 'requestPermission') {
        return <String, dynamic>{
          'status': 'ready',
          'textureId': 101,
          'zoom': 1.0,
        };
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(
      MaterialApp(
        home: CameraPage(
          camera: CameraService(channel: channel),
          initialScene: SceneMode.portrait,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    // Doka 空闲态：不播放开场白，也不画目标环。
    expect(find.text('AI正在分析画面'), findsNothing);
    expect(find.byType(GuideOverlay), findsNothing);

    await tester.tap(find.byKey(const ValueKey('ai-compose')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('AI正在分析画面'), findsOneWidget);

    final codec = const StandardMethodCodec();
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(
        const MethodCall('guidance', <String, dynamic>{
          'box': <double>[0.30, 0.08, 0.40, 0.62],
          'face': <double>[0.46, 0.10, 0.09, 0.16],
          'roll': 0.4,
          'pitch': 0.0,
          'frameW': 1080,
          'frameH': 1920,
          'hfov': 42.0,
          'ts': 1000,
        }),
      ),
      (_) {},
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('请对准彩色圆环'), findsOneWidget);
    final first = tester.widget<GuideOverlay>(find.byType(GuideOverlay));
    final firstCenterX = first.subjectBox[0] + first.subjectBox[2] / 2;

    // 用户往左移动手机后，主体框必须跟着原生新框走。
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(
        const MethodCall('guidance', <String, dynamic>{
          'box': <double>[0.08, 0.10, 0.30, 0.60],
          'face': <double>[0.18, 0.12, 0.09, 0.16],
          'roll': 0.4,
          'pitch': 0.0,
          'frameW': 1080,
          'frameH': 1920,
          'hfov': 42.0,
          'ts': 2000,
        }),
      ),
      (_) {},
    );
    await tester.pump(const Duration(milliseconds: 100));

    final second = tester.widget<GuideOverlay>(find.byType(GuideOverlay));
    final secondCenterX = second.subjectBox[0] + second.subjectBox[2] / 2;
    expect(secondCenterX, lessThan(firstCenterX - 0.05));
  });
}
