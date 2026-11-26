import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prime_camera/pages/camera_page.dart';
import 'package:prime_camera/services/camera_service.dart';
import 'package:prime_camera/widgets/guide_ring.dart';

/// 演示模式：不依赖原生相机，验证黑白取景页的排版与状态。
CameraService _demoCamera() => CameraService(forceDemo: true);

void main() {
  testWidgets('取景页先显示分析态，再显示拍法与焦段胶囊', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: CameraPage(camera: _demoCamera())),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('定焦'), findsOneWidget);
    expect(find.text('PRIME'), findsOneWidget);
    expect(find.text('正在读取画面构图'), findsOneWidget);
    expect(find.text('请稳住手机，不要移动'), findsOneWidget);
    expect(find.text('通用'), findsOneWidget);
    expect(find.text('人像'), findsOneWidget);
    expect(find.text('街景'), findsOneWidget);
    expect(find.byKey(const ValueKey('shutter')), findsOneWidget);
    // 取景层必须铺满屏幕，而不是 3:4 小框。
    expect(tester.getSize(find.byType(GuideOverlay)), const Size(390, 844));

    // 分析结束后出现通用口令；人像拍法入口只会在人像模式出现。
    await tester.pump(const Duration(milliseconds: 1800));
    expect(find.text('把画面重点放进中心环'), findsOneWidget);
    expect(find.text('通用构图 · 全屏'), findsOneWidget);
    expect(find.text('切换构图方案'), findsNothing);

    // 切到人像后恢复全身拍法与口令。
    await tester.tap(find.byKey(const ValueKey('scene-portrait')));
    await tester.pump(const Duration(milliseconds: 1800));
    expect(find.text('后退半步，镜头降到胸口'), findsOneWidget);
    expect(find.text('切换构图方案'), findsOneWidget);
    expect(find.text('全身 · 1× · 居中'), findsOneWidget);

    // 焦段切换后，拍法与口令一起更新。
    await tester.tap(find.byKey(const ValueKey('zoom-2')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('再靠近半步，肩膀切出画面'), findsOneWidget);
    expect(find.text('七分身 · 2× · 右三分'), findsOneWidget);
  });
}
