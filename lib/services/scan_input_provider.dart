import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

import 'scan_pipeline.dart';
import 'scan_tracking.dart';

/// Abstraction over camera / AR / simulated frame sources for Milestone 2.
abstract class ScanInputProvider {
  String get id;
  String get displayName;
  bool get isLiveCamera;

  Future<void> initialize();
  Future<void> start(void Function(ScanFrameInput frame) onFrame);
  Future<void> stop();
  Future<void> dispose();
}

/// Synthetic frames for web, tests, and camera-unavailable fallbacks.
class SimulatedScanInputProvider implements ScanInputProvider {
  final Duration interval;
  final int width;
  final int height;
  final Random _rng;

  Timer? _timer;
  int _frameIndex = 0;
  void Function(ScanFrameInput frame)? _onFrame;
  bool _running = false;

  SimulatedScanInputProvider({
    this.interval = const Duration(milliseconds: 220),
    this.width = 320,
    this.height = 240,
    Random? random,
  }) : _rng = random ?? Random(7);

  @override
  String get id => 'simulated';

  @override
  String get displayName => 'Simulated scan';

  @override
  bool get isLiveCamera => false;

  @override
  Future<void> initialize() async {
    _frameIndex = 0;
  }

  @override
  Future<void> start(void Function(ScanFrameInput frame) onFrame) async {
    await stop();
    _onFrame = onFrame;
    _running = true;
    _timer = Timer.periodic(interval, (_) {
      if (!_running) return;
      final callback = _onFrame;
      if (callback == null) return;
      callback(_buildFrame());
    });
  }

  @override
  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
    _onFrame = null;
  }

  ScanFrameInput _buildFrame() {
    _frameIndex++;
    final bytes = Uint8List(width * height);
    // Mild texture + furniture-shaped contrast so luma detection finds blobs.
    final base = 90 + ((_frameIndex * 3) % 40);
    final pan = (_frameIndex % 40) / 40.0;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final nx = x / width;
        final ny = y / height;
        final noise = _rng.nextInt(48);
        final stripe = ((x + _frameIndex) ~/ 12) % 2 == 0 ? 18 : 0;
        var v = base + noise + stripe;
        // Window band (top, bright)
        if (ny < 0.18 && nx > 0.25 && nx < 0.75) v += 70;
        // Door (left, tall)
        if (nx < 0.10 && ny > 0.20) v -= 45;
        // Desk (lower-middle, wide)
        if (ny > 0.55 && ny < 0.78 && nx > 0.22 + pan * 0.08 && nx < 0.72 + pan * 0.08) {
          v -= 35;
        }
        // Chair (in front of desk)
        if (ny > 0.72 && ny < 0.92 && nx > 0.38 && nx < 0.55) v -= 50;
        // Lamp (upper-right)
        if (ny > 0.12 && ny < 0.38 && nx > 0.72 && nx < 0.88) v += 55;
        bytes[y * width + x] = v.clamp(40, 220);
      }
    }

    return ScanFrameInput(
      timestamp: DateTime.now().toUtc(),
      width: width,
      height: height,
      bytes: bytes,
    );
  }
}

/// Wraps an existing camera image stream callback adapter.
/// The mobile scanner owns [CameraController]; this provider only
/// documents the live source and relays already-converted frames.
class RelayScanInputProvider implements ScanInputProvider {
  final String sourceId;
  final String sourceDisplayName;
  final bool liveCamera;

  void Function(ScanFrameInput frame)? _onFrame;
  bool _started = false;

  RelayScanInputProvider({
    this.sourceId = 'camera',
    this.sourceDisplayName = 'Device camera',
    this.liveCamera = true,
  });

  @override
  String get id => sourceId;

  @override
  String get displayName => sourceDisplayName;

  @override
  bool get isLiveCamera => liveCamera;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> start(void Function(ScanFrameInput frame) onFrame) async {
    _onFrame = onFrame;
    _started = true;
  }

  @override
  Future<void> stop() async {
    _started = false;
  }

  @override
  Future<void> dispose() async {
    _started = false;
    _onFrame = null;
  }

  void push(ScanFrameInput frame) {
    if (!_started) return;
    _onFrame?.call(frame);
  }
}

/// Android path when ARCore owns the camera (Galaxy S10+ class).
/// Polls `updateTracking` for pose + downsampled luma; do not open Flutter camera.
class ArCoreOwnedScanInputProvider implements ScanInputProvider {
  final MethodChannel channel;
  final Duration interval;

  Timer? _timer;
  void Function(ScanFrameInput frame)? _onFrame;
  bool _running = false;
  bool _polling = false;
  int _failStreak = 0;

  ArCoreOwnedScanInputProvider({
    MethodChannel? channel,
    this.interval = const Duration(milliseconds: 200),
  }) : channel = channel ?? const MethodChannel('room_rig/arcore');

  @override
  String get id => 'arcore';

  @override
  String get displayName => 'ARCore (device tracking)';

  @override
  bool get isLiveCamera => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> start(void Function(ScanFrameInput frame) onFrame) async {
    await stop();
    _onFrame = onFrame;
    _running = true;
    _timer = Timer.periodic(interval, (_) => unawaited(_pollOnce()));
  }

  @override
  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _polling = false;
  }

  @override
  Future<void> dispose() async {
    await stop();
    _onFrame = null;
  }

  Future<void> _pollOnce() async {
    if (!_running || _polling) return;
    final callback = _onFrame;
    if (callback == null) return;

    _polling = true;
    try {
      final result = await channel.invokeMethod<Map<Object?, Object?>>(
        'updateTracking',
        {'timestampMs': DateTime.now().millisecondsSinceEpoch},
      );
      if (!_running || result == null) return;

      final tracking = trackingSampleFromNativeMap(result);
      final width = (result['frameWidth'] as num?)?.toInt() ?? 0;
      final height = (result['frameHeight'] as num?)?.toInt() ?? 0;
      final raw = result['frameY'];
      Uint8List bytes;
      if (raw is Uint8List) {
        bytes = raw;
      } else if (raw is List) {
        bytes = Uint8List.fromList(List<int>.from(raw));
      } else {
        final w = width > 0 ? width : 64;
        final h = height > 0 ? height : 48;
        bytes = Uint8List(w * h);
        for (int i = 0; i < bytes.length; i++) {
          bytes[i] = 70 + (i % 50);
        }
      }

      final w = width > 0 ? width : (bytes.isEmpty ? 64 : max(1, sqrt(bytes.length).floor()));
      final h = height > 0
          ? height
          : (width > 0 ? max(1, bytes.length ~/ width) : max(1, bytes.length ~/ w));

      final attachNative = tracking.trackingStable || _failStreak < 8;
      _failStreak = 0;
      callback(
        ScanFrameInput(
          timestamp: DateTime.now().toUtc(),
          width: w,
          height: h,
          bytes: bytes,
          attachedTracking: attachNative ? tracking : null,
        ),
      );
    } catch (_) {
      _failStreak += 1;
      // Transient ARCore update failures are expected while GL warms up.
    } finally {
      _polling = false;
    }
  }
}
