# 定焦 PRIME

AI 构图相机 App 的前后端工程。当前已落地 Flutter 前端壳、相机引导页、AR 目标环、口令流、出片页，以及 FastAPI 构图服务；iOS 原生相机内核将在真机环境继续接入。

## 目录

```
lib/
  main.dart          App 入口与主题
  pages/             相机引导页、出片页
  widgets/           AR 目标环
  services/          构图接口客户端
backend/
  app/
    main.py          FastAPI 入口与路由
    config.py        环境变量配置
    schemas.py       请求响应模型
    geometry.py      端侧几何规则与图片解码
    ai_client.py     视觉模型适配与 JSON 归一化
    rate_limit.py    深度指挥计次与去重
  tests/             pytest 接口测试
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
- 服务端不持久化上传帧；模型不可用、超时或返回低置信度结果时自动回退几何规则。
