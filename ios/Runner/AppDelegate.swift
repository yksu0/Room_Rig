import Flutter
import UIKit
import CoreMotion

#if canImport(ARKit)
import ARKit
#endif

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let motionManager = CMMotionManager()
  private var hasOrigin = false
  private var posX: Double = 1.2
  private var posZ: Double = 1.1
  private var lastYaw: Double = 0
  private var activeBackend = "ios-coremotion"
  private var supportsDepthHint = false

  #if canImport(ARKit)
  private var arSession: ARSession?
  private var lastArX: Double = 1.2
  private var lastArY: Double = 1.5
  private var lastArZ: Double = 1.1
  private var lastArYaw: Double = 0
  private var lastArPitch: Double = -5
  private var lastArRoll: Double = 0
  private var lastArTrackingStable = false
  private var lastArConfidence: Double = 0.25
  private var lastArMotionMeters: Double = 0
  private var lastArDepthHint: Double = 2.0
  private var prevArPosition: SIMD3<Float>?
  #endif

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
          result(self.initializeTracking())
        case "updateTracking":
          result(self.updateTracking())
        case "disposeTracking":
          self.disposeTracking()
          result(nil)
        case "getCapabilities":
          result(self.capabilities())
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func initializeTracking() -> [String: Any] {
    hasOrigin = false
    posX = 1.2
    posZ = 1.1
    lastYaw = 0
    activeBackend = "ios-coremotion"
    supportsDepthHint = false

    #if canImport(ARKit)
    if ARWorldTrackingConfiguration.isSupported {
      let session = ARSession()
      let config = ARWorldTrackingConfiguration()
      config.worldAlignment = .gravity
      config.planeDetection = [.horizontal]

      var depth = false
      if #available(iOS 14.0, *) {
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
          config.frameSemantics.insert(.sceneDepth)
          depth = true
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
          config.frameSemantics.insert(.smoothedSceneDepth)
          depth = true
        }
      }

      session.delegate = self
      session.run(config, options: [.resetTracking, .removeExistingAnchors])
      arSession = session
      activeBackend = "ios-arkit"
      supportsDepthHint = depth
      lastArX = 1.2
      lastArY = 1.5
      lastArZ = 1.1
      lastArYaw = 0
      lastArPitch = -5
      lastArRoll = 0
      lastArTrackingStable = false
      lastArConfidence = 0.35
      lastArMotionMeters = 0
      lastArDepthHint = 2.0
      prevArPosition = nil

      return [
        "ready": true,
        "backend": activeBackend,
        "supportsDepthHint": supportsDepthHint,
        "supportsConfidence": true,
      ]
    }
    #endif

    motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
    if motionManager.isDeviceMotionAvailable {
      motionManager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical)
    }
    activeBackend = "ios-coremotion"
    supportsDepthHint = false
    return [
      "ready": motionManager.isDeviceMotionAvailable,
      "backend": activeBackend,
      "supportsDepthHint": false,
      "supportsConfidence": true,
    ]
  }

  private func updateTracking() -> [String: Any] {
    #if canImport(ARKit)
    if activeBackend == "ios-arkit", arSession != nil {
      return [
        "x": lastArX,
        "y": lastArY,
        "z": lastArZ,
        "yaw": lastArYaw,
        "pitch": lastArPitch,
        "roll": lastArRoll,
        "trackingStable": lastArTrackingStable,
        "confidence": lastArConfidence,
        "motionMeters": lastArMotionMeters,
        "depthHintMeters": lastArDepthHint,
        "backend": "ios-arkit",
      ]
    }
    #endif

    guard let motion = motionManager.deviceMotion else {
      return [
        "x": posX,
        "y": 1.5,
        "z": posZ,
        "yaw": lastYaw,
        "pitch": -5.0,
        "roll": 0.0,
        "trackingStable": false,
        "confidence": 0.25,
        "motionMeters": 0.0,
        "depthHintMeters": 2.0,
        "backend": "ios-coremotion",
      ]
    }

    if !hasOrigin {
      hasOrigin = true
    }

    let attitude = motion.attitude
    let yawDeg = attitude.yaw * 180.0 / .pi
    lastYaw = yawDeg.truncatingRemainder(dividingBy: 360)

    // Integrate user acceleration in the horizontal plane (m/s² → rough displacement).
    let ax = motion.userAcceleration.x
    let az = motion.userAcceleration.y
    let dt = motionManager.deviceMotionUpdateInterval
    posX += ax * dt * dt * 8.0
    posZ += az * dt * dt * 8.0
    posX = max(0.2, min(8.0, posX))
    posZ = max(0.2, min(8.0, posZ))

    let motionMag = sqrt(ax * ax + az * az)
    let confidence = max(0.35, min(0.92, 0.75 - motionMag * 0.8))

    return [
      "x": posX,
      "y": 1.5,
      "z": posZ,
      "yaw": lastYaw,
      "pitch": attitude.pitch * 180.0 / .pi,
      "roll": attitude.roll * 180.0 / .pi,
      "trackingStable": motionMag < 0.35,
      "confidence": confidence,
      "motionMeters": motionMag * dt,
      "depthHintMeters": 2.0,
      "backend": "ios-coremotion",
    ]
  }

  private func disposeTracking() {
    #if canImport(ARKit)
    arSession?.pause()
    arSession?.delegate = nil
    arSession = nil
    prevArPosition = nil
    #endif
    motionManager.stopDeviceMotionUpdates()
    hasOrigin = false
    activeBackend = "ios-coremotion"
    supportsDepthHint = false
  }

  private func capabilities() -> [String: Any] {
    #if canImport(ARKit)
    var depth = false
    if #available(iOS 14.0, *) {
      depth = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        || ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth)
    }
    if ARWorldTrackingConfiguration.isSupported {
      return [
        "backend": "ios-arkit",
        "supportsDepthHint": depth,
        "supportsConfidence": true,
        "supportsVisualFallback": true,
      ]
    }
    #endif
    return [
      "backend": "ios-coremotion",
      "supportsDepthHint": false,
      "supportsConfidence": true,
      "supportsVisualFallback": true,
    ]
  }
}

