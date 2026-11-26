import 'dart:io';
import 'package:flutter/material.dart';
import '../theme.dart';

/// 真机：直接读沙盒里的成片。
Widget buildPhotoImage(String? path, {BoxFit fit = BoxFit.cover}) {
  if (path == null || path.isEmpty) {
    return Container(
      color: PrimeColor.darkLift,
      alignment: Alignment.center,
      child: const Icon(Icons.photo_camera_back_outlined, color: Colors.white24, size: 42),
    );
  }
  return Image.file(File(path), fit: fit, gaplessPlayback: true);
}
