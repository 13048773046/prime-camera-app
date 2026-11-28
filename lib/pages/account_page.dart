import 'package:flutter/material.dart';

import '../services/camera_prefs.dart';
import '../services/doka_api.dart';
import '../services/prime_session.dart';
import '../theme.dart';

/// Doka `LoginActivity / GlobalLoginActivity / UserInfoActivity /
/// BindPhoneActivity / WechatAccountActivity / DeleteAccountActivity`
/// 的合并原生页面。
class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final CameraPrefs _prefs = CameraPrefs.instance;
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _newPhone = TextEditingController();
  final TextEditingController _bindCode = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _hint;

  bool get _loggedIn =>
      (_prefs.authToken != null && _prefs.authToken!.isNotEmpty) ||
      _prefs.accountPhone != null;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _newPhone.dispose();
    _bindCode.dispose();
    super.dispose();
  }

  Future<void> _sendCode({bool bind = false}) async {
    final phone = (bind ? _newPhone : _phone).text.trim();
    if (phone.length < 6) {
      setState(() => _hint = '请输入正确的手机号');
      return;
    }
    final dev = await DokaApi.instance.getCode(phone, scene: bind ? 'bind' : 'login');
    if (!mounted) return;
    setState(() {
      if (bind) {
        _codeSent = true;
      } else {
        _codeSent = true;
      }
      _hint = dev != null ? '开发验证码：$dev' : '验证码已发送，请查看短信';
    });
  }

  Future<void> _login() async {
    if (_busy) return;
    if (!_codeSent) {
      await _sendCode();
      return;
    }
    setState(() => _busy = true);
    final phone = _phone.text.trim();
    final profile = await DokaApi.instance.login(phone, _code.text.trim());
    if (!mounted) return;
    if (profile == null) {
      setState(() {
        _busy = false;
        _hint = '登录失败：验证码错误或服务不可用';
      });
      return;
    }
    await _applyLogin(profile, phone);
  }

  Future<void> _wechatLogin() async {
    if (_busy) return;
    setState(() => _busy = true);
    final profile = await DokaApi.instance.wechatLogin();
    if (!mounted) return;
    if (profile == null) {
      setState(() {
        _busy = false;
        _hint = '微信登录服务暂不可用；自托管环境未配置微信开放平台';
      });
      return;
    }
    await _applyLogin(profile, profile['phone_num']?.toString());
  }

  Future<void> _applyLogin(Map<String, dynamic> profile, String? phone) async {
    final token = profile['token']?.toString();
    _prefs.authToken = token;
    _prefs.accountPhone = phone;
    _prefs.userName = profile['username']?.toString();
    if (token != null && token.isNotEmpty) {
      final me = await DokaApi.instance.me(token);
      if (me != null) _prefs.applyProfile(me);
    }
    await _prefs.save();
    await PrimeSession.save();
    widget.onChanged();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _hint = null;
    });
  }

  Future<void> _bindPhone() async {
    final token = _prefs.authToken;
    if (token == null || token.isEmpty || _busy) return;
    if (_bindCode.text.trim().isEmpty) {
      await _sendCode(bind: true);
      return;
    }
    setState(() => _busy = true);
    final profile = await DokaApi.instance.bindPhone(
      _newPhone.text.trim(),
      _bindCode.text.trim(),
      token,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (profile == null) {
      _notice('绑定失败：验证码错误或手机号已被占用');
      return;
    }
    _prefs.applyProfile(profile);
    _prefs.accountPhone = _newPhone.text.trim();
    await _prefs.save();
    await PrimeSession.save();
    widget.onChanged();
    if (!mounted) return;
    setState(() => _hint = null);
    _notice('手机号已绑定');
  }

  Future<void> _bindWechat() async {
    final token = _prefs.authToken;
    if (token == null || token.isEmpty || _busy) return;
    setState(() => _busy = true);
    final profile = await DokaApi.instance.bindWechat(token);
    if (!mounted) return;
    setState(() => _busy = false);
    if (profile == null) {
      _notice('微信绑定失败；当前环境未配置微信开放平台');
      return;
    }
    _prefs.applyProfile(profile);
    await _prefs.save();
    widget.onChanged();
    if (!mounted) return;
    setState(() {});
    _notice('微信已绑定');
  }

  Future<void> _unbindWechat() async {
    final token = _prefs.authToken;
    if (token == null || token.isEmpty || _busy) return;
    if (_prefs.accountPhone == null) {
      _notice('请先绑定手机号，否则解绑微信后会失去账号入口');
      return;
    }
    setState(() => _busy = true);
    final profile = await DokaApi.instance.unbindWechat(token);
    if (!mounted) return;
    setState(() => _busy = false);
    if (profile == null) return;
    _prefs.applyProfile(profile);
    await _prefs.save();
    widget.onChanged();
    if (!mounted) return;
    setState(() {});
    _notice('微信已解绑');
  }

  Future<void> _replaceWechat() async {
    final token = _prefs.authToken;
    if (token == null || token.isEmpty || _busy) return;
    final verified = await DokaApi.instance.verifyWechatChange(token);
    if (verified == null) {
      _notice('换绑验证失败');
      return;
    }
    final profile = await DokaApi.instance.replaceWechat(token);
    if (profile == null) return;
    _prefs.applyProfile(profile);
    await _prefs.save();
    widget.onChanged();
    if (mounted) setState(() {});
    _notice('已完成微信换绑验证');
  }

  Future<void> _deleteAccount() async {
    final token = _prefs.authToken;
    if (token == null || token.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: PrimeColor.surfaceLift,
        title: const Text(
          '注销 PRIME 账号？',
          style: TextStyle(color: PrimeColor.white, fontSize: 16),
        ),
        content: const Text(
          '账号将进入软删除，登录立即失效；本机照片不会被删除。Pro 权益与剩余次数无法恢复。',
          style: TextStyle(color: PrimeColor.white54, fontSize: 12, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认注销', style: TextStyle(color: Color(0xFFFF7B72))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final data = await DokaApi.instance.deleteAccount(token);
    if (data == null) {
      _notice('注销失败，请稍后重试');
      return;
    }
    await _logout();
    if (mounted) {
      _notice('账号已注销，本机照片保留');
      Navigator.of(context).pop();
    }
  }

  Future<void> _logout() async {
    _prefs.authToken = null;
    _prefs.accountPhone = null;
    _prefs.userName = null;
    await _prefs.save();
    await PrimeSession.clear();
    widget.onChanged();
    if (mounted) setState(() {});
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

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
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                      color: PrimeColor.white54,
                    ),
                  ),
                  const Text(
                    'PRIME 账号',
                    style: TextStyle(
                      fontSize: 20,
                      color: PrimeColor.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                children: [
                  if (_loggedIn) _profileCard() else _loginCard(),
                  if (_hint != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _hint!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFC9A86A),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _section('账号安全'),
                  _card([
                    if (_prefs.accountPhone == null)
                      _bindPhoneBlock()
                    else
                      _row('手机号', _prefs.accountPhone!),
                    _divider(),
                    _wechatRow(),
                    _divider(),
                    _row('登录方式', _prefs.wechatBound && _prefs.accountPhone != null
                        ? '手机号 + 微信'
                        : (_prefs.accountPhone != null ? '手机号' : '微信')),
                    _divider(),
                    _row('账号合并', '同一手机号登录会自动合并权益'),
                  ]),
                  const SizedBox(height: 18),
                  _section('会话'),
                  _card([
                    if (_loggedIn)
                      _tapRow('退出登录', _logout)
                    else
                      _row('当前状态', '未登录'),
                    if (_loggedIn) ...[
                      _divider(),
                      _tapRow(
                        '注销账号',
                        _deleteAccount,
                        color: const Color(0xFFFF7B72),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 16),
                  const Text(
                    '账号接口走 https://uosar.yosar.cloud。微信登录/绑定在未配置开放平台时使用后端演示身份，不伪造真实微信资料。',
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.6,
                      color: PrimeColor.white24,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loginCard() {
    return _card([
      const SizedBox(height: 4),
      const Text(
        '登录后同步 Pro、AI 次数和滤镜解锁进度',
        style: TextStyle(fontSize: 11, color: PrimeColor.white38),
      ),
      const SizedBox(height: 14),
      _field(_phone, '手机号', keyboardType: TextInputType.phone),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(child: _field(_code, '验证码', keyboardType: TextInputType.number)),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _busy ? null : () => _sendCode(),
            child: Text(
              _codeSent ? '重新发送' : '获取验证码',
              style: const TextStyle(fontSize: 11, color: Color(0xFF7ECFC8)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      _primary('手机号登录 / 注册', _login),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _busy ? null : _wechatLogin,
        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
        label: const Text('微信登录'),
        style: OutlinedButton.styleFrom(
          foregroundColor: PrimeColor.white70,
          side: const BorderSide(color: PrimeColor.white12),
          minimumSize: const Size(double.infinity, 46),
        ),
      ),
    ]);
  }

  Widget _profileCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF15232A), Color(0xFF0C1014)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PrimeColor.white12),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF1E3A42),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.person_outline_rounded,
              color: Color(0xFF7ECFC8),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _prefs.userName ?? _prefs.accountPhone ?? 'PRIME 用户',
                  style: const TextStyle(
                    fontSize: 17,
                    color: PrimeColor.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_prefs.isPro ? 'Doka Pro · 已激活' : '免费版'}  ·  AI 次数 ${_prefs.freeAiText}',
                  style: const TextStyle(fontSize: 10, color: PrimeColor.white38),
                ),
              ],
            ),
          ),
          if (_prefs.isPro)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFC9A86A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'PRO',
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bindPhoneBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Text(
            '绑定手机号（当前账号仅微信登录）',
            style: TextStyle(fontSize: 12, color: PrimeColor.white70),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _field(_newPhone, '手机号', keyboardType: TextInputType.phone),
            ),
            const SizedBox(width: 6),
            TextButton(
              onPressed: _busy ? null : () => _sendCode(bind: true),
              child: const Text(
                '获取验证码',
                style: TextStyle(fontSize: 10, color: Color(0xFF7ECFC8)),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _field(_bindCode, '验证码', keyboardType: TextInputType.number),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _busy ? null : _bindPhone,
              child: const Text(
                '绑定',
                style: TextStyle(fontSize: 11, color: PrimeColor.white70),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _wechatRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const Text(
            '微信',
            style: TextStyle(fontSize: 12, color: PrimeColor.white54),
          ),
          const Spacer(),
          if (_prefs.wechatBound) ...[
            Text(
              _prefs.wechatNickname.isEmpty ? '已绑定' : _prefs.wechatNickname,
              style: const TextStyle(fontSize: 11, color: PrimeColor.white38),
            ),
            TextButton(
              onPressed: _busy ? null : _replaceWechat,
              child: const Text('换绑', style: TextStyle(fontSize: 10)),
            ),
            TextButton(
              onPressed: _busy ? null : _unbindWechat,
              child: const Text('解绑', style: TextStyle(fontSize: 10)),
            ),
          ] else
            TextButton(
              onPressed: _busy ? null : _bindWechat,
              child: const Text(
                '绑定微信',
                style: TextStyle(fontSize: 10, color: Color(0xFF7ECFC8)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      title,
      style: const TextStyle(fontSize: 12, color: PrimeColor.white38),
    ),
  );

  Widget _card(List<Widget> children) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: PrimeColor.surfaceLift,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: PrimeColor.white06, width: 0.8),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: PrimeColor.white54)),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 11, color: PrimeColor.white38)),
      ],
    ),
  );

  Widget _tapRow(String label, VoidCallback onTap, {Color? color}) => GestureDetector(
    onTap: _busy ? null : onTap,
    behavior: HitTestBehavior.opaque,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color ?? PrimeColor.white70),
          ),
          const Spacer(),
          const Icon(Icons.chevron_right_rounded, size: 16, color: PrimeColor.white24),
        ],
      ),
    ),
  );

  Widget _divider() => const Divider(height: 1, color: PrimeColor.white06);

  Widget _field(
    TextEditingController controller,
    String hint, {
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: PrimeColor.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: PrimeColor.white24),
        filled: true,
        fillColor: PrimeColor.white06,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _primary(String label, VoidCallback onTap) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: _busy ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: PrimeColor.white,
        foregroundColor: PrimeColor.black,
        padding: const EdgeInsets.symmetric(vertical: 13),
      ),
      child: Text(label),
    ),
  );
}
