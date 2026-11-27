# Doka 1.3.20 全量功能与 PRIME 迁移矩阵

来源：`analysis/doka/apktool`（185 layout / 1,538 res）与 `analysis/doka/jadx_full/sources/com/ydgn/doka`（415 个业务 Java），接口来自 `http/ApiService.java`。

标记：✅ 已落地；🟡 已有近似实现/需真机能力；⬜ 待补。

## A. 相机主界面与拍摄

| Doka 功能 | 证据 | PRIME |
|---|---|---|
| 3:4 圆角取景 + CameraMask | `fragment_camera.xml` / `CameraMaskView` | ✅ |
| 多焦段 .5/1x/2/5、拨盘、单焦段胶囊 | `rgZoomRatio` / `ZoomDialView` | ✅ 胶囊；⬜ 拨盘 |
| 双指缩放/点击焦段 | `CameraZoomController` | 🟡 焦段按钮 |
| 前后置切换 | `ivLensFacing` | ✅ |
| 闪光灯 | `camera_option_flash` | ✅ |
| 九宫格辅助线 | `NineGridView` | ✅ |
| 水平仪/水平标尺 | `LevelOverlayView` / `CameraLevelGaugeView` | 🟡 倾斜口令；⬜ 图形水平仪 |
| 曝光滑杆 | `seekbarExposure` / `CameraExposureController` | ⬜ |
| 点击对焦 | `focusPoint` | ⬜ |
| 触屏拍摄 | `mine_setting_touch_shot` | ⬜ |
| 自拍镜像 | `mine_setting_selfie_mirror` | ⬜ |
| 实况照片 | `LivePhotoCaptureCoordinator` + 各厂商 Provider | ⬜ iOS 需 Live Photo 管线 |
| 保存底片 RAW | `camera_option_save_raw` / `Camera2RawMetadataResolver` | ⬜ |
| 多帧降噪/HDR/夜景/人像 | `Camera2MultiFrameProcessor` / `CameraExtensionPrefs` | ⬜ 原生扩展能力 |
| 连拍/多帧快门反馈 | `viewShutterFlash` | 🟡 快门动画 |
| 权限说明与拒绝提示 | `llPermissionNotice` / `permission_*` | 🟡 权限页 |
| 拍摄后编辑（滤镜/裁切/旋转/边框/水印） | `photoedit/*` / `DokaCropActivity` | 🟡 仅拍摄时滤镜+比例裁切 |
| Doka 调色盘（颜色/色调/强度） | `DokaPaletteManager` / `DokaPalettePanelController` | ⬜ |
| 分享/保存到系统相册 | `PhotoSaveRepository` | ✅ |

## B. AI 构图与 AI 滤镜

| Doka 功能 | 证据 | PRIME |
|---|---|---|
| 当前帧上传 scan | `AiCompositionController.uploadJpegForScan` | ✅ `/v1/scan` |
| 服务端返回子区域/模板/理由/焦距 | `CameraData` / `ScanResp` | ✅ |
| ORB + BFMatcher + RANSAC 模板跟踪 | `CompositionMatcher` | 🟡 用 Vision 主体框替代 |
| Kalman 平滑目标中心 | `AIComposeMotionTracker` / `geo/*` | 🟡 原生 Vision 平滑 |
| 彩色目标环/渐变框/暗角 | `CameraMappingView` / `GradientBorderView` | ✅ |
| 黄色主体框 + 8 个可拖角点 | `SubjectMarkerOverlayView` | 🟡 显示；⬜ 拖拽 |
| 长按选择/指定主体 | `camera_subject_selection_*` | ⬜ |
| 多景别方案 1/2、切换方案 | `multi_compose_*` | 🟡 3 个拍法；⬜ 自动方案 2 |
| AI 滤镜推荐（卡片/空间卡） | `CameraAiFilterEffectController` | 🟡 5 个滤镜；⬜ 推荐卡/空间卡 |
| AI 滤镜偏好（场景/滤镜排序） | `AiFilterPreference*Activity` | ⬜ |
| AI 构图/滤镜免费次数、Pro 限制 | `vip_ai_*_limit_*` | ⬜ |
| AI 构图使用提示 3 条 | `ai_usage_tip_*` | ⬜ |
| 对齐停留确认 | `mine_alignment_confirm_info_*` | ⬜ |
| AI 滤镜单独入口 | `ivAiFilter` / `ai_filter_usage_tip` | ⬜ |

## C. 滤镜

| Doka 功能 | 证据 | PRIME |
|---|---|---|
| 原片 + 5 大类胶片滤镜 | `filter_category_*` / `filter_detail_*` | 🟡 5 个近似 |
| 滤镜详情、试用、Pro 锁 | `layout_filter_detail.xml` | ⬜ |
| 拍摄解锁进度 | `filter_detail_milestone_*` | ⬜ |
| 调色盘（颜色/色调/强度） | `doka_palette_*` | ⬜ |
| AI 推荐滤镜快速切换卡 | `aiQuickSwitch*` | ⬜ |

## D. 相册

