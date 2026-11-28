import 'package:flutter/material.dart';

import '../data/filters.dart';
import '../services/camera_prefs.dart';
import '../services/camera_service.dart';
import '../services/photo_source_stub.dart'
    if (dart.library.io) '../services/photo_source_io.dart';
import '../theme.dart';

/// Doka `photoedit/*` + `DokaCropActivity` 的合并版：裁切、旋转、翻转、
/// 换滤镜、边框与时间水印。预览在 Flutter 里即时模拟，导出交给 CoreImage。
class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    required this.path,
    this.camera,
  });

  final String path;
  final CameraService? camera;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  String _filterId = 'none';
  String _ratio = 'threeFour';
  int _rotate = 0;
  bool _flip = false;
  String _border = 'none';
  String _watermarkStyle = 'simpleWhite';
  bool _watermark = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _watermark = CameraPrefs.instance.watermark;
    _border = CameraPrefs.instance.borderStyle;
    _watermarkStyle = CameraPrefs.instance.watermarkStyle;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final camera = widget.camera;
    if (camera == null) {
      setState(() => _saving = false);
      Navigator.of(context).pop(widget.path);
      return;
    }
    final path = await camera.editPhoto(
      path: widget.path,
      filter: _filterId,
      ratio: _ratio,
      rotate: _rotate,
      flip: _flip,
      border: _border,
      watermark: _watermark,
      watermarkStyle: _watermarkStyle,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('导出失败，原片仍然保留')),
      );
      return;
    }
    Navigator.of(context).pop(path);
  }

  @override
  Widget build(BuildContext context) {
    final filter = filterById(_filterId);
    return Scaffold(
      backgroundColor: PrimeColor.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: PrimeColor.white54),
                    ),
                  ),
                  const Text('编辑', style: TextStyle(fontSize: 18, color: PrimeColor.white, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? '导出中' : '导出', style: const TextStyle(fontSize: 13, color: Color(0xFF7ECFC8), fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: switch (_ratio) {
                    'oneOne' => 1,
                    'sixteenNine' => 9 / 16,
                    _ => 3 / 4,
                  },
                  child: Container(
                    margin: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: PrimeColor.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: PrimeColor.white12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColorFiltered(
                          colorFilter: filter.colorFilter,
                          child: Transform.flip(
                            flipX: _flip,
                            child: RotatedBox(
                              quarterTurns: _rotate,
                              child: buildPhotoImage(widget.path),
                            ),
                          ),
                        ),
                        if (_border != 'none')
                          IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: _border == 'white'
                                      ? const Color(0xFFF2EFE7)
                                      : const Color(0xFF0E0E0E),
                                  width: _border == 'white' ? 14 : 10,
                                ),
                              ),
                            ),
                          ),
                        if (_watermark && _watermarkStyle != 'none')
                          Positioned(
                            left: 10,
                            bottom: 8,
                            child: Text(
                              switch (_watermarkStyle) {
                                'dated' =>
                                  '${DateTime.now().month}/${DateTime.now().day}',
                                'brand' => 'PRIME',
                                _ =>
                                  'PRIME  ·  ${DateTime.now().month}/${DateTime.now().day}',
                              },
                              style: TextStyle(
                                fontSize: _watermarkStyle == 'brand' ? 12 : 8,
                                color: Colors.white70,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _controls(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: PrimeColor.surfaceLift,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PrimeColor.white06),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 74,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: dokaFilters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = dokaFilters[index];
                final active = item.id == _filterId;
                return GestureDetector(
                  onTap: () => setState(() => _filterId = item.id),
                  child: SizedBox(
                    width: 52,
                    child: Column(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: active ? Colors.white : Colors.white12, width: active ? 1.5 : 0.8),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ColorFiltered(
                            colorFilter: item.colorFilter,
                            child: buildPhotoImage(widget.path),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, color: active ? Colors.white : Colors.white38)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _tool(Icons.crop_rounded, '裁切', _openRatio),
              _tool(Icons.rotate_right_rounded, '旋转', () => setState(() => _rotate = (_rotate + 1) % 4)),
              _tool(Icons.flip_rounded, '翻转', () => setState(() => _flip = !_flip)),
              _tool(Icons.border_all_rounded, '边框', _openBorder),
              _tool(
                _watermark ? Icons.branding_watermark_rounded : Icons.water_drop_outlined,
                '水印',
                _openWatermark,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tool(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Icon(icon, size: 19, color: PrimeColor.white70),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 9, color: PrimeColor.white38)),
        ],
      ),
    );
  }

  void _openRatio() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(color: PrimeColor.black, borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('裁切比例', style: TextStyle(fontSize: 18, color: PrimeColor.white, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final item in const [('threeFour', '3:4'), ('oneOne', '1:1'), ('sixteenNine', '16:9')])
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _ratio = item.$1);
                            Navigator.pop(context);
                          },
                          child: Container(
                            height: 56,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: _ratio == item.$1 ? Colors.white : PrimeColor.white06,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: Text(item.$2, style: TextStyle(fontSize: 13, color: _ratio == item.$1 ? Colors.black : Colors.white54)),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openWatermark() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: PrimeColor.black,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '水印',
                  style: TextStyle(
                    fontSize: 18,
                    color: PrimeColor.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                for (final item in const [
                  ('none', '无水印'),
                  ('simpleWhite', '简约白字'),
                  ('dated', '日期水印'),
                  ('brand', 'PRIME 品牌'),
                ])
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _watermarkStyle = item.$1;
                        _watermark = item.$1 != 'none';
                      });
                      Navigator.pop(context);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.$2,
                              style: const TextStyle(
                                fontSize: 13,
                                color: PrimeColor.white70,
                              ),
                            ),
                          ),
                          if (_watermarkStyle == item.$1)
                            const Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: PrimeColor.white,
                            ),
                        ],
                      ),
                    ),
                  ),
                SwitchListTile(
                  value: _watermark,
                  onChanged: (value) => setState(() {
                    _watermark = value;
                    if (!value) _watermarkStyle = 'none';
                  }),
                  title: const Text(
                    '导出时添加水印',
                    style: TextStyle(fontSize: 12, color: PrimeColor.white54),
                  ),
                  activeThumbColor: const Color(0xFF7ECFC8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openBorder() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(color: PrimeColor.black, borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('边框', style: TextStyle(fontSize: 18, color: PrimeColor.white, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                for (final item in const [('none', '无边框'), ('white', '白边'), ('film', '胶片'), ('magazine', '杂志')])
                  GestureDetector(
                    onTap: () {
                      setState(() => _border = item.$1);
                      Navigator.pop(context);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Expanded(child: Text(item.$2, style: const TextStyle(fontSize: 13, color: PrimeColor.white70))),
                          if (_border == item.$1) const Icon(Icons.check_rounded, size: 18, color: PrimeColor.white),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
