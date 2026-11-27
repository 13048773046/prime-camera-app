# Doka 前后端链路反推与 PRIME 对应实现

## 1. 从 APK 找到的真实接口

从 `com.ydgn.doka` 1.3.20 的反编译结果中核对到：

- `I1/f.java`：Retrofit baseUrl = `https://www.yindoka.com/`
- `http/ApiService.java`：`POST ai_camera/v2`，`@Multipart`
- 字段：`file`、`shoot_type`、`direction`、`compose_times`、`scan_focal_length`、`ai_filter`、`timestamp`、`comp_scene`、`recommend_mode`、`ai_filter_preferences`、`language`、`region`、`distribution`
- 返回：`BaseRespEntity<CameraData>`，即 `{code, message, data}`
- `CameraData` 字段：`ExifFocalLength`、`BodyRange`、`PredictSubAreaPicURL`、`PicWithPredictAreaLine`、`SubAreaSize`、`LeftTopCrd`、`RightDownCrd`、`ComposeReason`、`AiCameraFilter`、`AiCameraFilters`、`SubAreaRectNorm`
- `SubAreaRectNorm` 字段：`X/Y/W/H`
- `AiCameraFilterModel` 字段：`FilterName` / `Reason`
- 客户端 `AiCompositionController.uploadJpegForScan` 上传当前帧；拿到 `ScanResp` 后，`CompositionMatcher` 用 OpenCV ORB + BFMatcher + `findHomography(RANSAC 4.0)` 匹配模板，Kalman 平滑 `mappedCenter`，`CameraMappingView` 画目标环/渐变框。

这说明 Doka 的分工不是“每帧把图丢给大模型聊天”，而是：

```
Camera frame
  → client JPEG
  → POST /ai_camera/v2 (multipart)
  → server returns sub-area plan + template URL + focal/reason/filter
  → client tracks template (ORB/Kalman) and draws AR overlay
```

## 2. PRIME 的对应实现

`POST /v1/scan` 采用同一组字段和同一层响应包装，便于以后替换 base URL：

- 服务端只做一次轻量 scan，不逐帧解析大模型；
- `SubAreaRectNorm` 是构图裁切区域，客户端用它画对齐渐变框；
- `PredictSubAreaPicURL` 是干净模板裁切，`PicWithPredictAreaLine` 是带预测框的全幅图；
- 客户端 `ScanApi` 只在 `PRIME_API_BASE` 配置时抓帧上传；未配置时继续端侧 Vision，不阻塞预览。

由于 iOS 端不引入 OpenCV，PRIME 客户端把服务端 `SubAreaRectNorm` 映射到现有 `GuideOverlay` 的渐变框，跟踪仍由原生 Vision 给出的主体框驱动。这是 Doka 链路的可运行子集，不是把 Doka 的 ORB 实现伪装成已完成。

## 3. DeepSeek 的位置

Doka 的服务端是自研视觉服务；PRIME 没有同等规模的视觉模型，因此：

- 构图几何在服务端 `doka.py` 与端侧 Vision 里完成；
- DeepSeek 只接收已经结构化的构图 brief，输出林晓莹的口令与理由；
- 不向 DeepSeek 发送 `image_url`，避免使用它不支持的图片输入格式；
- `AI_API_KEY` 为空时自动退回本地林晓莹文案。

## 4. 运行

```bash
cd backend
python3 -m pip install -r requirements.txt
PRIME_DEBUG=0 python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8791
```

```bash
curl -F 'file=@frame.jpg' \
  -F 'shoot_type=preview' -F 'direction=portrait' \
  -F 'comp_scene=portrait' -F 'subject_box=[0.34,0.18,0.28,0.56]' \
  http://127.0.0.1:8791/v1/scan
```

客户端构建时指定后端：

```bash
flutter build ios --release --no-codesign \
  --dart-define=PRIME_API_BASE=https://your-domain.example
```

不指定时 IPA 仍可完整使用，构图由端侧 Vision + 本地规则驱动。
