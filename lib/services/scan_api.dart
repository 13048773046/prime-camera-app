import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Doka 式 scan 返回的最小客户端模型。
///
/// 服务端契约来自对 Doka 1.3.20 的反编译：
/// `POST ai_camera/v2`（multipart）→ `BaseRespEntity<CameraData>`。
/// 客户端只消费真正会用到的字段，其余字段保留在 [raw] 里。
class ScanPlan {
  const ScanPlan({
    required this.cropRect,
    required this.reason,
    required this.focalLength,
    required this.bodyRange,
    required this.subAreaSize,
    required this.filterName,
    this.templateUrl,
  });

  /// `SubAreaRectNorm`：X/Y/W/H，相对完整取景画幅归一化。
  final List<double> cropRect;
  final String reason;
  final String focalLength;
  final String bodyRange;
  final String subAreaSize;
  final String filterName;
  final String? templateUrl;

  /// 服务端只回中文/英文滤镜名；映射到 24 款本地胶片 id。
  String get filterId => switch (filterName) {
        'Doka S50' || 'S50' => 'doka_s50',
        'Doka S100' || 'S100' => 'doka_s100',
        'Doka S160' || 'S160' => 'doka_s160',
        'Doka S200' || 'S200' => 'doka_s200',
        'Doka S400' || 'S400' => 'doka_s400',
        'Doka X100' || 'X100' => 'doka_x100',
        'Doka X400' || 'X400' => 'doka_x400',
        'Classic Chrome' => 'f_classic_chrome',
        'PROVIA' || 'Provia' => 'f_provia',
        'Velvia' => 'f_velvia',
        'CC' => 'f_cc',
        'Classic Neg' => 'f_classic_neg',
        'CN' => 'f_cn',
        'C200' => 'f_c200',
        '160C' => 'f_160c',
        'Pro Neg' => 'f_pro_neg',
        '400H' => 'f_400h',
        'F S100' => 'f_s100',
        'F S400' => 'f_s400',
        'Portra 160' => 'k_portra160',
        'Gold 200' => 'k_gold200',
        'Portra 400' => 'k_portra400',
        'Vista 800' => 'agfa_vista800',
        'AP 100' || 'APX 100' => 'agfa_ap100',
        '清透' || 'Clear' => 'doka_s100',
        _ => 'none',
      };

  factory ScanPlan.fromData(Map<String, dynamic> data) {
    Map<String, dynamic> map(dynamic value) =>
        value is Map ? Map<String, dynamic>.from(value) : const {};
    final rect = map(data['SubAreaRectNorm']);
    double n(String key, String lower) {
      final value = (rect[key] as num?) ?? (rect[lower] as num?) ?? 0;
      return value.toDouble();
    }
    final filter = map(data['AiCameraFilter']);
    return ScanPlan(
      cropRect: [
        n('X', 'x'),
        n('Y', 'y'),
        n('W', 'w'),
        n('H', 'h'),
      ],
      reason: data['ComposeReason']?.toString() ?? '',
      focalLength: data['ExifFocalLength']?.toString() ?? '',
      bodyRange: data['BodyRange']?.toString() ?? '',
      subAreaSize: data['SubAreaSize']?.toString() ?? '',
      filterName: filter['FilterName']?.toString() ?? '',
      templateUrl: data['PredictSubAreaPicURL']?.toString(),
    );
  }
}

/// 仅在编译时传入 `--dart-define=PRIME_API_BASE=https://...` 时启用。
/// 未配置时保持纯端侧模式，IPA 不依赖任何外部服务。
class ScanApi {
  ScanApi({String? baseUrl})
    : baseUrl = baseUrl ?? const String.fromEnvironment('PRIME_API_BASE', defaultValue: 'https://uosar.yosar.cloud');

  final String baseUrl;

  bool get enabled => baseUrl.trim().isNotEmpty;

  Future<ScanPlan?> scan({
    required Uint8List jpeg,
    required String scene,
    required double zoom,
    required double tilt,
    required double roll,
    List<double>? subjectBox,
    String subjectKind = 'person',
    String aiFilterPreferences = '',
    String aspect = '3:4',
  }) async {
    if (!enabled) return null;
    final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/ai_camera/v2');
    final request = http.MultipartRequest('POST', uri)
      ..fields['shoot_type'] = 'preview'
      ..fields['direction'] = scene
      ..fields['compose_times'] = '0'
      ..fields['scan_focal_length'] = zoom.toStringAsFixed(2)
      ..fields['ai_filter'] = ''
      ..fields['timestamp'] = DateTime.now().millisecondsSinceEpoch.toString()
      ..fields['comp_scene'] = scene
      ..fields['recommend_mode'] = 'auto'
      ..fields['ai_filter_preferences'] = aiFilterPreferences
      ..fields['language'] = 'zh'
      ..fields['region'] = 'CN'
      ..fields['distribution'] = 'store'
      ..fields['subject_kind'] = subjectKind
      ..fields['aspect'] = aspect
      ..fields['zoom'] = zoom.toStringAsFixed(2)
      ..fields['tilt'] = tilt.toStringAsFixed(2)
      ..fields['roll'] = roll.toStringAsFixed(2);
    if (subjectBox != null && subjectBox.length == 4) {
      request.fields['subject_box'] = jsonEncode(subjectBox);
    }
    request.files.add(
      http.MultipartFile.fromBytes('file', jpeg, filename: 'frame.jpg'),
    );
    try {
      final streamed = await request.send().timeout(const Duration(seconds: 4));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'];
      if (body['code'] != 0 || data is! Map) return null;
      return ScanPlan.fromData(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }
}
