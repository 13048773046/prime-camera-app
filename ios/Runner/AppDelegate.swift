import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var cameraChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as? FlutterViewController
    if let controller = controller {
      cameraChannel = FlutterMethodChannel(name: "prime/camera", binaryMessenger: controller.binaryMessenger)
      cameraChannel?.setMethodCallHandler { [weak self] call, result in
        self?.handleCameraCall(call: call, result: result)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func handleCameraCall(call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "initialize":
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .authorized:
        result("ready")
      case .notDetermined:
        AVCaptureDevice.requestAccess(for: .video) { granted in
          DispatchQueue.main.async { result(granted ? "ready" : "denied") }
        }
      default:
        result("denied")
      }
    case "setZoom":
      result(nil)
    case "takePhoto":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
