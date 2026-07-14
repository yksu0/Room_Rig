// lib/screens/scanner_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../models/app_state.dart';
import '../models/scan_layout_model.dart';
import '../services/scan_pipeline.dart';
import '../services/scan_readiness.dart';
import '../services/scan_pipeline_stubs.dart';
import '../theme/app_theme.dart';
import '../widgets/room_icons.dart';

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
  static const double _requiredCoverageToFinish = 0.90;
  static const int _requiredStableQualityFrames = 8;

  late AnimationController _scanLineController;
  late AnimationController _pulseController;
  CameraController? _cameraController;
  ScanPipeline? _scanPipeline;
  bool _cameraReady = false;
  bool _processingFrame = false;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _qualityLogCooldown = 0;
  late final ScanFinishReadinessController _readiness;
  bool _latestQualityAcceptable = false;
  List<ScanQualityIssue> _latestQualityIssues = const [];

  bool _isScanning = false;
  final List<_ScanLogEntry> _logs = [];
  final List<_DetectedBox> _detectedBoxes = [];
  final Map<String, DateTime> _logLastAt = {};
  final Map<String, int> _logSuppressed = {};
  _ScanLogFilter _logFilter = _ScanLogFilter.all;
  bool _showReadinessHints = true;
  bool _logPanelCollapsed = false;
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

  @override
  void initState() {
    super.initState();
    _scanLineController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);

    _readiness = ScanFinishReadinessController(
      requiredCoverage: _requiredCoverageToFinish,
      requiredStableQualityFrames: _requiredStableQualityFrames,
    );

    unawaited(_restoreLogFilterPreference());
    unawaited(_restoreReadinessHintsPreference());
    unawaited(_restoreLogPanelPreferences());
    _initializeCamera();
  }

  @override
  void dispose() {
    _scanLineController.dispose();
    _pulseController.dispose();
    _stopCameraStream();
    _scanPipeline?.dispose();
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
          severity: _ScanLogSeverity.warning,
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
        severity: _ScanLogSeverity.error,
        key: 'camera-init-failed',
        minInterval: const Duration(seconds: 8),
      );
    }
  }

  ScanPipeline _createPipeline() {
    return ScanPipeline(
      trackingProvider: ArCoreTrackingProviderStub(),
      qualityAnalyzer: BasicFrameQualityAnalyzer(),
      objectDetector: HybridObjectDetector(
        primary: TfliteObjectDetectorPlaceholder(modelAssetPath: 'assets/models/yolo_roomrig.tflite'),
        fallback: HeuristicObjectDetector(),
      ),
      fusionEngine: GridCoverageFusionEngine(),
    );
  }

  Future<void> _startScan() async {
    final state = context.read<AppState>();
    state.resetScan();

    await _scanPipeline?.dispose();
    final pipeline = _createPipeline();
    _scanPipeline = pipeline;

    final seedLayout = RoomLayoutModel.emptyFromRoom(state.currentRoomData);
    await pipeline.initialize(seedLayout);
    state.applyScannedRoomLayout(seedLayout);

    setState(() {
      _isScanning = true;
      _qualityLogCooldown = 0;
      _readiness.reset();
      _latestQualityAcceptable = false;
      _latestQualityIssues = const [];
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
        const _ScanLogEntry(
          message: '> Scan session started. Move around slowly for full coverage.',
          severity: _ScanLogSeverity.info,
        ),
      );
      _logs.add(
        const _ScanLogEntry(
          message: '> Tracking provider attached (Android channel + fallback).',
          severity: _ScanLogSeverity.info,
        ),
      );
    });
    _scheduleLogAutoScroll();

    await _startCameraStream();
  }

  Future<void> _startCameraStream() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      _appendLog(
        '> Camera stream unavailable.',
        severity: _ScanLogSeverity.warning,
        key: 'camera-stream-unavailable',
        minInterval: const Duration(seconds: 8),
      );
      return;
    }

    if (controller.value.isStreamingImages) {
      return;
    }

    await controller.startImageStream((image) {
      _handleCameraFrame(image);
    });
  }

  Future<void> _stopCameraStream() async {
    final controller = _cameraController;
    if (controller == null) return;
    if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  }

  Future<void> _finishScan() async {
    if (!_isScanning) return;

    if (!_canFinishScan) {
      _appendLog(
        '> Cannot finish yet: coverage or quality threshold not met.',
        severity: _ScanLogSeverity.warning,
        key: 'finish-blocked',
        minInterval: const Duration(seconds: 3),
        includeSuppressedSummary: true,
      );
      return;
    }

    final state = context.read<AppState>();
    await _stopCameraStream();

    final layout = _scanPipeline?.finalize();
    if (layout != null) {
      state.applyScannedRoomLayout(layout);
      final completion = max(state.scanProgress, layout.coverageGrid.ratio());
      state.setScanProgress(completion < 0.92 ? 0.92 : 1.0);
    }

    await _scanPipeline?.dispose();
    _scanPipeline = null;

    if (!mounted) return;
    setState(() {
      _isScanning = false;
      _scanEndedAt = DateTime.now().toUtc();
    });
    _appendLog(
      '> Scan finalized. Opening rig customizer is now enabled.',
      key: 'scan-finalized',
      minInterval: const Duration(seconds: 6),
    );
  }

  Future<void> _handleCameraFrame(CameraImage image) async {
    if (!_isScanning || _processingFrame || _scanPipeline == null) return;

    final now = DateTime.now();
    if (now.difference(_lastFrameAt).inMilliseconds < 220) return;

    final planeBytes = image.planes.isNotEmpty ? image.planes.first.bytes : <int>[];
    if (planeBytes.isEmpty) return;

    _processingFrame = true;
    _lastFrameAt = now;

    try {
      final frame = ScanFrameInput(
        timestamp: now,
        width: image.width,
        height: image.height,
        bytes: planeBytes,
      );

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
      state.applyScannedRoomLayout(tick.layout);
      final coverage = tick.layout.coverageGrid.ratio();
      state.setScanProgress(max(state.scanProgress, coverage.clamp(0.0, 0.98)));

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

      _updateDetectionOverlays(tick.frameResult.detections);
      _maybeLogQuality(tick.frameResult.quality);
      _maybeLogPipelineDiagnostics(tick.diagnostics);

      if (coverage >= 0.9 && _qualityLogCooldown % 8 == 0) {
        _appendLog(
          '> Coverage threshold reached. Keep quality stable to finish.',
          key: 'coverage-threshold',
          minInterval: const Duration(seconds: 8),
        );
      }
    } catch (_) {
      _appendLog(
        '> Frame processing failed; continuing...',
        severity: _ScanLogSeverity.error,
        key: 'frame-processing-failed',
        minInterval: const Duration(seconds: 5),
        includeSuppressedSummary: true,
      );
    } finally {
      _processingFrame = false;
    }
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
            (d) => _DetectedBox(
              left: d.left,
              top: d.top,
              width: d.width,
              height: d.height,
              color: _colorForCategory(d.category),
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
    _latestQualityAcceptable = quality.acceptable;
    _latestQualityIssues = quality.issues;

    if (_qualityLogCooldown % 4 != 0) return;

    if (quality.acceptable) {
      return;
    }

    final notes = quality.issues.map(_qualityIssueText).join(', ');
    _appendLog(
      '> Scan quality warning: $notes',
      severity: _ScanLogSeverity.warning,
      key: 'quality:$notes',
      minInterval: const Duration(seconds: 3),
      includeSuppressedSummary: true,
    );
  }

  void _maybeLogPipelineDiagnostics(ScanPipelineDiagnostics diagnostics) {
    if (!diagnostics.hasFallback || !mounted) return;

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
      severity: _ScanLogSeverity.warning,
      key: 'fallback:$label',
      minInterval: const Duration(seconds: 4),
      includeSuppressedSummary: true,
    );
  }

  void _appendLog(
    String message, {
    String? key,
    _ScanLogSeverity severity = _ScanLogSeverity.info,
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
      _logs.add(_ScanLogEntry(message: nextMessage, severity: severity));
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

  Color _colorForCategory(String category) {
    switch (category) {
      case 'airflow':
        return AppColors.airflowColor;
      case 'lighting':
        return AppColors.lightingColor;
      case 'ergonomics':
        return AppColors.ergonomicsColor;
      default:
        return AppColors.cyan;
    }
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
    return _readiness.canFinish;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(state),
            Expanded(
              child: Stack(
                children: [
                  _buildCameraViewfinder(),
                  _buildCoverageOverlay(size, state),
                  if (_isScanning) _buildScanLine(size),
                  ..._detectedBoxes.map((b) => _buildDetectionBox(b, size)),
                  _buildCornerBrackets(size),
                  if (_isScanning || state.scanComplete)
                    _buildScanProgress(size, state),
                ],
              ),
            ),
            _buildLogPanel(),
            _buildBottomBar(state),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(AppState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Text(
            'ROOM SCANNER',
            style: TextStyle(
              color: AppColors.cyan,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
            ),
          ),
          const Spacer(),
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) => Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isScanning
                    ? AppColors.green.withValues(alpha: 0.5 + _pulseController.value * 0.5)
                    : AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _isScanning ? 'SCANNING' : (state.scanComplete ? 'COMPLETE' : 'READY'),
            style: TextStyle(
              color: _isScanning ? AppColors.green : AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraViewfinder() {
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

  Widget _buildCoverageOverlay(Size size, AppState state) {
    final grid = state.activeRoomLayout?.coverageGrid;
    if (grid == null || grid.coverage.isEmpty) {
      return const SizedBox.shrink();
    }

    final guidance = _isScanning ? _buildCoverageGuidance(grid) : null;

    return Positioned(
      left: 0,
      top: 0,
      width: size.width,
      height: size.height * 0.65,
      child: IgnorePointer(
        child: CustomPaint(
          painter: _CoverageGridPainter(
            grid: grid,
            guidance: guidance,
          ),
        ),
      ),
    );
  }

  Widget _buildScanLine(Size size) {
    return AnimatedBuilder(
      animation: _scanLineController,
      builder: (context, _) => Positioned(
        top: _scanLineController.value * size.height * 0.65,
        left: 0, right: 0,
        child: Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                AppColors.cyan.withValues(alpha: 0.3),
                AppColors.cyan,
                AppColors.cyan.withValues(alpha: 0.3),
                Colors.transparent,
              ],
            ),
            boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.6), blurRadius: 12)],
          ),
        ),
      ),
    );
  }

  Widget _buildDetectionBox(_DetectedBox b, Size size) {
    final h = size.height * 0.65;
    final w = size.width;
    return Positioned(
      left: b.left * w,
      top: b.top * h,
      width: b.width * w,
      height: b.height * h,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 300),
        builder: (context, v, child) => Opacity(
          opacity: v,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: b.color, width: 1.5),
              borderRadius: BorderRadius.circular(4),
              color: b.color.withValues(alpha: 0.08),
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                color: b.color.withValues(alpha: 0.9),
                child: const Text(
                  'DETECTED',
                  style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCornerBrackets(Size size) {
    const bSize = 24.0;
    const bThick = 3.0;
    final color = AppColors.cyan.withValues(alpha: 0.8);
    final h = size.height * 0.65;
    const margin = 20.0;

    Widget bracket(bool flipH, bool flipV) => Transform.scale(
      scaleX: flipH ? -1 : 1,
      scaleY: flipV ? -1 : 1,
      child: SizedBox(
        width: bSize, height: bSize,
        child: CustomPaint(painter: _BracketPainter(color: color, thickness: bThick)),
      ),
    );

    return Positioned(
      left: 0, top: 0, width: size.width, height: h,
      child: Stack(
        children: [
          Positioned(left: margin, top: margin, child: bracket(false, false)),
          Positioned(right: margin, top: margin, child: bracket(true, false)),
          Positioned(left: margin, bottom: margin, child: bracket(false, true)),
          Positioned(right: margin, bottom: margin, child: bracket(true, true)),
        ],
      ),
    );
  }

  Widget _buildScanProgress(Size size, AppState state) {
    final grid = state.activeRoomLayout?.coverageGrid;
    final coverageRatio = grid?.ratio() ?? 0;
    final coveragePct = (coverageRatio * 100).toInt();
    final qualityStatus = _readiness.smoothedQuality >= _readiness.qualityEnterThreshold
        ? 'GOOD'
        : 'NEEDS IMPROVEMENT';
    final scannedObjects = state.activeRoomLayout?.objects.where((o) => o.source == 'scan-fusion').length ?? 0;
    final stabilityRatio =
        (_readiness.stableQualityFrames / _requiredStableQualityFrames).clamp(0.0, 1.0);
    final readinessHints = _buildReadinessHints(
      coverageRatio: coverageRatio,
      qualityRatio: _readiness.smoothedQuality,
      stabilityRatio: stabilityRatio,
    );
    final coverageGuidance = grid == null ? null : _buildCoverageGuidance(grid);

    return Positioned(
      bottom: 16, left: 0, right: 0,
      child: Column(
        children: [
          Text(
            '${(state.scanProgress * 100).toInt()}%',
            style: TextStyle(color: AppColors.cyan, fontSize: 32, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: LinearProgressIndicator(
              value: state.scanProgress,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation(AppColors.cyan),
              minHeight: 3,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Coverage: $coveragePct%',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Objects Captured: $scannedObjects',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Quality: $qualityStatus  Stable Frames: ${_readiness.stableQualityFrames}',
            style: TextStyle(
              color: _latestQualityAcceptable ? AppColors.green : AppColors.amber,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_isScanning && coverageGuidance != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: _buildCoverageGuidanceCard(coverageGuidance),
            ),
          ],
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: _buildReadinessMeter(
              coverageRatio: coverageRatio,
              qualityRatio: _readiness.smoothedQuality,
              stabilityRatio: stabilityRatio,
              hints: readinessHints,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverageGuidanceCard(_CoverageGuidance guidance) {
    final remainingPct = guidance.totalCells == 0
        ? 0
        : ((guidance.remainingCells / guidance.totalCells) * 100).round();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(guidance.icon, size: 14, color: AppColors.cyan),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  guidance.remainingCells == 0
                      ? 'Coverage map complete.'
                      : 'Next area: ${guidance.targetLabel}',
                  style: TextStyle(
                    color: AppColors.cyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${guidance.scannedCells}/${guidance.totalCells} cells',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            guidance.remainingCells == 0
                ? 'Great coverage. Keep camera steady to lock quality and finish.'
                : '${guidance.instruction} Remaining: ${guidance.remainingCells} cells (~$remainingPct%).',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  _CoverageGuidance _buildCoverageGuidance(CoverageGrid grid) {
    final total = grid.coverage.length;
    final scanned = grid.coverage.where((v) => v >= 0.70).length;
    final remaining = (total - scanned).clamp(0, total);
    final cols = grid.cols;
    final rows = grid.rows;
    if (cols <= 0 || rows <= 0 || total == 0) {
      return const _CoverageGuidance(
        scannedCells: 0,
        totalCells: 0,
        remainingCells: 0,
        startCol: 0,
        endColExclusive: 1,
        startRow: 0,
        endRowExclusive: 1,
        targetLabel: 'Center',
        instruction: 'Sweep the room edges in slow arcs.',
        icon: Icons.center_focus_strong_rounded,
      );
    }

    final sectorCols = cols >= 3 ? 3 : cols;
    final sectorRows = rows >= 3 ? 3 : rows;
    final sectorCount = sectorCols * sectorRows;
    final sums = List<double>.filled(sectorCount, 0);
    final counts = List<int>.filled(sectorCount, 0);

    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final idx = row * cols + col;
        if (idx >= grid.coverage.length) continue;
        final sx = ((col * sectorCols) / cols).floor().clamp(0, sectorCols - 1);
        final sy = ((row * sectorRows) / rows).floor().clamp(0, sectorRows - 1);
        final sIdx = sy * sectorCols + sx;
        sums[sIdx] += grid.coverage[idx].clamp(0, 1).toDouble();
        counts[sIdx] += 1;
      }
    }

    var bestIdx = 0;
    var bestCoverage = double.infinity;
    for (int i = 0; i < sectorCount; i++) {
      final avg = counts[i] == 0 ? 1.0 : (sums[i] / counts[i]);
      if (avg < bestCoverage) {
        bestCoverage = avg;
        bestIdx = i;
      }
    }

    final targetSectorCol = bestIdx % sectorCols;
    final targetSectorRow = bestIdx ~/ sectorCols;
    final startCol = ((targetSectorCol * cols) / sectorCols).floor().clamp(0, cols - 1);
    final endCol = (((targetSectorCol + 1) * cols) / sectorCols).ceil().clamp(startCol + 1, cols);
    final startRow = ((targetSectorRow * rows) / sectorRows).floor().clamp(0, rows - 1);
    final endRow = (((targetSectorRow + 1) * rows) / sectorRows).ceil().clamp(startRow + 1, rows);

    final label = _sectorLabel(
      row: targetSectorRow,
      col: targetSectorCol,
      rows: sectorRows,
      cols: sectorCols,
    );

    return _CoverageGuidance(
      scannedCells: scanned,
      totalCells: total,
      remainingCells: remaining,
      startCol: startCol,
      endColExclusive: endCol,
      startRow: startRow,
      endRowExclusive: endRow,
      targetLabel: label,
      instruction: _sectorInstruction(
        row: targetSectorRow,
        col: targetSectorCol,
        rows: sectorRows,
        cols: sectorCols,
      ),
      icon: _sectorIcon(
        row: targetSectorRow,
        col: targetSectorCol,
        rows: sectorRows,
        cols: sectorCols,
      ),
    );
  }

  String _sectorLabel({
    required int row,
    required int col,
    required int rows,
    required int cols,
  }) {
    final vertical = row == 0
        ? 'Top'
        : (row == rows - 1 ? 'Bottom' : 'Middle');
    final horizontal = col == 0
        ? 'Left'
        : (col == cols - 1 ? 'Right' : 'Center');

    if (rows == 1 && cols == 1) {
      return 'Center';
    }
    if (rows == 1) {
      return horizontal;
    }
    if (cols == 1) {
      return vertical;
    }
    return '$vertical-$horizontal';
  }

  String _sectorInstruction({
    required int row,
    required int col,
    required int rows,
    required int cols,
  }) {
    final vertical = row == 0
        ? 'upper'
        : (row == rows - 1 ? 'lower' : 'middle');
    final horizontal = col == 0
        ? 'left'
        : (col == cols - 1 ? 'right' : 'center');
    return 'Sweep the $vertical-$horizontal view area with a slow side-to-side pass.';
  }

  IconData _sectorIcon({
    required int row,
    required int col,
    required int rows,
    required int cols,
  }) {
    final top = row == 0;
    final bottom = row == rows - 1;
    final left = col == 0;
    final right = col == cols - 1;

    if (top && left) return Icons.north_west_rounded;
    if (top && right) return Icons.north_east_rounded;
    if (bottom && left) return Icons.south_west_rounded;
    if (bottom && right) return Icons.south_east_rounded;
    if (top) return Icons.north_rounded;
    if (bottom) return Icons.south_rounded;
    if (left) return Icons.west_rounded;
    if (right) return Icons.east_rounded;
    return Icons.center_focus_strong_rounded;
  }

  Widget _buildReadinessMeter({
    required double coverageRatio,
    required double qualityRatio,
    required double stabilityRatio,
    required List<String> hints,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'READINESS DETAILS',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _toggleReadinessHints,
                child: Row(
                  children: [
                    Text(
                      _showReadinessHints ? 'Hide Tips' : 'Show Tips',
                      style: TextStyle(
                        color: AppColors.cyan,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      _showReadinessHints ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 16,
                      color: AppColors.cyan,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _ReadinessMetricRow(
            label: 'Coverage',
            value: coverageRatio,
            target: _requiredCoverageToFinish,
            color: AppColors.cyan,
          ),
          const SizedBox(height: 6),
          _ReadinessMetricRow(
            label: 'Quality',
            value: qualityRatio,
            target: _readiness.qualityEnterThreshold,
            color: AppColors.green,
          ),
          const SizedBox(height: 6),
          _ReadinessMetricRow(
            label: 'Stability',
            value: stabilityRatio,
            target: 1.0,
            color: AppColors.amber,
          ),
          if (_showReadinessHints && hints.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...hints.map(
              (hint) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.tips_and_updates_outlined, size: 12, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        hint,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<String> _buildReadinessHints({
    required double coverageRatio,
    required double qualityRatio,
    required double stabilityRatio,
  }) {
    if (_canFinishScan) {
      return const ['All conditions met. Tap Finish Scan to continue.'];
    }

    final hints = <String>[];

    if (coverageRatio < _requiredCoverageToFinish) {
      final needPct = ((_requiredCoverageToFinish - coverageRatio).clamp(0.0, 1.0) * 100).toInt();
      hints.add('Cover more floor area: scan roughly $needPct% more of the room.');
    }

    if (qualityRatio < _readiness.qualityEnterThreshold) {
      if (_latestQualityIssues.contains(ScanQualityIssue.trackingLost)) {
        hints.add('Tracking unstable: move slower and keep the camera pointed at fixed room features.');
      } else if (_latestQualityIssues.contains(ScanQualityIssue.motionBlur)) {
        hints.add('Motion blur detected: reduce camera speed and avoid quick turns.');
      } else if (_latestQualityIssues.contains(ScanQualityIssue.poorLighting)) {
        hints.add('Low light detected: increase lighting or face brighter sections of the room.');
      } else if (_latestQualityIssues.contains(ScanQualityIssue.lowTexture)) {
        hints.add('Low texture view: include edges, corners, and objects with detail.');
      } else {
        hints.add('Quality below threshold: hold the camera steady for a few seconds.');
      }
    }

    if (stabilityRatio < 1) {
      final missingFrames = (_requiredStableQualityFrames - _readiness.stableQualityFrames)
          .clamp(0, _requiredStableQualityFrames);
      hints.add('Maintain good quality for $missingFrames more stable frames.');
    }

    return hints;
  }

  Widget _buildLogPanel() {
    final filteredLogs = _filteredLogs();

    return Container(
      height: _logPanelCollapsed ? 52 : 140,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.95),
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _toggleLogPanelCollapsed,
                child: Icon(
                  _logPanelCollapsed ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 18,
                  color: AppColors.cyan,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'LOGS',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 8),
              _LogFilterChip(
                label: 'All',
                active: _logFilter == _ScanLogFilter.all,
                onTap: () => _setLogFilter(_ScanLogFilter.all),
              ),
              const SizedBox(width: 6),
              _LogFilterChip(
                label: 'Warn+Error',
                active: _logFilter == _ScanLogFilter.warnError,
                onTap: () => _setLogFilter(_ScanLogFilter.warnError),
              ),
              const SizedBox(width: 6),
              _LogFilterChip(
                label: 'Error',
                active: _logFilter == _ScanLogFilter.errorOnly,
                onTap: () => _setLogFilter(_ScanLogFilter.errorOnly),
              ),
              const SizedBox(width: 6),
              _LogFilterChip(
                label: _logAutoScroll ? 'AutoScroll On' : 'AutoScroll Off',
                active: _logAutoScroll,
                onTap: _toggleLogAutoScroll,
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _clearLogs,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.red.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'Clear',
                    style: TextStyle(color: AppColors.red, fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${filteredLogs.length}/${_logs.length}',
                style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (!_logPanelCollapsed) ...[
            const SizedBox(height: 8),
            Expanded(
              child: filteredLogs.isEmpty
                  ? Center(
                      child: Text(
                        'No logs for selected filter',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                    )
                  : ListView.builder(
                      controller: _logScrollController,
                      itemCount: filteredLogs.length,
                      itemBuilder: (_, i) {
                        final entry = filteredLogs[i];
                        final baseColor = _logSeverityColor(entry.severity);
                        final isLatest = i == filteredLogs.length - 1;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            entry.message,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              color: isLatest ? baseColor : baseColor.withValues(alpha: 0.58),
                              fontSize: 11,
                              fontWeight: isLatest ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }

  List<_ScanLogEntry> _filteredLogs() {
    switch (_logFilter) {
      case _ScanLogFilter.warnError:
        return _logs
            .where((e) => e.severity == _ScanLogSeverity.warning || e.severity == _ScanLogSeverity.error)
            .toList(growable: false);
      case _ScanLogFilter.errorOnly:
        return _logs.where((e) => e.severity == _ScanLogSeverity.error).toList(growable: false);
      case _ScanLogFilter.all:
        return _logs;
    }
  }

  void _setLogFilter(_ScanLogFilter filter) {
    if (_logFilter == filter) return;
    setState(() => _logFilter = filter);
    unawaited(_persistLogFilterPreference(filter));
  }

  Future<void> _restoreLogFilterPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt(_logFilterPrefKey);
      if (stored == null || stored < 0 || stored >= _ScanLogFilter.values.length) {
        return;
      }
      if (!mounted) return;
      setState(() => _logFilter = _ScanLogFilter.values[stored]);
    } catch (_) {
      // Ignore preference restore errors and keep default filter.
    }
  }

  Future<void> _persistLogFilterPreference(_ScanLogFilter filter) async {
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

  Widget _buildFinishBlockersStrip(AppState state) {
    final blockers = _finishBlockers(state);
    if (blockers.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: blockers
            .map(
              (text) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
                ),
                child: Text(
                  text,
                  style: TextStyle(color: AppColors.amber, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Widget _buildBottomBar(AppState state) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: _isScanning
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFinishBlockersStrip(state),
                GestureDetector(
                  onTap: _canFinishScan ? _finishScan : null,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: _canFinishScan ? AppColors.accentGradient : null,
                      color: _canFinishScan ? null : AppColors.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _canFinishScan ? Colors.transparent : AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: _canFinishScan ? AppColors.cyan.withValues(alpha: 0.35) : Colors.black.withValues(alpha: 0.12),
                          blurRadius: 20,
                        )
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgIcon(
                          RoomSvg.checkCircle,
                          size: 20,
                          color: _canFinishScan ? Colors.white : AppColors.textMuted,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _canFinishScan
                              ? 'FINISH SCAN'
                              : 'SCANNING... NEED ${(100 * _requiredCoverageToFinish).toInt()}% + STABLE QUALITY',
                          style: TextStyle(
                            color: _canFinishScan ? Colors.white : AppColors.textMuted,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            fontSize: _canFinishScan ? 13 : 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : state.scanComplete
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => _exportScanBundle(state),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.ios_share_rounded, color: AppColors.cyan, size: 18),
                        const SizedBox(width: 8),
                        const Text(
                          'EXPORT SCAN BUNDLE',
                          style: TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w800, letterSpacing: 1.2),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_lastExportFolder != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Export ready: $_lastExportFolder',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 10),
                    ),
                  ),
                GestureDetector(
                  onTap: () => context.read<AppState>().setTab(2),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: AppColors.accentGradient,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.4), blurRadius: 20)],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgIcon(RoomSvg.tune, size: 18, color: Colors.white),
                        const SizedBox(width: 8),
                        const Text(
                          'OPEN RIG CUSTOMIZER',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : GestureDetector(
              onTap: _startScan,
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) => Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.1 + _pulseController.value * 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.cyan,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.cyan.withValues(alpha: 0.2 + _pulseController.value * 0.15),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgIcon(
                        RoomSvg.camera,
                        size: 20,
                        color: AppColors.cyan,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'TAP TO SCAN ROOM',
                        style: TextStyle(
                          color: AppColors.cyan,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Future<void> _exportScanBundle(AppState state) async {
    final layout = state.activeRoomLayout;
    if (layout == null) {
      _appendLog(
        '> Export failed: no active room layout.',
        severity: _ScanLogSeverity.error,
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
        '> Export complete: shared scan bundle files.',
        key: 'export-complete',
        minInterval: const Duration(seconds: 2),
      );
    } catch (_) {
      _appendLog(
        '> Export failed: unable to generate scan bundle.',
        severity: _ScanLogSeverity.error,
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

  Color _logSeverityColor(_ScanLogSeverity severity) {
    switch (severity) {
      case _ScanLogSeverity.info:
        return AppColors.cyan;
      case _ScanLogSeverity.warning:
        return AppColors.amber;
      case _ScanLogSeverity.error:
        return AppColors.red;
    }
  }
}

enum _ScanLogSeverity { info, warning, error }

enum _ScanLogFilter { all, warnError, errorOnly }

class _ScanLogEntry {
  final String message;
  final _ScanLogSeverity severity;

  const _ScanLogEntry({required this.message, required this.severity});
}

class _LogFilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _LogFilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? AppColors.cyan.withValues(alpha: 0.2) : AppColors.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? AppColors.cyan : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? AppColors.cyan : AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _DetectedBox {
  final double left, top, width, height;
  final Color color;
  const _DetectedBox({required this.left, required this.top, required this.width, required this.height, required this.color});
}

class _ReadinessMetricRow extends StatelessWidget {
  final String label;
  final double value;
  final double target;
  final Color color;

  const _ReadinessMetricRow({
    required this.label,
    required this.value,
    required this.target,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = value.clamp(0.0, 1.0);
    final reached = ratio >= target;

    return Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 5,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(
                reached ? color : color.withValues(alpha: 0.55),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${(ratio * 100).toInt()}%',
          style: TextStyle(
            color: reached ? color : AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
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

class _BracketPainter extends CustomPainter {
  final Color color;
  final double thickness;
  const _BracketPainter({required this.color, required this.thickness});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(const Offset(0, 0), Offset(size.width, 0), paint);
    canvas.drawLine(const Offset(0, 0), Offset(0, size.height), paint);
  }
  @override bool shouldRepaint(_) => false;
}

class _CoverageGridPainter extends CustomPainter {
  final CoverageGrid grid;
  final _CoverageGuidance? guidance;

  const _CoverageGridPainter({required this.grid, this.guidance});

  @override
  void paint(Canvas canvas, Size size) {
    if (grid.cols == 0 || grid.rows == 0) return;

    final cellW = size.width / grid.cols;
    final cellH = size.height / grid.rows;

    for (int row = 0; row < grid.rows; row++) {
      for (int col = 0; col < grid.cols; col++) {
        final idx = row * grid.cols + col;
        if (idx >= grid.coverage.length) continue;
        final v = grid.coverage[idx].clamp(0, 1).toDouble();
        final color = Color.lerp(AppColors.red.withValues(alpha: 0.16), AppColors.green.withValues(alpha: 0.20), v)!;
        canvas.drawRect(
          Rect.fromLTWH(col * cellW, row * cellH, cellW - 1, cellH - 1),
          Paint()..color = color,
        );
      }
    }

    final target = guidance;
    if (target != null && grid.cols > 0 && grid.rows > 0) {
      final left = target.startCol * cellW;
      final top = target.startRow * cellH;
      final width = (target.endColExclusive - target.startCol) * cellW;
      final height = (target.endRowExclusive - target.startRow) * cellH;
      final focusRect = Rect.fromLTWH(left, top, width, height);

      final overlay = Paint()
        ..color = AppColors.cyan.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill;
      canvas.drawRect(focusRect, overlay);

      final border = Paint()
        ..color = AppColors.cyan.withValues(alpha: 0.85)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawRect(focusRect.deflate(1), border);
    }
  }

  @override
  bool shouldRepaint(covariant _CoverageGridPainter oldDelegate) => oldDelegate.grid != grid;
}

class _CoverageGuidance {
  final int scannedCells;
  final int totalCells;
  final int remainingCells;
  final int startCol;
  final int endColExclusive;
  final int startRow;
  final int endRowExclusive;
  final String targetLabel;
  final String instruction;
  final IconData icon;

  const _CoverageGuidance({
    required this.scannedCells,
    required this.totalCells,
    required this.remainingCells,
    required this.startCol,
    required this.endColExclusive,
    required this.startRow,
    required this.endRowExclusive,
    required this.targetLabel,
    required this.instruction,
    required this.icon,
  });
}
