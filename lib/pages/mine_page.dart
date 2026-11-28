import 'package:flutter/material.dart';

import '../services/camera_prefs.dart';
import '../services/doka_api.dart';
import '../services/prime_session.dart';
import '../services/camera_service.dart';
import '../theme.dart';
import '../services/app_config.dart';
import 'settings_page.dart';
import 'account_page.dart';

/// Doka 式「我的」页：账号卡 + 分组设置列表 + 底部三栏。
/// 账号、Pro、兑换和 AI 次数都走 PRIME 后端，不再用本地假会员。
class MinePage extends StatefulWidget {
  const MinePage({
    super.key,
    required this.photoCount,
    this.camera,
    required this.gridOn,
    required this.flashOn,
    required this.onGrid,
    required this.onFlash,
    required this.onGallery,
    required this.onCamera,
  });

  final int photoCount;
  final CameraService? camera;
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
  late int _photoCount = widget.photoCount;

  @override
  void initState() {
    super.initState();
    _refreshCount();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    await PrimeSession.restore();
    if (!mounted) return;
    setState(() {});
    await _refreshProfile();
  }

  Future<void> _refreshProfile() async {
    final token = CameraPrefs.instance.authToken;
    if (token == null || token.isEmpty) return;
    final profile = await DokaApi.instance.me(token);
    if (profile == null || !mounted) return;
    CameraPrefs.instance.applyProfile(profile);
    setState(() {});
  }

  Future<void> _refreshCount() async {
    final camera = widget.camera;
    if (camera == null) return;
    final photos = await camera.listPhotos();
    if (!mounted || photos.isEmpty) return;
    setState(() => _photoCount = photos.length);
  }

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
                    GestureDetector(
                      onTap: _openAccount,
                      behavior: HitTestBehavior.opaque,
                      child: _accountCard(),
                    ),
                    const SizedBox(height: 12),
                    _proCard(),
                    const SizedBox(height: 26),
                    _sectionTitle('账号与会员'),
                    _card([
                      _row(
                        icon: Icons.workspace_premium_outlined,
                        label: 'Doka Pro',
                        value: CameraPrefs.instance.isPro ? '已激活' : '未开通',
                        onTap: _openPro,
                      ),
                      _row(
                        icon: Icons.confirmation_number_outlined,
                        label: '兑换码',
                        value: '输入兑换',
                        onTap: _openRedeem,
                      ),
                      _row(
                        icon: Icons.auto_awesome_outlined,
                        label: '免费 AI 次数',
                        value: CameraPrefs.instance.freeAiText,
                      ),
                    ]),
                    const SizedBox(height: 22),
                    _sectionTitle('拍摄'),
                    _card([
                      _row(
                        icon: Icons.center_focus_strong_outlined,
                        label: '构图引导',
                        value: '流小萤 · 设备端',
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
                        value: CameraPrefs.instance.watermark ? '开启' : '关闭',
                        onTap: () => _openSettings(context),
                      ),
                      _row(
                        icon: Icons.filter_frames_outlined,
                        label: 'AI 多景别',
                        value: CameraPrefs.instance.multiCompose ? '开启' : '关闭',
                        onTap: () => _openSettings(context),
                      ),
                    ]),
                    const SizedBox(height: 22),
                    _sectionTitle('相册'),
                    _card([
                      _row(
                        icon: Icons.photo_library_outlined,
                        label: '最近照片',
                        value: '$_photoCount 张',
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
                        value: CameraPrefs.instance.language,
                        onTap: () => _openSettings(context),
                      ),
                      _row(
                        icon: Icons.tune_rounded,
                        label: '完整设置',
                        value: '18 项',
                        onTap: () => _openSettings(context),
                      ),
                      _row(
                        icon: Icons.info_outline_rounded,
                        label: '版本',
                        value: '0.5.0',
                      ),
                    ]),
                    const SizedBox(height: 22),
                    _sectionTitle('支持'),
                    _card([
                      _row(
                        icon: Icons.auto_stories_outlined,
                        label: '使用引导',
                        value: '5 步',
                        onTap: _openGuide,
                      ),
                      _row(
                        icon: Icons.help_outline_rounded,
                        label: '帮助与反馈',
                        value: '邮件 / 抖音 / 小红书',
                        onTap: _openHelp,
                      ),
                      _row(
                        icon: Icons.share_outlined,
                        label: '分享 PRIME',
                        value: '邀请朋友',
                        onTap: _shareApp,
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
    final loggedIn = CameraPrefs.instance.accountPhone != null;
    final name = loggedIn
        ? (CameraPrefs.instance.userName?.isNotEmpty == true
              ? CameraPrefs.instance.userName!
              : 'PRIME 用户')
        : '登录 PRIME';
    final subtitle = loggedIn
        ? '${CameraPrefs.instance.accountPhone} · ${CameraPrefs.instance.isPro ? 'Pro 已激活' : '免费账户'}'
        : '登录后同步 Pro 权益与 AI 次数';
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
            width: 46,
            height: 46,
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [
                  Color(0xFF80EEFF),
                  Color(0xFFB1CFFF),
                  Color(0xFFFFD2F6),
                  Color(0xFFFFC38F),
                  Color(0xFF80EEFF),
                ],
              ),
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/ai/liuxiaoying_face.png',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Color(0xFF2A2B31),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 21,
                    color: PrimeColor.white70,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 17,
                    color: PrimeColor.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: PrimeColor.white38,
                  ),
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

  Widget _proCard() {
    final pro = CameraPrefs.instance.isPro;
    return GestureDetector(
      onTap: _openPro,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: pro
                ? const [Color(0xFF30403F), Color(0xFF171B1B)]
                : const [Color(0xFF2A2620), Color(0xFF161412)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: const Color(0xFFC9A86A).withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.workspace_premium_rounded,
              size: 24,
              color: Color(0xFFC9A86A),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pro ? 'Doka Pro 已激活' : 'Doka Pro',
                    style: const TextStyle(
                      fontSize: 15,
                      color: PrimeColor.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    pro ? '全量胶片、AI 构图与无水印导出已解锁' : '解锁全量胶片、AI 构图与无水印导出',
                    style: const TextStyle(
                      fontSize: 11,
                      color: PrimeColor.white38,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: PrimeColor.white38,
            ),
          ],
        ),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsPage()));
  }

