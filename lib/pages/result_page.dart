import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../services/photo_source_stub.dart'
    if (dart.library.io) '../services/photo_source_io.dart';
import '../widgets/manga_bits.dart';
import '../widgets/paper.dart';

class ResultPage extends StatelessWidget {
  const ResultPage({
    super.key,
    this.photoPath,
    this.caption = '今天的光，刚好。',
    this.onSave,
    this.onShare,
    this.onRetake,
  });

  final String? photoPath;
  final String caption;
  final Future<void> Function()? onSave;
  final Future<void> Function()? onShare;
  final VoidCallback? onRetake;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PrimeColor.paper,
      body: PaperBackground(
        child: SafeArea(
          child: Column(
            children: [
              _header(context),
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 背后的一枚薄荷印章。
                    Positioned(
                      right: 26,
                      top: 30,
                      child: Transform.rotate(
                        angle: 0.16,
                        child: const _StraightOutStamp(),
                      ),
                    ),
                    Positioned(
                      left: 18,
                      top: 74,
                      child: Transform.rotate(
                        angle: -0.1,
                        child: const InkTag(
                          text: 'PLATE 01 · 35mm',
                          dense: true,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 20,
                      top: 102,
                      child: Text(
                        '第 01 张，直出，没有修。',
                        style: TextStyle(
                          fontFamily: PrimeFont.hand,
                          fontFamilyFallback: PrimeFont.handFallback,
                          fontSize: 10.5,
                          color: PrimeColor.inkFaint,
                        ),
                      ),
                    ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final w = math.min(constraints.maxWidth - 46, 322.0);
                        return Transform.rotate(
                          angle: -0.035,
                          child: _Polaroid(
                            width: w,
                            photoPath: photoPath,
                            caption: caption,
                          ),
                        );
                      },
                    ),
                    Positioned(
                      left: 18,
                      bottom: 4,
                      child: Transform.rotate(
                        angle: -0.03,
                        child: const _NoteCard(),
                      ),
                    ),
                    Positioned(
                      right: -8,
                      bottom: 18,
                      child: IgnorePointer(
                        child: Image.asset(
                          'assets/brand/xiaoying_bust.png',
                          height: 112,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: InkButton(
                            label: '存进相册',
                            filled: true,
                            height: 46,
                            expand: true,
                            icon: Icons.download_outlined,
                            onTap: onSave == null ? null : () => onSave!(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkButton(
                            label: '分享这张',
                            height: 46,
                            expand: true,
                            icon: Icons.ios_share,
                            onTap: onShare == null ? null : () => onShare!(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed:
                          onRetake ?? () => Navigator.of(context).maybePop(),
                      child: Text(
                        '再拍一张 →',
                        style: TextStyle(
                          fontFamily: PrimeFont.hand,
                          fontFamilyFallback: PrimeFont.handFallback,
                          fontSize: 14,
                          color: PrimeColor.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 18, 8),
      child: Row(
        children: [
          RoundInkButton(
            icon: Icons.arrow_back_ios_new,
            size: 36,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '出片手帐',
                style: TextStyle(
                  fontFamily: PrimeFont.hand,
                  fontFamilyFallback: PrimeFont.handFallback,
                  fontSize: 22,
                  height: 1.1,
                  color: PrimeColor.ink,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'ONE SHOT, NO RETOUCH',
                style: TextStyle(
                  fontSize: 8,
                  letterSpacing: 2.2,
                  color: PrimeColor.inkFaint,
                ),
              ),
            ],
          ),
          const Spacer(),
          const HeartBadge(count: 1, compact: true),
        ],
      ),
    );
  }
}

class _Polaroid extends StatelessWidget {
  const _Polaroid({
    required this.width,
    required this.photoPath,
    required this.caption,
  });

  final double width;
  final String? photoPath;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final photoH = width * 1.18;
    return Container(
      width: width,
      padding: EdgeInsets.fromLTRB(14, 14, 14, 0),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        border: Border.all(color: const Color(0x2217332B), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E1A1408),
            blurRadius: 18,
            offset: Offset(4, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              SizedBox(
                width: double.infinity,
                height: photoH,
                child: buildPhotoImage(photoPath),
              ),
              // 相纸上的轻微暗角与颗粒。
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _PhotoGrainPainter()),
                ),
              ),
              const Positioned(
                left: -10,
                top: -8,
                child: TapeStrip(width: 62, height: 18, angle: -0.28),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 14, 6, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  caption,
                  style: TextStyle(
                    fontFamily: PrimeFont.hand,
                    fontFamilyFallback: PrimeFont.handFallback,
                    fontSize: 18,
                    height: 1.3,
                    color: PrimeColor.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(width: 22, height: 1, color: PrimeColor.inkFaint),
                    const SizedBox(width: 6),
                    const Text(
                      '2026.11.26  ·  f/1.8  ·  1/125',
                      style: TextStyle(
                        fontSize: 8.5,
                        letterSpacing: 1.1,
                        color: PrimeColor.inkFaint,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoGrainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.95,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.16)],
          stops: const [0.55, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StraightOutStamp extends StatelessWidget {
  const _StraightOutStamp();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: PrimeColor.mintDeep.withValues(alpha: 0.55),
          width: 2,
        ),
      ),
      child: Container(
        width: 84,
        height: 84,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: PrimeColor.mintDeep.withValues(alpha: 0.4),
            width: 0.8,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '直出',
              style: TextStyle(
                fontFamily: PrimeFont.hand,
                fontFamilyFallback: PrimeFont.handFallback,
                fontSize: 26,
                height: 1,
                color: PrimeColor.mintDeep,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'PRIME',
              style: TextStyle(
                fontSize: 8,
                letterSpacing: 2.4,
                color: PrimeColor.mintDeep,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'NO RETOUCH',
              style: TextStyle(
                fontSize: 6,
                letterSpacing: 1.2,
                color: PrimeColor.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 176,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F0E0),
        border: Border.all(
          color: PrimeColor.ink.withValues(alpha: 0.35),
          width: 0.8,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x141A1408),
            blurRadius: 4,
            offset: Offset(1, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 12, height: 1, color: PrimeColor.mintDeep),
              const SizedBox(width: 5),
              const Text(
                'AI 小批注',
                style: TextStyle(
                  fontSize: 8,
                  letterSpacing: 1.4,
                  color: PrimeColor.mintDeep,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '这张留白舒服。下次换 2×，\n把背景再压近一点。',
            style: TextStyle(
              fontFamily: PrimeFont.hand,
              fontFamilyFallback: PrimeFont.handFallback,
              fontSize: 11.5,
              height: 1.5,
              color: PrimeColor.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}
