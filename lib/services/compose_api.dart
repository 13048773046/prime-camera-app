import 'dart:convert';

import 'package:http/http.dart' as http;

class ComposeResult {
  final String subject;
  final List<double> subjectBox;
  final List<double> targetBox;
  final double targetZoom;
  final double horizonFix;
  final String hint;
  final List<String> reasons;
  final double confidence;
  final String source;
  final String? actionLabel;
  final double? distanceMeters;
  final double progress;

  const ComposeResult({
    required this.subject,
    required this.subjectBox,
    required this.targetBox,
    required this.targetZoom,
    required this.horizonFix,
    required this.hint,
    required this.reasons,
    required this.confidence,
    required this.source,
    this.actionLabel,
    this.distanceMeters,
    this.progress = 0.12,
  });

  factory ComposeResult.fromJson(Map<String, dynamic> json) {
    List<double> box(String key) => (json[key] as List? ?? const [])
        .map((e) => (e as num).toDouble())
        .toList();
    return ComposeResult(
      subject: json['subject']?.toString() ?? 'unknown',
      subjectBox: box('subject_box'),
      targetBox: box('target_box'),
      targetZoom: (json['target_zoom'] as num? ?? 1).toDouble(),
      horizonFix: (json['horizon_fix'] as num? ?? 0).toDouble(),
      hint: json['hint']?.toString() ?? '把主体放到画面中间',
      reasons: (json['reasons'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      confidence: (json['confidence'] as num? ?? 0).toDouble(),
      source: json['source']?.toString() ?? 'fallback',
    );
  }
}

class ComposeApi {
  ComposeApi({this.baseUrl = 'http://127.0.0.1:8791'});

  final String baseUrl;

  Future<ComposeResult> compose({
    required String imageBase64,
    required String mode,
    required double zoom,
    required double tilt,
    required double roll,
  }) async {
    final uri = Uri.parse('$baseUrl/v1/compose');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'image': imageBase64,
            'mode': mode,
            'device': {'lens': 'wide', 'zoom': zoom, 'aspect': '3:4'},
            'tilt': tilt,
            'roll': roll,
          }),
        )
        .timeout(const Duration(seconds: 3));
    if (response.statusCode != 200) {
      throw StateError('compose failed: ${response.statusCode}');
    }
    return ComposeResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
