import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prime_camera/pages/settings_page.dart';
import 'package:prime_camera/services/camera_prefs.dart';
import 'package:prime_camera/theme.dart';

void main() {
  testWidgets('完整设置页展示 Doka 全部设置组', (tester) async {
    CameraPrefs.instance.reset();
    await tester.pumpWidget(
      MaterialApp(theme: PrimeTheme.build(), home: const SettingsPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('实况照片'), findsOneWidget);
    expect(find.text('保存底片'), findsOneWidget);
    final firstSwitch = find.byType(Switch).first;
    await tester.tap(firstSwitch);
    await tester.pump();
    expect(CameraPrefs.instance.livePhoto, isTrue);

    for (final label in ['AI 多景别构图', 'AI 构图停留确认', '降噪优化', '水印和边框', '问题诊断', '关于 PRIME']) {
      await tester.scrollUntilVisible(find.text(label), 260);
    }
  });

  testWidgets('使用引导页 5 步完整', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: PrimeTheme.build(), home: const GuidePage()),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('先选一个拍法'), findsOneWidget);
    expect(find.textContaining('等双环重合'), findsOneWidget);
    expect(find.textContaining('拍完再微调'), findsOneWidget);
  });
}
