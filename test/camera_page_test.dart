import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prime_camera/pages/camera_page.dart';
import 'package:prime_camera/services/camera_service.dart';
import 'package:prime_camera/services/guidance.dart';
import 'package:prime_camera/widgets/guide_ring.dart';

/// 演示模式：不依赖原生相机，验证黑白取景页的排版与状态。
CameraService _demoCamera() => CameraService(forceDemo: true);

void main() {
  testWidgets('取景页按 3:4 满宽排布，提示会收走，拍法和比例可切换', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: CameraPage(
          camera: _demoCamera(),
          initialScene: SceneMode.portrait,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('你好，我是林晓莹'), findsOneWidget);
    expect(find.text('正在看你的画面和光线'), findsOneWidget);
    expect(find.byKey(const ValueKey('shutter')), findsOneWidget);

    // 宽度必须铺满 390，高度按 3:4 限制在 520；不是 9:16 全屏。
    expect(tester.getSize(find.byType(GuideOverlay)), const Size(390, 520));
    expect(find.text('3:4'), findsOneWidget);

    // 2–3 秒后分析提示自动收走，只留下取景和构图入口。
    await tester.pump(const Duration(milliseconds: 2300));
    expect(find.text('你好，我是林晓莹'), findsNothing);
    expect(find.text('切换构图方案'), findsOneWidget);
    expect(find.byKey(const ValueKey('ratio-button')), findsOneWidget);

    // 测试直接给人像初始场景；真实页面由自动场景识别决定。
    await tester.tap(find.byKey(const ValueKey('plan-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('晓莹的 3 种拍法'), findsOneWidget);

    await tester.tap(find.text('2  七分身'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('切换构图方案'), findsOneWidget);

    // 比例可以自己设：切到 1:1 后取景层变成 390×390。
    await tester.tap(find.byKey(const ValueKey('ratio-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('取景比例'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ratio-oneOne')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getSize(find.byType(GuideOverlay)), const Size(390, 390));
  });
}
