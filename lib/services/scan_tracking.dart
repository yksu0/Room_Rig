import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/scan_layout_model.dart';
import 'scan_pipeline.dart';

/// Frame-to-frame visual odometry from luminance blocks (no AR SDK required).
/// Used when native ARCore/ARKit is unavailable or unstable.
class VisualOdometryEstimator {
  static const _grid = 4;
  List<double>? _prevBlocks;
  Vec3 _position = const Vec3(x: 1.4, y: 1.5, z: 1.4);
  double _yawDegrees = 0;
  double _lastMotion = 0;
  DateTime? _lastAt;

  void reset({Vec3? seedPosition}) {
    _prevBlocks = null;
    _position = seedPosition ?? const Vec3(x: 1.4, y: 1.5, z: 1.4);
    _yawDegrees = 0;
    _lastMotion = 0;
    _lastAt = null;
  }

  TrackingSample update(
    ScanFrameInput frame, {
    RoomDimensions? roomBounds,
  }) {
    if (frame.bytes.isEmpty || frame.width <= 0 || frame.height <= 0) {
      return TrackingSample(
        cameraPosition: _position,
        cameraEulerDegrees: Vec3(x: 0, y: _yawDegrees, z: 0),
        trackingStable: false,
        confidence: 0.15,
        source: 'visual',
        motionMeters: 0,
      );
    }

    final blocks = _blockAverages(frame);
    final prev = _prevBlocks;
    _prevBlocks = blocks;

    if (prev == null || prev.length != blocks.length) {
      return TrackingSample(
        cameraPosition: _position,
        cameraEulerDegrees: Vec3(x: 0, y: _yawDegrees, z: 0),
        trackingStable: true,
        confidence: 0.45,
        source: 'visual',
        motionMeters: 0,
        depthHintMeters: _estimateDepthHint(blocks),
      );
    }

    // Estimate horizontal / vertical image flow from block brightness deltas.
    double flowX = 0;
    double flowZ = 0;
    double energy = 0;
    for (int row = 0; row < _grid; row++) {
      for (int col = 0; col < _grid; col++) {
        final i = row * _grid + col;
        final d = blocks[i] - prev[i];
        energy += d.abs();
        flowX += d * (col - (_grid - 1) / 2);
        flowZ += d * (row - (_grid - 1) / 2);
      }
    }

    final scale = 1.0 / max(1.0, energy);
    final dxPx = (flowX * scale).clamp(-2.5, 2.5);
    final dzPx = (flowZ * scale).clamp(-2.5, 2.5);

    // Convert pixel-ish flow into meters (tuned for handheld walk speed).
    const metersPerUnit = 0.045;
    final dx = -dxPx * metersPerUnit;
    final dz = dzPx * metersPerUnit;
    _lastMotion = sqrt(dx * dx + dz * dz);

    final yawDelta = (-dxPx * 2.8).clamp(-8.0, 8.0);
    _yawDegrees = (_yawDegrees + yawDelta) % 360;
    if (_yawDegrees < 0) _yawDegrees += 360;

    final yawRad = _yawDegrees * pi / 180;
    final worldDx = dx * cos(yawRad) - dz * sin(yawRad);
    final worldDz = dx * sin(yawRad) + dz * cos(yawRad);

    var next = Vec3(
      x: _position.x + worldDx,
      y: _position.y,
      z: _position.z + worldDz,
    );

    if (roomBounds != null) {
      next = Vec3(
        x: next.x.clamp(0.25, max(0.5, roomBounds.lengthMeters - 0.25)),
        y: next.y,
        z: next.z.clamp(0.25, max(0.5, roomBounds.widthMeters - 0.25)),
      );
    }

    _position = next;

    final now = frame.timestamp;
    final dtMs = _lastAt == null ? 220.0 : now.difference(_lastAt!).inMilliseconds.toDouble().clamp(16.0, 800.0);
    _lastAt = now;
    final speed = _lastMotion / (dtMs / 1000.0);

    // High speed or flat texture → unstable.
    final texture = energy / blocks.length;
    final stable = speed < 1.8 && texture > 2.5;
    final confidence = (0.35 + (texture / 40.0).clamp(0.0, 0.4) + (stable ? 0.2 : 0.0) - (speed > 2.2 ? 0.25 : 0.0))
        .clamp(0.05, 0.92);

    return TrackingSample(
      cameraPosition: _position,
      cameraEulerDegrees: Vec3(x: 0, y: _yawDegrees, z: 0),
      trackingStable: stable,
      confidence: confidence.toDouble(),
      source: 'visual',
      motionMeters: _lastMotion,
      depthHintMeters: _estimateDepthHint(blocks),
    );
  }

