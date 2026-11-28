import 'package:flutter/services.dart';

import 'camera_prefs.dart';

/// 原生 UserDefaults 持有一个 7 天有效的 PRIME token；
/// 不把手机号/密码写进日志，也不依赖第三方存储插件。
class PrimeSession {
  PrimeSession._();

  static const MethodChannel _channel = MethodChannel('prime/camera');

  static Future<void> restore() async {
    try {
      final data = await _channel.invokeMapMethod<String, dynamic>(
        'loadSession',
      );
      if (data == null) return;
      final token = data['token']?.toString() ?? '';
      if (token.isEmpty) return;
      CameraPrefs.instance.authToken = token;
      final phone = data['phone']?.toString() ?? '';
      if (phone.isNotEmpty) CameraPrefs.instance.accountPhone = phone;
      final name = data['name']?.toString() ?? '';
      if (name.isNotEmpty) CameraPrefs.instance.userName = name;
    } on MissingPluginException {
      // Web/单测环境没有原生通道。
    } on PlatformException {
      // 读取失败不阻塞启动。
    }
  }

  static Future<void> save() async {
    try {
      await _channel.invokeMethod<void>('saveSession', {
        'token': CameraPrefs.instance.authToken ?? '',
        'phone': CameraPrefs.instance.accountPhone ?? '',
        'name': CameraPrefs.instance.userName ?? '',
      });
    } on MissingPluginException {
      // 忽略。
    } on PlatformException {
      // 忽略。
    }
  }

  static Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('clearSession');
    } on MissingPluginException {
      // 忽略。
    } on PlatformException {
      // 忽略。
    }
  }
}
