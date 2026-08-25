// lib/screens/scanner_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../models/app_state.dart';
import '../models/scan_layout_model.dart';
import '../services/scan_input_provider.dart';
import '../services/scan_pipeline.dart';
import '../services/scan_readiness.dart';
import '../services/scan_pipeline_stubs.dart';
import '../services/scan_model_availability.dart';
import '../services/tflite_object_detector.dart';
import '../services/scan_guidance.dart';
import '../services/scan_setup.dart';
import '../theme/app_theme.dart';
import '../widgets/scan_guidance_banner.dart';
import '../widgets/scan_luma_preview.dart';
import '../widgets/scan_minimap.dart';
import '../widgets/scan_pre_coach_sheet.dart';
import 'scanner/scan_bottom_bar.dart';
import '../widgets/scanner/scan_detection_overlay.dart';
import '../widgets/scanner/scan_log_panel.dart';
import '../widgets/scanner/scan_readiness_ui.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with TickerProviderStateMixin {
  static const String _logFilterPrefKey = 'room_rig.scanner.log_filter';
  static const String _readinessHintsExpandedPrefKey = 'room_rig.scanner.readiness_hints_expanded';
  static const String _logPanelCollapsedPrefKey = 'room_rig.scanner.log_panel_collapsed';
  static const String _logAutoScrollPrefKey = 'room_rig.scanner.log_auto_scroll';
  static const double _requiredCoverageToFinish = 0.68;
  static const int _requiredStableQualityFrames = 5;

  late AnimationController _pulseController;
  CameraController? _cameraController;
  ScanPipeline? _scanPipeline;
  ScanInputProvider? _inputProvider;
  String _inputProviderId = 'camera';
  bool _cameraReady = false;
  bool _arCoreOwnsCamera = false;
  bool _processingFrame = false;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _qualityLogCooldown = 0;
  late final ScanFinishReadinessController _readiness;
  List<ScanQualityIssue> _latestQualityIssues = const [];
  double _latestYawDegrees = 0;
  double _latestCamX = 1.4;
  double _latestCamZ = 1.4;
  ScanCoachBanner? _coachBanner;
  Uint8List? _previewBytes;
  int _previewWidth = 0;
  int _previewHeight = 0;
  ScanCoachBannerKind? _lastBannerKind;
  ScanTurnAction? _lastTurnAction;
  int _lastCornersDone = 0;
  bool _didFinishHaptic = false;

  bool _isScanning = false;
  final List<ScanLogEntry> _logs = [];
  final List<DetectedBox> _detectedBoxes = [];
  final Map<String, DateTime> _logLastAt = {};
  final Map<String, int> _logSuppressed = {};
  ScanLogFilter _logFilter = ScanLogFilter.all;
  bool _showReadinessHints = true;
  bool _logPanelCollapsed = true;
  DateTime _lastAppNotifyAt = DateTime.fromMillisecondsSinceEpoch(0);
  RoomLayoutModel? _liveLayout;
  int _previewTick = 0;
  final ScanSetupController _setup = ScanSetupController();
  bool _logAutoScroll = true;
  final ScrollController _logScrollController = ScrollController();
  int _processedFrames = 0;
  int _framesWithDetections = 0;
  int _totalDetectionBoxes = 0;
  int _trackingFallbackFrames = 0;
  int _qualityFallbackFrames = 0;
  int _detectorFallbackFrames = 0;
  int _fusionFallbackFrames = 0;
  DateTime? _scanStartedAt;
  DateTime? _scanEndedAt;
  String? _lastExportFolder;
  String _detectorLabel = 'Approximate layout scan';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);

    _readiness = ScanFinishReadinessController(
      requiredCoverage: _requiredCoverageToFinish,
      requiredStableQualityFrames: _requiredStableQualityFrames,
      qualityEnterThreshold: 0.50,
      qualityExitThreshold: 0.35,
    );

    unawaited(_restoreLogFilterPreference());
    unawaited(_restoreReadinessHintsPreference());
    unawaited(_restoreLogPanelPreferences());
    unawaited(_refreshDetectorLabel());
    // On Android, ARCore owns the camera during scan (S10+). Defer Flutter
    // camera until AR is unavailable so the two never fight for the lens.
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _appendLog(
          '> Android: preferring ARCore world tracking (Galaxy S10+ class).',
          key: 'android-arcore-pref',
        );
      });
    } else {
      _initializeCamera();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    unawaited(_stopInputProvider());
    unawaited(_stopCameraStream());
    unawaited(_scanPipeline?.dispose());
    _cameraController?.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _appendLog(
          '> Camera not found. Running fallback visual mode.',
          severity: ScanLogSeverity.warning,
          key: 'camera-missing',
          minInterval: const Duration(seconds: 6),
        );
        return;
      }

      final selected = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _cameraReady = true;
      });
      _appendLog('> Camera ready. Back lens initialized.', key: 'camera-ready');
    } catch (_) {
      _appendLog(
        '> Failed to initialize camera stream.',
        severity: ScanLogSeverity.error,
        key: 'camera-init-failed',
        minInterval: const Duration(seconds: 8),
      );
    }
  }

  ScanPipeline _createPipeline() {
    final state = context.read<AppState>();
    final dims = state.activeRoomLayout?.dimensions ??
        RoomDimensions(
          lengthMeters: state.currentRoomData.gridCols * 0.6,
          widthMeters: state.currentRoomData.gridRows * 0.6,
          heightMeters: 2.7,
        );
    return ScanPipeline(
      trackingProvider: CompositeTrackingProvider(roomBounds: dims),
      qualityAnalyzer: BasicFrameQualityAnalyzer(),
      objectDetector: HybridObjectDetector(
        primary: TfliteObjectDetectorPlaceholder(modelAssetPath: 'assets/models/yolo_roomrig.tflite'),
        fallback: HeuristicObjectDetector(),
      ),
      fusionEngine: GridCoverageFusionEngine(),
    );
  }

  Future<void> _refreshDetectorLabel() async {
    final bundled = await ScanModelAvailability.isProductionModelBundled();
    final label = await ScanModelAvailability.detectorLabel(
      usingHeuristicFallback: !bundled,
    );
    if (!mounted) return;
    setState(() => _detectorLabel = label);
  }

  Future<void> _requestStartScan() async {
    if (_isScanning) return;
    await _refreshDetectorLabel();
    if (!mounted) return;
    final go = await showScanPreCoachSheet(
      context,
      detectorLabel: _detectorLabel,
    );
    if (!go || !mounted) return;
    await _startScan();
  }

  Future<void> _startScan() async {
    final state = context.read<AppState>();
    state.resetScan();

    await _stopInputProvider();
    await _scanPipeline?.dispose();
    final pipeline = _createPipeline();
    _scanPipeline = pipeline;

    final seedLayout = RoomLayoutModel.emptyFromRoom(state.currentRoomData);
    await pipeline.initialize(seedLayout);
    state.applyScannedRoomLayout(seedLayout);

    _setup.reset();

    setState(() {
      _isScanning = true;
      _qualityLogCooldown = 0;
      _readiness.reset();
      _latestQualityIssues = const [];
      _latestYawDegrees = 0;
      _latestCamX = 1.4;
      _latestCamZ = 1.4;
      _coachBanner = null;
      _previewBytes = null;
      _previewWidth = 0;
      _previewHeight = 0;
      _lastBannerKind = null;
      _lastTurnAction = null;
      _lastCornersDone = 0;
      _didFinishHaptic = false;
      _logPanelCollapsed = true;
      _processedFrames = 0;
      _framesWithDetections = 0;
      _totalDetectionBoxes = 0;
      _trackingFallbackFrames = 0;
      _qualityFallbackFrames = 0;
      _detectorFallbackFrames = 0;
      _fusionFallbackFrames = 0;
      _scanStartedAt = DateTime.now().toUtc();
      _scanEndedAt = null;
      _lastExportFolder = null;
      _logs.clear();
      _logLastAt.clear();
      _logSuppressed.clear();
      _detectedBoxes.clear();
      _logs.add(
        const ScanLogEntry(
          message: '> Setup first: lock tracking, then one walk to size the room.',
          severity: ScanLogSeverity.info,
        ),
      );
      _logs.add(
        const ScanLogEntry(
          message: '> Tracking: composite (ARCore → visual odometry → simulated).',
          severity: ScanLogSeverity.info,
        ),
      );
    });
    unawaited(_persistLogPanelPreferences());
    _scheduleLogAutoScroll();

    await _startInputSource();
    if (!_arCoreOwnsCamera) {
      _skipSetupToPresetCapture(reason: 'no ARCore — using preset room size');
    }
  }

  void _skipSetupToPresetCapture({required String reason}) {
    _setup.skipToCapture();
    _appendLog('> Setup skipped ($reason).', key: 'setup-skip');
  }

  void _beginMeasuredCapture() {
    if (!mounted) return;
    final state = context.read<AppState>();
    final pipeline = _scanPipeline;
    if (pipeline == null) return;

    final seed = _setup.buildLayout(
      roomName: state.currentRoomData.name,
      fallback: RoomDimensions(
        lengthMeters: state.currentRoomData.gridCols * 0.6,
        widthMeters: state.currentRoomData.gridRows * 0.6,
        heightMeters: 2.7,
      ),
    );
    final fusion = pipeline.fusionEngine;
    final origin = _setup.origin;
    if (fusion is GridCoverageFusionEngine && origin != null) {
      fusion.useWorldOrigin(origin);
    }
    pipeline.rebindLayout(seed);
    final tracking = pipeline.trackingProvider;
    if (tracking is CompositeTrackingProvider) {
      tracking.roomBounds = seed.dimensions;
    }
    state.applyScannedRoomLayout(seed, persist: false);
    _liveLayout = seed;
    _appendLog(
      '> Room sized ${seed.dimensions.lengthMeters.toStringAsFixed(1)}×${seed.dimensions.widthMeters.toStringAsFixed(1)} m. Capture started.',
      key: 'setup-capture',
    );
    HapticFeedback.mediumImpact();
  }

  Future<void> _startInputSource() async {
    final tracking = _scanPipeline?.trackingProvider;
    final nativeReady =
        tracking is CompositeTrackingProvider && tracking.isNativeReady;

    if (Platform.isAndroid && nativeReady) {
      await _releaseFlutterCamera();
      final arInput = ArCoreOwnedScanInputProvider();
      _inputProvider = arInput;
      _inputProviderId = arInput.id;
      _arCoreOwnsCamera = true;
      await arInput.initialize();
      await arInput.start(_ingestFrame);
      final backend = tracking.nativeBackend;
      _appendLog(
        '> Input provider: ARCore ($backend). Camera owned by AR session.',
        key: 'input-arcore',
      );
      if (mounted) setState(() {});
      return;
    }

    if (Platform.isAndroid && tracking is CompositeTrackingProvider) {
      final reason = tracking.nativeInitReason ?? 'unavailable';
      _appendLog(
        '> ARCore not ready ($reason). Falling back to device camera.',
        severity: ScanLogSeverity.warning,
        key: 'arcore-fallback',
      );
    }

    _arCoreOwnsCamera = false;
    if (!_cameraReady || _cameraController == null) {
      await _initializeCamera();
    }

    if (_cameraReady && _cameraController != null) {
      final relay = RelayScanInputProvider();
      _inputProvider = relay;
      _inputProviderId = relay.id;
      await relay.initialize();
      await relay.start(_ingestFrame);
      await _startCameraStream();
      _appendLog('> Input provider: device camera.', key: 'input-camera');
      return;
    }

    final simulated = SimulatedScanInputProvider();
    _inputProvider = simulated;
    _inputProviderId = simulated.id;
    await simulated.initialize();
    await simulated.start(_ingestFrame);
    _appendLog(
      '> Input provider: simulated scan (camera unavailable).',
      severity: ScanLogSeverity.warning,
      key: 'input-simulated',
    );
  }

  Future<void> _releaseFlutterCamera() async {
    await _stopCameraStream();
    final controller = _cameraController;
    _cameraController = null;
    _cameraReady = false;
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {}
    }
  }

  Future<void> _stopInputProvider() async {
    await _inputProvider?.stop();
    await _inputProvider?.dispose();
    _inputProvider = null;
  }

  Future<void> _finishScan() async {
    if (!_isScanning) return;

    if (!_canFinishScan) {
      _appendLog(
        '> Cannot finish yet: coverage or quality threshold not met.',
        severity: ScanLogSeverity.warning,
        key: 'finish-blocked',
        minInterval: const Duration(seconds: 3),
        includeSuppressedSummary: true,
      );
      return;
    }

    final state = context.read<AppState>();
    await _stopCameraStream();
    await _stopInputProvider();

    final layout = _scanPipeline?.finalize();
    if (layout != null) {
      final usedFallback = _trackingFallbackFrames > 0 ||
          _qualityFallbackFrames > 0 ||
          _detectorFallbackFrames > 0 ||
          _fusionFallbackFrames > 0 ||
          _inputProviderId == 'simulated';
      state.commitScannedRoomLayout(
        layout,
        inputProviderId: _inputProviderId,
        usedFallback: usedFallback,
        diagnostics: ScanPipelineDiagnostics(
          trackingFallbackUsed: _trackingFallbackFrames > 0,
          qualityFallbackUsed: _qualityFallbackFrames > 0,
          detectorFallbackUsed: _detectorFallbackFrames > 0,
          fusionFallbackUsed: _fusionFallbackFrames > 0,
        ),
      );
    }

    await _scanPipeline?.dispose();
    _scanPipeline = null;

    if (!mounted) return;
    setState(() {
      _isScanning = false;
      _scanEndedAt = DateTime.now().toUtc();
      _arCoreOwnsCamera = false;
    });
    final conf = state.lastScanConfidence;
    final confPct = conf == null ? '--' : '${(conf.overallScore * 100).round()}%';
    _appendLog(
      '> Scan committed to Rig ($confPct confidence). Open Rig to edit placements.',
      key: 'scan-finalized',
      minInterval: const Duration(seconds: 6),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Scan saved · $confPct confidence — edit placements on Rig'),
        backgroundColor: AppColors.cyan.withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'OPEN RIG',
          textColor: Colors.black,
          onPressed: () => state.setTab(2),
        ),
      ),
    );
  }

  Future<void> _cancelScan() async {
    if (!_isScanning) return;
    await _stopCameraStream();
    await _stopInputProvider();
    await _scanPipeline?.dispose();
    _scanPipeline = null;
    if (!mounted) return;
    setState(() {
      _isScanning = false;
      _arCoreOwnsCamera = false;
      _liveLayout = null;
      _detectedBoxes.clear();
    });
    _appendLog('> Scan cancelled.', key: 'scan-cancelled');
  }

  Future<void> _ingestSetupFrame(ScanFrameInput frame) async {
    final pipeline = _scanPipeline;
    if (pipeline == null) return;

    final sample = await pipeline.sampleTrackingAndQuality(frame);
    if (!mounted) return;
    final tracking = sample.$1;
    final quality = sample.$2;
    final previous = _setup.phase;
    _setup.observe(tracking);

    Uint8List? previewBytes = _previewBytes;
    var previewW = _previewWidth;
    var previewH = _previewHeight;
    _previewTick++;
    if (_previewTick % 2 == 1 &&
        frame.bytes.isNotEmpty &&
        frame.width > 0 &&
        frame.height > 0) {
      previewBytes = frame.bytes is Uint8List
          ? frame.bytes as Uint8List
          : Uint8List.fromList(frame.bytes);
      previewW = frame.width;
      previewH = frame.height;
    }

    if (previous == ScanSessionPhase.lockTracking &&
        _setup.phase == ScanSessionPhase.sizeRoom) {
      HapticFeedback.selectionClick();
      _appendLog('> Tracking locked. Walk toward the far wall.', key: 'setup-sized');
    }

    if (_setup.phase == ScanSessionPhase.capture) {
      _beginMeasuredCapture();
    }

    setState(() {
      _latestQualityIssues = quality.issues;
      _latestYawDegrees = tracking.cameraEulerDegrees.y;
      _latestCamX = tracking.cameraPosition.x;
      _latestCamZ = tracking.cameraPosition.z;
      _coachBanner = ScanGuidance.coachBanner(
        issues: quality.issues,
        trackingStable: tracking.trackingStable,
        trackingConfidence: tracking.confidence,
        coverageReadyForFinish: false,
        canFinish: false,
        stableQualityFrames: 0,
        requiredStableQualityFrames: 1,
      );
      _previewBytes = previewBytes;
      _previewWidth = previewW;
      _previewHeight = previewH;
    });
  }

  Future<void> _ingestFrame(ScanFrameInput frame) async {
    if (!_isScanning || _processingFrame || _scanPipeline == null) return;

    final now = DateTime.now();
    if (now.difference(_lastFrameAt).inMilliseconds < 280) return;

    _processingFrame = true;
    _lastFrameAt = now;

    try {
      if (_setup.phase != ScanSessionPhase.capture) {
        await _ingestSetupFrame(frame);
        return;
      }

      final tick = await _scanPipeline!.processFrame(frame);
      if (!mounted) return;

      _processedFrames++;
      if (tick.frameResult.detections.isNotEmpty) {
        _framesWithDetections++;
        _totalDetectionBoxes += tick.frameResult.detections.length;
      }
      if (tick.diagnostics.trackingFallbackUsed) {
        _trackingFallbackFrames++;
      }
      if (tick.diagnostics.qualityFallbackUsed) {
        _qualityFallbackFrames++;
      }
      if (tick.diagnostics.detectorFallbackUsed) {
        _detectorFallbackFrames++;
      }
      if (tick.diagnostics.fusionFallbackUsed) {
        _fusionFallbackFrames++;
      }

      final state = context.read<AppState>();
      final coverage = tick.layout.coverageGrid.ratio();
      final progress = max(state.scanProgress, coverage.clamp(0.0, 0.98));
      final shouldNotify = now.difference(_lastAppNotifyAt).inMilliseconds >= 500;
      state.applyScannedRoomLayout(tick.layout, persist: false, notify: false);
      state.setScanProgress(progress, notify: shouldNotify);
      if (shouldNotify) _lastAppNotifyAt = now;

      final wasReady = _readiness.canFinish;
      final readiness = _readiness.update(
        coverageRatio: coverage,
        quality: tick.frameResult.quality,
      );
      if (!wasReady && readiness.canFinish) {
        _appendLog(
          '> Finish criteria stabilized. You can finalize scan now.',
          key: 'finish-ready',
          minInterval: const Duration(seconds: 10),
        );
      }

      _maybeLogQuality(tick.frameResult.quality);
      _maybeLogPipelineDiagnostics(tick.diagnostics);
      if (coverage >= 0.9 && _qualityLogCooldown % 8 == 0) {
        _appendLog(
          '> Coverage threshold reached. Keep quality stable to finish.',
          key: 'coverage-threshold',
          minInterval: const Duration(seconds: 8),
        );
      }

      final tracking = tick.frameResult.tracking;
      final coach = ScanGuidance.coachBanner(
        issues: tick.frameResult.quality.issues,
        trackingStable: tracking.trackingStable,
        trackingConfidence: tracking.confidence,
        coverageReadyForFinish: coverage >= _requiredCoverageToFinish,
        canFinish: readiness.canFinish,
        stableQualityFrames: _readiness.stableQualityFrames,
        requiredStableQualityFrames: _requiredStableQualityFrames,
      );

      Uint8List? previewBytes = _previewBytes;
      var previewW = _previewWidth;
      var previewH = _previewHeight;
      _previewTick++;
      if (_previewTick % 2 == 1 &&
          frame.bytes.isNotEmpty &&
          frame.width > 0 &&
          frame.height > 0) {
        previewBytes = frame.bytes is Uint8List
            ? frame.bytes as Uint8List
            : Uint8List.fromList(frame.bytes);
        previewW = frame.width;
        previewH = frame.height;
      }

      final corners = tick.layout.coverageGrid.cols > 0
          ? ScanGuidance.cornerChecklist(tick.layout.coverageGrid)
          : const <ScanCornerStatus>[];
      final cornersDone = corners.where((c) => c.done).length;

      ScanTurnAction? turnAction;
      final dims = tick.layout.dimensions;
      final target = ScanGuidance.findWeakestSector(
        grid: tick.layout.coverageGrid,
        dimensions: dims,
      );
      if (target != null) {
        turnAction = ScanGuidance.directionCue(
          target: target,
          cameraX: tracking.cameraPosition.x,
          cameraZ: tracking.cameraPosition.z,
          yawDegrees: tracking.cameraEulerDegrees.y,
          coverageReadyForFinish: coverage >= _requiredCoverageToFinish,
        ).action;
      }

      _emitScanHaptics(
        coach: coach,
        turnAction: turnAction,
        cornersDone: cornersDone,
        canFinish: readiness.canFinish,
      );

      if (tick.frameResult.detections.isNotEmpty) {
        _updateDetectionOverlays(tick.frameResult.detections);
      }

      setState(() {
        _liveLayout = tick.layout;
        _latestQualityIssues = tick.frameResult.quality.issues;
        _latestYawDegrees = tracking.cameraEulerDegrees.y;
        _latestCamX = tracking.cameraPosition.x;
        _latestCamZ = tracking.cameraPosition.z;
        _coachBanner = coach;
        _previewBytes = previewBytes;
        _previewWidth = previewW;
        _previewHeight = previewH;
        _qualityLogCooldown++;
      });
    } catch (e) {
      _appendLog(
        '> Frame ingest error: $e',
        severity: ScanLogSeverity.error,
        key: 'frame-error',
        minInterval: const Duration(seconds: 4),
      );
    } finally {
      _processingFrame = false;
    }
  }

  Future<void> _startCameraStream() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      _appendLog(
        '> Camera stream unavailable.',
        severity: ScanLogSeverity.warning,
        key: 'camera-stream-unavailable',
        minInterval: const Duration(seconds: 8),
      );
      return;
    }

    if (controller.value.isStreamingImages) {
      return;
    }

    await controller.startImageStream((image) {
      final relay = _inputProvider;
      if (relay is! RelayScanInputProvider) return;
      final packed = _packedLumaPlane(image);
      if (packed.isEmpty) return;
      relay.push(
        ScanFrameInput(
          timestamp: DateTime.now(),
          width: image.width,
          height: image.height,
          bytes: packed,
        ),
      );
    });
  }

  Future<void> _stopCameraStream() async {
    final controller = _cameraController;
    if (controller == null) return;
    if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  }

  Uint8List _packedLumaPlane(CameraImage image) {
    if (image.planes.isEmpty) return Uint8List(0);
    final plane = image.planes.first;
    final w = image.width;
    final h = image.height;
    final src = plane.bytes;
    final stride = plane.bytesPerRow;
    if (w <= 0 || h <= 0 || src.isEmpty) return Uint8List(0);
    if (stride <= w && src.length >= w * h) {
      return src.length == w * h ? src : Uint8List.sublistView(src, 0, w * h);
    }
    final out = Uint8List(w * h);
    for (int y = 0; y < h; y++) {
      final srcOff = y * stride;
      final dstOff = y * w;
      final count = min(w, src.length - srcOff);
      if (count <= 0) break;
      out.setRange(dstOff, dstOff + count, src, srcOff);
    }
    return out;
  }

  void _updateDetectionOverlays(List<Detection2D> detections) {
    if (!mounted) return;
    if (detections.isEmpty) return;

    final detectedLabels = detections.map((d) => d.label).toSet().toList()..sort();
    final labelsJoined = detectedLabels.join(', ');

    setState(() {
      _detectedBoxes
        ..clear()
        ..addAll(
          detections.map(
            (d) => DetectedBox(
              left: d.left,
              top: d.top,
              width: d.width,
              height: d.height,
              color: colorForDetectionCategory(d.category),
            ),
          ),
        );
    });

    _appendLog(
      '> Detected: $labelsJoined',
      key: 'detected:$labelsJoined',
      minInterval: const Duration(seconds: 2),
      includeSuppressedSummary: true,
    );
  }

  void _maybeLogQuality(ScanQualityReport quality) {
    _qualityLogCooldown++;
    _latestQualityIssues = quality.issues;

    if (_qualityLogCooldown % 4 != 0) return;

    if (quality.acceptable) {
      return;
    }

    final notes = quality.issues.map(_qualityIssueText).join(', ');
    _appendLog(
      '> Scan quality warning: $notes',
      severity: ScanLogSeverity.warning,
      key: 'quality:$notes',
      minInterval: const Duration(seconds: 3),
      includeSuppressedSummary: true,
    );
  }

  void _maybeLogPipelineDiagnostics(ScanPipelineDiagnostics diagnostics) {
    if (!mounted) return;

    _appendLog(
      '> Tracking ${diagnostics.trackingSource} @ ${(diagnostics.trackingConfidence * 100).round()}%',
      key: 'tracking-source:${diagnostics.trackingSource}',
      minInterval: const Duration(seconds: 5),
    );

    if (!diagnostics.hasFallback) return;

    final notes = <String>[];
    if (diagnostics.trackingFallbackUsed) {
      notes.add('tracking');
    }
    if (diagnostics.qualityFallbackUsed) {
      notes.add('quality');
    }
    if (diagnostics.detectorFallbackUsed) {
      notes.add('detection');
    }
    if (diagnostics.fusionFallbackUsed) {
      notes.add('fusion');
    }

    final label = notes.join(', ');
    _appendLog(
      '> Pipeline fallback activated: $label',
      severity: ScanLogSeverity.warning,
      key: 'fallback:$label',
      minInterval: const Duration(seconds: 4),
      includeSuppressedSummary: true,
    );
  }

  void _appendLog(
    String message, {
    String? key,
    ScanLogSeverity severity = ScanLogSeverity.info,
    Duration minInterval = const Duration(seconds: 2),
    bool includeSuppressedSummary = false,
  }) {
    if (!mounted) return;

    final now = DateTime.now();
    final dedupeKey = key ?? message;
    final lastAt = _logLastAt[dedupeKey];
    if (lastAt != null && now.difference(lastAt) < minInterval) {
      _logSuppressed[dedupeKey] = (_logSuppressed[dedupeKey] ?? 0) + 1;
      return;
    }

    _logLastAt[dedupeKey] = now;
    final suppressedCount = _logSuppressed.remove(dedupeKey) ?? 0;
    final nextMessage = includeSuppressedSummary && suppressedCount > 0
        ? '$message (+$suppressedCount similar)'
        : message;

    setState(() {
      _logs.add(ScanLogEntry(message: nextMessage, severity: severity));
      if (_logs.length > 40) {
        _logs.removeRange(0, _logs.length - 40);
      }
    });
    _scheduleLogAutoScroll();
  }

  void _scheduleLogAutoScroll() {
    if (!_logAutoScroll || !_logScrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logAutoScroll || !_logScrollController.hasClients) return;
      _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
    });
  }

  String _qualityIssueText(ScanQualityIssue issue) {
    switch (issue) {
      case ScanQualityIssue.lowTexture:
        return 'Low texture';
      case ScanQualityIssue.motionBlur:
        return 'Motion blur';
      case ScanQualityIssue.poorLighting:
        return 'Poor lighting';
      case ScanQualityIssue.trackingLost:
        return 'Tracking lost';
    }
  }

  bool get _canFinishScan {
    return _setup.phase == ScanSessionPhase.capture && _readiness.canFinish;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCameraViewfinder(),
                  if (_isScanning) _buildCoachBannerOverlay(),
                  if (_isScanning && _detectorFallbackFrames > 0)
                    _buildFallbackBadge(),
                  if (_isScanning && _setup.phase == ScanSessionPhase.capture)
                    _buildScanHud(state),
                  if (_isScanning && _setup.phase != ScanSessionPhase.capture)
                    _buildSetupHud(),
                  if (!_isScanning) _buildIdleHeader(state),
                  if (_isScanning) ScanDetectionOverlay(boxes: _detectedBoxes),
                ],
              ),
            ),
            ScanLogPanel(
              logs: _logs,
              logFilter: _logFilter,
              logPanelCollapsed: _logPanelCollapsed,
              logAutoScroll: _logAutoScroll,
              logScrollController: _logScrollController,
              compact: _isScanning,
              onToggleCollapsed: _toggleLogPanelCollapsed,
              onSetFilter: _setLogFilter,
              onToggleAutoScroll: _toggleLogAutoScroll,
              onClearLogs: _clearLogs,
            ),
            ScanBottomBar(
              isScanning: _isScanning,
              setupPhase: _setup.phase,
              setupSnap: _setup.snapshot(),
              scanComplete: state.scanComplete,
              canFinishScan: _canFinishScan,
              requiredCoverageToFinish: _requiredCoverageToFinish,
              finishBlockers: _finishBlockers(state),
              pulseAnimation: _pulseController,
              onRequestStartScan: _requestStartScan,
              onSetupAdvance: () {
                if (_setup.phase == ScanSessionPhase.lockTracking) {
                  _setup.advanceFromLock();
                  HapticFeedback.selectionClick();
                  setState(() {});
                } else {
                  _setup.advanceFromSize();
                  _beginMeasuredCapture();
                  setState(() {});
                }
              },
              onSetupSkipToPreset: () {
                _skipSetupToPresetCapture(reason: 'user skipped sizing');
                _beginMeasuredCapture();
                setState(() {});
              },
              onFinishScan: _finishScan,
              onCancelScan: _cancelScan,
              onOpenRig: () => context.read<AppState>().setTab(2),
              onExportScanBundle: () => _exportScanBundle(state),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdleHeader(AppState state) {
    return Positioned(
      top: 12,
      left: 16,
      right: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'ROOM SCANNER',
                style: TextStyle(
                  color: AppColors.cyan,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
              const Spacer(),
              Text(
                state.scanComplete ? 'COMPLETE' : 'READY',
                style: TextStyle(
                  color: state.scanComplete ? AppColors.green : AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _detectorLabel,
            style: TextStyle(
              color: AppColors.amber.withValues(alpha: 0.9),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraViewfinder() {
    if (_arCoreOwnsCamera || (_isScanning && _previewBytes != null)) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ScanLumaPreview(
            bytes: _previewBytes,
            width: _previewWidth,
            height: _previewHeight,
            placeholder: Container(
              color: const Color(0xFF020508),
              child: CustomPaint(painter: _GridPainter()),
            ),
          ),
        ],
      );
    }

    final controller = _cameraController;
    if (_cameraReady && controller != null && controller.value.isInitialized) {
      return CameraPreview(controller);
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF020508),
            AppColors.cyanDim.withValues(alpha: 0.05),
            const Color(0xFF020508),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: CustomPaint(painter: _GridPainter()),
    );
  }

  void _emitScanHaptics({
    required ScanCoachBanner? coach,
    required ScanTurnAction? turnAction,
    required int cornersDone,
    required bool canFinish,
  }) {
    final kind = coach?.kind;
    if (kind != null &&
        kind != _lastBannerKind &&
        (kind == ScanCoachBannerKind.trackingLost ||
            kind == ScanCoachBannerKind.motionBlur)) {
      HapticFeedback.heavyImpact();
    } else if (kind == ScanCoachBannerKind.holdForFinish && kind != _lastBannerKind) {
      HapticFeedback.mediumImpact();
    }
    _lastBannerKind = kind;

    if (turnAction != null &&
        turnAction != _lastTurnAction &&
        turnAction != ScanTurnAction.holdStill &&
        turnAction != ScanTurnAction.scanInPlace) {
      HapticFeedback.selectionClick();
    }
    _lastTurnAction = turnAction;

    if (cornersDone > _lastCornersDone) {
      HapticFeedback.lightImpact();
      _lastCornersDone = cornersDone;
    }

    if (canFinish && !_didFinishHaptic) {
      _didFinishHaptic = true;
      HapticFeedback.mediumImpact();
    }
  }

  Widget _buildCoachBannerOverlay() {
    final banner = _coachBanner;
    if (banner == null) return const SizedBox.shrink();

    return Positioned(
      top: 12,
      left: 16,
      right: 16,
      child: ScanCoachBannerCard(banner: banner),
    );
  }

  Widget _buildSetupHud() {
    final snap = _setup.snapshot();
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cyan.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              snap.stepLabel,
              style: const TextStyle(
                color: AppColors.cyan,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              snap.headline,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              snap.detail,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: snap.progress.clamp(0.05, 1.0),
              minHeight: 6,
              borderRadius: BorderRadius.circular(6),
              backgroundColor: AppColors.border,
              color: AppColors.cyan,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanHud(AppState state) {
    final layout = _liveLayout ?? state.activeRoomLayout;
    final grid = layout?.coverageGrid;
    if (layout == null || grid == null || grid.coverage.isEmpty) {
      return const SizedBox.shrink();
    }

    final coverageRatio = grid.ratio();
    final target = ScanGuidance.findWeakestSector(
      grid: grid,
      dimensions: layout.dimensions,
    );
    final cue = target == null
        ? null
        : ScanGuidance.directionCue(
            target: target,
            cameraX: _latestCamX,
            cameraZ: _latestCamZ,
            yawDegrees: _latestYawDegrees,
            coverageReadyForFinish: coverageRatio >= _requiredCoverageToFinish,
          );
    final corners = ScanGuidance.cornerChecklist(grid);
    final cornersDone = corners.where((c) => c.done).length;
    final allCornersDone = cornersDone == 4;

    return Stack(
      children: [
        Positioned(
          top: _coachBanner == null ? 12 : 88,
          right: 12,
          child: ScanMinimap(
            grid: grid,
            dimensions: layout.dimensions,
            cameraX: _latestCamX,
            cameraZ: _latestCamZ,
            yawDegrees: _latestYawDegrees,
            coverageRatio: coverageRatio,
            target: target,
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (cue != null)
                ScanDirectionCueCard(
                  cue: cue,
                  remainingCells: target?.remainingCells ?? 0,
                  scannedCells: target?.scannedCells ?? 0,
                  totalCells: target?.totalCells ?? 0,
                ),
              const SizedBox(height: 8),
              ScanReadinessMeter(
                coverageRatio: coverageRatio,
                qualityRatio: _readiness.smoothedQuality,
                stabilityRatio: (_readiness.stableQualityFrames / _requiredStableQualityFrames)
                    .clamp(0.0, 1.0),
                hints: buildReadinessHints(
                  canFinishScan: _canFinishScan,
                  coverageRatio: coverageRatio,
                  qualityRatio: _readiness.smoothedQuality,
                  stabilityRatio: (_readiness.stableQualityFrames / _requiredStableQualityFrames)
                      .clamp(0.0, 1.0),
                  requiredCoverageToFinish: _requiredCoverageToFinish,
                  qualityEnterThreshold: _readiness.qualityEnterThreshold,
                  requiredStableQualityFrames: _requiredStableQualityFrames,
                  stableQualityFrames: _readiness.stableQualityFrames,
                  latestQualityIssues: _latestQualityIssues,
                ),
                showHints: _showReadinessHints,
                requiredCoverageToFinish: _requiredCoverageToFinish,
                qualityEnterThreshold: _readiness.qualityEnterThreshold,
                onToggleHints: _toggleReadinessHints,
              ),
              const SizedBox(height: 8),
              ScanCornerChecklist(grid: grid),
              if (!allCornersDone) ...[
                const SizedBox(height: 4),
                Text(
                  'Cyan = done · amber = go here',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Text(
                      _canFinishScan ? 'Ready to finish' : 'Finish when all bars are green',
                      style: TextStyle(
                        color: _canFinishScan ? AppColors.green : AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFallbackBadge() {
    return Positioned(
      top: 12,
      left: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.amber.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'Approximate detection',
          style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  void _setLogFilter(ScanLogFilter filter) {
    if (_logFilter == filter) return;
    setState(() => _logFilter = filter);
    unawaited(_persistLogFilterPreference(filter));
  }

  Future<void> _restoreLogFilterPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt(_logFilterPrefKey);
      if (stored == null || stored < 0 || stored >= ScanLogFilter.values.length) {
        return;
      }
      if (!mounted) return;
      setState(() => _logFilter = ScanLogFilter.values[stored]);
    } catch (_) {
      // Ignore preference restore errors and keep default filter.
    }
  }

  Future<void> _persistLogFilterPreference(ScanLogFilter filter) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_logFilterPrefKey, filter.index);
    } catch (_) {
      // Ignore preference persistence errors.
    }
  }

  void _toggleReadinessHints() {
    setState(() => _showReadinessHints = !_showReadinessHints);
    unawaited(_persistReadinessHintsPreference(_showReadinessHints));
  }

  Future<void> _restoreReadinessHintsPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getBool(_readinessHintsExpandedPrefKey);
      if (stored == null) return;
      if (!mounted) return;
      setState(() => _showReadinessHints = stored);
    } catch (_) {
      // Ignore preference restore errors and keep default expanded state.
    }
  }

  Future<void> _persistReadinessHintsPreference(bool expanded) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_readinessHintsExpandedPrefKey, expanded);
    } catch (_) {
      // Ignore preference persistence errors.
    }
  }

  Future<void> _restoreLogPanelPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final collapsed = prefs.getBool(_logPanelCollapsedPrefKey);
      final autoScroll = prefs.getBool(_logAutoScrollPrefKey);
      if (!mounted) return;
      setState(() {
        if (collapsed != null) {
          _logPanelCollapsed = collapsed;
        }
        if (autoScroll != null) {
          _logAutoScroll = autoScroll;
        }
      });
    } catch (_) {
      // Ignore preference restore errors and keep defaults.
    }
  }

  Future<void> _persistLogPanelPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_logPanelCollapsedPrefKey, _logPanelCollapsed);
      await prefs.setBool(_logAutoScrollPrefKey, _logAutoScroll);
    } catch (_) {
      // Ignore preference persistence errors.
    }
  }

  void _toggleLogPanelCollapsed() {
    setState(() => _logPanelCollapsed = !_logPanelCollapsed);
    unawaited(_persistLogPanelPreferences());
  }

  void _toggleLogAutoScroll() {
    setState(() => _logAutoScroll = !_logAutoScroll);
    unawaited(_persistLogPanelPreferences());
    if (_logAutoScroll) {
      _scheduleLogAutoScroll();
    }
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
      _logLastAt.clear();
      _logSuppressed.clear();
    });
  }

  List<String> _finishBlockers(AppState state) {
    if (_canFinishScan) return const [];

    final blockers = <String>[];
    final coverage = state.activeRoomLayout?.coverageGrid.ratio() ?? 0;
    if (coverage < _requiredCoverageToFinish) {
      blockers.add('Coverage ${(coverage * 100).toInt()}%/${(_requiredCoverageToFinish * 100).toInt()}%');
    }
    if (_readiness.smoothedQuality < _readiness.qualityEnterThreshold) {
      blockers.add('Quality ${(_readiness.smoothedQuality * 100).toInt()}%/${(_readiness.qualityEnterThreshold * 100).toInt()}%');
    }
    if (_readiness.stableQualityFrames < _requiredStableQualityFrames) {
      blockers.add('Stable frames ${_readiness.stableQualityFrames}/$_requiredStableQualityFrames');
    }
    return blockers;
  }

  Future<void> _exportScanBundle(AppState state) async {
    final layout = state.activeRoomLayout;
    if (layout == null) {
      _appendLog(
        '> Export failed: no active room layout.',
        severity: ScanLogSeverity.error,
        key: 'export-no-layout',
      );
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
      final roomToken = _normalizeFileToken(layout.roomName);
      final exportDir = Directory('${tempDir.path}/room_rig_export_${roomToken}_$stamp');
      await exportDir.create(recursive: true);

      final detectedObjects = layout.objects
          .where((o) => o.source == 'scan-fusion')
          .map((o) => o.toJson())
          .toList(growable: false);

      final logs = _logs
          .map(
            (l) => {
              'severity': l.severity.name,
              'message': l.message,
            },
          )
          .toList(growable: false);

      final summary = {
        'exportedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'roomName': layout.roomName,
        'scanProgress': state.scanProgress,
        'coverageRatio': layout.coverageGrid.ratio(),
        'scanStartedAtUtc': _scanStartedAt?.toIso8601String(),
        'scanEndedAtUtc': _scanEndedAt?.toIso8601String(),
        'processedFrames': _processedFrames,
        'framesWithDetections': _framesWithDetections,
        'totalDetectionBoxes': _totalDetectionBoxes,
        'fallbackFrames': {
          'tracking': _trackingFallbackFrames,
          'quality': _qualityFallbackFrames,
          'detector': _detectorFallbackFrames,
          'fusion': _fusionFallbackFrames,
        },
        'readiness': {
          'canFinish': _canFinishScan,
          'smoothedQuality': _readiness.smoothedQuality,
          'stableQualityFrames': _readiness.stableQualityFrames,
        },
        'detectedObjectCount': detectedObjects.length,
      };

      final encoder = const JsonEncoder.withIndent('  ');
      final layoutFile = File('${exportDir.path}/room_layout.json');
      final objectsFile = File('${exportDir.path}/detected_objects.json');
      final logsFile = File('${exportDir.path}/scan_logs.json');
      final summaryFile = File('${exportDir.path}/scan_summary.json');
      final notesFile = File('${exportDir.path}/EXPORT_NOTES.txt');

      await layoutFile.writeAsString(encoder.convert(layout.toJson()));
      await objectsFile.writeAsString(encoder.convert(detectedObjects));
      await logsFile.writeAsString(encoder.convert(logs));
      await summaryFile.writeAsString(encoder.convert(summary));
      await notesFile.writeAsString(
        'Room Rig Scan Export\n'
        'Generated: ${DateTime.now().toUtc().toIso8601String()}\n\n'
        'Files:\n'
        '- room_layout.json\n'
        '- detected_objects.json\n'
        '- scan_logs.json\n'
        '- scan_summary.json\n\n'
        'Share these files back in workspace for analysis.\n',
      );

      setState(() {
        _lastExportFolder = exportDir.path;
      });

      await Share.shareXFiles(
        [
          XFile(layoutFile.path),
          XFile(objectsFile.path),
          XFile(logsFile.path),
          XFile(summaryFile.path),
          XFile(notesFile.path),
        ],
        text: 'Room Rig scan bundle export',
      );

      _appendLog(
        '> Export complete: shared scan bundle files ($_lastExportFolder).',
        key: 'export-complete',
        minInterval: const Duration(seconds: 2),
      );
    } catch (_) {
      _appendLog(
        '> Export failed: unable to generate scan bundle.',
        severity: ScanLogSeverity.error,
        key: 'export-failed',
        minInterval: const Duration(seconds: 2),
      );
    }
  }

  String _normalizeFileToken(String input) {
    final cleaned = input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final compact = cleaned.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
    return compact.isEmpty ? 'room' : compact;
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.cyan.withValues(alpha: 0.04)
      ..strokeWidth = 0.5;
    const spacing = 30.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }
  @override bool shouldRepaint(_) => false;
}