  List<double> _blockAverages(ScanFrameInput frame) {
    final out = List<double>.filled(_grid * _grid, 0);
    final counts = List<int>.filled(_grid * _grid, 0);
    final bw = max(1, frame.width ~/ _grid);
    final bh = max(1, frame.height ~/ _grid);
    final stride = max(1, frame.bytes.length ~/ (frame.width * frame.height));

    for (int y = 0; y < frame.height; y += 2) {
      final rowBlock = min(_grid - 1, y ~/ bh);
      for (int x = 0; x < frame.width; x += 2) {
        final colBlock = min(_grid - 1, x ~/ bw);
        final idx = (y * frame.width + x) * stride;
        if (idx >= frame.bytes.length) continue;
        final bi = rowBlock * _grid + colBlock;
        out[bi] += frame.bytes[idx].toDouble();
        counts[bi]++;
      }
    }

    for (int i = 0; i < out.length; i++) {
      out[i] = counts[i] == 0 ? 0 : out[i] / counts[i];
    }
    return out;
  }

  double _estimateDepthHint(List<double> blocks) {
    // Higher mid-frame contrast tends to mean nearer clutter; invert softly.
    final mid = blocks[5] + blocks[6] + blocks[9] + blocks[10];
    final edge = blocks[0] + blocks[3] + blocks[12] + blocks[15];
    final ratio = (mid / max(1.0, edge)).clamp(0.4, 2.5);
    return (2.8 / ratio).clamp(0.8, 4.5);
  }
}

/// Prefers native AR channel, then visual odometry, then a bounded simulated sweep.
class CompositeTrackingProvider implements TrackingProvider {
  final MethodChannel channel;
  final VisualOdometryEstimator visual;
  RoomDimensions? roomBounds;

  bool _nativeReady = false;
  String _nativeBackend = 'none';
  String? _nativeInitReason;
  int _simFrame = 0;
  TrackingSample? _last;

  CompositeTrackingProvider({
    MethodChannel? channel,
    VisualOdometryEstimator? visual,
    this.roomBounds,
  })  : channel = channel ?? const MethodChannel('room_rig/arcore'),
        visual = visual ?? VisualOdometryEstimator();

  bool get isNativeReady => _nativeReady;
  String get nativeBackend => _nativeBackend;
  String? get nativeInitReason => _nativeInitReason;

  String get backendLabel {
    if (_nativeReady) return _nativeBackend;
    if (_last?.source == 'visual') return 'visual-odometry';
    return 'simulated';
  }

  @override
  Future<void> initialize() async {
    _simFrame = 0;
    _nativeReady = false;
    _nativeBackend = 'none';
    _nativeInitReason = null;
    visual.reset(
      seedPosition: roomBounds == null
          ? null
          : Vec3(
              x: roomBounds!.lengthMeters * 0.35,
              y: 1.5,
              z: roomBounds!.widthMeters * 0.35,
            ),
    );

    final platform = defaultTargetPlatform;
    final isMobile = platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    if (!isMobile) return;

    try {
      final result = await channel.invokeMethod<Map<Object?, Object?>>('initializeTracking');
      _nativeReady = (result?['ready'] as bool?) ?? false;
      _nativeBackend = (result?['backend'] as String?) ?? 'native';
      _nativeInitReason = result?['reason'] as String?;
    } catch (_) {
      _nativeReady = false;
      _nativeInitReason = 'channel_error';
    }
  }

  @override
  Future<void> dispose() async {
    if (_nativeReady) {
      try {
        await channel.invokeMethod<void>('disposeTracking');
      } catch (_) {}
    }
    _nativeReady = false;
    _last = null;
  }