  void _openGuide() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const GuidePage()));
  }

  Future<void> _openAccount() async {
    await _refreshProfile();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AccountPage(onChanged: () => setState(() {})),
      ),
    );
  }

  void _openPro() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ProSheet(onChanged: () => setState(() {})),
    );
  }

  void _openRedeem() {
    if (!AppConfig.instance.showRedeemCodeEntry) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('兑换码入口暂未开放')),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => _RedeemDialog(onChanged: () => setState(() {})),
    );
  }

  void _openHelp() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: PrimeColor.black,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '帮助与反馈',
                  style: TextStyle(
                    fontSize: 18,
                    color: PrimeColor.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '遇到问题先看“使用引导”；仍然卡住时，把机型、系统版本和截图一起发给我们。',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.6,
                    color: PrimeColor.white38,
                  ),
                ),
                const SizedBox(height: 14),
                for (final item in const [
                  ('发邮件', 'support@prime.camera'),
                  ('抖音', '@PRIME 相机'),
                  ('小红书', '@PRIME 拍摄手记'),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Text(
                          item.$1,
                          style: const TextStyle(
                            fontSize: 13,
                            color: PrimeColor.white70,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          item.$2,
                          style: const TextStyle(
                            fontSize: 11,
                            color: PrimeColor.white38,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _shareApp() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: PrimeColor.surfaceLift,
        title: const Text(
          '分享 PRIME',
          style: TextStyle(color: PrimeColor.white, fontSize: 16),
        ),
        content: const Text(
          '把链接发给朋友：\nhttps://github.com/13048773046/prime-camera-app',
          style: TextStyle(
            color: PrimeColor.white54,
            fontSize: 12,
            height: 1.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('好'),
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

class _AccountSheet extends StatefulWidget {
  const _AccountSheet({required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _code = TextEditingController();
  bool _codeSent = false;
  String? _hint;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = _phone.text.trim();
    if (phone.length < 6) {
      setState(() => _hint = '请输入正确的手机号');
      return;
    }
    final api = DokaApi.instance;
    if (api.enabled) {
      final devCode = await api.getCode(phone);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _hint = devCode != null ? '开发验证码：$devCode' : '验证码已发送，请查看短信';
      });
      return;
    }
    setState(() {
      _codeSent = true;
      _hint = '本地体验模式：验证码 123456';
    });
  }

  Future<void> _login() async {
    if (!_codeSent) {
      await _sendCode();
      return;
    }
    final phone = _phone.text.trim();
    final api = DokaApi.instance;
    if (api.enabled) {
      final profile = await api.login(phone, _code.text.trim());
      if (!mounted) return;
      if (profile == null) {
        setState(() => _hint = '登录失败：验证码错误或服务不可用');
        return;
      }
      final token = profile['token']?.toString();
      CameraPrefs.instance.accountPhone = phone;
      CameraPrefs.instance.authToken = token;
      CameraPrefs.instance.userName = profile['username']?.toString();
      // login 只回 token；再用 me 拉真实 Pro / 剩余 AI 次数，不能拿本地 5/5 冒充。
      if (token != null && token.isNotEmpty) {
        final me = await api.me(token);
        if (me != null) CameraPrefs.instance.applyProfile(me);
      }
      await PrimeSession.save();
      widget.onChanged();
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }
    if (_code.text.trim() != '123456') {
      setState(() => _hint = '验证码错误，本地体验码为 123456');
      return;
    }
    CameraPrefs.instance.accountPhone = phone;
    CameraPrefs.instance.userName = '本地体验账号';
    widget.onChanged();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final phone = CameraPrefs.instance.accountPhone;
    return Container(
      decoration: const BoxDecoration(
        color: PrimeColor.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            18,
            20,
            24 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 3,
                  decoration: BoxDecoration(
                    color: PrimeColor.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                phone == null ? '登录 PRIME' : '账号信息',
                style: const TextStyle(
                  fontSize: 20,
                  color: PrimeColor.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                phone == null
                    ? '登录后同步 Pro 权益与 AI 次数。演示环境会直接显示开发验证码。'
                    : '手机号：$phone\n登录方式：${DokaApi.instance.enabled ? 'PRIME 云端账号' : '本地体验账号'}',
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.6,
                  color: PrimeColor.white38,
                ),
              ),
              if (phone == null) ...[
                const SizedBox(height: 18),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: PrimeColor.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '手机号',
                    hintStyle: const TextStyle(color: PrimeColor.white24),
                    filled: true,
                    fillColor: PrimeColor.white06,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _code,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          color: PrimeColor.white,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: '验证码',
                          hintStyle: const TextStyle(color: PrimeColor.white24),
                          filled: true,
                          fillColor: PrimeColor.white06,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _sendCode,
                      child: Text(
                        _codeSent ? '重新发送' : '获取验证码',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF7ECFC8),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_hint != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _hint!,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFFC9A86A),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _login,
                    style: FilledButton.styleFrom(
                      backgroundColor: PrimeColor.white,
                      foregroundColor: PrimeColor.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('登录 / 注册'),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 18),
                _infoRow(
                  '账号',
                  CameraPrefs.instance.userName ??
                      CameraPrefs.instance.accountPhone ??
                      'PRIME 用户',
                ),
                _infoRow('Pro 状态', CameraPrefs.instance.isPro ? '已激活' : '未开通'),
                _infoRow('免费 AI 次数', CameraPrefs.instance.freeAiText),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      CameraPrefs.instance.accountPhone = null;
                      CameraPrefs.instance.authToken = null;
                      CameraPrefs.instance.userName = null;
                      PrimeSession.clear();
                      widget.onChanged();
                      Navigator.of(context).pop();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: PrimeColor.white54,
                      side: const BorderSide(color: PrimeColor.white12),
                    ),
                    child: const Text('退出账号'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: PrimeColor.white54),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(fontSize: 12, color: PrimeColor.white38),
        ),
      ],
    ),
  );
}

class _ProSheet extends StatefulWidget {
  const _ProSheet({required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<_ProSheet> createState() => _ProSheetState();
}

class _ProSheetState extends State<_ProSheet> {
  static const _fallbackProducts = <Map<String, dynamic>>[
    {
      'product_id': 'prime.pro.month',
      'title': '连续包月',
      'actual_price': 18,
      'duration_days': 30,
      'daily_price': '0.60',
    },
    {
      'product_id': 'prime.pro.year',
      'title': '连续包年',
      'actual_price': 128,
      'duration_days': 365,
      'daily_price': '0.35',
    },
    {
      'product_id': 'prime.pro.lifetime',
      'title': '终身 Pro',
      'actual_price': 298,
      'duration_days': 3650,
      'daily_price': '—',
    },
  ];

  final DokaApi _api = DokaApi.instance;
  List<Map<String, dynamic>> _products = _fallbackProducts;
  bool _loading = true;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _api.vipProducts();
    if (!mounted) return;
    final raw = data?['products'];
    if (raw is List && raw.isNotEmpty) {
      _products = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    setState(() => _loading = false);
  }

  Future<void> _buy(Map<String, dynamic> product) async {
    final token = CameraPrefs.instance.authToken;
    if (token == null || token.isEmpty) {
      _notice('请先登录 PRIME 账号，再开通 Pro');
      return;
    }
    final id = product['product_id']?.toString() ?? '';
    if (id.isEmpty || _busyId != null) return;
    setState(() => _busyId = id);
    final order = await _api.createOrder(id, token);
    if (!mounted) return;
    final orderNo = order?['out_trade_no']?.toString() ?? '';
    if (orderNo.isEmpty) {
      setState(() => _busyId = null);
      _notice('下单失败；套餐服务暂不可用，可先用兑换码 PRIME2026');
      return;
    }
    // 自托管演示：真实微信/Google 商户未接入，不伪造外部支付，只走服务端确认。
    final profile = await _api.mockConfirm(orderNo, token);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (profile == null) {
      _notice('支付确认失败；没有扣款，请稍后再试');
      return;
    }
    CameraPrefs.instance.applyProfile(profile);
    widget.onChanged();
    if (!mounted) return;
    _notice('Pro 已开通，权益已同步到本机');
    Navigator.of(context).pop();
  }

  void _notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: PrimeColor.surfaceLift),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: PrimeColor.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.workspace_premium_rounded,
                    color: Color(0xFFC9A86A),
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Doka Pro',
                    style: TextStyle(
                      fontSize: 20,
                      color: PrimeColor.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (_loading)
                    const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: PrimeColor.white38,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                '全量胶片、AI 构图不限次、无水印导出、多景别方案。',
                style: TextStyle(fontSize: 11, color: PrimeColor.white38),
              ),
              const SizedBox(height: 16),
              for (final product in _products)
                GestureDetector(
                  onTap: () => _buy(product),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: PrimeColor.white06,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: PrimeColor.white12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product['title']?.toString() ?? 'Pro 套餐',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: PrimeColor.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${product['duration_days'] ?? ''} 天 · ${product['daily_price'] ?? '—'}/天',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: PrimeColor.white38,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '¥${product['actual_price'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFFC9A86A),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _busyId == (product['product_id']?.toString() ?? '')
                              ? '处理中'
                              : '演示开通',
                          style: const TextStyle(
                            fontSize: 10,
                            color: PrimeColor.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                '当前为 PRIME 自托管演示：订单与会员状态走服务端，真实微信 / Google 支付需要商户资质，不会伪造外部扣款。',
                style: TextStyle(
                  fontSize: 10,
                  height: 1.5,
                  color: PrimeColor.white24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RedeemDialog extends StatefulWidget {
  const _RedeemDialog({required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<_RedeemDialog> createState() => _RedeemDialogState();
}

class _RedeemDialogState extends State<_RedeemDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _hint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final code = _controller.text.trim().toUpperCase();
    final api = DokaApi.instance;
    if (api.enabled) {
      final token = CameraPrefs.instance.authToken;
      if (token == null || token.isEmpty) {
        setState(() => _hint = '请先登录云端账号再兑换');
        return;
      }
      final data = await api.redeem(code, token);
      if (!mounted) return;
      if (data == null) {
        setState(() => _hint = '兑换码无效，或服务暂不可用');
        return;
      }
      final profile = data['profile'];
      if (profile is Map) {
        CameraPrefs.instance.applyProfile(Map<String, dynamic>.from(profile));
      }
      widget.onChanged();
      Navigator.pop(context);
      return;
    }
    if (code == 'PRIME2026' || code == 'PRIME-30') {
      CameraPrefs.instance.redeemPro(30);
      widget.onChanged();
      Navigator.pop(context);
    } else if (code == 'PRIME-LIFETIME') {
      CameraPrefs.instance.redeemPro(3650);
      widget.onChanged();
      Navigator.pop(context);
    } else {
      setState(() => _hint = '兑换码无效；体验码 PRIME2026');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PrimeColor.surfaceLift,
      title: const Text(
        '兑换 Pro',
        style: TextStyle(color: PrimeColor.white, fontSize: 16),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            style: const TextStyle(color: PrimeColor.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: '输入兑换码',
              hintStyle: const TextStyle(color: PrimeColor.white24),
              filled: true,
              fillColor: PrimeColor.white06,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_hint != null) ...[
            const SizedBox(height: 8),
            Text(
              _hint!,
              style: const TextStyle(fontSize: 10, color: Color(0xFFC9A86A)),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _redeem, child: const Text('兑换')),
      ],
    );
  }
}
