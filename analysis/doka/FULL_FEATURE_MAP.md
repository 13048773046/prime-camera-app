# Doka 1.3.20 全量功能与 PRIME v0.4.4 迁移矩阵

来源：`analysis/doka/apktool`（185 layout / 1,538 res）与
`analysis/doka/jadx_full/sources/com/ydgn/doka`（415 个业务 Java），
接口与字段来自 `http/ApiService.java`、`http/entity/*`、`AiCompositionController`。

标记：✅ 已落地并可运行；🟡 已有可运行实现，但与原版能力有差距/待真机验证；⬜ 未实现或受平台资质限制。

## A. 相机主界面与拍摄

| Doka 功能 | Doka 证据 | PRIME |
|---|---|---|
| 3:4 圆角取景 + CameraMask | `fragment_camera.xml` / `CameraMaskView` | ✅ 3:4 满宽圆角预览，支持 1:1/16:9 裁切 |
| 多焦段 .5/1x/2/5、拨盘、单焦段胶囊 | `rgZoomRatio` / `ZoomDialView` | 🟡 四档胶囊 + 0.5–8x 滑杆；没有原版横向拨盘 |
| 双指缩放 | `CameraZoomController` | 🟡 有缩放滑杆，未做双指手势 |
| 前后置切换 | `ivLensFacing` | ✅ |
| 闪光灯 | `camera_option_flash` | ✅ 设置 + 原生 flashMode |
| 九宫格辅助线 | `NineGridView` | ✅ |
| 水平仪/水平标尺 | `LevelOverlayView` / `CameraLevelGaugeView` | ✅ Canvas 水平泡 + 俯仰刻度 |
| 曝光滑杆 | `seekbarExposure` | ✅ 左侧上滑 EV，原生 exposureTargetBias |
| 点击对焦 | `focusPoint` | ✅ 原生 focusPointOfInterest + 对焦框 |
| 触屏拍摄 | `mine_setting_touch_shot` | ✅ 设置开关 + 取景轻点快门 |
| 自拍镜像 | `mine_setting_selfie_mirror` | ✅ 前置成片水平翻转 |
| 实况照片 | `LivePhotoCaptureCoordinator` | ✅ iOS `AVCapturePhotoOutput` Live Photo + `PHAssetCreationRequest` 配对视频 |
| 保存底片 RAW | `camera_option_save_raw` / `Camera2RawMetadataResolver` | 🟡 已保留未滤镜/未裁切 JPEG 到 `PRIME/ORIGINALS`；DNG 双流受 AVFoundation 限制未做 |
| 多帧降噪/HDR/夜景/人像 | `Camera2MultiFrameProcessor` / `CameraExtensionPrefs` | 🟡 设置项 + `photoQualityPrioritization = .quality`；没有厂商多帧管线 |
| 连拍/多帧快门反馈 | `viewShutterFlash` | 🟡 快门闪光动画 |
| 权限说明与拒绝提示 | `llPermissionNotice` / `permission_*` | 🟡 相机权限页，相册/麦克风权限交由系统弹窗 |
| 拍摄后编辑 | `photoedit/*` / `DokaCropActivity` | ✅ 滤镜/旋转/翻转/3:4/1:1/16:9 裁切/边框/水印 |
| Doka 调色盘 | `DokaPaletteManager` | ⬜ 只做了胶片 ColorFilter 矩阵，没有 HSL/色调盘 |
| 分享/保存系统相簿 | `PhotoSaveRepository` | ✅ 系统分享 + 保存相簿 |

## B. AI 构图与 AI 滤镜

