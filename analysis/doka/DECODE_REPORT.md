# Doka 1.3.20 全量反编译报告

## 1. 包信息

- 包名：`com.ydgn.doka`
- 版本：`1.3.20`
- 文件：`analysis/doka/Doka-1.3.20.apk`
- 大小：`98,738,187 bytes`
- SHA-256：`931af70142e57fcc061f3960e2413f42920823e54df0776fa034dff75ab5a4bc`
- 校验：`unzip -t` 通过
- 来源：`https://m.niucoo.cn/downs/detail/12514/2`，下载票据记录在 `apk_url.txt`
- 官方商店当前版本为 1.3.22，本报告基于可下载的 1.3.20 完整包

## 2. 反编译产物

### apktool 全量资源 + smali

- 目录：`analysis/doka/apktool`
- 约 243 MB
- `res/` 资源文件：1,538 个
- `res/layout/` 布局：185 个
- `smali/`、`smali_classes2/`、`smali_classes3/`：3 个 dex 的 smali
- 完整 `AndroidManifest.xml`、`values/colors.xml`、`values/dimens.xml`、`values/strings.xml`、drawable/anim/raw 资源

### JADX 全量 Java

- 目录：`analysis/doka/jadx_full/sources`
- Java 文件：11,617 个
- Doka 业务代码 `com/ydgn/doka`：415 个 Java 文件
- 体积：87 MB
- 结束状态：`finished with errors, count: 9`（9 个类因混淆/异常字节码失败，其余全部输出）
- 早期不完整目录：`analysis/doka/jadx`（约 10,848 个文件，仅作对照）

### 工具

- `analysis/doka/tools/apktool.jar`（2.9.3）
- `analysis/doka/tools/jadx`（1.5.3）

## 3. Doka 的完整界面清单

Doka 是原生 Android/Kotlin + Camera2/厂商相机 + OpenGL + OpenCV，不是 Flutter。

主界面：

- `fragment_camera.xml` — 相机
- `fragment_gallery.xml` — 相册
- `fragment_mine.xml` — 我的
- `view_tab_bar.xml` / `view_glass_tabbar.xml` — 底部三栏
- `layout_camera_option_fixed.xml`、`layout_camera_option_fixed_item.xml` — 固定选项行
- `layout_camera_option_bar.xml`、`layout_camera_option_item.xml` — 浮动选项行
- `layout_camera_filter.xml`、`layout_filter_detail.xml` — 滤镜面板
- `activity_settings.xml` — 设置
- `activity_photo_border_settings.xml`、`layout_photo_border_editor.xml` — 照片边框
- `activity_watermark_settings.xml`、`item_watermark_setting.xml` — 水印
- `activity_doka_crop_overlay.xml`、`item_doka_crop_ratio.xml` — 裁切
- `activity_guide.xml`、`item_guide_banner.xml` — 引导页
- `activity_login.xml`、`activity_bind_phone.xml`、`activity_user_info.xml`、`activity_wechat_account.xml` — 账号
- `activity_vip_purchase.xml`、`activity_redeem_vip.xml`、`item_vip_product.xml`、`item_vip_banner.xml` — 会员
- `activity_about.xml`、`activity_language_settings.xml`、`activity_diagnostics.xml`、`activity_webview.xml` — 通用
- `dialog_ai_compose_usage_tip.xml`、`dialog_permission_explanation.xml`、`dialog_glass_confirm.xml` 等 — 弹窗

Doka 的“整个界面”包含 22 个 Activity；`prime_app` 不复制账号、VIP、兑换、诊断这些与产品无关的业务，只复刻相机主界面、相册、设置、滤镜和拍摄链路。

## 4. 相机页的真实结构（从 layout 读出来的）

根布局：

- 黑色背景，`paddingBottom=70dp`
- 预览 `CameraGLSurfaceView` 在 ConstraintLayout 中铺满父容器，实际画面由 CameraMaskView/GL 裁成 3:4
- 顶部左：`ivLivePhotoToggle` 48×48；顶部右：`ivSetting` 48×48
- 预览内底部：
  - `rgZoomRatio` 40dp 高，背景 `#30000000`，圆角 20
  - `flAiFilterEntry` 44×44，内部圆钮 40×40，右下 10dp
  - `tvAiSwitchPlan` 40dp 高，底部 12dp，渐变描边胶囊
  - `tvSubjectSelectionHint` 顶部 28dp，13sp 白字，玻璃底
- 固定选项行：
  - `cameraOptionFixed` 48dp 高，左右 margin 20dp
  - 从左到右：多构图（Beta）、主体选择、AI 滤镜、比例、翻转；AI 构图态用 `llAiScanAction` 或切换方案胶囊替换中间项
