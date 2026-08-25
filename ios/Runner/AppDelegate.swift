import Flutter
import UIKit
import CoreMotion

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let motionManager = CMMotionManager()
  private var hasOrigin = false
  private var posX: Double = 1.2
  private var posZ: Double = 1.1
  private var lastYaw: Double = 0

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
          self.hasOrigin = false
          self.posX = 1.2
          self.posZ = 1.1
          self.lastYaw = 0
          self.motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
          if self.motionManager.isDeviceMotionAvailable {
            self.motionManager.startDeviceMotionUpdates(
              using: .xArbitraryCorrectedZVertical
            )
          }
          result([
            "ready": self.motionManager.isDeviceMotionAvailable,
            "backend": "ios-coremotion",
            "supportsDepthHint": false,
            "supportsConfidence": true,
          ])
        case "updateTracking":
          guard let motion = self.motionManager.deviceMotion else {
            result([
              "x": self.posX,
              "y": 1.5,
              "z": self.posZ,
              "yaw": self.lastYaw,
              "pitch": -5.0,
              "roll": 0.0,
              "trackingStable": false,
              "confidence": 0.25,
              "motionMeters": 0.0,
              "depthHintMeters": 2.0,
              "backend": "ios-coremotion",
            ])
            return
          }

          if !self.hasOrigin {
            self.hasOrigin = true
          }

          let attitude = motion.attitude
          let yawDeg = attitude.yaw * 180.0 / .pi
          self.lastYaw = yawDeg.truncatingRemainder(dividingBy: 360)

          // Integrate user acceleration in the horizontal plane (m/s² → rough displacement).
          let ax = motion.userAcceleration.x
          let az = motion.userAcceleration.y
          let dt = self.motionManager.deviceMotionUpdateInterval
          self.posX += ax * dt * dt * 8.0
          self.posZ += az * dt * dt * 8.0
          self.posX = max(0.2, min(8.0, self.posX))
          self.posZ = max(0.2, min(8.0, self.posZ))

          let motionMag = sqrt(ax * ax + az * az)
          let confidence = max(0.35, min(0.92, 0.75 - motionMag * 0.8))

          result([
            "x": self.posX,
            "y": 1.5,
            "z": self.posZ,
            "yaw": self.lastYaw,
            "pitch": attitude.pitch * 180.0 / .pi,
            "roll": attitude.roll * 180.0 / .pi,
            "trackingStable": motionMag < 0.35,
            "confidence": confidence,
            "motionMeters": motionMag * dt,
            "depthHintMeters": 2.0,
            "backend": "ios-coremotion",
          ])
        case "disposeTracking":
          self.motionManager.stopDeviceMotionUpdates()
          self.hasOrigin = false
          result(nil)
        case "getCapabilities":
          result([
            "backend": "ios-coremotion",
            "supportsDepthHint": false,
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