| Doka 功能 | Doka 证据 | PRIME |
|---|---|---|
| 当前帧上传 scan | `AiCompositionController.uploadJpegForScan` | ✅ `POST /ai_camera/v2` multipart |
| 服务端子区域/模板/理由/焦距 | `CameraData` / `ScanResp` | ✅ 全字段同构返回 |
| ORB + BFMatcher + RANSAC 模板跟踪 | `CompositionMatcher` | 🟡 用 iOS Vision 主体框 + 规则跟踪替代 |
| Kalman 平滑目标中心 | `AIComposeMotionTracker` | 🟡 原生 Vision 平滑，不是 Kalman |
| 彩色目标环/渐变框/暗角 | `CameraMappingView` / `GradientBorderView` | ✅ 双环 + 渐变框 + 暗角 |
| 黄色主体框 + 8 个可拖角点 | `SubjectMarkerOverlayView` | 🟡 主体框显示 + 长按框选；角点不可拖 |
| 长按选择/指定主体 | `camera_subject_selection_*` | ✅ 长按锁定，双击解除 |
| 多景别方案 1/2、切换方案 | `multi_compose_*` | ✅ 远景/中景/近景三套拍法 + 方案切换 |
| AI 滤镜推荐 | `CameraAiFilterEffectController` | ✅ 扫描后胶囊推荐 + 底部 AI 滤镜入口 |
| AI 滤镜偏好（场景/系列） | `AiFilterPreference*Activity` | ✅ 设置页保存，随 scan 上传 |
| AI 构图/滤镜免费次数、Pro 限制 | `vip_ai_*_limit_*` | 🟡 我的页展示 5/5；客户端未硬性扣次 |
| AI 构图使用提示 3 条 | `ai_usage_tip_*` | ✅ 引导页 + 对齐停留提示 |
| 对齐停留确认 | `mine_alignment_confirm_info_*` | ✅ 0.4 秒停留确认 |
| AI 滤镜单独入口 | `ivAiFilter` / `ai_filter_usage_tip` | ✅ 快门右侧 60dp 入口 |

## C. 滤镜

| Doka 功能 | Doka 证据 | PRIME |
|---|---|---|
| 原片 + 5 大类胶片滤镜 | `filter_category_*` / `filter_detail_*` | ✅ 24 款：原片/Doka/F 系列/Kodak/Agfa/黑白 |
| 滤镜详情、试用、Pro 锁 | `layout_filter_detail.xml` | 🟡 分类横向胶片库 + PRO 标记；Pro 胶片未解锁会提示 |
| 拍摄解锁进度 | `filter_detail_milestone_*` | ⬜ 未做“拍 N 张解锁” |
| 调色盘 | `doka_palette_*` | ⬜ |
| AI 推荐滤镜快速切换卡 | `aiQuickSwitch*` | 🟡 推荐胶囊可一键套用 |

## D. 相册

| Doka 功能 | Doka 证据 | PRIME |
|---|---|---|
| 三列网格、按日期分组 | `fragment_gallery.xml` / `GalleryGroupItem` | ✅ 日期分组 + 三列 |
| 空状态、去拍摄 | `gallery_empty_title` | ✅ |
| 多选、已选计数、取消 | `gallery_selected_*` | ✅ |
| 删除单张/多张 | `delete_single_*` / `delete_multiple_*` | ✅ 二次确认 + 原生删除 |
| 分享图片/微信/朋友圈 | `gallery_share_*` / `share_wechat_*` | ✅ 系统多图分享；微信 SDK 需 AppID |
| 导入照片 | `gallery_import*` | ✅ PHPicker 多选导入 |
| 图片预览/大图 | `PopupLookPictureBinding` / `LookPictureAdapter` | ✅ 预览 + 分享/删除 |
| 图片失效/部分删除失败提示 | `gallery_delete_*` | ⬜ |

## E. 我的 / 账号 / 会员

| Doka 功能 | Doka 证据 | PRIME |
|---|---|---|
| 账号卡、登录/未登录 | `fragment_mine.xml` | ✅ |
| 手机号验证码登录/注册 | `LoginActivity` / `login_*` | ✅ 云端登录客户端已接；未配 `PRIME_API_BASE` 时本地体验码 123456 |
| 微信登录/绑定/换绑/解绑 | `WechatAccountActivity` / `wxapi` | 🟡 本地演示身份；真实微信开放平台 AppID 未配 |
| Google/邮箱登录（海外） | `GlobalLoginActivity` | ⬜ 无 Google OAuth 凭据 |
| 用户信息/昵称/头像/手机号 | `UserInfoActivity` | 🟡 账号弹层显示手机号/昵称；昵称头像不可编辑 |
| 注销账号 | `DeleteAccountActivity` | ⬜ 后端 `delete_account` 已备，前端入口未做 |
| Pro 套餐/购买/续费/兑换 | `VipPurchaseActivity` / `RedeemVipActivity` | 🟡 套餐页、兑换（云端/本地）、`PRIME2026`；真实微信/支付宝/Google Play 商户未接 |
| 免费 AI 次数展示 | `mine_free_ai_counts` | 🟡 我的页显示 5/5；未按服务端计数扣减 |
| 使用引导 5 步 | `GuideActivity` / `guide_step*` | ✅ |
| 帮助反馈/邮件/抖音/小红书 | `mine_help_feedback` | 🟡 有入口 sheet，未配置真实账号跳转 |
| 语言切换并重启 | `LanguageSettingsActivity` | 🟡 可选语言；未重启生效 |
| 问题诊断/日志 | `DiagnosticsActivity` | ✅ |
| 关于/检查更新/ICP/SDK | `AboutActivity` | 🟡 版本/说明；无真实更新检查与 ICP 页 |
| 安全环境拦截 | `SecurityBlockActivity` | ⬜ 后端 `security/report` 已备，客户端未拦截 |

