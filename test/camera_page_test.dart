import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prime_camera/pages/camera_page.dart';
import 'package:prime_camera/services/camera_service.dart';
import 'package:prime_camera/services/guidance.dart';
import 'package:prime_camera/widgets/guide_ring.dart';

/// 演示模式：不依赖原生相机，验证 Doka 相机页的排版与状态。
CameraService _demoCamera() => CameraService(forceDemo: true);

void main() {
  testWidgets('Doka 1.3.20 相机页：空闲 5 选项、构图态 3 选项、3:4 满宽取景', (tester) async {
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

    expect(find.byKey(const ValueKey('shutter')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-compose')), findsOneWidget);
    expect(find.byKey(const ValueKey('ratio-button')), findsOneWidget);
    expect(find.text('AI正在分析画面'), findsNothing);
    // 空闲态不自动扫，不出现 Doka 的分析 HUD。
    expect(find.text('AI构图'), findsNothing);
    expect(find.text('退出构图'), findsNothing);

    // Doka 空闲态不显示目标环/扫描层。
    expect(find.byType(GuideOverlay), findsNothing);

    // 点 AI 构图：进入 Doka 分析态，HUD 原文 + 扫描层。
    await tester.tap(find.byKey(const ValueKey('ai-compose')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('AI正在分析画面'), findsOneWidget);
    expect(find.text('请稳住手机，不要移动'), findsOneWidget);
    // 预览左右各留 12dp，3:4 高度 = 366 * 4/3。
    expect(tester.getSize(find.byType(GuideOverlay)), const Size(366, 488));

    // 2 秒后拿到构图结果，HUD 切成“请对准彩色圆环”，选项行收成 3 个。
    await tester.pump(const Duration(milliseconds: 1900));
    expect(find.text('请对准彩色圆环'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    // 比例可切：1:1 后取景层变成 366×366。
    await tester.tap(find.byKey(const ValueKey('ratio-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('取景比例'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ratio-oneOne')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getSize(find.byType(GuideOverlay)), const Size(366, 366));
  });
}
