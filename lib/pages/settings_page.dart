import 'package:flutter/material.dart';

import '../services/camera_prefs.dart';
import '../services/guidance.dart';
import '../theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.onOpenGuide});

  final VoidCallback? onOpenGuide;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final CameraPrefs _prefs = CameraPrefs.instance;
  bool _advanced = false;

  void _set(VoidCallback fn) {
    setState(fn);
    // 让相机页下次 build 时读到同一份设置。
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PrimeColor.black,
      appBar: AppBar(
        backgroundColor: PrimeColor.black,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          color: PrimeColor.white70,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '设置',
          style: TextStyle(fontSize: 17, color: PrimeColor.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 40),
        children: [
          _section('拍摄场景'),
          _card([
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final scene in SceneMode.values)
                    GestureDetector(
                      onTap: () => _set(() => _prefs.scene = scene),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: _prefs.scene == scene ? PrimeColor.white : PrimeColor.white06,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: _prefs.scene == scene ? Colors.transparent : PrimeColor.white12, width: 0.8),
                        ),
                        child: Text(
                          scene.label,
                          style: TextStyle(fontSize: 11, color: _prefs.scene == scene ? PrimeColor.black : PrimeColor.white54, fontWeight: _prefs.scene == scene ? FontWeight.w600 : FontWeight.w400),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 2, 14, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('锁定场景后，AI 会按这个场景的构图规则给拍法。', style: TextStyle(fontSize: 10, color: PrimeColor.white38)),
              ),
            ),
          ]),
          _section('拍摄'),
          _card([
            _switchRow(
              '实况照片',
              '记录快门前后的 3 秒；iOS 以 Live Photo 形式保存',
              _prefs.livePhoto,
              (v) => _set(() => _prefs.livePhoto = v),
              icon: Icons.motion_photos_on_outlined,
            ),
            _divider(),
            _switchRow(
              '保存底片',
              '同时保留未经滤镜与裁切的原始文件',
              _prefs.saveRaw,
              (v) => _set(() => _prefs.saveRaw = v),
              icon: Icons.camera_roll_outlined,
            ),
            _divider(),
            _switchRow(
              '构图网格',
              '九宫格辅助线，帮助对齐三分线',
              _prefs.grid,
              (v) => _set(() => _prefs.grid = v),
              icon: Icons.grid_3x3_rounded,
            ),
            _divider(),
            _switchRow(
              '水平仪',
              '取景框边缘显示俯仰与横滚，拍建筑时保持水平',
              _prefs.level,
              (v) => _set(() => _prefs.level = v),
              icon: Icons.straighten_rounded,
            ),
            _divider(),
            _switchRow(
              '闪光灯',
              '光线不足时自动补光；下一次拍摄生效',
              _prefs.flash,
              (v) => _set(() => _prefs.flash = v),
              icon: Icons.flash_on_outlined,
            ),
            _divider(),
            _switchRow(
              '触屏拍摄',
              '轻点取景框任意位置即按快门，适合单手自拍',
              _prefs.touchShot,
              (v) => _set(() => _prefs.touchShot = v),
              icon: Icons.touch_app_outlined,
            ),
            _divider(),
            _switchRow(
              '自拍镜像',
              '保存前置镜头看到的方向，而不是翻转后的方向',
              _prefs.selfieMirror,
              (v) => _set(() => _prefs.selfieMirror = v),
              icon: Icons.flip_camera_ios_outlined,
            ),
          ]),

          _section('AI 构图'),
          _card([
            _switchRow(
              '构图附带 AI 滤镜',
              '扫描时让 AI 同时给出适合这个场景的胶片',
              _prefs.aiFilter,
              (v) => _set(() => _prefs.aiFilter = v),
              icon: Icons.auto_awesome_outlined,
            ),
            _divider(),
            _switchRow(
              'AI 多景别构图',
              '一次取景给出远景、中景、近景多套拍法',
              _prefs.multiCompose,
              (v) => _set(() => _prefs.multiCompose = v),
              icon: Icons.filter_frames_outlined,
            ),
            _divider(),
            _switchRow(
              '指定 AI 构图主体',
              '长按画面锁定人物或物体，避免 AI 判断错主体',
              _prefs.subjectGuide,
              (v) => _set(() => _prefs.subjectGuide = v),
              icon: Icons.center_focus_strong_outlined,
            ),
            _divider(),
            _switchRow(
              'AI 构图停留确认',
              '对齐后停留 0.4 秒再给结果，避免手抖误判',
              _prefs.alignmentConfirm,
              (v) => _set(() => _prefs.alignmentConfirm = v),
              icon: Icons.timer_outlined,
            ),
            _divider(),
            _navRow(
              'AI 滤镜偏好',
              "${_prefs.preferredScenes.join('、')} · ${_prefs.preferredSeries.join('、')}",
              () => _openFilterPrefs(context),
            ),
            _divider(),
            _navRow(
              'AI 构图使用引导',
              '3 条规则：怎么站、怎么等、怎么切换方案',
              () => _showGuide(context),
            ),
          ]),

          _section('成片'),
          _card([
            _switchRow(
              '降噪优化',
              '多帧合成降低暗光噪点；会增加约 0.6 秒处理',
              _prefs.noiseReduction,
              (v) => _set(() => _prefs.noiseReduction = v),
              icon: Icons.grain_outlined,
            ),
            _divider(),
            _switchRow(
              '时间水印',
              '在成片右下角保留拍摄时间与机型',
              _prefs.watermark,
              (v) => _set(() => _prefs.watermark = v),
              icon: Icons.branding_watermark_outlined,
            ),
            _divider(),
            _navRow(
              '水印和边框',
              '选择无边框、白边、胶片边框或杂志边框',
              () => _openBorder(context),
            ),
          ]),

          _section('通用'),
          _card([
            _navRow('语言', _prefs.language, () => _openLanguage(context)),
            _divider(),
            _navRow('使用引导', '5 步了解 PRIME 的拍法', () => _showGuide(context)),
            _divider(),
            _navRow('问题诊断', '检查相机权限、网络与 AI 服务状态', () => _diagnose(context)),
            _divider(),
            _navRow('帮助与反馈', '邮件、抖音、小红书三个入口', () => _feedback(context)),
            _divider(),
            _navRow('关于 PRIME', '版本 0.4.4 · 隐私政策 · 开源许可', () => _about(context)),
          ]),

          _section('高级'),
          _card([
            _switchRow(
              '显示高级原生参数',
              '曝光、焦距、RAW 与多帧策略',
              _advanced,
              (v) => _set(() => _advanced = v),
              icon: Icons.tune_rounded,
            ),
            if (_advanced) ...[
              _divider(),
              _valueRow('视频质量', _prefs.videoQuality),
              _divider(),
              _valueRow('快门延迟', '${_prefs.timerSeconds} 秒'),
              _divider(),
              _valueRow('相机管线', 'AVFoundation · 多帧合成'),
            ],
          ]),

          const SizedBox(height: 18),
          const Center(
            child: Text(
              'PRIME 0.4.4 · 设置会立即生效',
              style: TextStyle(fontSize: 10, color: PrimeColor.white24),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8, left: 4),
        child: Text(
          title,
          style: const TextStyle(fontSize: 11, color: PrimeColor.white38, letterSpacing: 1.2),
        ),
      );

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: PrimeColor.surfaceLift,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: PrimeColor.white06, width: 0.8),
        ),
        child: Column(children: children),
      );

  Widget _divider() => const Divider(height: 0.8, thickness: 0.8, color: PrimeColor.white06, indent: 52);

  Widget _switchRow(String title, String subtitle, bool value, ValueChanged<bool> onChanged, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: PrimeColor.white38),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, color: PrimeColor.white, fontWeight: FontWeight.w500)),
                const SizedBox(height: 3),
                Text(subtitle, style: const TextStyle(fontSize: 10, height: 1.35, color: PrimeColor.white38)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: PrimeColor.white,
            activeTrackColor: const Color(0xFF7ECFC8),
            inactiveThumbColor: PrimeColor.white54,
            inactiveTrackColor: PrimeColor.white12,
          ),
        ],
      ),
    );
  }

  Widget _navRow(String title, String value, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 15, 12, 15),
          child: Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 13, color: PrimeColor.white))),
              Text(value, style: const TextStyle(fontSize: 11, color: PrimeColor.white38)),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, size: 18, color: PrimeColor.white24),
            ],
          ),
        ),
      );

  Widget _valueRow(String title, String value) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
        child: Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 12, color: PrimeColor.white54))),
            Text(value, style: const TextStyle(fontSize: 11, color: PrimeColor.white38)),
          ],
        ),
      );

  void _openBorder(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheet) => _BorderSheet(
        selected: _prefs.watermarkStyle,
        onSelect: (style) {
          setState(() => _prefs.watermarkStyle = style);
          Navigator.of(sheet).pop();
        },
      ),
    );
  }

  void _openLanguage(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheet) => _SimpleListSheet(
        title: '语言',
        options: const ['简体中文', '繁體中文', 'English', '日本語'],
        selected: _prefs.language,
        onSelect: (value) {
          setState(() => _prefs.language = value);
          Navigator.of(sheet).pop();
        },
      ),
    );
  }

  void _openFilterPrefs(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheet) => _FilterPrefsSheet(
        initialScenes: _prefs.preferredScenes,
        initialSeries: _prefs.preferredSeries,
        onSave: (scenes, series) {
          setState(() {
            _prefs.preferredScenes = scenes;
            _prefs.preferredSeries = series;
          });
        },
      ),
    );
  }

  void _showGuide(BuildContext context) {
    if (widget.onOpenGuide != null) {
      widget.onOpenGuide!();
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuidePage()));
  }

  void _diagnose(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: PrimeColor.surfaceLift,
        title: const Text('问题诊断', style: TextStyle(color: PrimeColor.white, fontSize: 16)),
        content: const Text(
          '相机：等待真机授权\nAI 服务：本地规则可用\n后端：未连接（可在“我的”里配置 PRIME_API_BASE）\n存储：可写\n\n如遇黑屏，请先在系统设置里允许 PRIME 使用相机。',
          style: TextStyle(color: PrimeColor.white54, fontSize: 12, height: 1.7),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了'))],
      ),
    );
  }

  void _feedback(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SimpleListSheet(
        title: '帮助与反馈',
        options: ['发邮件给支持团队', '在抖音关注 PRIME', '在小红书看拍摄教程'],
        selected: '',
        onSelect: _noop,
      ),
    );
  }

  void _about(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: PrimeColor.surfaceLift,
        title: const Text('关于 PRIME', style: TextStyle(color: PrimeColor.white, fontSize: 16)),
        content: const Text(
          'PRIME 0.4.4\n把手机当成一台有摄影指导的相机。\n\nDoka 1.3.20 前端逻辑研究项目；PRIME 使用自有品牌与素材。',
          style: TextStyle(color: PrimeColor.white54, fontSize: 12, height: 1.7),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
      ),
    );
  }
}

