import 'dart:async';
import 'package:flutter/services.dart';

/// 相机插件占位接口。
///
/// 当前 MVP 壳先通过 MethodChannel 与原生侧通信；iOS 原生相机内核在 Mac/Xcode 环境接入。
/// 未接入真机内核时，页面展示深色取景窗占位和权限/状态提示，不伪装成真实预览。
class CameraService {
  CameraService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('prime/camera');

  final MethodChannel _channel;
  bool _initialized = false;

  Future<CameraStatus> initialize() async {
    if (_initialized) return CameraStatus.ready;
    try {
      final result = await _channel.invokeMethod<String>('initialize');
      _initialized = result == 'ready';
      return _initialized ? CameraStatus.ready : CameraStatus.unavailable;
    } on MissingPluginException {
      return CameraStatus.unavailable;
    } on PlatformException {
      return CameraStatus.permissionDenied;
    }
  }

  Future<void> setZoom(double zoom) => _channel.invokeMethod<void>('setZoom', {'zoom': zoom});

  Future<String?> takePhoto() async {
    try {
      return await _channel.invokeMethod<String>('takePhoto');
    } on MissingPluginException {
      return null;
    }
  }
}

enum CameraStatus {
  unavailable,
  permissionDenied,
  ready,
}
