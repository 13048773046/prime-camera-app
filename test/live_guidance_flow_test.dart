import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prime_camera/pages/camera_page.dart';
import 'package:prime_camera/services/camera_service.dart';

/// 端到端（Dart 侧）验证：原生 guidance 消息 → CameraService 流 → 页面口令。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('原生推送识别帧后，取景页实时口令替换分析中', (tester) async {
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
        home: CameraPage(camera: CameraService(channel: channel)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    // 默认是通用场景，先显示阶段性的“稳住手机”小提示。
    expect(find.text('稳住手机'), findsOneWidget);
    expect(find.text('正在识别主体与场景'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('scene-portrait')));
    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.text('识别完成'), findsOneWidget);

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

    expect(find.text('构图已锁定'), findsOneWidget);
    expect(find.text('可以按快门'), findsOneWidget);
    expect(find.text('全身 · 切换构图'), findsOneWidget);

    // 用户往一个方向移动手机后，主体框变化，口令必须跟着变；
    // 这是“移动位置没反应”的回归测试：不能一直停在上一条口令。
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

    expect(find.text('构图建议'), findsOneWidget);
    expect(find.text('手机往左带一点，把人物放进环'), findsOneWidget);
    expect(find.text('构图已锁定'), findsNothing);
  });
}
