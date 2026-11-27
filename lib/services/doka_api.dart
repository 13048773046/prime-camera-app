import 'dart:convert';

import 'package:http/http.dart' as http;

/// Doka `ApiService` 的 Dart 同构客户端。
///
/// 只有编译时传入 `--dart-define=PRIME_API_BASE=https://...` 才会启用；
/// 未配置时保持本地体验账号，不把手机号发到任何地方。
class DokaApi {
  DokaApi({String? baseUrl})
    : baseUrl = baseUrl ?? const String.fromEnvironment('PRIME_API_BASE', defaultValue: 'https://uosar.yosar.cloud');

  static final DokaApi instance = DokaApi();

  final String baseUrl;

  bool get enabled => baseUrl.trim().isNotEmpty;

  Uri _uri(String path) =>
      Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');

  Future<Map<String, dynamic>?> _post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    if (!enabled) return null;
    try {
      final response = await http
          .post(
            _uri(path),
            headers: {
              'Content-Type': 'application/json',
              if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['code'] != 0) return null;
      final data = map['data'];
      return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    } catch (_) {
      return null;
    }
  }

  /// 返回开发环境的验证码；生产环境返回 null。
  Future<String?> getCode(String phone, {String scene = 'login'}) async {
    final data = await _post('/ai_camera/auth/get_code', {
      'phone_num': phone,
      'scene': scene,
    });
    return data?['dev_code']?.toString();
  }

  Future<Map<String, dynamic>?> login(String phone, String code, {String username = ''}) {
    return _post('/ai_camera/auth/login', {
      'phone_num': phone,
      'msg_code': code,
      'username': username,
    });
  }

  Future<Map<String, dynamic>?> me(String token) async {
    return _post('/ai_camera/auth/me', const {}, token: token);
  }

  Future<Map<String, dynamic>?> redeem(String code, String token) async {
    return _post('/api/v1/redeem_vip_code', {'redeem_code': code}, token: token);
  }
}