## F. 设置

| Doka 设置项 | 证据 | PRIME |
|---|---|---|
| 拍摄场景 Auto/Bokeh/HDR/Night/Face Retouch | `mine_setting_scene_*` | 🟡 场景 chips；没有 Auto/Bokeh/HDR/Night 算法切换 |
| 构图网格 | `mine_setting_nine_grid` | ✅ |
| 水平仪 | `mine_setting_gradient` | ✅ |
| 闪光灯 | `mine_setting_flash` | ✅ |
| 保存底片 | `mine_setting_save_raw` | 🟡 原始 JPEG 备份 |
| 自拍镜像 | `mine_setting_selfie_mirror` | ✅ |
| 触屏拍摄 | `mine_setting_touch_shot` | ✅ |
| AI 多景别 | `mine_setting_multi_compose` | ✅ |
| 构图附带 AI 滤镜 | `mine_setting_ai_filter` | ✅ |
| 指定 AI 构图主体 | `mine_setting_subject_selection_guide` | ✅ |
| 对齐停留确认 | `mine_setting_ai_alignment_confirm` | ✅ |
| 降噪优化 | `mine_setting_camera2_post_processing` | 🟡 设置项；未接多帧 |
| 水印和边框 | `mine_setting_photo_border` | ✅ 4 种边框 + 时间水印 |
| 语言 | `LanguageSettingsActivity` | 🟡 |
| 诊断 | `DiagnosticsActivity` | ✅ |
| 关于/更新 | `AboutActivity` | 🟡 |
| 高级参数 | `mine_setting_advanced_*` | 🟡 视频质量/快门延迟展示，未全部生效 |

## G. 后端接口（从 `ApiService.java` 逆推）

| Doka 路径 | 方法 | PRIME |
|---|---|---|
| `ai_camera/v2` | multipart POST | ✅ 同构入口，复用 scan 几何/模板/文案 |
| `ai_camera/auth/get_code` | POST | ✅ `scene=login/bind`，开发环境返回 `dev_code` |
| `ai_camera/auth/login` / `api/v1/auth/login` | POST | ✅ 手机号 + 验证码，返回 `token`/`AuthData` |
| `ai_camera/auth/me` | POST | ✅ Bearer token → `CurrentUserData` |
| `ai_camera/auth/bind_phone` | POST | ✅ 需 `scene=bind` 验证码 |
| `ai_camera/auth/wechat_login` / `bind_wechat` / `unbind_wechat` / `replace_wechat` / `verify_wechat_change` | POST | 🟡 本地演示身份；未接微信开放平台 |
| `ai_camera/auth/delete_account` | POST | ✅ 软删除，token 失效 |
| `ai_camera/vip/products` / `vip/status` | GET | ✅ 套餐/权益/免费次数 |
| `ai_camera/pay/create_order` / `pay/order_status` | POST/GET | 🟡 订单与状态机可跑；微信支付参数占位 |
| `ai_camera/pay/google_play/verify` | POST | 🟡 未配 Google Play 时明确失败，不伪造成功 |
| `api/v1/redeem_vip_code` | POST | ✅ `PRIME2026` / `PRIME-30` / `PRIME-LIFETIME` |
| `app/config_doka` | POST | ✅ 功能开关 |
| `app/version_doka_android` | POST | ✅ 版本/更新占位 |
| `app/security/report` | POST | ✅ 写入事件表 |

