import 'package:flutter/material.dart';

import '../theme.dart';

/// Doka 式「我的」页：账号卡 + 分组设置列表 + 底部三栏。
/// PRIME 没有账号体系，所以这里不放假登录/假 VIP，只保留真实可用的拍摄设置。
class MinePage extends StatefulWidget {
  const MinePage({
    super.key,
    required this.photoCount,
    required this.gridOn,
    required this.flashOn,
    required this.onGrid,
    required this.onFlash,
    required this.onGallery,
    required this.onCamera,
  });

  final int photoCount;
  final bool gridOn;
  final bool flashOn;
  final ValueChanged<bool> onGrid;
  final ValueChanged<bool> onFlash;
  final VoidCallback onGallery;
  final VoidCallback onCamera;

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  late bool _grid = widget.gridOn;
  late bool _flash = widget.flashOn;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PrimeColor.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _accountCard(),
                    const SizedBox(height: 26),
                    _sectionTitle('拍摄'),
                    _card([
                      _row(
                        icon: Icons.center_focus_strong_outlined,
                        label: '构图引导',
                        value: '设备端 AI',
                      ),
                      _switchRow(
                        icon: Icons.grid_3x3_rounded,
                        label: '构图网格',
                        value: _grid,
                        onChanged: (value) {
                          setState(() => _grid = value);
                          widget.onGrid(value);
                        },
                      ),
                      _switchRow(
                        icon: Icons.flash_on_rounded,
                        label: '闪光灯',
                        value: _flash,
                        onChanged: (value) {
                          setState(() => _flash = value);
                          widget.onFlash(value);
                        },
                      ),
                      _row(
                        icon: Icons.water_drop_outlined,
                        label: '保存水印',
                        value: '开启',
                      ),
                    ]),
                    const SizedBox(height: 22),
                    _sectionTitle('相册'),
                    _card([
                      _row(
                        icon: Icons.photo_library_outlined,
                        label: '最近照片',
                        value: '${widget.photoCount} 张',
                        onTap: widget.onGallery,
                      ),
                      _row(
                        icon: Icons.crop_original_rounded,
                        label: '拍摄比例',
                        value: '3:4',
                      ),
                    ]),
                    const SizedBox(height: 22),
                    _sectionTitle('通用'),
                    _card([
                      _row(
                        icon: Icons.language_rounded,
                        label: '语言',
                        value: '简体中文',
                      ),
                      _row(
                        icon: Icons.info_outline_rounded,
                        label: '版本',
                        value: '0.3.1',
                      ),
                    ]),
                    const SizedBox(height: 32),
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: PrimeColor.white06,
                              shape: BoxShape.circle,
                              border: Border.all(color: PrimeColor.white12),
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              size: 20,
                              color: PrimeColor.white70,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'PRIME CAMERA',
                            style: TextStyle(
                              fontSize: 12,
                              color: PrimeColor.white38,
                              letterSpacing: 1.6,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _tabBar(),
          ],
        ),
      ),
    );
  }

  Widget _accountCard() {
    return Container(
      height: 112,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF1C1D22), Color(0xFF111114)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: PrimeColor.white12, width: 0.8),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: Color(0xFF2A2B31),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.camera_alt_rounded,
              size: 21,
              color: PrimeColor.white70,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PRIME 本地模式',
                  style: TextStyle(
                    fontSize: 17,
                    color: PrimeColor.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  '照片只保存在这台手机',
                  style: TextStyle(fontSize: 12, color: PrimeColor.white38),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 22,
            color: PrimeColor.white38,
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, color: Color(0x99FFFFFF)),
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141417),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PrimeColor.white06, width: 0.8),
      ),
      child: Column(children: children),
    );
  }

  Widget _row({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: PrimeColor.white54),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    color: PrimeColor.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                value,
                style: const TextStyle(fontSize: 13, color: PrimeColor.white38),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: PrimeColor.white24,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _switchRow({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: PrimeColor.white54),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  color: PrimeColor.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => onChanged(!value),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 40,
                height: 24,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: value ? const Color(0xFF80EEFF) : PrimeColor.white12,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 160),
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: PrimeColor.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabBar() {
    return Center(
      child: Container(
        width: 310,
        height: 52,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: PrimeColor.white12, width: 0.8),
        ),
        child: Row(
          children: [
            Expanded(child: _tab('相机', onTap: widget.onCamera)),
            Expanded(child: _tab('相册', onTap: widget.onGallery)),
            Expanded(child: _tab('我的', active: true)),
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
          color: active ? PrimeColor.white12 : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            height: 1,
            color: active ? PrimeColor.white : const Color(0xFFBFBFBF),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