- 功能行：
  - `cameraFunction` 96dp 高，左右 margin 10dp，底部 margin 12dp
  - 左：`ivFilter` 60×60
  - 中：`ivCapture` 70×70
  - 右：`llAiScanCancel` / `llAiScanToggle`，12sp 文案
- 底部：
  - `view_tab_bar` 310×52，底部 margin 16dp，三栏 相机/相册/我的
  - 另一套 `view_glass_tabbar` 220×48

颜色：

- 品牌色 `doka_brand = #FFC6F3F7`
- 主体框 `#FFFFD76A`
- 对齐框渐变：`#E8FFFC → #80EEFF → #B1CFFF → #FFD2F6 → #FFC38F`
- 主体框描边 2.5dp，角长 18dp，标签 13sp 黑字黄胶囊
- 切换方案胶囊：外层渐变描边 + 内层 `#E012161C` 玻璃底

## 5. 动效与构图覆盖层

关键类：

- `view/CameraMappingView.java` — AR 覆盖层
- `view/SubjectMarkerOverlayView.java` — 黄色主体框和 8 个可拖拽角点
- `view/GradientBorderView.java` — 对齐后的渐变圆角框
- `view/CameraMaskView.java` — 3:4 预览遮罩
- `view/ZoomDialView.java` — 焦段拨盘
- `view/NineGridView.java` — 九宫格
- `view/CameraLevelGaugeView.java` — 水平仪
- `camera/composition/AiCompositionController.java` — 上传当前帧、请求构图方案
- `camera/composition/CompositionMatcher.java` — OpenCV ORB + BFMatcher + findHomography(RANSAC 4.0)
- `camera/composition/geo/*` — 陀螺仪/旋转/坐标映射/Kalman 平滑

构图链路：

1. 预览帧 JPEG 上传 `uploadJpegForScan`
2. 响应包含 `predictSubAreaPicURL`、`exifFocalLength`、`composeReason`、`subAreaRectNorm`
3. `CompositionMatcher` 对目标子图做 ORB 特征匹配，RANSAC 单应矩阵
4. `mappedCenter` 用 Kalman 平滑，目标环跟随手机移动
5. 对齐后 `GradientBorderView` 压暗主体外区域，显示渐变圆角裁切框
6. 拍摄后按选择的画幅裁切，进 `photoedit` / 滤镜管线

## 6. 前端拍照处理

- 原生 Camera2，按厂商分支：小米/华为/荣耀/OPPO/vivo/三星/Google
- OpenGL 预览与滤镜
- 多帧、Live Photo、HDR/夜景/人像分支
- 拍照后进入 `photoedit`，再做边框/水印/裁切/滤镜
- 本报告不包含 iOS 端源码：App Store 包是加密的，无法反编译 SwiftUI

## 7. prime_app 的复刻映射

已按 Doka 结构和尺寸重做：

| Doka | prime_app |
|---|---|
| 3:4 圆角预览 | `camera_page.dart` 390×520 预览，圆角 24 |
| 顶部眼睛/设置 | 40×40 玻璃按钮，重识别/设置 |
| 预览内焦段 | `.5 / 1x / 2 / 5` 胶囊，40 高 |
| 预览内 AI 滤镜入口 | 右下 40 圆钮 |
| 固定选项行 | 48 高，左右 20；多构图 Beta / 主体 / 比例 / 翻转；构图态切换方案胶囊 |
| 功能行 | 96 高；左相机滤镜、中 AI 摄影师头像快门、右 AI 构图/退出构图 |
| 底部三栏 | 310×52，相机/相册/我的 |
| 渐变对齐框 | `GuideOverlay` 3:4 渐变框 + 暗角 |
| 黄色主体框 | 2dp 四角 + “拍照主体”黄标签 |
| 距离卡 | 约 305 宽，底部 58，含距离滑轨/开始构图 |
| 滤镜 | 原片/清透/暖调/冷调/黑白，预览 ColorFilter，成片 CoreImage |
| 相册 | 黑底网格、空状态、顶部 48 标题 |
| 拍照比例 | 3:4 / 1:1 / 16:9，原生按比例中心裁切 |

未复制：

- Doka 账号、手机绑定、微信、VIP 购买/兑换、邀请、诊断上报
- Doka 的云端 scan 构图接口与模板跟踪；prime_app 当前用设备端 Vision + 本地构图规则
- Doka 的 Romy/Nick 角色素材；prime_app 用自己生成的 PRIME AI 摄影师头像
- Doka 的 Live Photo、多帧夜景、厂商相机分支
