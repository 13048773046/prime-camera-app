import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prime_camera/pages/camera_page.dart';
import 'package:prime_camera/services/camera_service.dart';

class _FakeCameraService extends CameraService {
  @override
  Future<CameraStatus> initialize() async => CameraStatus.unavailable;

  @override
  Future<void> setZoom(double zoom) async {}

  @override
  Future<String?> takePhoto() async => null;
}

void main() {
  testWidgets('Camera page renders guide hint, viewfinder status and capture button', (tester) async {
    await tester.pumpWidget(MaterialApp(home: CameraPage(camera: _FakeCameraService())));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('定焦 PRIME'), findsOneWidget);
    expect(find.text('原生相机内核待接入，当前为取景窗占位'), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt), findsWidgets);
    expect(find.text('重新构图'), findsOneWidget);
    expect(find.text('对齐'), findsOneWidget);
    expect(find.text('后退半步，镜头降到胸口'), findsOneWidget);
  });
}