后端存储：`backend/prime.db`（SQLite，users/codes/orders/events），
`PRIME_AUTH_SECRET` 默认仅本地开发用，生产必须替换；生产应关闭 `PRIME_DEV_AUTH` 并接入短信。

前端客户端：`lib/services/doka_api.dart`（登录/兑换/me），
`lib/services/scan_api.dart`（`ai_camera/v2` multipart）。
未配置 `--dart-define=PRIME_API_BASE` 时，App 自动使用端侧 Vision + 本地规则/体验码，不依赖外部服务。

## H. Doka Activity 覆盖

| Doka Activity | PRIME 对应 |
|---|---|
| `SplashActivity` / `MainActivity` | `main.dart` 启动页 / `CameraPage` |
| `SettingsActivity` | `SettingsPage` |
| `GuideActivity` | `GuidePage` |
| `DiagnosticsActivity` | 设置页诊断弹窗 |
| `AboutActivity` | 设置页关于弹窗 |
| `LanguageSettingsActivity` | 设置页语言 sheet |
| `PhotoBorderSettingsActivity` / `WatermarkSettingsActivity` | 设置页“水印和边框” sheet + 编辑页 |
| `AiFilterPreferenceSceneActivity` / `EditorActivity` / `SummaryActivity` / `RecommendationDisplaySettingsActivity` | 设置页“AI 滤镜偏好” sheet（场景/系列） |
| `LoginActivity` / `BindPhoneActivity` / `UserInfoActivity` / `DeleteAccountActivity` | 我的页账号弹层；注销入口未做 |
| `WechatAccountActivity` | 我的页微信演示入口（未接 SDK） |
| `VipPurchaseActivity` / `RedeemVipActivity` | 我的页 Pro sheet / 兑换弹层 |
| `GlobalLoginActivity` / `GlobalVipPurchaseActivity` / `GlobalDeleteAccountActivity` | 未做（海外版） |
| `DokaCropActivity` | `EditorPage` 裁切/旋转/翻转 |
| `WebViewActivity` | 关于/隐私弹窗（未做内嵌网页） |
| `SecurityBlockActivity` | 未做 |
| `wxapi.WXEntryActivity` / `WXPayEntryActivity` | 未做（需微信 AppID） |

## I. 当前明确未完成 / 平台限制

1. **ORB/Kalman**：Doka 用 OpenCV ORB + BFMatcher + RANSAC + Kalman 跟踪模板；iOS 端不引入 OpenCV，改用 Vision 主体框 + 规则平滑。构图结果可跑，跟踪精度不同。
2. **厂商相机私有管线**：`Camera2MultiFrameProcessor`、`Camera2RawMetadataResolver`、小米/华为/荣耀/OPPO/vivo/三星分支是 Android Camera2 私有能力，iOS AVFoundation 无对应 API；只保留设置项与 qualityPrioritization。
3. **真实支付/微信/Google 登录**：需要商户号、AppID、证书、服务端密钥；当前为本地演示/占位，不伪造支付成功。
4. **调色盘/滤镜解锁进度/角点拖拽/图片失效提示**：尚未实现，已在矩阵中标 ⬜/🟡。
5. **双指缩放/拨盘**：当前是焦段胶囊 + 滑杆，未复刻原版拨盘手势。
6. **设置持久化**：`CameraPrefs` 仍是进程内单例；重启 App 会回到默认值，接入 `auth/me` 后应服务端同步。

## J. v0.4.4 已落地清单

- 24 款胶片滤镜 + Pro 锁提示
- 全屏设置页 18 项 + 引导页 5 步 + AI 滤镜偏好保存/上传
- 相机：3:4 预览、四焦段、缩放滑杆、对焦、EV、水平仪、九宫格、主体锁定、双环/渐变框、AI 滤镜胶囊、对齐确认、实况照片顶栏开关、自拍镜像、水印
- 原生：Live Photo、PHPicker 导入、相册列表/删除/分享、编辑导出、原片备份、24 滤镜 CoreImage 映射
- 相册：日期分组、三列、多选、全选、删除、分享、导入、预览
- 我的：账号卡、云端/本地登录、Pro 卡/套餐、兑换、免费次数、设置/引导/诊断/关于
- 后端：`ai_camera/v2`、auth、VIP、pay 占位、redeem、config、version、security
