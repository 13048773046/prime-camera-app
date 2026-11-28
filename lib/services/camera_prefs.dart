import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color;

import 'package:shared_preferences/shared_preferences.dart';

import '../data/filters.dart';
import 'guidance.dart';

/// Doka 的本地设置与账号缓存。
///
/// v0.6.0 开始不再用进程内单例：所有开关、调色盘、滤镜解锁进度和
/// 登录态都会写入 `SharedPreferences`，冷启动恢复。
class CameraPrefs {
  CameraPrefs._();

  static final CameraPrefs instance = CameraPrefs._();
  static const _storageKey = 'prime.prefs.v1';

  SharedPreferences? _store;

  bool privacyAccepted = false;
  bool guideSeen = false;
  bool aiTipSeen = false;
  bool filterTipSeen = false;

  bool grid = false;
  bool flash = false;
  bool livePhoto = false;
  bool saveRaw = false;
  bool level = false;
  bool touchShot = false;
  bool selfieMirror = true;
  bool multiCompose = true;
  bool aiFilter = true;
  bool autoZoom = true;
  bool actionRecognition = true;
  bool subjectGuide = true;
  bool alignmentConfirm = true;
  bool noiseReduction = true;
  bool watermark = true;

  /// 水印：none / simpleWhite / vintageOrange / camera。
  String watermarkStyle = 'simpleWhite';

  /// 边框：none / classic / camera / timeDevice / shotOnDoka。
  String borderStyle = 'none';

  /// AI 滤镜推荐展示：panel（底部面板）/ cards（空间旋转卡片）。
  String aiFilterDisplayStyle = 'panel';

  String language = '简体中文';
  SceneMode scene = SceneMode.general;
  int timerSeconds = 0;
  String videoQuality = '1080P';

  DateTime? proUntil;
  int remainingCompose = 5;
  int remainingFilter = 5;
  int freeAiLimit = 5;
  String? accountPhone;
  String? authToken;
  String? userName;
  String? email;
  String loginType = 'phone';
  bool wechatBound = false;
  String wechatNickname = '';
  bool hasPhoneBound = false;

  List<String> preferredScenes = ['人像'];
  List<String> preferredSeries = ['Doka'];
  Map<String, int> filterShots = <String, int>{};

  bool paletteEnabled = false;
  double paletteTone = 0.5;
  double paletteStrength = 0.5;
  int paletteColorValue = 0xFFB7E5FF;

  bool get isPro => proUntil != null && proUntil!.isAfter(DateTime.now());

  Color get paletteColor => Color(paletteColorValue);

