# 定焦 PRIME

AI 构图相机 App 的前后端工程。v0.4.5 在 Doka 1.3.20 全量反编译（185 layout / 415 业务 Java）基础上，补齐了 27 款胶片滤镜、完整设置页、实况照片/对焦/曝光/水平仪/主体锁定、相册日期分组与多选删除/导入、照片编辑（裁切/旋转/翻转/边框/水印）、账号与 Pro/兑换页面，以及一组与 Doka `ApiService` 同构的账号、VIP、支付、配置后端接口。AI 人格为“流小萤”，头像使用用户提供的日系动漫素材。

完整迁移矩阵见 `analysis/doka/FULL_FEATURE_MAP.md`；接口逆推见 `backend/DOKA_INFERENCE.md`。

## 目录

```
lib/
  main.dart          App 入口与主题
  pages/             相机、设置、相册、编辑、成片、我的
  data/filters.dart  Doka 胶片滤镜库（27 款 + 分类 + Pro 标记）
  widgets/           AR 目标环
  services/          相机原生通道、scan、设置、照片归档
backend/
  app/
    main.py          FastAPI 入口与路由
    config.py        环境变量配置
    schemas.py       请求响应模型
    geometry.py      端侧几何规则与图片解码
    ai_client.py     DeepSeek 文本口令适配与 JSON 归一化
    doka.py          Doka 式 scan 几何/模板生成
    persona.py       流小萤人设与本地文案
    rate_limit.py    深度指挥计次与去重
    store.py         SQLite 用户/验证码/VIP/订单/兑换码/设置/审计
    api_doka.py      Doka auth / vip / pay / config 同构接口
    api_admin.py     管理台 API（admin token）
  web/
    index.html       落地页（https://uosar.yosar.cloud/）
    h5/              H5 相机（/h5/）
    admin/           管理台（/admin/）
  tests/             pytest 接口测试
deploy/              uosar.yosar.cloud 的 systemd + Nginx 配置
```

## 本地启动

```bash
cd backend
python3 -m pip install -r requirements.txt
cp .env.example .env
python3 -m uvicorn app.main:app --host 127.0.0.1 --port 8791
```

健康检查：

```bash
curl http://127.0.0.1:8791/health
```

## 前端开发与测试

```bash
flutter pub get
flutter analyze
flutter test
```

## 后端测试

```bash
cd backend
pytest -q
```

## iOS 未签名 IPA

仓库内置 `.github/workflows/ios-unsigned.yml`，在 macOS Runner 上执行：

```bash
flutter build ios --release --no-codesign
```

产物为未签名 IPA，需 AltStore、Sideloadly 或自签证书安装；TestFlight / App Store 还需要 Apple Developer 账号、证书和 Provisioning Profile。

## 接口

### GET /health

返回服务状态与 AI 密钥是否已配置。

### POST /ai_camera/v2

Doka `POST ai_camera/v2` 的同构入口；字段与 `/v1/scan` 完全一致，复用同一套几何/模板/文案逻辑。

### 账号 / VIP / 配置

- `POST /ai_camera/auth/get_code`、`login`、`me`、`bind_phone`、`bind_wechat`、`unbind_wechat`、`delete_account`
- `GET /ai_camera/vip/products`、`vip/status`
- `POST /ai_camera/pay/create_order`、`GET /pay/order_status`
- `POST /api/v1/redeem_vip_code`
- `POST /app/config_doka`、`/app/version_doka_android`、`/app/security/report`

登录验证码默认走本地联调：`PRIME_DEV_AUTH=1` 时 `get_code` 会在响应里返回 `dev_code`，生产环境置 0 并接短信通道。支付未接入真实商户，`pay/mock_confirm` 只在本地联调模式可用，不会伪造线上支付成功。

### POST /v1/scan

Doka `ai_camera/v2` 同构的 multipart 接口，返回 `{code,message,data}`，其中 `data` 为 `CameraData`（含 `SubAreaRectNorm`、`PredictSubAreaPicURL`、`ComposeReason` 等）。详见 `backend/DOKA_INFERENCE.md`。

### 管理台

- 管理台：`https://uosar.yosar.cloud/admin/`
- 默认管理员：`玉玲`；默认密码 `prime-admin-2026`。生产必须用 `PRIME_ADMIN_PASSWORD` 覆盖。
- 管理 API：`/admin/api/login`、`overview`、`users`、`orders`、`redeem-codes`、`settings`、`persona`、`filters`、`usage`、`events`
- 所有写操作都会写入 `events` 审计；管理 token 有效期 7 天。
- 头像、人格名、System Prompt、免费/Pro AI 次数、公告、维护模式、App 版本、下载地址、水印样式都可在管理台修改。

### H5

- `https://uosar.yosar.cloud/h5/`：移动端 3:4 取景、AI 构图（上传当前帧到 `/ai_camera/v2` 并绘制 `SubAreaRectNorm`）、27 款胶片、相册、登录/兑换/Pro 演示。
- H5 默认使用同源 `location.origin`，域名部署后无需再写死 API 地址。
- 浏览器无相机权限时自动用 `assets/scene.jpg` 做演示帧，方便审核与预览。

### POST /v1/persona/line

用流小萤的口吻把结构化构图 brief 变成一句可执行口令；配置 `AI_API_KEY` 时走 DeepSeek `deepseek-chat`，否则本地文案。

### POST /v1/compose

请求体：

```json
{
  "image": "data:image/jpeg;base64,...",
  "mode": "portrait",
  "device": {"lens": "wide", "zoom": 1.0, "aspect": "3:4"},
  "tilt": -2.4,
  "roll": 0.8
}
```

响应：

```json
{
  "subject": "person",
  "subject_box": [0.33, 0.22, 0.34, 0.68],
  "target_box": [0.33, 0.22, 0.34, 0.68],
  "target_zoom": 1.0,
  "horizon_fix": 0.0,
  "hint": "把主体放到画面中间",
  "reasons": ["构图基本稳定"],
  "confidence": 0.62,
  "source": "rule"
}
```

## 安全说明

- `AI_API_KEY`、服务器密码等敏感信息只通过环境变量或 GitHub Secrets 注入，不写入仓库。
- 服务端不持久化上传帧；scan 模板会在 `backend/static/templates` 短期缓存并自动清理。
- DeepSeek 只接收结构化 brief，不接收图片；几何与主体框由端侧 Vision / 服务端轻量规则完成。
- 模型不可用、超时或返回低置信度结果时自动回退本地规则。
- 生产部署见 `deploy/README.md`：先签发 `uosar.yosar.cloud` 证书，再把 Nginx 反代到 `127.0.0.1:8791`。当前域名已解析，但证书必须重新签发，否则 HTTPS 会报域名不匹配。