#if canImport(ARKit)
extension AppDelegate: ARSessionDelegate {
  public func session(_ session: ARSession, didUpdate frame: ARFrame) {
    let transform = frame.camera.transform
    let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)

    // Map ARKit world (Y up) into the same room-ish coords used by CoreMotion path.
    let mappedX = Double(1.2 + position.x)
    let mappedY = Double(1.5 + position.y)
    let mappedZ = Double(1.1 - position.z)

    var motionMeters: Double = 0
    if let prev = prevArPosition {
      let dx = position.x - prev.x
      let dy = position.y - prev.y
      let dz = position.z - prev.z
      motionMeters = Double(sqrt(dx * dx + dy * dy + dz * dz))
    }
    prevArPosition = position

    let (yaw, pitch, roll) = Self.eulerDegrees(from: transform)
    let state = frame.camera.trackingState
    let (stable, confidence): (Bool, Double) = {
      switch state {
      case .normal:
        return (true, max(0.55, min(0.98, 0.9 - motionMeters * 2.0)))
      case .limited(let reason):
        switch reason {
        case .excessiveMotion:
          return (false, 0.35)
        case .insufficientFeatures:
          return (false, 0.4)
        case .initializing:
          return (false, 0.3)
        case .relocalizing:
          return (false, 0.45)
        @unknown default:
          return (false, 0.4)
        }
      case .notAvailable:
        return (false, 0.15)
      @unknown default:
        return (false, 0.25)
      }
    }()

    var depthHint = lastArDepthHint
    if #available(iOS 14.0, *) {
      if let sceneDepth = frame.sceneDepth {
        depthHint = Self.centerDepthMeters(from: sceneDepth.depthMap) ?? depthHint
      } else if let smoothed = frame.smoothedSceneDepth {
        depthHint = Self.centerDepthMeters(from: smoothed.depthMap) ?? depthHint
      }
    }

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.lastArX = max(0.2, min(8.0, mappedX))
      self.lastArY = mappedY
      self.lastArZ = max(0.2, min(8.0, mappedZ))
      self.lastArYaw = yaw
      self.lastArPitch = pitch
      self.lastArRoll = roll
      self.lastArTrackingStable = stable
      self.lastArConfidence = confidence
      self.lastArMotionMeters = motionMeters
      self.lastArDepthHint = depthHint
    }
  }

  public func session(_ session: ARSession, didFailWithError error: Error) {
    NSLog("RoomRig ARKit session failed: \(error.localizedDescription)")
    // Fall back to CoreMotion on next initialize; keep last pose for now.
  }

  private static func eulerDegrees(from transform: simd_float4x4) -> (Double, Double, Double) {
    let m = transform
    let yaw = atan2(Double(m.columns.0.z), Double(m.columns.2.z)) * 180.0 / .pi
    let pitch = asin(max(-1.0, min(1.0, Double(-m.columns.1.z)))) * 180.0 / .pi
    let roll = atan2(Double(m.columns.1.x), Double(m.columns.1.y)) * 180.0 / .pi
    return (yaw.truncatingRemainder(dividingBy: 360), pitch, roll)
  }

  @available(iOS 14.0, *)
  private static func centerDepthMeters(from depthMap: CVPixelBuffer) -> Double? {
    CVPixelBufferLockBaseAddress(depthMap, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
    let width = CVPixelBufferGetWidth(depthMap)
    let height = CVPixelBufferGetHeight(depthMap)
    guard width > 0, height > 0,
          let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
    let cx = width / 2
    let cy = height / 2
    let row = base.advanced(by: cy * bytesPerRow).assumingMemoryBound(to: Float32.self)
    let meters = Double(row[cx])
    guard meters.isFinite, meters > 0.05, meters < 20 else { return nil }
    return meters
  }
}
#endif
