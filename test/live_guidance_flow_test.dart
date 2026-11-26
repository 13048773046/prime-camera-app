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
      MaterialApp(home: CameraPage(camera: CameraService(channel: channel))),
    );
    await tester.pump(const Duration(milliseconds: 300));
    // 原生 ready 后先显示“分析中”，一秒后才允许口令接管。
    expect(find.text('正在进行人像构图分析'), findsOneWidget);
    expect(find.text('请稳住手机，不要移动'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1200));
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
    expect(find.text('对齐了 · 可以按快门'), findsOneWidget);
    expect(find.text('双环重合 · 直接出片'), findsOneWidget);
    expect(find.text('切换构图方案'), findsOneWidget);
  });
}
