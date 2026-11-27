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

  /// 服务端只回中文滤镜名；沿用 Doka 的命名并映射到本地胶片 id。
  String get filterId => switch (filterName) {
        '清透' => 'clear',
        '暖调' => 'warm',
        '冷调' => 'cool',
        '黑白' => 'mono',
        'Doka S50' => 'doka_s50',
        'Doka S100' => 'doka_s100',
        'Doka S400' => 'doka_s400',
        'Classic Chrome' => 'classic_chrome',
        'Portra 400' => 'portra400',
        'Gold 200' => 'kodak_gold',
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
    : baseUrl = baseUrl ?? const String.fromEnvironment('PRIME_API_BASE');

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
  }) async {
    if (!enabled) return null;
    final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/v1/scan');
    final request = http.MultipartRequest('POST', uri)
      ..fields['shoot_type'] = 'preview'
      ..fields['direction'] = scene
      ..fields['compose_times'] = '0'
      ..fields['scan_focal_length'] = zoom.toStringAsFixed(2)
      ..fields['ai_filter'] = ''
      ..fields['timestamp'] = DateTime.now().millisecondsSinceEpoch.toString()
      ..fields['comp_scene'] = scene
      ..fields['recommend_mode'] = 'auto'
      ..fields['ai_filter_preferences'] = ''
      ..fields['language'] = 'zh'
      ..fields['region'] = 'CN'
      ..fields['distribution'] = 'store'
      ..fields['subject_kind'] = subjectKind
      ..fields['aspect'] = '3:4'
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
