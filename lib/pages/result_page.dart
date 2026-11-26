import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/photo_source_stub.dart'
    if (dart.library.io) '../services/photo_source_io.dart';
import '../theme.dart';

class ResultPage extends StatelessWidget {
  const ResultPage({
    super.key,
    this.photoPath,
    this.caption = '直出 · 未修图',
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: PrimeColor.black,
      ),
      child: Scaffold(
        backgroundColor: PrimeColor.black,
        body: SafeArea(
          child: Column(
            children: [
              _header(context),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = math.min(
                      math.min(constraints.maxWidth - 24, 384.0),
                      (constraints.maxHeight - 24) * 0.75,
                    );
                    final height = width * 4 / 3;
                    return Center(
                      child: SizedBox(
                        width: width,
                        height: height,
                        child: _buildPhoto(),
                      ),
                    );
                  },
                ),
              ),
              _caption(),
              _actions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        children: [
          _roundIcon(
            Icons.close_rounded,
            () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '成片',
                style: TextStyle(
                  fontSize: 18,
                  height: 1.1,
                  color: PrimeColor.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'ONE SHOT · NO RETOUCH',
                style: TextStyle(
                  fontSize: 8.5,
                  height: 1.2,
                  color: PrimeColor.white38,
                  letterSpacing: 2.2,
                ),
              ),
            ],
          ),
          const Spacer(),
          _roundIcon(
            Icons.ios_share,
            onShare == null ? null : () => onShare!(),
          ),
        ],
      ),
    );
  }

  Widget _roundIcon(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: PrimeColor.white12, width: 0.8),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: PrimeColor.white54),
      ),
    );
  }

  Widget _buildPhoto() {
    return Container(
      decoration: BoxDecoration(
        color: PrimeColor.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PrimeColor.white12, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          buildPhotoImage(photoPath),
          const Positioned(
            left: 12,
            bottom: 12,
            child: Text(
              'SHOT ON PRIME',
              style: TextStyle(
                fontSize: 8,
                height: 1,
                color: PrimeColor.white70,
                letterSpacing: 1.8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _caption() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 12, 26, 0),
      child: Row(
        children: [
          const Text(
            'PRIME / 01',
            style: TextStyle(
              fontSize: 9,
              height: 1.2,
              color: PrimeColor.white38,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                height: 1.2,
                color: PrimeColor.white54,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _primaryButton(
                  '存进相册',
                  onSave == null ? null : () => onSave!(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _outlineButton(
                  '分享',
                  onShare == null ? null : () => onShare!(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: onRetake ?? () => Navigator.of(context).maybePop(),
            style: TextButton.styleFrom(
              foregroundColor: PrimeColor.white54,
              minimumSize: const Size(120, 40),
            ),
            child: const Text(
              '再拍一张',
              style: TextStyle(
                fontSize: 12,
                color: PrimeColor.white54,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton(String label, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: PrimeColor.white,
          borderRadius: BorderRadius.circular(24),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: PrimeColor.black,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _outlineButton(String label, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: PrimeColor.white24, width: 0.9),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: PrimeColor.white70,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
