import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prime_camera/pages/camera_page.dart';

void main() {
  testWidgets('Camera page renders guide hint and capture button', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CameraPage()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('定焦 PRIME'), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt), findsWidgets);
    expect(find.text('重新构图'), findsOneWidget);
    expect(find.text('对齐'), findsOneWidget);
  });
}
