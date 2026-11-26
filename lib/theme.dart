import 'package:flutter/material.dart';

/// 定焦 PRIME · 黑白极简视觉。
///
/// 取景器是纯黑的，所有信息只用白、灰、透明三层。
/// 不再使用纸纹、手写字体、彩色印章；引导只保留一根细线和一句动作。
class PrimeColor {
  /// 主色：纯黑。整个 App 的背景、取景器外框、卡片底色都从它派生。
  static const Color black = Color(0xFF000000);

  /// 比纯黑高一档的界面层，用于底部控制区与浮层。
  static const Color surface = Color(0xFF0A0A0A);
  static const Color surfaceLift = Color(0xFF141414);

  /// 唯一的高光色：白。
  static const Color white = Color(0xFFFFFFFF);
  static const Color white90 = Color(0xE6FFFFFF);
  static const Color white70 = Color(0xB3FFFFFF);
  static const Color white54 = Color(0x8AFFFFFF);
  static const Color white38 = Color(0x61FFFFFF);
  static const Color white24 = Color(0x3DFFFFFF);
  static const Color white12 = Color(0x1FFFFFFF);
  static const Color white06 = Color(0x0FFFFFFF);
  static const Color line = Color(0x33FFFFFF);

  /// 兼容旧组件的遗留令牌。新 UI 不再使用，但保留别名避免旧代码编译失败。
  static const Color ink = white;
  static const Color inkSoft = white70;
  static const Color inkFaint = white38;
  static const Color paper = black;
  static const Color paperDeep = surface;
  static const Color paperShade = surfaceLift;
  static const Color mint = white;
  static const Color mintDeep = white;
  static const Color dark = black;
  static const Color darkLift = surfaceLift;
  static const Color nearWhite = white;
  static const Color mist = white38;
  static const Color vermilion = white;
  static const Color dusk = surfaceLift;
  static const Color night = surfaceLift;
  static const Color rule = line;
}

class PrimeFont {
  /// 极简风不打包手写体，正文全部走系统无衬线。
  static const String? hand = null;
  static const List<String> handFallback = <String>[];

  /// 数字与参数：系统等宽数字，保持取景器仪表感。
  static const List<String> mono = <String>[
    'SF Mono',
    'Menlo',
    'Roboto Mono',
    'monospace',
  ];
}

class PrimeType {
  static const TextStyle display = TextStyle(
    fontSize: 22,
    height: 1.1,
    color: PrimeColor.white,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  static const TextStyle title = TextStyle(
    fontSize: 17,
    height: 1.2,
    color: PrimeColor.white,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    height: 1.45,
    color: PrimeColor.white70,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 11,
    height: 1.35,
    color: PrimeColor.white54,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
  );

  static const TextStyle overline = TextStyle(
    fontSize: 9,
    height: 1.2,
    color: PrimeColor.white38,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.8,
  );

  static const TextStyle mono = TextStyle(
    fontFamily: null,
    fontFeatures: [FontFeature.tabularFigures()],
    fontSize: 12,
    height: 1.1,
    color: PrimeColor.white,
    letterSpacing: 0.6,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle monoDim = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
    fontSize: 11,
    height: 1.1,
    color: PrimeColor.white54,
    letterSpacing: 0.6,
    fontWeight: FontWeight.w500,
  );

  // 旧命名兼容。
  static const TextStyle hand = body;
  static const TextStyle handSmall = caption;
  static const TextStyle label = overline;
}

class PrimeTheme {
  static ThemeData build() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'PrimeSans',
      scaffoldBackgroundColor: PrimeColor.black,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      dividerColor: PrimeColor.white12,
      colorScheme: const ColorScheme.dark(
        primary: PrimeColor.white,
        onPrimary: PrimeColor.black,
        surface: PrimeColor.black,
        onSurface: PrimeColor.white,
        outline: PrimeColor.white24,
      ),
      textTheme: const TextTheme(
        titleLarge: PrimeType.display,
        titleMedium: PrimeType.title,
        bodyLarge: PrimeType.body,
        bodyMedium: PrimeType.caption,
        labelSmall: PrimeType.overline,
      ),
      iconTheme: const IconThemeData(color: PrimeColor.white70, size: 20),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: PrimeColor.black,
        modalBackgroundColor: PrimeColor.black,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
    );
  }
}