  @override
  Future<TrackingSample> update(ScanFrameInput frame) async {
    final attached = frame.attachedTracking;
    if (attached != null && attached.trackingStable && attached.confidence >= 0.4) {
      _last = attached;
      return attached;
    }

    TrackingSample? nativeSample;
    if (_nativeReady) {
      try {
        final result = await channel.invokeMethod<Map<Object?, Object?>>(
          'updateTracking',
          {
            'timestampMs': frame.timestamp.millisecondsSinceEpoch,
            'width': frame.width,
            'height': frame.height,
            'byteLength': frame.bytes.length,
          },
        );
        if (result != null) {
          nativeSample = trackingSampleFromNativeMap(result);
        }
      } catch (_) {
        _nativeReady = false;
      }
    }

    final visualSample = visual.update(frame, roomBounds: roomBounds);

    if (nativeSample != null && nativeSample.trackingStable && nativeSample.confidence >= 0.4) {
      // Lightly blend visual depth hint when native omits it.
      final fused = nativeSample.depthHintMeters == null
          ? TrackingSample(
              cameraPosition: nativeSample.cameraPosition,
              cameraEulerDegrees: nativeSample.cameraEulerDegrees,
              trackingStable: nativeSample.trackingStable,
              confidence: nativeSample.confidence,
              source: nativeSample.source,
              motionMeters: nativeSample.motionMeters,
              depthHintMeters: visualSample.depthHintMeters,
              lookAtPosition: nativeSample.lookAtPosition,
              hasFloorHit: nativeSample.hasFloorHit,
            )
          : nativeSample;
      _last = fused;
      return fused;
    }

    if (nativeSample != null && !nativeSample.trackingStable) {
      // Native lost — prefer visual continuity if it looks healthy.
      if (visualSample.trackingStable && visualSample.confidence >= 0.35) {
        _last = visualSample;
        return visualSample;
      }
    }

    if (!_nativeReady) {
      if (visualSample.confidence >= 0.3) {
        _last = visualSample;
        return visualSample;
      }
      final simulated = _simulatedStep(roomBounds);
      _last = simulated;
      return simulated;
    }

    // Native present but weak — fuse positions.
    if (nativeSample != null) {
      final fusedPos = Vec3(
        x: nativeSample.cameraPosition.x * 0.55 + visualSample.cameraPosition.x * 0.45,
        y: nativeSample.cameraPosition.y,
        z: nativeSample.cameraPosition.z * 0.55 + visualSample.cameraPosition.z * 0.45,
      );
      final fused = TrackingSample(
        cameraPosition: fusedPos,
        cameraEulerDegrees: nativeSample.cameraEulerDegrees,
        trackingStable: visualSample.trackingStable || nativeSample.trackingStable,
        confidence: max(nativeSample.confidence * 0.7, visualSample.confidence * 0.85),
        source: 'fused',
        motionMeters: max(nativeSample.motionMeters, visualSample.motionMeters),
        depthHintMeters: nativeSample.depthHintMeters ?? visualSample.depthHintMeters,
        lookAtPosition: nativeSample.lookAtPosition,
        hasFloorHit: nativeSample.hasFloorHit,
      );
      _last = fused;
      return fused;
    }

    _last = visualSample;
    return visualSample;
  }


  TrackingSample _simulatedStep(RoomDimensions? bounds) {
    _simFrame++;
    final t = _simFrame / 14.0;
    final length = bounds?.lengthMeters ?? 3.6;
    final width = bounds?.widthMeters ?? 4.8;
    final x = (length * 0.5 + sin(t) * length * 0.28).clamp(0.3, length - 0.3);
    final z = (width * 0.5 + cos(t * 0.85) * width * 0.28).clamp(0.3, width - 0.3);
    final motion = _last == null
        ? 0.05
        : sqrt(pow(x - _last!.cameraPosition.x, 2) + pow(z - _last!.cameraPosition.z, 2));

    return TrackingSample(
      cameraPosition: Vec3(x: x, y: 1.5, z: z),
      cameraEulerDegrees: Vec3(x: 0, y: (t * 28) % 360, z: 0),
      trackingStable: true,
      confidence: 0.55,
      source: 'simulated',
      motionMeters: motion,
      depthHintMeters: 2.2,
    );
  }
}

/// Parses the `room_rig/arcore` MethodChannel pose map into a [TrackingSample].
TrackingSample trackingSampleFromNativeMap(Map<Object?, Object?> result) {
  final conf = (result['confidence'] as num?)?.toDouble() ??
      ((result['trackingStable'] as bool?) ?? true ? 0.8 : 0.25);
  final lookX = (result['lookAtX'] as num?)?.toDouble();
  final lookY = (result['lookAtY'] as num?)?.toDouble();
  final lookZ = (result['lookAtZ'] as num?)?.toDouble();
  final hasFloorHit = (result['hasFloorHit'] as bool?) ?? false;
  return TrackingSample(
    cameraPosition: Vec3(
      x: (result['x'] as num?)?.toDouble() ?? 0,
      y: (result['y'] as num?)?.toDouble() ?? 1.5,
      z: (result['z'] as num?)?.toDouble() ?? 0,
    ),
    cameraEulerDegrees: Vec3(
      x: (result['pitch'] as num?)?.toDouble() ?? 0,
      y: (result['yaw'] as num?)?.toDouble() ?? 0,
      z: (result['roll'] as num?)?.toDouble() ?? 0,
    ),
    trackingStable: (result['trackingStable'] as bool?) ?? conf >= 0.45,
    confidence: conf.clamp(0.0, 1.0),
    source: (result['backend'] as String?) ?? 'arcore',
    motionMeters: (result['motionMeters'] as num?)?.toDouble() ?? 0,
    depthHintMeters: (result['depthHintMeters'] as num?)?.toDouble(),
    lookAtPosition: lookX == null || lookZ == null
        ? null
        : Vec3(x: lookX, y: lookY ?? 0, z: lookZ),
    hasFloorHit: hasFloorHit,
  );
}

/// Back-compat alias used by older call sites / tests.
class ArCoreTrackingProviderStub extends CompositeTrackingProvider {
  ArCoreTrackingProviderStub({super.roomBounds});
}
