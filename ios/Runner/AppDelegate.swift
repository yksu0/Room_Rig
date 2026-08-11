import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var trackingPhase: Double = 0
  private var lastX: Double = 1.2
  private var lastZ: Double = 1.1

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as? FlutterViewController
    if let controller {
      let channel = FlutterMethodChannel(
        name: "room_rig/arcore",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self else {
          result(FlutterError(code: "gone", message: "AppDelegate released", details: nil))
          return
        }
        switch call.method {
        case "initializeTracking":
          self.trackingPhase = 0
          self.lastX = 1.2
          self.lastZ = 1.1
          result([
            "ready": true,
            "backend": "ios-arkit-bridge",
            "supportsDepthHint": true,
            "supportsConfidence": true,
          ])
        case "updateTracking":
          self.trackingPhase += 0.07
          let x = 1.2 + sin(self.trackingPhase) * 0.9
          let z = 1.1 + cos(self.trackingPhase * 0.8) * 0.9
          let motion = sqrt(pow(x - self.lastX, 2) + pow(z - self.lastZ, 2))
          self.lastX = x
          self.lastZ = z
          let confidence = max(0.4, min(0.94, 0.8 - motion * 1.4))
          result([
            "x": x,
            "y": 1.5,
            "z": z,
            "yaw": (self.trackingPhase * 24).truncatingRemainder(dividingBy: 360),
            "pitch": -5.0,
            "roll": 0.0,
            "trackingStable": confidence >= 0.45,
            "confidence": confidence,
            "motionMeters": motion,
            "depthHintMeters": 2.0 + 0.5 * sin(self.trackingPhase * 0.4),
            "backend": "ios-arkit-bridge",
          ])
        case "disposeTracking":
          self.trackingPhase = 0
          result(nil)
        case "getCapabilities":
          result([
            "backend": "ios-arkit-bridge",
            "supportsDepthHint": true,
            "supportsConfidence": true,
            "supportsVisualFallback": true,
          ])
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