| Doka 功能 | 证据 | PRIME |
|---|---|---|
| 三列网格、按日期分组 | `fragment_gallery.xml` / `GalleryGroupItem` | 🟡 网格，无日期 |
| 空状态、去拍摄 | `gallery_empty_title` | ✅ |
| 多选、已选计数、取消 | `gallery_selected_*` | ⬜ |
| 删除单张/多张 | `delete_single_*` / `delete_multiple_*` | ⬜ |
| 分享图片/微信/朋友圈 | `gallery_share_*` / `share_wechat_*` | 🟡 系统分享 |
| 导入照片 | `gallery_import*` | ⬜ |
| 图片预览/大图 | `PopupLookPictureBinding` / `LookPictureAdapter` | ✅ 简单预览 |
| 图片失效/部分删除失败提示 | `gallery_delete_*` | ⬜ |

## E. 我的 / 账号 / 会员

| Doka 功能 | 证据 | PRIME |
|---|---|---|
| 账号卡、登录/未登录 | `fragment_mine.xml` | 🟡 本地模式 |
| 手机号验证码登录/注册 | `LoginActivity` / `login_*` | ⬜ |
| 微信登录/绑定/换绑/解绑 | `WechatAccountActivity` / `wxapi` | ⬜ |
| Google/邮箱登录（海外） | `GlobalLoginActivity` | ⬜ |
| 用户信息/昵称/头像/手机号 | `UserInfoActivity` | ⬜ |
| 注销账号 | `DeleteAccountActivity` | ⬜ |
| Pro 套餐/购买/续费/兑换 | `VipPurchaseActivity` / `RedeemVipActivity` | ⬜ |
| 免费 AI 次数展示 | `mine_free_ai_counts` | ⬜ |
| 使用引导 5 步 | `GuideActivity` / `guide_step*` | ⬜ |
| 帮助反馈/邮件/抖音/小红书 | `mine_help_feedback` | ⬜ |
| 语言切换并重启 | `LanguageSettingsActivity` | ⬜ |
| 问题诊断/日志 | `DiagnosticsActivity` | ⬜ |
| 关于/检查更新/ICP/SDK | `AboutActivity` | ⬜ |
| 安全环境拦截 | `SecurityBlockActivity` | ⬜ |

## F. 设置

| Doka 功能 | 证据 | PRIME |
|---|---|---|
| 构图网格 | `mine_setting_nine_grid` | ✅ |
| 水平仪 | `mine_setting_gradient` | ⬜ |
| 闪光灯 | `mine_setting_flash` | ✅ |
| 构图附带 AI 滤镜 | `mine_setting_ai_filter` | ⬜ |
| AI 多景别构图 | `mine_setting_multi_compose` | 🟡 |
| 指定 AI 构图主体 | `mine_setting_subject_selection_guide` | ⬜ |
| 触屏拍摄 | `mine_setting_touch_shot` | ⬜ |
| 保存底片 | `mine_setting_save_raw` | ⬜ |
| 自拍镜像 | `mine_setting_selfie_mirror` | ⬜ |
| 降噪优化 | `mine_setting_camera2_post_processing` | ⬜ |
| 时间水印 | `mine_setting_watermark` | 🟡 固定 SHOT ON PRIME |
| 水印和边框 | `mine_setting_photo_border` | ⬜ |
| AI 构图停留确认 | `mine_setting_ai_alignment_confirm` | ⬜ |
| 语言 / 版本 / 关于 | `settings_*` | 🟡 |

## G. 后端接口（ApiService）

| 接口 | 方法 | PRIME |
|---|---|---|
| `ai_camera/auth/get_code` | POST | ⬜ |
| `ai_camera/auth/login` / `api/v1/auth/login` | POST | ⬜ |
| `ai_camera/auth/me` | POST | ⬜ |
| `ai_camera/auth/bind_phone` / `bind_wechat` / `unbind_wechat` / `replace_wechat` / `verify_wechat_change` | POST | ⬜ |
| `ai_camera/auth/wechat_login` | POST | ⬜ |
| `ai_camera/auth/delete_account` | POST | ⬜ |
| `ai_camera/v2` | multipart POST | ✅ `/v1/scan` |
| `ai_camera/vip/products` / `vip/status` | GET | ⬜ |
| `ai_camera/pay/create_order` / `pay/order_status` / `pay/google_play/verify` | POST/GET | ⬜ |
| `api/v1/redeem_vip_code` | POST | ⬜ |
| `app/config_doka` | POST | ⬜ |
| `app/version_doka_android` | POST | ⬜ |
| `app/security/report` | POST | ⬜ |
| `ai_camera/auth/get_code` / `login` 等账号安全字段 | — | ⬜ |

## H. 不直接复制的部分

- Doka 品牌名、Doka 角色 Romy/Nick 素材、官方文案与图标：PRIME 使用自己的品牌和用户提供的“流小萤”头像。
- 微信/Google/Apple 支付与第三方登录：需要真实 AppID、证书与服务端密钥；PRIME 先做本地可运行模式，不伪造支付成功。
- 厂商相机私有 SDK（小米/华为/荣耀/OPPO/vivo/三星专属管线）：Android 私有能力，iOS 无对应实现；iOS 用 AVFoundation 能力近似。
