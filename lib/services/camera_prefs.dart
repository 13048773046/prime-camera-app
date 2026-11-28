import 'guidance.dart';

/// Doka `SettingsActivity` 里的本地设置。先用进程内单例承载，接入登录后
/// 可整体同步到 `/ai_camera/auth/me` 返回的用户配置。
class CameraPrefs {
  CameraPrefs._();

  static final CameraPrefs instance = CameraPrefs._();

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
  String watermarkStyle = 'minimal';
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
  List<String> preferredScenes = ['人像'];
  List<String> preferredSeries = ['Doka'];

  bool get isPro => proUntil != null && proUntil!.isAfter(DateTime.now());

  void redeemPro(int days) {
    proUntil = DateTime.now().add(Duration(days: days));
  }

  /// 把 `/ai_camera/auth/me` 或支付/兑换返回的资料统一落到本地。
  void applyProfile(Map<String, dynamic> profile) {
    final phone = profile['phone_num']?.toString() ?? '';
    if (phone.isNotEmpty) accountPhone = phone;
    final name = profile['username']?.toString() ?? '';
    if (name.isNotEmpty) userName = name;
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
        int.tryParse(profile['remaining_filter_count']?.toString() ?? '') ??
        remainingFilter;
  }

  String get freeAiText {
    if (isPro) return '不限';
    return '$remainingCompose / $freeAiLimit';
  }

  void reset() {
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
    watermarkStyle = 'minimal';
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
    preferredScenes = ['人像'];
    preferredSeries = ['Doka'];
  }
}
