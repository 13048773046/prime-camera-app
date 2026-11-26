import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prime_camera/pages/camera_page.dart';
import 'package:prime_camera/services/camera_service.dart';

/// 演示模式：不依赖原生相机，验证排版与口令卡。
CameraService _demoCamera() => CameraService(forceDemo: true);

void main() {
  testWidgets('取景页渲染标题、口令气泡、焦段胶片条与快门', (tester) async {
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
    expect(find.text('口令刻度'), findsOneWidget);
    expect(find.text('流萤 · 口令 ①'), findsOneWidget);
    expect(find.text('后退半步，镜头降到胸口'), findsOneWidget);
    expect(find.text('拍'), findsOneWidget);

    // 焦段切换后口令应更新。
    await tester.tap(find.text('2×'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('再靠近半步，肩膀切出画面'), findsOneWidget);
  });
}
