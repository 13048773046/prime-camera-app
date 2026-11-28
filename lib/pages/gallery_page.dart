import 'package:flutter/material.dart';

import '../services/camera_service.dart';
import 'editor_page.dart';
import '../services/photo_source_stub.dart'
    if (dart.library.io) '../services/photo_source_io.dart';
import '../theme.dart';

/// Doka `fragment_gallery.xml`：日期分组、三列网格、多选删除、分享、导入。
class GalleryPage extends StatefulWidget {
  const GalleryPage({
    super.key,
    required this.photos,
    this.camera,
    this.onMine,
  });

  final List<String> photos;
  final CameraService? camera;
  final VoidCallback? onMine;

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  late List<String> _photos = List<String>.of(widget.photos);
  final Set<String> _selected = <String>{};
  bool _selecting = false;
  bool _busy = false;

  CameraService? get _camera => widget.camera;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final camera = _camera;
    if (camera == null) return;
    final disk = await camera.listPhotos();
    if (!mounted) return;
    setState(() {
      final merged = <String>{...disk, ..._photos}.toList();
      _photos = merged;
    });
  }

  Future<void> _importPhotos() async {
    final camera = _camera;
    if (camera == null) return;
    final imported = await camera.pickPhotos();
    if (!mounted || imported.isEmpty) return;
    setState(() => _photos = <String>{...imported, ..._photos}.toList());
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty || _busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: PrimeColor.surfaceLift,
        title: const Text('删除照片？', style: TextStyle(color: PrimeColor.white, fontSize: 16)),
        content: Text(
          '将从 PRIME 相册删除 ${_selected.length} 张。系统相簿里的副本不会被删除。',
          style: const TextStyle(color: PrimeColor.white54, fontSize: 12, height: 1.6),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除', style: TextStyle(color: Color(0xFFFF7B72)))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    for (final path in _selected) {
      await _camera?.deletePhoto(path);
      _photos.remove(path);
    }
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _selecting = false;
      _busy = false;
    });
  }

  Future<void> _shareSelected() async {
    if (_selected.isEmpty) return;
    await _camera?.shareFiles(_selected.toList());
  }

  void _toggle(String path) {
    setState(() {
      if (_selected.contains(path)) {
        _selected.remove(path);
      } else {
        _selected.add(path);
      }
      _selecting = _selected.isNotEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = _grouped();
    return Scaffold(
      backgroundColor: PrimeColor.black,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: _photos.isEmpty
                  ? _empty(context)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                      itemCount: groups.length,
                      itemBuilder: (context, index) => _group(groups[index]),
                    ),
            ),
            if (_selecting) _actionBar(),
            const SizedBox(height: 12),
            _tabBar(context),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    if (_selecting) {
      return SizedBox(
        height: 48,
        child: Row(
          children: [
            IconButton(
              onPressed: () => setState(() {
                _selected.clear();
                _selecting = false;
              }),
              icon: const Icon(Icons.close_rounded, size: 20, color: PrimeColor.white70),
            ),
            Text(
              '已选 ${_selected.length} 项',
              style: const TextStyle(fontSize: 17, color: PrimeColor.white, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() {
                if (_selected.length == _photos.length) {
                  _selected.clear();
                } else {
                  _selected.addAll(_photos);
                }
              }),
              child: Text(
                _selected.length == _photos.length ? '全不选' : '全选',
                style: const TextStyle(fontSize: 12, color: PrimeColor.white70),
              ),
            ),
          ],
        ),
      );
    }
    return SizedBox(
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
              child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: PrimeColor.white54),
            ),
          ),
          const Text(
            '全部照片',
            style: TextStyle(fontSize: 20, color: PrimeColor.white, fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          IconButton(
            onPressed: _importPhotos,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 20, color: PrimeColor.white54),
            tooltip: '导入照片',
          ),
          if (_photos.isNotEmpty) ...[
            Text('${_photos.length} 张', style: const TextStyle(fontSize: 12, color: PrimeColor.white38)),
            const SizedBox(width: 10),
            TextButton(
              onPressed: () => setState(() => _selecting = true),
              child: const Text('选择', style: TextStyle(fontSize: 12, color: PrimeColor.white70)),
            ),
          ] else
            const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _actionBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: PrimeColor.surfaceLift,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PrimeColor.white06),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _action(Icons.ios_share_rounded, '分享', _shareSelected),
          _action(Icons.delete_outline_rounded, '删除', _deleteSelected),
          _action(Icons.done_rounded, '完成', () => setState(() {
            _selected.clear();
            _selecting = false;
          })),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: _busy ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        child: Column(
          children: [
            Icon(icon, size: 20, color: PrimeColor.white70),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 9, color: PrimeColor.white38)),
          ],
        ),
      ),
    );
  }

  String _dateKey(String path) {
    final date = photoModified(path);
    if (date == null) return '最近';
    return '${date.year}年${date.month}月${date.day}日';
  }

  List<MapEntry<String, List<String>>> _grouped() {
    final map = <String, List<String>>{};
    for (final path in _photos) {
      map.putIfAbsent(_dateKey(path), () => <String>[]).add(path);
    }
    return map.entries.toList();
  }

  Widget _group(MapEntry<String, List<String>> group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 14, 6, 8),
          child: Row(
            children: [
              Text(group.key, style: const TextStyle(fontSize: 12, color: PrimeColor.white70, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text('${group.value.length}', style: const TextStyle(fontSize: 10, color: PrimeColor.white24)),
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 3,
            crossAxisSpacing: 3,
            childAspectRatio: 0.75,
          ),
          itemCount: group.value.length,
          itemBuilder: (context, index) {
            final path = group.value[index];
            final active = _selected.contains(path);
            return GestureDetector(
              onTap: () {
                if (_selecting) {
                  _toggle(path);
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _PhotoPreview(
                        path: path,
                        camera: _camera,
                        onDeleted: () {
                          setState(() => _photos.remove(path));
                          Navigator.of(context).pop();
                        },
                        onEdited: (newPath) {
                          setState(() {
                            _photos.remove(path);
                            _photos.insert(0, newPath);
                          });
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
                  );
                }
              },
              onLongPress: () => _toggle(path),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  buildPhotoImage(path),
                  if (_selecting)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active ? const Color(0xFF7ECFC8) : Colors.black45,
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                        child: active
                            ? const Icon(Icons.check_rounded, size: 14, color: Colors.black)
                            : null,
                      ),
                    ),
                  if (active)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.28),
                        child: const Center(
                          child: Icon(Icons.check_circle_rounded, size: 26, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
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
            Expanded(child: _tab('相机', onTap: () => Navigator.of(context).maybePop())),
            Expanded(child: _tab('相册', active: true)),
            Expanded(
              child: _tab('我的', onTap: () {
                Navigator.of(context).maybePop();
                widget.onMine?.call();
              }),
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
          const Icon(Icons.folder_open_outlined, size: 80, color: PrimeColor.white24),
          const SizedBox(height: 16),
          const Text('还没有照片', style: TextStyle(fontSize: 16, color: PrimeColor.white70, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('按一次快门，成片会出现在这里', style: TextStyle(fontSize: 12, color: PrimeColor.white38)),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 92,
              height: 48,
              decoration: BoxDecoration(color: const Color(0xFF80EEFF), borderRadius: BorderRadius.circular(24)),
              alignment: Alignment.center,
              child: const Text('去拍摄', style: TextStyle(fontSize: 14, color: Color(0xFF101820), fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({
    required this.path,
    this.camera,
    this.onDeleted,
    this.onEdited,
  });

  final String path;
  final CameraService? camera;
  final VoidCallback? onDeleted;
  final ValueChanged<String>? onEdited;

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
                  child: Icon(Icons.close_rounded, size: 20, color: Colors.white70),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _circle(Icons.tune_rounded, () async {
                    final result = await Navigator.of(context).push<String>(
                      MaterialPageRoute<String>(
                        builder: (_) => EditorPage(path: path, camera: camera),
                      ),
                    );
                    if (result != null) onEdited?.call(result);
                  }, context),
                  const SizedBox(width: 14),
                  _circle(Icons.ios_share_rounded, () => camera?.shareFiles([path]), context),
                  const SizedBox(width: 14),
                  _circle(Icons.delete_outline_rounded, () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: PrimeColor.surfaceLift,
                        title: const Text('删除这张照片？', style: TextStyle(color: PrimeColor.white, fontSize: 16)),
                        content: const Text('只从 PRIME 相册删除；系统相簿副本保留。', style: TextStyle(color: PrimeColor.white54, fontSize: 12)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除', style: TextStyle(color: Color(0xFFFF7B72)))),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await camera?.deletePhoto(path);
                      onDeleted?.call();
                    }
                  }, context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circle(IconData icon, VoidCallback onTap, BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.42),
          border: Border.all(color: Colors.white24, width: 0.8),
        ),
        child: Icon(icon, size: 20, color: Colors.white70),
      ),
    );
  }
}
