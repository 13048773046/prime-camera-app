import 'package:flutter/material.dart';

/// 定焦 PRIME 视觉令牌。
/// 取自交接手册：奶油纸底 + 墨绿墨线 + 薄荷绿引导 + 深色取景窗。
class PrimeColor {
  static const Color paper = Color(0xFFFBF7F0);
  static const Color paperDeep = Color(0xFFF3EBDD);
  static const Color paperShade = Color(0xFFE9DFCC);
  static const Color ink = Color(0xFF17332B);
  static const Color inkSoft = Color(0xFF4A5F56);
  static const Color inkFaint = Color(0xFF8A968E);
  static const Color mint = Color(0xFF8FD9BE);
  static const Color mintDeep = Color(0xFF4FB894);
  static const Color dark = Color(0xFF121212);
  static const Color darkLift = Color(0xFF1E2320);
  static const Color nearWhite = Color(0xFFF7F5F0);
  static const Color mist = Color(0xFFC9CCC9);
  static const Color vermilion = Color(0xFFE8484F);
  static const Color dusk = Color(0xFF4A3F5C);
  static const Color night = Color(0xFF2C3E5A);
  static const Color rule = Color(0x2417332B);
}

class PrimeFont {
  /// 霞鹜文楷：标题与口令的手写语气。
  static const String hand = 'WenKai';

  /// iOS 自带楷体，作为未打包字体时的兜底。
  static const List<String> handFallback = <String>[
    'Kaiti SC',
    'STKaiti',
    'KaiTi',
    'Songti SC',
    'serif',
  ];

  /// 数字：DIN / SF Mono 的窄等宽气质。
  static const List<String> mono = <String>[
    'DIN Alternate',
    'SF Mono',
    'Menlo',
    'Roboto Mono',
    'monospace',
  ];
}

class PrimeType {
  static const TextStyle title = TextStyle(
    fontFamily: PrimeFont.hand,
    fontFamilyFallback: PrimeFont.handFallback,
    fontSize: 30,
    height: 1.1,
    color: PrimeColor.ink,
    letterSpacing: 1.5,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle hand = TextStyle(
    fontFamily: PrimeFont.hand,
    fontFamilyFallback: PrimeFont.handFallback,
    fontSize: 19,
    height: 1.35,
    color: PrimeColor.ink,
  );

  static const TextStyle handSmall = TextStyle(
    fontFamily: PrimeFont.hand,
    fontFamilyFallback: PrimeFont.handFallback,
    fontSize: 14,
    height: 1.3,
    color: PrimeColor.inkSoft,
  );

  static const TextStyle label = TextStyle(
    fontSize: 11,
    height: 1.2,
    color: PrimeColor.ink,
    letterSpacing: 2.4,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 10,
    height: 1.2,
    color: PrimeColor.inkFaint,
    letterSpacing: 1.2,
  );

  static const TextStyle mono = TextStyle(
    fontFamily: null,
    fontFeatures: [FontFeature.tabularFigures()],
    fontSize: 11,
    height: 1.1,
    color: PrimeColor.ink,
    letterSpacing: 0.8,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle monoDark = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
    fontSize: 11,
    height: 1.1,
    color: Colors.white70,
    letterSpacing: 0.8,
    fontWeight: FontWeight.w600,
  );
}

class PrimeTheme {
  static ThemeData build() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: PrimeColor.paper,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      colorScheme: ColorScheme.fromSeed(
        seedColor: PrimeColor.mint,
        primary: PrimeColor.ink,
        surface: PrimeColor.paper,
      ),
      textTheme: const TextTheme(
        titleLarge: PrimeType.title,
        bodyLarge: TextStyle(fontSize: 15, height: 1.6, color: PrimeColor.ink),
        bodyMedium: TextStyle(fontSize: 13, height: 1.6, color: PrimeColor.inkSoft),
      ),
      iconTheme: const IconThemeData(color: PrimeColor.ink, size: 20),
    );
  }
}