  Future<void> load() async {
    _store = await SharedPreferences.getInstance();
    final raw = _store!.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return;
      final data = Map<String, dynamic>.from(map);
      privacyAccepted = data['privacyAccepted'] == true;
      guideSeen = data['guideSeen'] == true;
      aiTipSeen = data['aiTipSeen'] == true;
      filterTipSeen = data['filterTipSeen'] == true;
      grid = data['grid'] == true;
      flash = data['flash'] == true;
      livePhoto = data['livePhoto'] == true;
      saveRaw = data['saveRaw'] == true;
      level = data['level'] == true;
      touchShot = data['touchShot'] == true;
      selfieMirror = data['selfieMirror'] != false;
      multiCompose = data['multiCompose'] != false;
      aiFilter = data['aiFilter'] != false;
      autoZoom = data['autoZoom'] != false;
      actionRecognition = data['actionRecognition'] != false;
      subjectGuide = data['subjectGuide'] != false;
      alignmentConfirm = data['alignmentConfirm'] != false;
      noiseReduction = data['noiseReduction'] != false;
      watermark = data['watermark'] != false;
      watermarkStyle =
          data['watermarkStyle']?.toString() ?? watermarkStyle;
      borderStyle = data['borderStyle']?.toString() ?? borderStyle;
      aiFilterDisplayStyle =
          data['aiFilterDisplayStyle']?.toString() ?? aiFilterDisplayStyle;
      language = data['language']?.toString() ?? language;
      scene = SceneMode.values.firstWhere(
        (e) => e.name == data['scene'],
        orElse: () => SceneMode.general,
      );
      timerSeconds = int.tryParse(data['timerSeconds']?.toString() ?? '') ?? 0;
      videoQuality = data['videoQuality']?.toString() ?? videoQuality;
      proUntil = DateTime.tryParse(data['proUntil']?.toString() ?? '');
      remainingCompose =
          int.tryParse(data['remainingCompose']?.toString() ?? '') ??
          remainingCompose;
      remainingFilter =
          int.tryParse(data['remainingFilter']?.toString() ?? '') ??
          remainingFilter;
      freeAiLimit =
          int.tryParse(data['freeAiLimit']?.toString() ?? '') ?? freeAiLimit;
      accountPhone = data['accountPhone']?.toString();
      authToken = data['authToken']?.toString();
      userName = data['userName']?.toString();
      email = data['email']?.toString();
      loginType = data['loginType']?.toString() ?? loginType;
      wechatBound = data['wechatBound'] == true;
      wechatNickname = data['wechatNickname']?.toString() ?? '';
      hasPhoneBound = data['hasPhoneBound'] == true;
      final scenes = data['preferredScenes'];
      if (scenes is List) {
        preferredScenes = scenes.map((e) => e.toString()).toList();
      }
      final series = data['preferredSeries'];
      if (series is List) {
        preferredSeries = series.map((e) => e.toString()).toList();
      }
      final shots = data['filterShots'];
      if (shots is Map) {
        filterShots = shots.map(
          (key, value) => MapEntry(key.toString(), int.tryParse('$value') ?? 0),
        );
      }
      paletteEnabled = data['paletteEnabled'] == true;
      paletteTone = _double(data['paletteTone'], paletteTone);
      paletteStrength = _double(data['paletteStrength'], paletteStrength);
      paletteColorValue =
          int.tryParse(data['paletteColorValue']?.toString() ?? '') ??
          paletteColorValue;
    } catch (_) {
      // 配置损坏时回退默认值，不影响启动。
    }
  }

  double _double(dynamic value, double fallback) =>
      value is num ? value.toDouble() : fallback;

  /// 立即写入磁盘。设置页每次操作都会调用，冷启动恢复。
  Future<void> save() async {
    _store ??= await SharedPreferences.getInstance();
    final data = <String, dynamic>{
      'privacyAccepted': privacyAccepted,
      'guideSeen': guideSeen,
      'aiTipSeen': aiTipSeen,
      'filterTipSeen': filterTipSeen,
      'grid': grid,
      'flash': flash,
      'livePhoto': livePhoto,
      'saveRaw': saveRaw,
      'level': level,
      'touchShot': touchShot,
      'selfieMirror': selfieMirror,
      'multiCompose': multiCompose,
      'aiFilter': aiFilter,
      'autoZoom': autoZoom,
      'actionRecognition': actionRecognition,
      'subjectGuide': subjectGuide,
      'alignmentConfirm': alignmentConfirm,
      'noiseReduction': noiseReduction,
      'watermark': watermark,
      'watermarkStyle': watermarkStyle,
      'borderStyle': borderStyle,
      'aiFilterDisplayStyle': aiFilterDisplayStyle,
      'language': language,
      'scene': scene.name,
      'timerSeconds': timerSeconds,
      'videoQuality': videoQuality,
      'proUntil': proUntil?.toIso8601String(),
      'remainingCompose': remainingCompose,
      'remainingFilter': remainingFilter,
      'freeAiLimit': freeAiLimit,
      'accountPhone': accountPhone,
      'authToken': authToken,
      'userName': userName,
      'email': email,
      'loginType': loginType,
      'wechatBound': wechatBound,
      'wechatNickname': wechatNickname,
      'hasPhoneBound': hasPhoneBound,
      'preferredScenes': preferredScenes,
      'preferredSeries': preferredSeries,
      'filterShots': filterShots,
      'paletteEnabled': paletteEnabled,
      'paletteTone': paletteTone,
      'paletteStrength': paletteStrength,
      'paletteColorValue': paletteColorValue,
    };
    await _store!.setString(_storageKey, jsonEncode(data));
  }

  /// 立即排队写入：SharedPreferences 本身批量提交，不再留计时器。
  void touch() {
    unawaited(save());
  }

  void redeemPro(int days) {
    proUntil = DateTime.now().add(Duration(days: days));
    touch();
  }

  int filterShotCount(String id) => filterShots[id] ?? 0;

  bool filterUnlocked(FilterPreset filter) {
    if (!filter.pro) return true;
    if (isPro) return true;
    return filterShotCount(filter.id) >= filter.unlockShots;
  }

  int filterUnlockRemaining(FilterPreset filter) {
    if (!filter.pro || isPro) return 0;
    return (filter.unlockShots - filterShotCount(filter.id)).clamp(0, 999);
  }

  void recordFilterShot(String id) {
    filterShots[id] = filterShotCount(id) + 1;
    touch();
  }

  /// 把 `/ai_camera/auth/me` 或支付/兑换返回的资料统一落到本地。
  void applyProfile(Map<String, dynamic> profile) {
    final phone = profile['phone_num']?.toString() ?? '';
    if (phone.isNotEmpty) accountPhone = phone;
    final name = profile['username']?.toString() ?? '';
    if (name.isNotEmpty) userName = name;
    final mail = profile['email']?.toString() ?? '';
    if (mail.isNotEmpty) email = mail;
    final expire = DateTime.tryParse(
      profile['vip_expire_at']?.toString() ?? '',
    );
    proUntil = expire;
    freeAiLimit =
        int.tryParse(profile['free_ai_limit']?.toString() ?? '') ?? freeAiLimit;
    remainingCompose =
        int.tryParse(profile['remaining_compose_count']?.toString() ?? '') ??
        remainingCompose;
    remainingFilter =
        int.tryParse(
          profile['remaining_filter_free_count']?.toString() ??
              profile['remaining_filter_count']?.toString() ??
              '',
        ) ??
        remainingFilter;
    loginType = profile['login_type']?.toString() ?? loginType;
    hasPhoneBound = profile['has_phone_bound'] == true;
    wechatBound = profile['wechat_bound'] == true;
    wechatNickname = profile['wechat_nickname']?.toString() ?? '';
    touch();
  }

  String get freeAiText {
    if (isPro) return '不限';
    return '$remainingCompose / $freeAiLimit';
  }

  void reset() {
    privacyAccepted = false;
    guideSeen = false;
    aiTipSeen = false;
    filterTipSeen = false;
    grid = false;
    flash = false;
    livePhoto = false;
    saveRaw = false;
    level = false;
    touchShot = false;
    selfieMirror = true;
    multiCompose = true;
    aiFilter = true;
    autoZoom = true;
    actionRecognition = true;
    subjectGuide = true;
    alignmentConfirm = true;
    noiseReduction = true;
    watermark = true;
    watermarkStyle = 'simpleWhite';
    borderStyle = 'none';
    aiFilterDisplayStyle = 'panel';
    language = '简体中文';
    scene = SceneMode.general;
    timerSeconds = 0;
    videoQuality = '1080P';
    proUntil = null;
    remainingCompose = 5;
    remainingFilter = 5;
    freeAiLimit = 5;
    accountPhone = null;
    authToken = null;
    userName = null;
    email = null;
    loginType = 'phone';
    wechatBound = false;
    wechatNickname = '';
    hasPhoneBound = false;
    preferredScenes = ['人像'];
    preferredSeries = ['Doka'];
    filterShots = <String, int>{};
    paletteEnabled = false;
    paletteTone = 0.5;
    paletteStrength = 0.5;
    paletteColorValue = 0xFFB7E5FF;
    unawaited(save());
  }
}
