import 'package:flutter/material.dart';

import '../data/filters.dart';
import '../services/camera_prefs.dart';
import '../theme.dart';

/// Doka `layout_filter_detail.xml` 的底部弹层：样片、描述、试用/Pro/拍摄解锁。
class FilterDetailSheet extends StatelessWidget {
  const FilterDetailSheet({
    super.key,
    required this.filter,
    required this.onApply,
    required this.onBuyPro,
    this.previewPath,
  });

  final FilterPreset filter;
  final VoidCallback onApply;
  final VoidCallback onBuyPro;
  final String? previewPath;

  @override
  Widget build(BuildContext context) {
    final prefs = CameraPrefs.instance;
    final unlocked = prefs.filterUnlocked(filter);
    final remaining = prefs.filterUnlockRemaining(filter);
    final shots = prefs.filterShotCount(filter.id);
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0B0B0B),
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          border: Border(top: BorderSide(color: Color(0x22FFFFFF))),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: PrimeColor.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 38,
                      height: 38,
                      child: ColorFiltered(
                        colorFilter: filter.colorFilter,
                        child: Image.asset(
                          'assets/demo/scene.jpg',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                filter.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: PrimeColor.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (filter.pro) ...[
                              const SizedBox(width: 7),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFC9A86A),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'PRO',
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: Colors.black,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          filter.category.label,
                          style: const TextStyle(
                            fontSize: 10,
                            color: PrimeColor.white38,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: PrimeColor.white38,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _sample(context, filter, false)),
                  const SizedBox(width: 8),
                  Expanded(child: _sample(context, filter, true)),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                filter.description,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: PrimeColor.white70,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in filter.positives)
                    _tag(tag, const Color(0xFF80EEFF)),
                  for (final tag in filter.negatives)
                    _tag(tag, Colors.white38),
                ],
              ),
              if (filter.pro && !unlocked) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF171512),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0x33C9A86A)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.workspace_premium_rounded,
                            size: 17,
                            color: Color(0xFFC9A86A),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            remaining > 0
                                ? '拍摄解锁 · 还差 $remaining 张'
                                : 'Doka Pro 胶片',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFE3C98A),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '$shots/${filter.unlockShots}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: PrimeColor.white38,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (shots / filter.unlockShots).clamp(0.0, 1.0),
                          minHeight: 4,
                          backgroundColor: PrimeColor.white12,
                          valueColor: const AlwaysStoppedAnimation(
                            Color(0xFFC9A86A),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '也可以直接开通 Doka Pro，解锁全部胶片、无限 AI 构图与 AI 滤镜。',
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.45,
                          color: PrimeColor.white38,
                        ),
                      ),
                      const SizedBox(height: 9),
                      GestureDetector(
                        onTap: onBuyPro,
                        child: Container(
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFC9A86A),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            '开通 Doka Pro',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              GestureDetector(
                onTap: onApply,
                child: Container(
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: unlocked
                        ? PrimeColor.white
                        : PrimeColor.white.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    unlocked ? '使用这个滤镜' : '试用这个滤镜',
                    style: const TextStyle(
                      fontSize: 13,
                      color: PrimeColor.black,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sample(BuildContext context, FilterPreset filter, bool filtered) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/demo/scene.jpg', fit: BoxFit.cover),
            if (filtered)
              ColorFiltered(
                colorFilter: filter.colorFilter,
                child: Image.asset('assets/demo/scene.jpg', fit: BoxFit.cover),
              ),
            Positioned(
              left: 7,
              bottom: 7,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  filtered ? filter.name : '原片',
                  style: const TextStyle(
                    fontSize: 8,
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

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 9, color: color),
      ),
    );
  }
}
