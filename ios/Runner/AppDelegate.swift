import AVFoundation
import CoreImage
import CoreMedia
import CoreMotion
import Flutter
import ImageIO
import Photos
import PhotosUI
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var cameraHost: PrimeCameraHost?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    cameraHost = PrimeCameraHost(registrar: engineBridge.applicationRegistrar)
  }
}

/// 定焦 PRIME 的原生相机内核。
/// AVCaptureSession -> AVCaptureVideoDataOutput -> FlutterTexture 实时预览，
/// AVCapturePhotoOutput 负责快门直出，Photos 负责存相册。
final class PrimeCameraHost: NSObject, FlutterTexture, AVCaptureVideoDataOutputSampleBufferDelegate {
  private let registry: FlutterTextureRegistry
  private let channel: FlutterMethodChannel

  private let session = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "com.prime.camera.session")
  private let videoQueue = DispatchQueue(label: "com.prime.camera.video")
  private let visionQueue = DispatchQueue(label: "com.prime.camera.vision")
  private let videoOutput = AVCaptureVideoDataOutput()
  private let photoOutput = AVCapturePhotoOutput()
  private var photoPicker: PrimePhotoPicker?

  // 实时构图：Vision 以 ~6fps 找人脸/人体，CoreMotion 读取手机水平角。
  private let visionLock = NSLock()
  private var visionBusy = false
  private var lastVisionAt: CFTimeInterval = 0
  private var lastFrameNoticeAt: CFTimeInterval = 0
  private let motionManager = CMMotionManager()
  private let motionLock = NSLock()
  private var rollDegrees: Double = 0
  private var pitchDegrees: Double = 0

  private var textureId: Int64 = -1
  private var latestBuffer: CVPixelBuffer?
  private let bufferLock = NSLock()

  private var isConfigured = false
  private var isRunning = false
  private var currentInput: AVCaptureDeviceInput?
  private var currentDevice: AVCaptureDevice?
  private var currentPosition: AVCaptureDevice.Position = .back
  private var currentZoom: CGFloat = 1.0

  private var photoDelegates: [Int64: AVCapturePhotoCaptureDelegate] = [:]

  init(registrar: FlutterApplicationRegistrar) {
    registry = registrar.textures()
    channel = FlutterMethodChannel(name: "prime/camera", binaryMessenger: registrar.messenger())
    super.init()
    textureId = registry.register(self)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleWillResignActive),
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleSessionInterrupted),
      name: .AVCaptureSessionWasInterrupted,
      object: session
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleSessionInterruptionEnded),
      name: .AVCaptureSessionInterruptionEnded,
      object: session
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleSessionRuntimeError),
      name: .AVCaptureSessionRuntimeError,
      object: session
    )
    startMotionTracking()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    motionManager.stopDeviceMotionUpdates()
    if textureId >= 0 {
      registry.unregisterTexture(textureId)
    }
  }

  /// 手机水平角：用于“手机回正”口令，死区 1.2°。
  private func startMotionTracking() {
    guard motionManager.isDeviceMotionAvailable else { return }
    motionManager.deviceMotionUpdateInterval = 0.1
    motionManager.startDeviceMotionUpdates(
      using: .xArbitraryZVertical,
      to: .main
    ) { [weak self] motion, _ in
      guard let self = self, let motion = motion else { return }
      self.motionLock.lock()
      self.rollDegrees = motion.attitude.roll * 180.0 / Double.pi
      self.pitchDegrees = motion.attitude.pitch * 180.0 / Double.pi
      self.motionLock.unlock()
    }
  }

  private func currentAngles() -> (roll: Double, pitch: Double) {
    motionLock.lock()
    defer { motionLock.unlock() }
    return (rollDegrees, pitchDegrees)
  }

  /// 回前台强制重启一次取景，避免系统挂起后纹理停在最后一帧。
  @objc private func handleDidBecomeActive() {
    sessionQueue.async { [weak self] in
      guard let self = self, self.isConfigured else { return }
      if self.isRunning {
        self.session.stopRunning()
        self.isRunning = false
      }
      self.startIfNeeded()
    }
  }

  @objc private func handleWillResignActive() {
    sessionQueue.async { [weak self] in
      self?.stopIfNeeded()
    }
  }

  @objc private func handleSessionInterrupted() {
    // 电话、控制中心等抢占相机时系统会自行停会话；把状态同步成未运行，
    // 等 interruptionEnded 再恢复，避免用 isRunning=true 造成永久黑屏。
    sessionQueue.async { [weak self] in
      self?.isRunning = false
    }
  }

  @objc private func handleSessionInterruptionEnded() {
    sessionQueue.async { [weak self] in
      self?.startIfNeeded()
    }
  }

  @objc private func handleSessionRuntimeError(_ notification: Notification) {
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      self.isRunning = false
      guard self.isConfigured else { return }
      // Media services 偶发 reset；稍等系统恢复后重建 running 状态。
      self.sessionQueue.asyncAfter(deadline: .now() + 0.35) { [weak self] in
        self?.startIfNeeded()
      }
    }
  }

  // MARK: - FlutterTexture

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    bufferLock.lock()
    defer { bufferLock.unlock() }
    guard let buffer = latestBuffer else { return nil }
    return Unmanaged.passRetained(buffer)
  }

  // MARK: - Method channel

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      initialize(result: result)
    case "requestPermission":
      requestPermission(result: result)
    case "openSettings":
      openSettings(result: result)
    case "setZoom":
      let zoom = (call.arguments as? [String: Any])?["zoom"] as? NSNumber
      applyZoom(CGFloat(truncating: zoom ?? 1.0), result: result)
    case "restart":
      restart(result: result)
    case "switchCamera":
      switchCamera(result: result)
    case "capturePreviewJpeg":
      capturePreviewJpeg(result: result)
    case "focusAt":
      let args = call.arguments as? [String: Any]
      let x = (args?["x"] as? NSNumber)?.doubleValue ?? 0.5
      let y = (args?["y"] as? NSNumber)?.doubleValue ?? 0.5
      focusAt(x: x, y: y, result: result)
    case "setExposure":
      let value = (call.arguments as? [String: Any])?["value"] as? NSNumber
      setExposure(CGFloat(truncating: value ?? 0), result: result)
    case "takePhoto":
      let args = call.arguments as? [String: Any]
      let flash = args?["flash"] as? Bool ?? false
      let filter = args?["filter"] as? String ?? "none"
      let ratio = args?["ratio"] as? String ?? "threeFour"
      let selfieMirror = args?["selfieMirror"] as? Bool ?? true
      let watermark = args?["watermark"] as? Bool ?? true
      let watermarkStyle = args?["watermarkStyle"] as? String ?? "minimal"
      let livePhoto = args?["livePhoto"] as? Bool ?? false
      takePhoto(
        flash: flash,
        filter: filter,
        ratio: ratio,
        selfieMirror: selfieMirror,
        watermark: watermark,
        watermarkStyle: watermarkStyle,
        livePhoto: livePhoto,
        result: result
      )
    case "saveToAlbum":
      saveToAlbum(call: call, result: result)
    case "share":
      share(call: call, result: result)
    case "listPhotos":
      listPhotos(result: result)
    case "pickPhotos":
      pickPhotos(result: result)
    case "editPhoto":
      let args = call.arguments as? [String: Any]
      editPhoto(
        path: args?["path"] as? String ?? "",
        filter: args?["filter"] as? String ?? "none",
        ratio: args?["ratio"] as? String ?? "threeFour",
        rotate: args?["rotate"] as? Int ?? 0,
        flip: args?["flip"] as? Bool ?? false,
        border: args?["border"] as? String ?? "minimal",
        watermark: args?["watermark"] as? Bool ?? true,
        result: result
      )
    case "deletePhoto":
      deletePhoto(call: call, result: result)
    case "shareFiles":
      shareFiles(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// 给服务端 scan 抓一帧当前取景。只在预览帧被消费时调用，绝不影响
  /// 预览纹理或快门路径；拿不到 buffer 就返回 nil，让 Dart 继续端侧引导。
  private func capturePreviewJpeg(result: @escaping FlutterResult) {
    bufferLock.lock()
    let buffer = latestBuffer
    bufferLock.unlock()
    guard let buffer = buffer else {
      result(nil)
      return
    }
    let ciImage = CIImage(cvPixelBuffer: buffer)
    let context = CIContext(options: [.useSoftwareRenderer: false])
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
      result(nil)
      return
    }
    let image = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    guard let data = image.jpegData(compressionQuality: 0.62) else {
      result(nil)
      return
    }
    result(FlutterStandardTypedData(bytes: data))
  }

  private func initialize(result: @escaping FlutterResult) {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      prepareAndReply(result)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          if granted {
            self?.prepareAndReply(result)
          } else {
            result(["status": "denied"])
          }
        }
      }
    case .denied:
      result(["status": "denied"])
    case .restricted:
      result(["status": "restricted"])
    @unknown default:
      result(["status": "denied"])
    }
  }

  private func requestPermission(result: @escaping FlutterResult) {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      prepareAndReply(result)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          if granted {
            self?.prepareAndReply(result)
          } else {
            result(["status": "denied"])
          }
        }
      }
    case .denied:
      result(["status": "denied"])
    case .restricted:
      result(["status": "restricted"])
    @unknown default:
      result(["status": "denied"])
    }
  }

  private func prepareAndReply(_ result: @escaping FlutterResult) {
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      do {
        try self.configureIfNeeded(position: self.currentPosition, zoom: self.currentZoom)
        self.applyConnectionSettings()
        self.startIfNeeded()
        DispatchQueue.main.async {
          result([
            "status": "ready",
            "textureId": self.textureId,
            "zoom": self.currentZoom,
            "lens": PrimeCameraHost.lensName(self.currentDevice),
            "ultraWide": PrimeCameraHost.makeUltraWideDevice() != nil,
          ])
        }
      } catch {
        DispatchQueue.main.async {
          result(["status": "unavailable", "message": error.localizedDescription])
        }
      }
    }
  }

  // MARK: - Session

  private static func makeBackWideDevice() -> AVCaptureDevice? {
    if #available(iOS 13.0, *) {
      if let triple = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
        return triple
      }
      if let dualWide = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
        return dualWide
      }
      if let dual = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
        return dual
      }
    }
    return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
  }

  private static func makeUltraWideDevice() -> AVCaptureDevice? {
    guard #available(iOS 13.0, *) else { return nil }
    return AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
  }

  private static func lensName(_ device: AVCaptureDevice?) -> String {
    guard let device = device else { return "none" }
    if #available(iOS 13.0, *) {
      switch device.deviceType {
      case .builtInUltraWideCamera:
        return "ultraWide"
      case .builtInTelephotoCamera:
        return "telephoto"
      default:
        return "wide"
      }
    }
    return "wide"
  }

  /// 0.5× 需要超广角；虚拟三摄的 videoZoomFactor 下限通常是 1.0，
  /// 所以不能用 zoomFactor=0.5，而是直接切换到超广角输入，再以 1.0 作为 0.5×。
  private static func makeDevice(
    position: AVCaptureDevice.Position,
    zoom: CGFloat = 1.0
  ) -> AVCaptureDevice? {
    if position == .back, zoom < 0.9, let ultraWide = makeUltraWideDevice() {
      return ultraWide
    }
    if position == .back {
      return makeBackWideDevice()
    }
    return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
  }

  private func configureIfNeeded(position: AVCaptureDevice.Position, zoom: CGFloat) throws {
    if isConfigured { return }

    session.beginConfiguration()
    var didCommit = false
    defer {
      if !didCommit {
        if let input = currentInput, session.inputs.contains(where: { $0 === input }) {
          session.removeInput(input)
        }
        if session.outputs.contains(where: { $0 === videoOutput }) {
          session.removeOutput(videoOutput)
        }
        if session.outputs.contains(where: { $0 === photoOutput }) {
          session.removeOutput(photoOutput)
        }
        currentInput = nil
        currentDevice = nil
        session.commitConfiguration()
      }
    }

    // 固定 1080p 16:9 视频流：预览纹理尺寸稳定，Vision 坐标按完整 9:16 画幅映射。
    if session.canSetSessionPreset(.hd1920x1080) {
      session.sessionPreset = .hd1920x1080
    } else {
      session.sessionPreset = .high
    }

    guard let device = PrimeCameraHost.makeDevice(position: position, zoom: zoom) else {
      throw NSError(
        domain: "com.prime.camera",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "没有找到可用的摄像头"]
      )
    }
    let input = try AVCaptureDeviceInput(device: device)
    guard session.canAddInput(input) else {
      throw NSError(
        domain: "com.prime.camera",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "摄像头输入不可用"]
      )
    }
    session.addInput(input)
    currentInput = input
    currentDevice = device
    currentPosition = position
    currentZoom = 1.0

    videoOutput.alwaysDiscardsLateVideoFrames = true
    videoOutput.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
    ]
    videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
    guard session.canAddOutput(videoOutput) else {
      throw NSError(
        domain: "com.prime.camera",
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "视频输出不可用"]
      )
    }
    session.addOutput(videoOutput)

    guard session.canAddOutput(photoOutput) else {
      throw NSError(
        domain: "com.prime.camera",
        code: 4,
        userInfo: [NSLocalizedDescriptionKey: "拍照输出不可用"]
      )
    }
    session.addOutput(photoOutput)
    photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
    updatePhotoOutputCapabilities(for: device, position: position)

    isConfigured = true
    applyConnectionSettings()
    currentZoom = setZoomFactor(on: device, logicalZoom: zoom)
    session.commitConfiguration()
    didCommit = true
  }

  /// 超广角和前置通常不支持高分辨率静态照片；在超广角上强行打开会让
  /// 0.5× 拍照偶发失败，这里按设备能力收窄，保证快门始终能出片。
  private func updatePhotoOutputCapabilities(
    for device: AVCaptureDevice,
    position: AVCaptureDevice.Position
  ) {
    let highResolution: Bool
    if position == .back {
      switch device.deviceType {
      case .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera,
           .builtInWideAngleCamera:
        highResolution = true
      default:
        highResolution = false
      }
    } else {
      highResolution = false
    }
    photoOutput.isHighResolutionCaptureEnabled = highResolution
  }

  private func applyConnectionSettings() {
    if let connection = videoOutput.connection(with: .video) {
      configure(connection: connection, mirrored: currentPosition == .front)
    }
    if let connection = photoOutput.connection(with: .video) {
      // 前置成片跟预览一致做镜像，避免拍完左右反过来。
      configure(connection: connection, mirrored: currentPosition == .front)
    }
  }

  private func configure(connection: AVCaptureConnection, mirrored: Bool) {
    if #available(iOS 17.0, *) {
      if connection.isVideoRotationAngleSupported(90) {
        connection.videoRotationAngle = 90
      }
    }
    // 某些输出在 iOS 17 上并不支持 rotationAngle；保留旧 orientation
    // 兜底，避免拿到未旋转的横屏 buffer 后 Vision 框完全对不上。
    if connection.isVideoOrientationSupported {
      connection.videoOrientation = .portrait
    }
    if connection.isVideoMirroringSupported {
      connection.isVideoMirrored = mirrored
    }
  }

  private func startIfNeeded() {
    guard isConfigured, !isRunning else { return }
    session.startRunning()
    isRunning = true
  }

  private func stopIfNeeded() {
    guard isRunning else { return }
    session.stopRunning()
    isRunning = false
  }

  /// 预览纹理长时间没有新帧时，Dart 侧会调用它做一次轻量重启。
  /// 不重建 input / output，只重启 running 状态，避免打断正在进行的镜头切换。
  private func restart(result: @escaping FlutterResult) {
    sessionQueue.async { [weak self] in
      guard let self = self else {
        DispatchQueue.main.async { result(false) }
        return
      }
      guard self.isConfigured else {
        DispatchQueue.main.async { result(false) }
        return
      }
      if self.isRunning {
        self.session.stopRunning()
        self.isRunning = false
      }
      self.applyConnectionSettings()
      self.session.startRunning()
      self.isRunning = true
      DispatchQueue.main.async { result(true) }
    }
  }

  // MARK: - Video frames

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    bufferLock.lock()
    latestBuffer = imageBuffer
    bufferLock.unlock()
    registry.textureFrameAvailable(textureId)

    // 只抽一部分帧做识别，保证预览优先流畅。
    let now = CACurrentMediaTime()
    if now - lastFrameNoticeAt >= 0.45 {
      lastFrameNoticeAt = now
      let width = Int(CVPixelBufferGetWidth(imageBuffer))
      let height = Int(CVPixelBufferGetHeight(imageBuffer))
      let ts = Int(Date().timeIntervalSince1970 * 1000)
      DispatchQueue.main.async { [weak self] in
        self?.channel.invokeMethod("frame", arguments: [
          "ts": ts,
          "w": width,
          "h": height
        ])
      }
    }
    guard now - lastVisionAt >= 0.16, beginVision() else { return }
    lastVisionAt = now
    let angles = currentAngles()
    let buffer = imageBuffer
    visionQueue.async { [weak self] in
      guard let self = self else { return }
      self.analyzeFrame(buffer, roll: angles.roll, pitch: angles.pitch)
      self.endVision()
    }
  }

  private func beginVision() -> Bool {
    visionLock.lock()
    defer { visionLock.unlock() }
    if visionBusy { return false }
    visionBusy = true
    return true
  }

  private func endVision() {
    visionLock.lock()
    visionBusy = false
    visionLock.unlock()
  }

  /// 在取景流上实时找人/脸，同时找非人像场景的显著区域。
  /// 坐标按完整 9:16 画幅归一化，页面全屏预览再按 cover 裁切映射。
  private func analyzeFrame(_ pixelBuffer: CVPixelBuffer, roll: Double, pitch: Double) {
    let rawWidth = CVPixelBufferGetWidth(pixelBuffer)
    let rawHeight = CVPixelBufferGetHeight(pixelBuffer)
    // 正常情况下 videoOutput connection 已旋转成竖屏；万一某个系统版本
    // 没有应用 rotation，这里按横屏 buffer 用 .right 兜底，保证 Vision
    // 仍然拿到正立的画面，而不是把横向画面当成竖屏来识别。
    let orientation: CGImagePropertyOrientation = rawWidth > rawHeight ? .right : .up
    let orientedWidth = rawWidth > rawHeight ? rawHeight : rawWidth
    let orientedHeight = rawWidth > rawHeight ? rawWidth : rawHeight
    let handler = VNImageRequestHandler(
      cvPixelBuffer: pixelBuffer,
      orientation: orientation,
      options: [:]
    )

    // 人/脸和显著区域分开 perform。某个 request 在特定系统上失败时，
    // 不会把另一组结果一起丢掉，这是实时引导“没有反应”最常见的原因。
    var human: VNHumanObservation?
    var face: VNFaceObservation?
    do {
      let humanRequest = VNDetectHumanRectanglesRequest()
      humanRequest.upperBodyOnly = false
      let faceRequest = VNDetectFaceRectanglesRequest()
      try handler.perform([humanRequest, faceRequest])
      human = (humanRequest.results ?? []).max {
        area(of: $0.boundingBox) < area(of: $1.boundingBox)
      }
      face = (faceRequest.results ?? []).max {
        area(of: $0.boundingBox) < area(of: $1.boundingBox)
      }
    } catch {
      human = nil
      face = nil
    }

    var salient: VNSaliencyImageObservation?
    var salientObject: VNRectangleObservation?
    do {
      let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
      try handler.perform([saliencyRequest])
      salient = saliencyRequest.results?.first as? VNSaliencyImageObservation
      salientObject = salient?.salientObjects?.max {
        area(of: $0.boundingBox) < area(of: $1.boundingBox)
      }
    } catch {
      salientObject = nil
    }

    // attention saliency 偶发无结果时，用 objectness saliency 兜底，
    // 街景/建筑/静物至少还能得到一个可跟随的区域。
    if salientObject == nil {
      do {
        let objectness = VNGenerateObjectnessBasedSaliencyImageRequest()
        try handler.perform([objectness])
        let result = objectness.results?.first as? VNSaliencyImageObservation
        salientObject = result?.salientObjects?.max {
          area(of: $0.boundingBox) < area(of: $1.boundingBox)
        }
      } catch {
        salientObject = nil
      }
    }

    sendGuidance(
      box: human.map { normalizeFrame($0.boundingBox) },
      face: face.map { normalizeFrame($0.boundingBox) },
      saliency: salientObject.map { normalizeFrame($0.boundingBox) },
      roll: roll,
      pitch: pitch,
      orientedWidth: orientedWidth,
      orientedHeight: orientedHeight
    )
  }

  private func area(of rect: CGRect) -> CGFloat {
    rect.width * rect.height
  }

  /// Vision 的 boundingBox 是左下原点；转成 Flutter 左上原点，保留整幅。
  private func normalizeFrame(_ box: CGRect) -> [Double] {
    let left = max(0, min(1, Double(box.minX)))
    let right = max(0, min(1, Double(box.maxX)))
    let top = max(0, min(1, 1.0 - Double(box.maxY)))
    let bottom = max(0, min(1, 1.0 - Double(box.minY)))
    return [left, top, max(0, right - left), max(0, bottom - top)]
  }

  private func sendGuidance(
    box: [Double]?,
    face: [Double]?,
    saliency: [Double]?,
    roll: Double,
    pitch: Double,
    orientedWidth: Int,
    orientedHeight: Int
  ) {
    let width = Double(orientedWidth)
    let height = Double(orientedHeight)
    // videoFieldOfView 是传感器横向视场；旋转到竖屏后横向对应传感器短边，按画幅比折算。
    let nativeFov = Double(currentDevice?.activeFormat.videoFieldOfView ?? 60)
    let shortSide = min(width, height)
    let longSide = max(width, height)
    let portraitFov = 2 * atan(tan(nativeFov * Double.pi / 360) * (shortSide / longSide)) * 180 / Double.pi
    var payload: [String: Any] = [
      "roll": roll,
      "pitch": pitch,
      "frameW": Int(width),
      "frameH": Int(height),
      "hfov": portraitFov,
      "ts": Int(Date().timeIntervalSince1970 * 1000)
    ]
    if let box = box { payload["box"] = box }
    if let face = face { payload["face"] = face }
    if let saliency = saliency { payload["saliency"] = saliency }
    DispatchQueue.main.async { [weak self] in
      self?.channel.invokeMethod("guidance", arguments: payload)
    }
  }

  // MARK: - Zoom / lens

  private func applyZoom(_ zoom: CGFloat, result: @escaping FlutterResult) {
    let requested = max(0.5, min(6.0, zoom))
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      guard self.isConfigured else {
        DispatchQueue.main.async { result(["zoom": self.currentZoom]) }
        return
      }

      let target = PrimeCameraHost.makeDevice(position: self.currentPosition, zoom: requested)
      if let target = target, target.uniqueID != self.currentDevice?.uniqueID {
        _ = self.replaceInput(with: target)
      }
      let actual = self.currentDevice.map {
        self.setZoomFactor(on: $0, logicalZoom: requested)
      } ?? self.currentZoom
      self.currentZoom = actual
      DispatchQueue.main.async {
        result([
          "zoom": actual,
          "position": self.currentPosition == .back ? "back" : "front",
          "lens": PrimeCameraHost.lensName(self.currentDevice),
        ])
      }
    }
  }

  /// 返回“相对广角”的逻辑倍率：超广角设备的 factor=1.0 对应 0.5×。
  private func setZoomFactor(on device: AVCaptureDevice, logicalZoom: CGFloat) -> CGFloat {
    let isUltraWide = device.deviceType == .builtInUltraWideCamera
    let minFactor = max(1.0, device.minAvailableVideoZoomFactor)
    let maxFactor = min(device.maxAvailableVideoZoomFactor, 6.0)
    let desiredFactor = isUltraWide ? logicalZoom / 0.5 : logicalZoom
    var actualFactor = max(minFactor, min(maxFactor, desiredFactor))
    do {
      try device.lockForConfiguration()
      if device.isFocusModeSupported(.continuousAutoFocus) {
        device.focusMode = .continuousAutoFocus
      }
      if device.isExposureModeSupported(.continuousAutoExposure) {
        device.exposureMode = .continuousAutoExposure
      }
      if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
        device.whiteBalanceMode = .continuousAutoWhiteBalance
      }
      device.isSubjectAreaChangeMonitoringEnabled = true
      device.videoZoomFactor = actualFactor
      device.unlockForConfiguration()
    } catch {
      actualFactor = device.videoZoomFactor
    }
    return isUltraWide ? actualFactor * 0.5 : actualFactor
  }

  /// 在运行中的 session 上换输入；失败会把旧输入装回去，避免切镜头后黑屏。
  @discardableResult
  private func replaceInput(
    with device: AVCaptureDevice,
    position: AVCaptureDevice.Position? = nil
  ) -> Bool {
    guard let newInput = try? AVCaptureDeviceInput(device: device) else { return false }
    let oldInput = currentInput
    let oldDevice = currentDevice
    let oldPosition = currentPosition
    let targetPosition = position ?? currentPosition
    session.beginConfiguration()
    // 先按目标镜头收窄高分辨率拍照能力，避免超广角/前置在切输入时被旧的
    // high-resolution 配置挡住，导致 0.5× 看似选中却切不过去。
    updatePhotoOutputCapabilities(for: device, position: targetPosition)
    if let oldInput = oldInput, session.inputs.contains(where: { $0 === oldInput }) {
      session.removeInput(oldInput)
    }
    let added = session.canAddInput(newInput)
    if added {
      session.addInput(newInput)
      currentInput = newInput
      currentDevice = device
      if let position = position {
        currentPosition = position
      }
      updatePhotoOutputCapabilities(for: device, position: position ?? currentPosition)
    } else {
      // 新镜头装不上时优先把旧输入原样装回；旧 input 失效就按旧设备重建。
      var restored = false
      if let oldInput = oldInput, session.canAddInput(oldInput) {
        session.addInput(oldInput)
        currentInput = oldInput
        currentDevice = oldDevice
        restored = true
      } else if
        let oldDevice = oldDevice,
        let fallbackInput = try? AVCaptureDeviceInput(device: oldDevice),
        session.canAddInput(fallbackInput)
      {
        session.addInput(fallbackInput)
        currentInput = fallbackInput
        currentDevice = oldDevice
        restored = true
      }
      if !restored {
        currentInput = nil
        currentDevice = nil
      }
      if let oldDevice = oldDevice {
        updatePhotoOutputCapabilities(for: oldDevice, position: oldPosition)
      }
    }
    session.commitConfiguration()
    applyConnectionSettings()
    return added
  }

  private func switchCamera(result: @escaping FlutterResult) {
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      let newPosition: AVCaptureDevice.Position =
        self.currentPosition == .back ? .front : .back
      let requested = max(0.5, self.currentZoom)
      guard let device = PrimeCameraHost.makeDevice(position: newPosition, zoom: requested) else {
        DispatchQueue.main.async {
          result(FlutterError(code: "no-camera", message: "切换镜头失败", details: nil))
        }
        return
      }
      guard self.replaceInput(with: device, position: newPosition) else {
        DispatchQueue.main.async {
          result(FlutterError(code: "no-camera", message: "找不到可用镜头", details: nil))
        }
        return
      }
      let actual = self.setZoomFactor(on: device, logicalZoom: requested)
      self.currentZoom = actual
      DispatchQueue.main.async {
        result([
          "position": newPosition == .back ? "back" : "front",
          "zoom": actual,
          "lens": PrimeCameraHost.lensName(self.currentDevice),
        ])
      }
    }
  }

  // MARK: - Focus / exposure

  private func focusAt(x: Double, y: Double, result: @escaping FlutterResult) {
    sessionQueue.async { [weak self] in
      guard let self = self, let device = self.currentDevice else {
        DispatchQueue.main.async { result(false) }
        return
      }
      do {
        try device.lockForConfiguration()
        if device.isFocusPointOfInterestSupported {
          let point = CGPoint(
            x: CGFloat(min(max(x, 0), 1)),
            y: CGFloat(min(max(y, 0), 1))
          )
          device.focusPointOfInterest = point
          device.focusMode = .autoFocus
        }
        // 轻点后 1.2 秒回到连续对焦，避免一直锁在错误位置。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
          self?.sessionQueue.async {
            guard let self = self, let device = self.currentDevice else { return }
            do {
              try device.lockForConfiguration()
              if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
              }
              device.unlockForConfiguration()
            } catch {
              // 设备可能已被切换，忽略。
            }
          }
        }
        device.unlockForConfiguration()
        DispatchQueue.main.async { result(true) }
      } catch {
        DispatchQueue.main.async { result(false) }
      }
    }
  }

  private func setExposure(_ value: CGFloat, result: @escaping FlutterResult) {
    sessionQueue.async { [weak self] in
      guard let self = self, let device = self.currentDevice else {
        DispatchQueue.main.async { result(false) }
        return
      }
      let bias = max(-2.0, min(2.0, value))
      guard device.isExposureTargetBiasSupported(bias) else {
        DispatchQueue.main.async { result(false) }
        return
      }
      do {
        try device.lockForConfiguration()
        device.setExposureTargetBias(Float(bias), completionHandler: nil)
        device.unlockForConfiguration()
        DispatchQueue.main.async { result(true) }
      } catch {
        DispatchQueue.main.async { result(false) }
      }
    }
  }

  // MARK: - Photo

  private func takePhoto(
    flash: Bool,
    filter: String,
    ratio: String,
    selfieMirror: Bool,
    watermark: Bool,
    watermarkStyle: String,
    livePhoto: Bool,
    result: @escaping FlutterResult
  ) {
    sessionQueue.async { [weak self] in
      guard let self = self, self.isConfigured else {
        DispatchQueue.main.async { result(nil) }
        return
      }
      guard self.photoOutput.connection(with: .video) != nil else {
        DispatchQueue.main.async {
          result(FlutterError(code: "capture", message: "相机还没准备好", details: nil))
        }
        return
      }

      let settings: AVCapturePhotoSettings
      if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
        settings = AVCapturePhotoSettings(format: [
          AVVideoCodecKey: AVVideoCodecType.jpeg
        ])
      } else {
        settings = AVCapturePhotoSettings()
      }
      settings.flashMode = (flash && self.currentDevice?.hasFlash == true) ? .on : .off
      var liveMovieURL: URL? = nil
      if livePhoto && self.photoOutput.isLivePhotoCaptureSupported {
        let movie = FileManager.default.temporaryDirectory
          .appendingPathComponent("prime-live-\(UUID().uuidString).mov")
        settings.livePhotoMovieFileURL = movie
        liveMovieURL = movie
      }
      settings.photoQualityPrioritization = .quality
      settings.isHighResolutionPhotoEnabled = self.photoOutput.isHighResolutionCaptureEnabled

      let id = settings.uniqueID
      let finish: (Data?, URL?, Error?) -> Void = { [weak self] data, movie, error in
        guard let self = self else { return }
        self.sessionQueue.async { [weak self] in
          self?.photoDelegates[id] = nil
        }
        if let error = error {
          DispatchQueue.main.async {
            result(FlutterError(code: "capture", message: error.localizedDescription, details: nil))
          }
          return
        }
        guard let data = data else {
          DispatchQueue.main.async {
            result(FlutterError(code: "capture", message: "照片数据为空", details: nil))
          }
          return
        }
        var finalData = self.applyFilter(data, filter: filter, ratio: ratio) ?? data
        if selfieMirror && self.currentPosition == .front,
           let ui = UIImage(data: finalData) {
          finalData = self.flipHorizontal(ui).jpegData(compressionQuality: 0.95) ?? finalData
        }
        if watermark, let ui = UIImage(data: finalData) {
          finalData = self.decorate(ui, border: watermarkStyle, watermark: true)
            .jpegData(compressionQuality: 0.95) ?? finalData
        }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
          .appendingPathComponent("PRIME", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("prime-\(UUID().uuidString).jpg")
        do {
          try finalData.write(to: url, options: .atomic)
          if let movie = movie {
            self.saveLivePhoto(data: finalData, movieURL: movie)
          }
          DispatchQueue.main.async { result(url.path) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "capture", message: error.localizedDescription, details: nil))
          }
        }
      }
      let delegate: AVCapturePhotoCaptureDelegate
      if liveMovieURL != nil {
        delegate = PrimeLivePhotoDelegate(handler: finish)
      } else {
        delegate = PrimePhotoDelegate { photo, error in
          finish(photo?.fileDataRepresentation(), nil, error)
        }
      }
      self.photoOutput.capturePhoto(with: settings, delegate: delegate)
    }
  }

  /// 传感器原生多为 4:3；按用户选的取景比例做中心裁切，成片和预览一致。
  private func crop(_ image: CIImage, ratio: String) -> CIImage {
    let extent = image.extent
    guard extent.width > 0, extent.height > 0 else { return image }
    let target: CGFloat
    switch ratio {
    case "oneOne": target = 1.0
    case "sixteenNine": target = 9.0 / 16.0
    default: target = 3.0 / 4.0
    }
    let current = extent.width / extent.height
    if abs(current - target) < 0.01 { return image }
    if current > target {
      let width = extent.height * target
      let x = extent.midX - width / 2
      return image.cropped(to: CGRect(
        x: x, y: extent.minY, width: width, height: extent.height
      ))
    }
    let height = extent.width / target
    let y = extent.midY - height / 2
    return image.cropped(to: CGRect(
      x: extent.minX, y: y, width: extent.width, height: height
    ))
  }

  private func editPhoto(
    path: String,
    filter: String,
    ratio: String,
    rotate: Int,
    flip: Bool,
    border: String,
    watermark: Bool,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else { return }
      guard
        let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
        var image = CIImage(data: data, options: [.applyOrientationProperty: true])
      else {
        DispatchQueue.main.async {
          result(FlutterError(code: "edit", message: "无法读取照片", details: nil))
        }
        return
      }
      image = self.crop(image, ratio: ratio)
      image = self.applyLook(image, id: filter)
      guard let cg = CIContext(options: nil).createCGImage(image, from: image.extent) else {
        DispatchQueue.main.async { result(nil) }
        return
      }
      var ui = UIImage(cgImage: cg, scale: 1, orientation: .up)
      ui = self.rotate(ui, quarterTurns: rotate)
      if flip { ui = self.flipHorizontal(ui) }
      ui = self.decorate(ui, border: border, watermark: watermark)
      guard let finalData = ui.jpegData(compressionQuality: 0.95) else {
        DispatchQueue.main.async { result(nil) }
        return
      }
      let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PRIME", isDirectory: true)
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let url = dir.appendingPathComponent("edit-\(UUID().uuidString).jpg")
      do {
        try finalData.write(to: url, options: .atomic)
        DispatchQueue.main.async { result(url.path) }
      } catch {
        DispatchQueue.main.async { result(nil) }
      }
    }
  }

  private func rotate(_ image: UIImage, quarterTurns: Int) -> UIImage {
    let turns = ((quarterTurns % 4) + 4) % 4
    guard turns != 0 else { return image }
    let radians = CGFloat(turns) * .pi / 2
    let size = turns % 2 == 0
      ? image.size
      : CGSize(width: image.size.height, height: image.size.width)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
      let cg = context.cgContext
      cg.translateBy(x: size.width / 2, y: size.height / 2)
      cg.rotate(by: radians)
      image.draw(in: CGRect(
        x: -image.size.width / 2,
        y: -image.size.height / 2,
        width: image.size.width,
        height: image.size.height
      ))
    }
  }

  private func flipHorizontal(_ image: UIImage) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: image.size)
    return renderer.image { context in
      let cg = context.cgContext
      cg.translateBy(x: image.size.width, y: 0)
      cg.scaleBy(x: -1, y: 1)
      image.draw(in: CGRect(origin: .zero, size: image.size))
    }
  }

  private func decorate(_ image: UIImage, border: String, watermark: Bool) -> UIImage {
    let margin: CGFloat = border == "white" ? 26 : (border == "magazine" ? 22 : 0)
    let bottomExtra: CGFloat = border == "magazine" ? 64 : (border == "film" ? 34 : 0)
    let size = CGSize(width: image.size.width + margin * 2, height: image.size.height + margin * 2 + bottomExtra)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
      let cg = context.cgContext
      switch border {
      case "white":
        UIColor(white: 0.96, alpha: 1).setFill()
      case "film":
        UIColor(white: 0.06, alpha: 1).setFill()
      case "magazine":
        UIColor(white: 0.08, alpha: 1).setFill()
      default:
        UIColor.black.setFill()
      }
      cg.fill(CGRect(origin: .zero, size: size))
      image.draw(in: CGRect(x: margin, y: margin, width: image.size.width, height: image.size.height))

      if border == "film" {
        UIColor(white: 0.22, alpha: 1).setFill()
        let hole: CGFloat = 7
        var x: CGFloat = 8
        while x < size.width - 8 {
          cg.fillEllipse(in: CGRect(x: x, y: 6, width: hole, height: hole))
          cg.fillEllipse(in: CGRect(x: x, y: size.height - hole - 6, width: hole, height: hole))
          x += hole + 7
        }
      }

      if watermark {
        let text = "PRIME  ·  \(Date().formatted(date: .numeric, time: .shortened))" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
          .font: UIFont.systemFont(ofSize: border == "magazine" ? 11 : 8, weight: .semibold),
          .foregroundColor: border == "white" ? UIColor.black.withAlphaComponent(0.55) : UIColor.white.withAlphaComponent(0.72),
          .kern: 1.2,
        ]
        let textSize = text.size(withAttributes: attrs)
        let point = CGPoint(
          x: margin + 8,
          y: size.height - textSize.height - (border == "magazine" ? 18 : 8)
        )
        text.draw(at: point, withAttributes: attrs)
      }
    }
  }

  /// 预览用 Flutter ColorFilter 矩阵近似；成片用 CoreImage 按同一组
  /// Doka 胶片 id 再渲染一次。这里覆盖 1.3.20 滤镜库的全部系列。
  private func applyFilter(_ data: Data, filter: String, ratio: String) -> Data? {
    guard var input = CIImage(
      data: data,
      options: [.applyOrientationProperty: true]
    ) else { return data }
    input = crop(input, ratio: ratio)
    return render(applyLook(input, id: filter))
  }

  private func applyLook(_ input: CIImage, id: String) -> CIImage {
    if id == "none" || id.isEmpty { return input }
    switch id {
    case "mono":
      return input.applyingFilter("CIPhotoEffectMono")
    case "agfa_ap100":
      return input.applyingFilter("CIPhotoEffectNoir")
        .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.12])
    case "bw_high":
      return input.applyingFilter("CIPhotoEffectTonal")
        .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.22])
    case "clear":
      return controls(input, saturation: 1.08, contrast: 1.10, brightness: 0.03)
    case "warm":
      return temp(controls(input, saturation: 1.04, contrast: 1.04), from: 6500, to: 5200)
    case "cool":
      return temp(controls(input, saturation: 1.02, contrast: 1.04), from: 6500, to: 8000)
    case "doka_s50":
      return controls(temp(input, from: 6500, to: 5200), saturation: 0.95, contrast: 0.92, brightness: 0.14)
    case "doka_s100":
      return controls(input, saturation: 1.0, contrast: 0.98, brightness: 0.08)
    case "doka_s160":
      return controls(temp(input, from: 6500, to: 5600), saturation: 1.06, contrast: 1.02, brightness: 0.03)
    case "doka_s200":
      return controls(temp(input, from: 6500, to: 6000), saturation: 1.0, contrast: 1.10, brightness: 0.0)
    case "doka_s400":
      return controls(temp(input, from: 6500, to: 5000), saturation: 1.06, contrast: 1.16, brightness: 0.0)
    case "f160c":
      return controls(temp(input, from: 6500, to: 7000), saturation: 1.10, contrast: 1.02, brightness: 0.03)
    case "f400h":
      return controls(temp(input, from: 6500, to: 7800), saturation: 0.90, contrast: 0.95, brightness: 0.10)
    case "fc200":
      return controls(temp(input, from: 6500, to: 5000), saturation: 1.05, contrast: 1.06, brightness: 0.04)
    case "fcc":
      return controls(input, saturation: 1.08, contrast: 1.10, brightness: 0.01)
    case "classic_chrome":
      return controls(input, saturation: 0.86, contrast: 1.12, brightness: 0.02)
    case "classic_neg":
      return controls(temp(input, from: 6500, to: 6800), saturation: 1.0, contrast: 1.08, brightness: 0.02)
    case "pro_neg":
      return controls(temp(input, from: 6500, to: 5400), saturation: 0.95, contrast: 0.98, brightness: 0.06)
    case "provia":
      return controls(input, saturation: 1.05, contrast: 1.06, brightness: 0.02)
    case "velvia":
      return controls(input, saturation: 1.25, contrast: 1.18, brightness: 0.0)
    case "astia":
      return controls(input, saturation: 1.08, contrast: 1.02, brightness: 0.04)
    case "kodak_gold":
      return controls(temp(input, from: 6500, to: 5000), saturation: 1.06, contrast: 1.02, brightness: 0.05)
    case "portra160":
      return controls(temp(input, from: 6500, to: 5400), saturation: 0.95, contrast: 0.96, brightness: 0.08)
    case "portra400":
      return controls(temp(input, from: 6500, to: 5400), saturation: 1.0, contrast: 1.0, brightness: 0.06)
    case "ektar":
      return controls(input, saturation: 1.15, contrast: 1.16, brightness: 0.0)
    case "agfa_vista":
      return controls(temp(input, from: 6500, to: 6500), saturation: 1.05, contrast: 1.06, brightness: 0.08)
    default:
      return controls(input, saturation: 1.04, contrast: 1.04, brightness: 0.0)
    }
  }

  private func controls(
    _ image: CIImage,
    saturation: CGFloat,
    contrast: CGFloat,
    brightness: CGFloat
  ) -> CIImage {
    image.applyingFilter("CIColorControls", parameters: [
      kCIInputSaturationKey: saturation,
      kCIInputContrastKey: contrast,
      kCIInputBrightnessKey: brightness,
    ])
  }

  private func temp(_ image: CIImage, from: CGFloat, to: CGFloat) -> CIImage {
    image.applyingFilter("CITemperatureAndTint", parameters: [
      "inputNeutral": CIVector(x: from, y: 0),
      "inputTargetNeutral": CIVector(x: to, y: 0),
    ])
  }

  private func render(_ image: CIImage) -> Data? {
    let context = CIContext(options: nil)
    guard let cgImage = context.createCGImage(image, from: image.extent) else {
      return nil
    }
    let ui = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    return ui.jpegData(compressionQuality: 0.95)
  }

  private func pickPhotos(result: @escaping FlutterResult) {
    guard let controller = PrimeCameraHost.topViewController() else {
      result([])
      return
    }
    var config = PHPickerConfiguration(photoLibrary: .shared())
    config.filter = .images
    config.selectionLimit = 0
    config.preferredAssetRepresentationMode = .current
    let picker = PHPickerViewController(configuration: config)
    let delegate = PrimePhotoPicker { [weak self] paths in
      self?.photoPicker = nil
      result(paths)
    }
    photoPicker = delegate
    picker.delegate = delegate
    controller.present(picker, animated: true)
  }

  private func listPhotos(result: @escaping FlutterResult) {
    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("PRIME", isDirectory: true)
    guard let files = try? FileManager.default.contentsOfDirectory(
      at: dir,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    ) else {
      result([])
      return
    }
    let sorted = files
      .filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
      .sorted {
        let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return a > b
      }
    result(sorted.map { $0.path })
  }

  private func deletePhoto(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let path = args["path"] as? String
    else {
      result(false)
      return
    }
    do {
      try FileManager.default.removeItem(atPath: path)
      result(true)
    } catch {
      result(false)
    }
  }

  private func shareFiles(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let paths = args["paths"] as? [String],
      let controller = PrimeCameraHost.topViewController()
    else {
      result(false)
      return
    }
    let urls = paths.filter { FileManager.default.fileExists(atPath: $0) }
      .map { URL(fileURLWithPath: $0) }
    guard !urls.isEmpty else {
      result(false)
      return
    }
    let activity = UIActivityViewController(activityItems: urls, applicationActivities: nil)
    if let popover = activity.popoverPresentationController {
      popover.sourceView = controller.view
      popover.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1)
      popover.permittedArrowDirections = []
    }
    controller.present(activity, animated: true) { result(true) }
  }

  private func saveLivePhoto(data: Data, movieURL: URL) {
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else { return }
      PHPhotoLibrary.shared().performChanges {
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: .photo, data: data, options: nil)
        request.addResource(with: .pairedVideo, fileURL: movieURL, options: nil)
      } completionHandler: { _, _ in
        try? FileManager.default.removeItem(at: movieURL)
      }
    }
  }

  private func saveToAlbum(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let path = args["path"] as? String
    else {
      result(false)
      return
    }
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: path) else {
      result(false)
      return
    }
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else {
        DispatchQueue.main.async { result(false) }
        return
      }
      PHPhotoLibrary.shared().performChanges {
        PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
      } completionHandler: { success, _ in
        DispatchQueue.main.async { result(success) }
      }
    }
  }

  private func share(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let path = args["path"] as? String,
      FileManager.default.fileExists(atPath: path),
      let controller = PrimeCameraHost.topViewController()
    else {
      result(false)
      return
    }
    let activity = UIActivityViewController(
      activityItems: [URL(fileURLWithPath: path)],
      applicationActivities: nil
    )
    if let popover = activity.popoverPresentationController {
      popover.sourceView = controller.view
      popover.sourceRect = CGRect(
        x: controller.view.bounds.midX,
        y: controller.view.bounds.midY,
        width: 1,
        height: 1
      )
      popover.permittedArrowDirections = []
    }
    controller.present(activity, animated: true) {
      result(true)
    }
  }

  private func openSettings(result: @escaping FlutterResult) {
    guard let url = URL(string: UIApplication.openSettingsURLString) else {
      result(false)
      return
    }
    UIApplication.shared.open(url, options: [:]) { success in
      result(success)
    }
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
    var controller = window?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
  }
}

