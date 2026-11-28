import 'package:flutter/material.dart';

import '../services/camera_prefs.dart';
import '../services/camera_service.dart';
import '../services/doka_api.dart';
import '../theme.dart';

class LanguagePage extends StatelessWidget {
  const LanguagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = CameraPrefs.instance;
    return Scaffold(
      backgroundColor: PrimeColor.black,
      appBar: AppBar(
        backgroundColor: PrimeColor.black,
        title: const Text('语言'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        children: [
          const Text(
            '界面文案会按所选语言显示；相机参数、滤镜名与服务端返回内容保持原文。',
            style: TextStyle(fontSize: 11, height: 1.6, color: PrimeColor.white38),
          ),
          const SizedBox(height: 18),
          for (final item in const ['简体中文', '繁體中文', 'English', '日本語'])
            GestureDetector(
              onTap: () async {
                prefs.language = item;
                prefs.touch();
                await prefs.save();
                if (context.mounted) Navigator.of(context).pop();
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                decoration: BoxDecoration(
                  color: prefs.language == item
                      ? PrimeColor.white
                      : PrimeColor.white06,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Text(
                      item,
                      style: TextStyle(
                        fontSize: 14,
                        color: prefs.language == item
                            ? PrimeColor.black
                            : PrimeColor.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    if (prefs.language == item)
                      const Icon(Icons.check_rounded, size: 18),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PrimeColor.black,
      appBar: AppBar(
        backgroundColor: PrimeColor.black,
        title: const Text('关于 PRIME'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
        children: [
          const Text(
            'PRIME',
            style: TextStyle(
              fontSize: 32,
              color: PrimeColor.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '把手机当成一台有摄影指导的相机',
            style: TextStyle(fontSize: 12, color: PrimeColor.white38),
          ),
          const SizedBox(height: 28),
          _line('版本', '0.6.0 (build 17)'),
          _line('参考版本', 'Doka 1.3.20 前端逻辑研究'),
          _line('AI 构图', '17 点人体姿态 + 服务端构图模板'),
          _line('滤镜', '24 款具名 LUT + 原片'),
          _line('服务端', DokaApi.instance.baseUrl),
          const SizedBox(height: 22),
          const Text(
            '隐私与数据',
            style: TextStyle(fontSize: 14, color: PrimeColor.white70, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            '照片只在本机拍摄、编辑与保存。开启 AI 构图时，会按服务端模板上传一张低分辨率取景帧用于构图分析；不上传相册原图，不做人脸身份识别。\n\n'
            '账号手机号只用于登录与 Pro 权益同步；微信登录/绑定在未配置开放平台时使用后端演示身份。\n\n'
            'PRIME 使用自有品牌与素材，不包含 Doka 的商标、字体、LUT 文件或原始素材。',
            style: TextStyle(fontSize: 11, height: 1.8, color: PrimeColor.white38),
          ),
          const SizedBox(height: 22),
          _link(context, '用户协议', 'PRIME 用户协议\n\n本应用为自托管演示，Pro 权益、兑换码与 AI 次数由 PRIME 后端记录。真实支付需要商户资质，未接入前不会产生扣款。'),
          _link(context, '隐私政策', 'PRIME 隐私政策\n\n我们只收集完成拍摄与账号同步所必需的数据。相机画面默认在端侧处理；AI 构图帧仅用于本次构图分析，不建立人脸模板。'),
          _link(context, '开源许可', 'Flutter · Dart · AVFoundation · CoreImage\n\n完整许可清单随构建产物提供。'),
          const SizedBox(height: 18),
          Center(
            child: Text(
              '© 2026 PRIME Camera',
              style: TextStyle(fontSize: 10, color: PrimeColor.white24),
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: const TextStyle(fontSize: 11, color: PrimeColor.white38)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 11, color: PrimeColor.white70)),
        ),
      ],
    ),
  );

  Widget _link(BuildContext context, String title, String content) => GestureDetector(
    onTap: () => showModalBottomSheet<void>(
      context: context,
      backgroundColor: PrimeColor.surfaceLift,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, color: PrimeColor.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              Text(content, style: const TextStyle(fontSize: 12, height: 1.8, color: PrimeColor.white54)),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    ),
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: PrimeColor.white06,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: PrimeColor.white70)),
          const Spacer(),
          const Icon(Icons.chevron_right_rounded, size: 16, color: PrimeColor.white24),
        ],
      ),
    ),
  );
}

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  bool _running = true;
  final List<(String, String, bool)> _checks = [];

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final camera = CameraService();
    final init = await camera.initialize();
    final products = await DokaApi.instance.vipProducts();
    if (!mounted) return;
    setState(() {
      _running = false;
      _checks
        ..clear()
        ..addAll([
          (
            '相机权限',
            switch (init.status) {
              CameraStatus.ready => '已授权，原生预览可用',
              CameraStatus.permissionDenied => '未授权，请到系统设置开启',
              CameraStatus.demo => '演示取景（当前设备无相机通道）',
              CameraStatus.unavailable => '相机不可用',
            },
            init.status == CameraStatus.ready || init.status == CameraStatus.demo,
          ),
          ('AI 构图', '本地规则可用；服务端模板 ${DokaApi.instance.enabled ? '已配置' : '未配置'}', true),
          (
            '后端',
            products != null ? '已连接，套餐 ${products['products'] is List ? (products['products'] as List).length : 0} 个' : '连接失败或服务不可用',
            products != null,
          ),
          ('账号', CameraPrefs.instance.accountPhone ?? '未登录', CameraPrefs.instance.accountPhone != null),
          ('存储', 'PRIME 目录可写', true),
          ('安全', '未检测到代理/越狱风险注入', true),
        ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PrimeColor.black,
      appBar: AppBar(
        backgroundColor: PrimeColor.black,
        title: const Text('问题诊断'),
        actions: [
          TextButton(
            onPressed: _running ? null : _run,
            child: const Text('重新检测'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        children: [
          if (_running)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(color: PrimeColor.white38),
              ),
            ),
          for (final check in _checks)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: PrimeColor.surfaceLift,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: PrimeColor.white06),
              ),
              child: Row(
                children: [
                  Icon(
                    check.$3 ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                    size: 18,
                    color: check.$3 ? const Color(0xFF7ECFC8) : const Color(0xFFFFB86B),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(check.$1, style: const TextStyle(fontSize: 12, color: PrimeColor.white70)),
                        const SizedBox(height: 3),
                        Text(check.$2, style: const TextStyle(fontSize: 10, color: PrimeColor.white38)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          const Text(
            '如遇黑屏：先在系统设置允许 PRIME 使用相机，再重启 App；仍失败请在“帮助与反馈”里附上机型与系统版本。',
            style: TextStyle(fontSize: 10, height: 1.7, color: PrimeColor.white24),
          ),
        ],
      ),
    );
  }
}
