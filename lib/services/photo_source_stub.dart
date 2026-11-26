import 'package:flutter/material.dart';

/// Web / 无照片环境下的占位；真机上由 photo_source_io.dart 覆盖。
Widget buildPhotoImage(String? path, {BoxFit fit = BoxFit.cover}) {
  return Image.asset('assets/demo/scene.jpg', fit: fit);
}
