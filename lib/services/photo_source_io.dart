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
  return Image.file(
    File(path),
    fit: fit,
    gaplessPlayback: true,
    errorBuilder: (context, error, stack) => Container(
      color: PrimeColor.darkLift,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: Colors.white24, size: 32),
          SizedBox(height: 6),
          Text(
            '照片已失效',
            style: TextStyle(fontSize: 9, color: Colors.white38),
          ),
        ],
      ),
    ),
  );
}

DateTime? photoModified(String path) {
  try {
    return File(path).lastModifiedSync();
  } catch (_) {
    return null;
  }
}
