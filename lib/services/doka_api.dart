import 'dart:convert';

import 'package:http/http.dart' as http;

/// Doka `ApiService` 的 Dart 同构客户端。
///
/// 只有编译时传入 `--dart-define=PRIME_API_BASE=https://...` 才会启用；
/// 未配置时保持本地体验账号，不把手机号发到任何地方。
class DokaApi {
  DokaApi({String? baseUrl})
    : baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'PRIME_API_BASE',
            defaultValue: 'https://uosar.yosar.cloud',
          );

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
              if (token != null && token.isNotEmpty)
                'Authorization': 'Bearer $token',
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
      return data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};
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

  Future<Map<String, dynamic>?> login(
    String phone,
    String code, {
    String username = '',
  }) {
    return _post('/ai_camera/auth/login', {
      'phone_num': phone,
      'msg_code': code,
      'username': username,
    });
  }

  Future<Map<String, dynamic>?> me(String token) async {
    return _post('/ai_camera/auth/me', const {}, token: token);
  }

  Future<Map<String, dynamic>?> bindPhone(
    String phone,
    String code,
    String token,
  ) {
    return _post('/ai_camera/auth/bind_phone', {
      'phone_num': phone,
      'msg_code': code,
    }, token: token);
  }

  Future<Map<String, dynamic>?> wechatLogin() {
    return _post('/ai_camera/auth/wechat_login', const {});
  }

  Future<Map<String, dynamic>?> bindWechat(String token) {
    return _post('/ai_camera/auth/bind_wechat', const {}, token: token);
  }

  Future<Map<String, dynamic>?> unbindWechat(String token) {
    return _post('/ai_camera/auth/unbind_wechat', const {}, token: token);
  }

  Future<Map<String, dynamic>?> replaceWechat(String token) {
    return _post('/ai_camera/auth/replace_wechat', const {}, token: token);
  }

  Future<Map<String, dynamic>?> verifyWechatChange(String token) {
    return _post('/ai_camera/auth/verify_wechat_change', const {}, token: token);
  }

  Future<Map<String, dynamic>?> redeem(String code, String token) async {
    return _post('/api/v1/redeem_vip_code', {
      'redeem_code': code,
    }, token: token);
  }

  Future<Map<String, dynamic>?> vipProducts() async {
    if (!enabled) return null;
    try {
      final response = await http
          .get(_uri('/ai_camera/vip/products'))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['code'] != 0) return null;
      final data = decoded['data'];
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> createOrder(String productId, String token) {
    return _post('/ai_camera/pay/create_order', {
      'product_id': productId,
    }, token: token);
  }

  Future<Map<String, dynamic>?> mockConfirm(
    String orderNo,
    String token,
  ) async {
    if (!enabled) return null;
    try {
      final response = await http
          .post(
            _uri(
              '/ai_camera/pay/mock_confirm?out_trade_no=${Uri.encodeQueryComponent(orderNo)}',
            ),
            headers: {if (token.isNotEmpty) 'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['code'] != 0) return null;
      final data = decoded['data'];
      return data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> deleteAccount(String token) {
    return _post('/ai_camera/auth/delete_account', const {}, token: token);
  }
}
