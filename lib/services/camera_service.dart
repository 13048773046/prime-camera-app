import 'dart:async';

import 'package:flutter/services.dart';

import 'guidance.dart';

/// 原生相机内核的 Dart 端。
///
/// iOS 侧通过 `prime/camera` MethodChannel 暴露：
/// initialize / requestPermission / openSettings / setZoom / switchCamera /
/// takePhoto / saveToAlbum / share。
/// 取景期间原生会反向调用 `guidance`，推送实时的主体框与手机角度。
/// 未接入内核（Web 预览、单元测试）时返回 demo 状态，页面显示演示取景，不伪装成实时画面。
class CameraService {
  CameraService({MethodChannel? channel, bool? forceDemo})
    : _channel = channel ?? const MethodChannel('prime/camera'),
      _forceDemo = forceDemo ?? false {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  final MethodChannel _channel;
  final bool _forceDemo;
  final StreamController<GuidanceFrame> _guidance =
      StreamController<GuidanceFrame>.broadcast();
  final StreamController<CameraFrameTick> _frames =
      StreamController<CameraFrameTick>.broadcast();

  bool _initialized = false;
  int? _textureId;
  bool _ultraWide = false;

  int? get textureId => _textureId;
  bool get isReady => _initialized && _textureId != null;
  bool get ultraWideAvailable => _ultraWide;

  /// 实时构图流：原生约 5–6fps 推送，空结果表示画面里没有找到主体。
  Stream<GuidanceFrame> get guidanceStream => _guidance.stream;

  /// 原生取景帧心跳，约 2fps。用于发现纹理停止刷新并触发轻量重启。
  Stream<CameraFrameTick> get frameStream => _frames.stream;

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'guidance' && call.arguments is Map) {
      _guidance.add(
        GuidanceFrame.fromMap(Map<String, dynamic>.from(call.arguments as Map)),
      );
    } else if (call.method == 'frame' && call.arguments is Map) {
      _frames.add(
        CameraFrameTick.fromMap(
          Map<String, dynamic>.from(call.arguments as Map),
        ),
      );
    }
    return null;
  }

  Future<CameraInitResult> initialize() async {
    if (_initialized) {
      return CameraInitResult(
        status: CameraStatus.ready,
        textureId: _textureId,
        ultraWide: _ultraWide,
      );
    }
    if (_forceDemo) {
      return const CameraInitResult(status: CameraStatus.demo, message: '演示取景');
    }
    // 原生 host 在 implicit engine 初始化时才注册 channel。Dart 的
    // 第一帧可能比 host 早几毫秒，这里短暂重试，避免第一次
    // MissingPluginException 后永久落到演示图（取景不动、0.5×无反应）。
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        final result = await _channel.invokeMapMethod<String, dynamic>(
          'initialize',
        );
        final status = result?['status']?.toString() ?? 'unavailable';
        final id = (result?['textureId'] as num?)?.toInt();
        _ultraWide = result?['ultraWide'] == true;
        switch (status) {
          case 'ready':
            _initialized = true;
            _textureId = id;
            return CameraInitResult(
              status: CameraStatus.ready,
              textureId: id,
              ultraWide: _ultraWide,
            );
          case 'denied':
            return const CameraInitResult(
              status: CameraStatus.permissionDenied,
              message: '相机权限未开启',
            );
          case 'restricted':
            return const CameraInitResult(
              status: CameraStatus.permissionDenied,
              message: '系统限制了相机访问',
            );
          case 'demo':
            return CameraInitResult(
              status: CameraStatus.demo,
              textureId: id,
              ultraWide: true,
            );
          default:
            return CameraInitResult(
              status: CameraStatus.unavailable,
              message: result?['message']?.toString() ?? '相机暂不可用',
            );
        }
      } on MissingPluginException {
        if (attempt == 5) {
          return const CameraInitResult(
            status: CameraStatus.unavailable,
            message: '原生相机内核未连接',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 350));
      } on PlatformException catch (error) {
        return CameraInitResult(
          status: CameraStatus.unavailable,
          message: error.message ?? '相机初始化失败',
        );
      }
    }
    return const CameraInitResult(
      status: CameraStatus.unavailable,
      message: '原生相机内核未连接',
    );
  }

  Future<bool> requestPermission() async {
    try {
      // 原生侧申请权限后直接配置会话，返回与 initialize 相同的结果字典。
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'requestPermission',
      );
      if (result?['status']?.toString() == 'ready') {
        _initialized = true;
        _textureId = (result?['textureId'] as num?)?.toInt();
        _ultraWide = result?['ultraWide'] == true;
        return true;
      }
      return false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openSettings');
    } on MissingPluginException {
      // 忽略：Web 预览无系统设置页。
    } on PlatformException {
      // 忽略。
    }
  }

  /// 返回镜头实际采用的倍率；无超广角/受限机型会回落到最近可用的倍率。
  Future<double?> setZoom(double zoom) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'setZoom',
        {'zoom': zoom},
      );
      return (result?['zoom'] as num?)?.toDouble();
    } on MissingPluginException {
      // 演示模式。
      return null;
    } on PlatformException {
      // 镜头可能不支持该倍率，静默回退。
      return null;
    }
  }

  Future<void> focusAt(double x, double y) async {
    try {
      await _channel.invokeMethod<void>('focusAt', <String, dynamic>{
        'x': x,
        'y': y,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<void> setExposure(double value) async {
    try {
      await _channel.invokeMethod<void>('setExposure', <String, dynamic>{
        'value': value,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<double?> switchCamera() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'switchCamera',
      );
      return (result?['zoom'] as num?)?.toDouble();
    } on MissingPluginException {
      // 演示模式。
      return null;
    } on PlatformException {
      // 忽略。
      return null;
    }
  }

  /// 纹理长时间没有新帧时，重启一次 running 状态；返回是否成功。
  Future<bool> restart() async {
    try {
      final ok = await _channel.invokeMethod<bool>('restart');
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<String?> takePhoto({
    bool flash = false,
    String filter = 'none',
    String ratio = 'threeFour',
    bool livePhoto = false,
    bool saveRaw = false,
    bool selfieMirror = true,
    bool noiseReduction = true,
    bool watermark = true,
    String watermarkStyle = 'minimal',
    double exposure = 0.0,
  }) async {
    try {
      return await _channel.invokeMethod<String>('takePhoto', <String, dynamic>{
        'flash': flash,
        'filter': filter,
        'ratio': ratio,
        'livePhoto': livePhoto,
        'saveRaw': saveRaw,
        'selfieMirror': selfieMirror,
        'noiseReduction': noiseReduction,
        'watermark': watermark,
        'watermarkStyle': watermarkStyle,
        'exposure': exposure,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<String?> editPhoto({
    required String path,
    String filter = 'none',
    String ratio = 'threeFour',
    int rotate = 0,
    bool flip = false,
    String border = 'minimal',
    bool watermark = true,
  }) async {
    try {
      return await _channel.invokeMethod<String>('editPhoto', {
        'path': path,
        'filter': filter,
        'ratio': ratio,
        'rotate': rotate,
        'flip': flip,
        'border': border,
        'watermark': watermark,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<List<String>> pickPhotos() async {
    try {
      final list = await _channel.invokeListMethod<String>('pickPhotos');
      return list ?? <String>[];
    } on MissingPluginException {
      return <String>[];
    } on PlatformException {
      return <String>[];
    }
  }

  Future<List<String>> listPhotos() async {
    try {
      final list = await _channel.invokeListMethod<String>('listPhotos');
      return list ?? <String>[];
    } on MissingPluginException {
      return <String>[];
    } on PlatformException {
      return <String>[];
    }
  }

  Future<bool> deletePhoto(String path) async {
    try {
      return await _channel.invokeMethod<bool>('deletePhoto', {'path': path}) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> shareFiles(List<String> paths) async {
    if (paths.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('shareFiles', {'paths': paths}) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 抓一帧当前取景 JPEG，用于服务端 scan。只在真机原生内核可用；
  /// Web/单元测试返回 null，页面继续走端侧 Vision，不阻塞取景。
  Future<Uint8List?> capturePreviewJpeg() async {
    if (_forceDemo) return null;
    try {
      final bytes = await _channel.invokeMethod<Uint8List>(
        'capturePreviewJpeg',
      );
      if (bytes == null || bytes.isEmpty) return null;
      return bytes;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<bool> saveToAlbum(String? path, {String? bytes}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('saveToAlbum', {
        'path': ?path,
      });
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> share(String? path) async {
    try {
      final ok = await _channel.invokeMethod<bool>('share', {'path': ?path});
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

enum CameraStatus { ready, demo, permissionDenied, unavailable }

class CameraInitResult {
  const CameraInitResult({
    required this.status,
    this.textureId,
    this.message,
    this.ultraWide = false,
  });

  final CameraStatus status;
  final int? textureId;
  final String? message;
  final bool ultraWide;
}

class CameraFrameTick {
  const CameraFrameTick({
    required this.ts,
    required this.width,
    required this.height,
  });

  final int ts;
  final int width;
  final int height;

  factory CameraFrameTick.fromMap(Map<String, dynamic> map) => CameraFrameTick(
    ts: (map['ts'] as num? ?? 0).toInt(),
    width: (map['w'] as num? ?? 1080).toInt(),
    height: (map['h'] as num? ?? 1920).toInt(),
  );
}
