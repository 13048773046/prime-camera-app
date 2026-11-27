import 'package:flutter/material.dart';

import '../services/photo_source_stub.dart'
    if (dart.library.io) '../services/photo_source_io.dart';
import '../theme.dart';

/// 极简相册页：Doka 的相册也只放照片网格和空状态，不在这里堆功能。
class GalleryPage extends StatelessWidget {
  const GalleryPage({super.key, required this.photos, this.onMine});

  final List<String> photos;
  final VoidCallback? onMine;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PrimeColor.black,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox(
                      width: 40,
                      height: 48,
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 18,
                        color: PrimeColor.white54,
                      ),
                    ),
                  ),
                  const Text(
                    '全部照片',
                    style: TextStyle(
                      fontSize: 20,
                      color: PrimeColor.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  if (photos.isNotEmpty)
                    Text(
                      '${photos.length} 张',
                      style: const TextStyle(
                        fontSize: 12,
                        color: PrimeColor.white38,
                      ),
                    ),
                  const SizedBox(width: 16),
                ],
              ),
            ),
            Expanded(
              child: photos.isEmpty
                  ? _empty(context)
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(4, 6, 4, 12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 3,
                            crossAxisSpacing: 3,
                            childAspectRatio: 0.75,
                          ),
                      itemCount: photos.length,
                      itemBuilder: (context, index) {
                        return GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    _PhotoPreview(path: photos[index]),
                              ),
                            );
                          },
                          child: buildPhotoImage(photos[index]),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            _tabBar(context),
          ],
        ),
      ),
    );
  }

  Widget _tabBar(BuildContext context) {
    return Center(
      child: Container(
        width: 310,
        height: 52,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white12, width: 0.8),
        ),
        child: Row(
          children: [
            Expanded(
              child: _tab('相机', onTap: () => Navigator.of(context).maybePop()),
            ),
            Expanded(child: _tab('相册', active: true)),
            Expanded(
              child: _tab(
                '我的',
                onTap: () {
                  Navigator.of(context).maybePop();
                  onMine?.call();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab(String label, {bool active = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: active ? Colors.white12 : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            height: 1,
            color: active ? Colors.white : const Color(0xFFBFBFBF),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.folder_open_outlined,
            size: 80,
            color: PrimeColor.white24,
          ),
          const SizedBox(height: 16),
          const Text(
            '还没有照片',
            style: TextStyle(
              fontSize: 16,
              color: PrimeColor.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '按一次快门，成片会出现在这里',
            style: TextStyle(fontSize: 12, color: PrimeColor.white38),
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 92,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF80EEFF),
                borderRadius: BorderRadius.circular(24),
              ),
              alignment: Alignment.center,
              child: const Text(
                '去拍摄',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF101820),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(child: buildPhotoImage(path, fit: BoxFit.contain)),
            Positioned(
              top: 8,
              left: 12,
              child: GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