void _noop(String _) {}

class _BorderSheet extends StatelessWidget {
  const _BorderSheet({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    const styles = [
      ('minimal', '无边框', '只保留极细时间水印'),
      ('white', '白边', '四周留白，像一张冲洗出来的相纸'),
      ('film', '胶片边框', '黑色片基 + 齿孔 + 参数'),
      ('magazine', '杂志边框', '底部大留白与标题排版'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: PrimeColor.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('水印和边框', style: TextStyle(fontSize: 18, color: PrimeColor.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text('边框只影响导出，不改动原始底片。', style: TextStyle(fontSize: 11, color: PrimeColor.white38)),
              const SizedBox(height: 14),
              for (final item in styles)
                GestureDetector(
                  onTap: () => onSelect(item.$1),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: item.$1 == selected ? PrimeColor.white : PrimeColor.white06,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 54,
                          decoration: BoxDecoration(
                            color: item.$1 == 'white'
                                ? Colors.white
                                : item.$1 == 'film'
                                    ? const Color(0xFF151515)
                                    : PrimeColor.white12,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: item.$1 == 'film' ? PrimeColor.white24 : Colors.transparent),
                          ),
                          child: Center(
                            child: Container(
                              width: 30,
                              height: 38,
                              color: item.$1 == 'white' ? const Color(0xFFE9E6DE) : PrimeColor.white24,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.$2, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: item.$1 == selected ? PrimeColor.black : PrimeColor.white)),
                              const SizedBox(height: 2),
                              Text(item.$3, style: TextStyle(fontSize: 10, color: item.$1 == selected ? Colors.black54 : PrimeColor.white38)),
                            ],
                          ),
                        ),
                        if (item.$1 == selected)
                          const Icon(Icons.check_circle_rounded, size: 18, color: PrimeColor.black),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SimpleListSheet extends StatelessWidget {
  const _SimpleListSheet({required this.title, required this.options, required this.selected, required this.onSelect});

  final String title;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: PrimeColor.black, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, color: PrimeColor.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              for (final item in options)
                GestureDetector(
                  onTap: () => onSelect(item),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      children: [
                        Expanded(child: Text(item, style: const TextStyle(fontSize: 13, color: PrimeColor.white70))),
                        if (item == selected) const Icon(Icons.check_rounded, size: 18, color: PrimeColor.white),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterPrefsSheet extends StatefulWidget {
  const _FilterPrefsSheet({
    required this.initialScenes,
    required this.initialSeries,
    required this.onSave,
  });

  final List<String> initialScenes;
  final List<String> initialSeries;
  final void Function(List<String> scenes, List<String> series) onSave;

  @override
  State<_FilterPrefsSheet> createState() => _FilterPrefsSheetState();
}

class _FilterPrefsSheetState extends State<_FilterPrefsSheet> {
  late final Set<String> _scenes = {...widget.initialScenes};
  late final Set<String> _series = {...widget.initialSeries};

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: PrimeColor.black, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('AI 滤镜偏好', style: TextStyle(fontSize: 18, color: PrimeColor.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 5),
              const Text('AI 会先推荐你常拍的场景，再从偏好系列里选一款。', style: TextStyle(fontSize: 11, color: PrimeColor.white38)),
              const SizedBox(height: 16),
              const Text('常拍场景', style: TextStyle(fontSize: 12, color: PrimeColor.white54)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final scene in ['人像', '街拍', '风景', '静物', '美食', '夜景'])
                    ChoiceChip(
                      label: Text(scene),
                      selected: _scenes.contains(scene),
                      onSelected: (v) => setState(() => v ? _scenes.add(scene) : _scenes.remove(scene)),
                      selectedColor: PrimeColor.white,
                      backgroundColor: PrimeColor.white06,
                      labelStyle: TextStyle(fontSize: 11, color: _scenes.contains(scene) ? PrimeColor.black : PrimeColor.white54),
                      side: BorderSide.none,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('偏好胶片系列', style: TextStyle(fontSize: 12, color: PrimeColor.white54)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final series in ['Doka', 'F 系列', 'Kodak', 'Agfa', '黑白'])
                    ChoiceChip(
                      label: Text(series),
                      selected: _series.contains(series),
                      onSelected: (v) => setState(() => v ? _series.add(series) : _series.remove(series)),
                      selectedColor: PrimeColor.white,
                      backgroundColor: PrimeColor.white06,
                      labelStyle: TextStyle(fontSize: 11, color: _series.contains(series) ? PrimeColor.black : PrimeColor.white54),
                      side: BorderSide.none,
                    ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    widget.onSave(_scenes.toList(), _series.toList());
                    Navigator.of(context).pop();
                  },
                  style: FilledButton.styleFrom(backgroundColor: PrimeColor.white, foregroundColor: PrimeColor.black),
                  child: const Text('保存偏好'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GuidePage extends StatelessWidget {
  const GuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    const steps = [
      ('01', '先选一个拍法', '底部左侧的“多构图”给出全身、半身、特写；点一下切换，目标框会跟着变。'),
      ('02', '把主体放进黄框', '人物站进黄色主体框，距离卡会告诉你该前进还是后退。'),
      ('03', '等双环重合', '彩色目标环和中心环重合时，画面会自动变绿；停 0.4 秒再按快门更稳。'),
      ('04', '让 AI 给胶片', '右下角 AI 滤镜入口会按场景推荐一款胶片，点一下套用到取景。'),
      ('05', '拍完再微调', '成片页可以裁切、旋转、换滤镜、加边框；原片永远保留。'),
    ];
    return Scaffold(
      backgroundColor: PrimeColor.black,
      appBar: AppBar(
        backgroundColor: PrimeColor.black,
        elevation: 0,
        leading: IconButton(
          color: PrimeColor.white70,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('使用引导', style: TextStyle(fontSize: 17, color: PrimeColor.white, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
        children: [
          const Text('把手机当成一台\n有摄影指导的相机', style: TextStyle(fontSize: 26, height: 1.14, color: PrimeColor.white, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('5 步，第一次拍也能得到一张能发出去的图。', style: TextStyle(fontSize: 12, color: PrimeColor.white38)),
          const SizedBox(height: 26),
          for (final step in steps) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.$1, style: const TextStyle(fontSize: 12, color: Color(0xFF7ECFC8), fontWeight: FontWeight.w700)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(step.$2, style: const TextStyle(fontSize: 15, color: PrimeColor.white, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 5),
                      Text(step.$3, style: const TextStyle(fontSize: 12, height: 1.55, color: PrimeColor.white54)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            if (step != steps.last) const Divider(color: PrimeColor.white06, height: 1),
            const SizedBox(height: 22),
          ],
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: PrimeColor.white06, borderRadius: BorderRadius.circular(14)),
            child: const Text('小提示：如果 AI 一直找不到主体，长按画面把主体锁在框里。', style: TextStyle(fontSize: 11, height: 1.6, color: PrimeColor.white54)),
          ),
        ],
      ),
    );
  }
}
