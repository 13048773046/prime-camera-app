import AVFoundation
import CoreMotion
import Flutter
import Photos
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

  // 实时构图：Vision 以 ~6fps 找人脸/人体，CoreMotion 读取手机水平角。
  private let visionLock = NSLock()
  private var visionBusy = false
  private var lastVisionAt: CFTimeInterval = 0
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

  private var photoDelegates: [Int64: PrimePhotoDelegate] = [:]

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
    startMotionTracking()
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

  /// 从后台回前台时恢复取景，避免纹理停在最后一帧。
  @objc private func handleDidBecomeActive() {
    sessionQueue.async { [weak self] in
      guard let self = self, self.isConfigured else { return }
      self.startIfNeeded()
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
      applyZoom(CGFloat(truncating: zoom ?? 1.0))
      result(nil)
    case "switchCamera":
      switchCamera(result: result)
    case "takePhoto":
      takePhoto(result: result)
    case "saveToAlbum":
      saveToAlbum(call: call, result: result)
    case "share":
      share(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
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
    case .denied, .restricted:
      result(["status": "denied"])
    @unknown default:
      result(["status": "denied"])
    }
  }

  private func requestPermission(result: @escaping FlutterResult) {
    AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
      DispatchQueue.main.async {
        if granted {
          self?.prepareAndReply(result)
        } else {
          result(["status": "denied"])
        }
      }
    }
  }

  private func prepareAndReply(_ result: @escaping FlutterResult) {
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      do {
        try self.configureIfNeeded(position: self.currentPosition)
        self.applyConnectionSettings()
        self.startIfNeeded()
        DispatchQueue.main.async {
          result([
            "status": "ready",
            "textureId": self.textureId,
            "zoom": self.currentZoom,
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

  private static func makeDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
    if position == .back {
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
    return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
  }

  private func configureIfNeeded(position: AVCaptureDevice.Position) throws {
    if isConfigured { return }

    session.beginConfiguration()
    defer { session.commitConfiguration() }
    // 预览走 1080p 视频流，拍照仍由 photoOutput 输出全分辨率，兼顾流畅与画质。
    session.sessionPreset = .high

    guard let device = PrimeCameraHost.makeDevice(position: position) else {
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
    do {
      try device.lockForConfiguration()
      device.videoZoomFactor = 1.0
      device.unlockForConfiguration()
    } catch {
      // 少数机型不支持改 zoom，预览与拍照不受影响。
    }

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

    isConfigured = true
    applyConnectionSettings()
  }

  private func applyConnectionSettings() {
    if let connection = videoOutput.connection(with: .video) {
      configure(connection: connection, mirrored: currentPosition == .front)
    }
    if let connection = photoOutput.connection(with: .video) {
      configure(connection: connection, mirrored: false)
    }
  }

  private func configure(connection: AVCaptureConnection, mirrored: Bool) {
    if #available(iOS 17.0, *) {
      if connection.isVideoRotationAngleSupported(90) {
        connection.videoRotationAngle = 90
      }
    } else {
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

  /// 在取景流上实时找人：人体框 + 人脸框，结果按 3:4 可见区域归一化后推给 Flutter。
  private func analyzeFrame(_ pixelBuffer: CVPixelBuffer, roll: Double, pitch: Double) {
    let humanRequest = VNDetectHumanRectanglesRequest()
    humanRequest.upperBodyOnly = false
    let faceRequest = VNDetectFaceRectanglesRequest()
    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

    do {
      try handler.perform([humanRequest, faceRequest])
      let humans = humanRequest.results ?? []
      let faces = faceRequest.results ?? []
      let human = humans.max { area(of: $0.boundingBox) < area(of: $1.boundingBox) }
      let face = faces.max { area(of: $0.boundingBox) < area(of: $1.boundingBox) }
      sendGuidance(
        box: human.map { normalizeVisible($0.boundingBox) },
        face: face.map { normalizeVisible($0.boundingBox) },
        roll: roll,
        pitch: pitch,
        buffer: pixelBuffer
      )
    } catch {
      sendGuidance(box: nil, face: nil, roll: roll, pitch: pitch, buffer: pixelBuffer)
    }
  }

  private func area(of rect: CGRect) -> CGFloat {
    rect.width * rect.height
  }

  /// 预览是 9:16 纹理按 3:4 裁切显示，只保留中间 75% 高度；坐标同步映射，避免框偏。
  private func normalizeVisible(_ box: CGRect) -> [Double] {
    let cropTop = 0.125
    let cropHeight = 0.75
    let left = max(0, min(1, Double(box.minX)))
    let right = max(0, min(1, Double(box.maxX)))
    let top = max(0, min(1, (1.0 - Double(box.maxY) - cropTop) / cropHeight))
    let bottom = max(0, min(1, (1.0 - Double(box.minY) - cropTop) / cropHeight))
    return [left, top, max(0, right - left), max(0, bottom - top)]
  }

  private func sendGuidance(
    box: [Double]?,
    face: [Double]?,
    roll: Double,
    pitch: Double,
    buffer: CVPixelBuffer
  ) {
    let width = Double(CVPixelBufferGetWidth(buffer))
    let height = Double(CVPixelBufferGetHeight(buffer))
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
    DispatchQueue.main.async { [weak self] in
      self?.channel.invokeMethod("guidance", arguments: payload)
    }
  }

  // MARK: - Zoom / lens

  private func applyZoom(_ zoom: CGFloat) {
    currentZoom = zoom
    sessionQueue.async { [weak self] in
      guard let self = self, let device = self.currentDevice else { return }
      do {
        try device.lockForConfiguration()
        let lower = device.minAvailableVideoZoomFactor
        let upper = device.maxAvailableVideoZoomFactor
        device.videoZoomFactor = max(lower, min(upper, zoom))
        device.unlockForConfiguration()
      } catch {
        // 忽略：镜头可能正在切换。
      }
    }
  }

  private func switchCamera(result: @escaping FlutterResult) {
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      let newPosition: AVCaptureDevice.Position = self.currentPosition == .back ? .front : .back
      guard
        let device = PrimeCameraHost.makeDevice(position: newPosition),
        let input = try? AVCaptureDeviceInput(device: device)
      else {
        DispatchQueue.main.async { result(FlutterError(code: "no-camera", message: "切换镜头失败", details: nil)) }
        return
      }

      self.session.beginConfiguration()
      if let oldInput = self.currentInput {
        self.session.removeInput(oldInput)
      }
      if self.session.canAddInput(input) {
        self.session.addInput(input)
        self.currentInput = input
        self.currentDevice = device
        self.currentPosition = newPosition
      }
      self.session.commitConfiguration()
      self.applyConnectionSettings()

      do {
        try device.lockForConfiguration()
        device.videoZoomFactor = max(device.minAvailableVideoZoomFactor, min(device.maxAvailableVideoZoomFactor, 1.0))
        device.unlockForConfiguration()
      } catch {}

      DispatchQueue.main.async { result(nil) }
    }
  }

  // MARK: - Photo

  private func takePhoto(result: @escaping FlutterResult) {
    sessionQueue.async { [weak self] in
      guard let self = self, self.isConfigured else {
        DispatchQueue.main.async { result(nil) }
        return
      }

      let settings = AVCapturePhotoSettings()
      settings.flashMode = .off
      settings.photoQualityPrioritization = .speed

      let id = settings.uniqueID
      let delegate = PrimePhotoDelegate { [weak self] photo, error in
        guard let self = self else { return }
        // 回调可能在任意线程；字典只在 sessionQueue 上增删，避免并发写崩。
        self.sessionQueue.async { [weak self] in
          self?.photoDelegates[id] = nil
        }
        if let error = error {
          DispatchQueue.main.async {
            result(FlutterError(code: "capture", message: error.localizedDescription, details: nil))
          }
          return
        }
        guard
          let photo = photo,
          let data = photo.fileDataRepresentation()
        else {
          DispatchQueue.main.async {
            result(FlutterError(code: "capture", message: "照片数据为空", details: nil))
          }
          return
        }
        let url = FileManager.default.temporaryDirectory
          .appendingPathComponent("prime-\(UUID().uuidString).jpg")
        do {
          try data.write(to: url, options: .atomic)
          DispatchQueue.main.async { result(url.path) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "capture", message: error.localizedDescription, details: nil))
          }
        }
      }
      self.photoDelegates[id] = delegate
      self.photoOutput.capturePhoto(with: settings, delegate: delegate)
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
