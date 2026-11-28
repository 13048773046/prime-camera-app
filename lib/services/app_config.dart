import 'doka_api.dart';

/// Doka `DokaAppConfigResp` 的客户端镜像。
///
/// 启动时异步拉取，网络失败不阻塞拍摄；所有开关默认保持可用。
class AppConfig {
  AppConfig._();

  static final AppConfig instance = AppConfig._();

  bool loaded = false;
  bool globalEnabled = true;
  bool maintenance = false;
  bool showRedeemCodeEntry = true;
  bool wechatLoginEnabled = true;
  bool wechatPhoneBindEnabled = true;
  bool wechatAccountManagementEnabled = true;
  bool securityBlockInstallerRisk = false;
  bool securityBlockProxyRisk = false;
  bool showCompleteCopywriting = true;
  String announcement = '';

  Future<void> load() async {
    final data = await DokaApi.instance.appConfig();
    if (data == null) return;
    loaded = true;
    globalEnabled = data['globalEnabled'] != false;
    maintenance = data['maintenance'] == true;
    showRedeemCodeEntry = data['showRedeemCodeEntry'] != false;
    wechatLoginEnabled = data['wechatLoginEnabled'] != false;
    wechatPhoneBindEnabled = data['wechatPhoneBindEnabled'] != false;
    wechatAccountManagementEnabled =
        data['wechatAccountManagementEnabled'] != false;
    securityBlockInstallerRisk =
        data['securityBlockInstallerRisk'] == true;
    securityBlockProxyRisk = data['securityBlockProxyRisk'] == true;
    showCompleteCopywriting = data['showCompleteCopywriting'] != false;
    announcement = data['announcement']?.toString() ?? '';
  }
}