final class PrimePhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
  private let handler: (AVCapturePhoto?, Error?) -> Void

  init(handler: @escaping (AVCapturePhoto?, Error?) -> Void) {
    self.handler = handler
  }

  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {
    handler(photo, error)
  }
}


final class PrimePhotoPicker: NSObject, PHPickerViewControllerDelegate {
  private let completion: ([String]) -> Void

  init(completion: @escaping ([String]) -> Void) {
    self.completion = completion
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard !results.isEmpty else {
      completion([])
      return
    }
    let group = DispatchGroup()
    let lock = NSLock()
    var paths: [String] = []
    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("PRIME", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    for result in results {
      guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else { continue }
      group.enter()
      result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
        defer { group.leave() }
        guard let image = object as? UIImage,
              let data = image.jpegData(compressionQuality: 0.95) else { return }
        let url = dir.appendingPathComponent("import-\(UUID().uuidString).jpg")
        do {
          try data.write(to: url, options: .atomic)
          lock.lock()
          paths.append(url.path)
          lock.unlock()
        } catch {}
      }
    }
    group.notify(queue: .main) { [completion] in
      completion(paths)
    }
  }
}


final class PrimeLivePhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
  private let handler: (Data?, URL?, Error?) -> Void

  init(handler: @escaping (Data?, URL?, Error?) -> Void) {
    self.handler = handler
  }

  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {
    // 数据在 didFinishCapture 统一回调，此处只保存引用。
    self.photo = photo
  }

  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingLivePhotoToMovieFileAt movieFileURL: URL,
    duration: CMTime,
    photoDisplayTime: CMTime,
    resolvedSettings: AVCaptureResolvedPhotoSettings,
    error: Error?
  ) {
    self.movieURL = movieFileURL
  }

  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
    error: Error?
  ) {
    handler(photo?.fileDataRepresentation(), movieURL, error)
  }

  private var photo: AVCapturePhoto?
  private var movieURL: URL?
}
