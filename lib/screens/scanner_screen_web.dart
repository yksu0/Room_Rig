import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../models/scan_layout_model.dart';
import '../services/scan_guidance.dart';
import '../services/scan_input_provider.dart';
import '../services/scan_pipeline.dart';
import '../services/scan_pipeline_stubs.dart';
import '../services/scan_readiness.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm_dialogs.dart';
import '../widgets/room_icons.dart';
import '../widgets/scan_guidance_banner.dart';
import '../widgets/scan_minimap.dart';
import '../widgets/scanner/scan_readiness_ui.dart';

/// Web / desktop path: simulated camera + heuristic detector with mobile HUD parity.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  static const double _requiredCoverageToFinish = 0.68;
  static const int _requiredStableQualityFrames = 5;
  static const int _scanTabIndex = 1;

  ScanPipeline? _pipeline;
  SimulatedScanInputProvider? _input;
  late final ScanFinishReadinessController _readiness;
  AppState? _appState;
  bool _scanTabActive = false;

  bool _isScanning = false;
  RoomLayoutModel? _layoutBeforeScan;
  bool _scanCompleteBeforeScan = false;
  bool _processing = false;
  double _coverage = 0;
  int _objects = 0;
  bool _canFinish = false;
  RoomLayoutModel? _liveLayout;
  double _quality = 0;
  double _latestYaw = 0;
  double _latestCamX = 3;
  double _latestCamZ = 3;
  bool _showHints = true;

  @override
  void initState() {
    super.initState();
    _readiness = ScanFinishReadinessController(
      requiredCoverage: _requiredCoverageToFinish,
      requiredStableQualityFrames: _requiredStableQualityFrames,
      qualityEnterThreshold: 0.50,
      qualityExitThreshold: 0.35,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    if (!identical(_appState, app)) {
      _appState?.removeListener(_onAppStateChanged);
      _appState = app;
      _appState!.addListener(_onAppStateChanged);
    }
    _syncScanTabVisibility();
  }

  void _onAppStateChanged() => _syncScanTabVisibility();

  void _syncScanTabVisibility() {
    final active = (_appState?.currentTab ?? 0) == _scanTabIndex;
    if (active == _scanTabActive) return;
    _scanTabActive = active;
    if (active) {
      _onScanTabVisible();
    } else {
      _onScanTabHidden();
    }
  }

  void _onScanTabHidden() {
    // IndexedStack keeps this screen mounted; stop simulated capture off-tab.
    unawaited(_input?.stop() ?? Future<void>.value());
  }

  void _onScanTabVisible() {
    if (_isScanning && _input != null) {
      unawaited(_input!.start(_onFrame));
    }
  }

  @override
  void dispose() {
    _appState?.removeListener(_onAppStateChanged);
    _input?.dispose();
    _pipeline?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final state = context.read<AppState>();
    if (state.hasLayoutWork || state.roomIsReady) {
      final ok = await confirmAction(
        context,
        title: 'Start a new scan?',
        body:
            'Scanning replaces the active room layout with a fresh scan seed. '
            'Cancel during the scan to restore what you have now.',
        confirmLabel: 'Start scan',
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    _layoutBeforeScan = state.activeRoomLayout;
    _scanCompleteBeforeScan = state.scanComplete;
    state.resetScan();

    await _input?.dispose();
    await _pipeline?.dispose();

    final pipeline = ScanPipeline(
      trackingProvider: CompositeTrackingProvider(
        roomBounds: RoomDimensions(
          lengthMeters: state.currentRoomData.gridCols * 0.6,
          widthMeters: state.currentRoomData.gridRows * 0.6,
          heightMeters: 2.7,
        ),
      ),
      qualityAnalyzer: BasicFrameQualityAnalyzer(),
      objectDetector: HeuristicObjectDetector(),
      fusionEngine: GridCoverageFusionEngine(),
    );
    final input = SimulatedScanInputProvider();
    final seed = RoomLayoutModel.emptyFromRoom(state.currentRoomData);

    await pipeline.initialize(seed);
    await input.initialize();
    state.applyScannedRoomLayout(seed);

    _pipeline = pipeline;
    _input = input;
    _readiness.reset();

    setState(() {
      _isScanning = true;
      _coverage = 0;
      _objects = 0;
      _canFinish = false;
      _liveLayout = seed;
    });

    await input.start(_onFrame);
  }

  Future<void> _cancel() async {
    await _input?.stop();
    await _pipeline?.dispose();
    _pipeline = null;
    _input = null;
    if (!mounted) return;
    final state = context.read<AppState>();
    final prior = _layoutBeforeScan;
    if (prior != null) {
      state.applyScannedRoomLayout(prior);
    }
    if (_scanCompleteBeforeScan) {
      state.restoreScanComplete(true);
    }
    _layoutBeforeScan = null;
    setState(() {
      _isScanning = false;
      _liveLayout = null;
    });
  }

  Future<void> _onFrame(ScanFrameInput frame) async {
    if (!_isScanning || _processing || _pipeline == null) return;
    _processing = true;
    try {
      final tick = await _pipeline!.processFrame(frame);
      if (!mounted) return;
      final state = context.read<AppState>();
      state.applyScannedRoomLayout(tick.layout);
      final coverage = tick.layout.coverageGrid.ratio();
      state.setScanProgress(max(state.scanProgress, coverage.clamp(0.0, 0.98)));
      final snap = _readiness.update(
        coverageRatio: coverage,
        quality: tick.frameResult.quality,
      );
      final tracking = tick.frameResult.tracking;
      setState(() {
        _liveLayout = tick.layout;
        _coverage = coverage;
        _objects = tick.layout.objects.length;
        _canFinish = snap.canFinish;
        _quality = snap.smoothedQuality;
        _latestYaw = tracking.cameraEulerDegrees.y;
        _latestCamX = tracking.cameraPosition.x;
        _latestCamZ = tracking.cameraPosition.z;
      });
    } finally {
      _processing = false;
    }
  }

  Future<void> _finish() async {
    if (!_isScanning || !_canFinish || _pipeline == null) return;
    final state = context.read<AppState>();
    await _input?.stop();
    final layout = _pipeline!.finalize();
    state.commitScannedRoomLayout(
      layout,
      inputProviderId: 'simulated',
      usedFallback: true,
    );
    await _pipeline?.dispose();
    await _input?.dispose();
    _pipeline = null;
    _input = null;
    if (!mounted) return;
    final conf = state.lastScanConfidence;
    final confPct = ((conf?.overallScore ?? 0) * 100).round();
    setState(() {
      _isScanning = false;
      _liveLayout = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Scan saved · $confPct% confidence — edit placements on Rig'),
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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final layout = _liveLayout ?? state.activeRoomLayout;
    final grid = layout?.coverageGrid;
    final target = grid == null || grid.coverage.isEmpty
        ? null
        : ScanGuidance.findWeakestSector(grid: grid, dimensions: layout!.dimensions);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  SvgIcon(RoomSvg.scan, size: 20, color: AppColors.cyan),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Room Scanner · Web simulator',
                      style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.amber.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Simulated',
                      style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF020508),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Center(
                      child: Text(
                        _isScanning
                            ? 'Simulated camera feed\nCoverage ${(_coverage * 100).round()}%'
                            : 'Tap Start to run a simulated room scan',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  if (_isScanning && grid != null && grid.coverage.isNotEmpty)
                    Positioned(
                      top: 24,
                      right: 24,
                      child: ScanMinimap(
                        grid: grid,
                        dimensions: layout!.dimensions,
                        cameraX: _latestCamX,
                        cameraZ: _latestCamZ,
                        yawDegrees: _latestYaw,
                        coverageRatio: _coverage,
                        target: target,
                      ),
                    ),
                  if (_isScanning && grid != null)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ScanReadinessMeter(
                            coverageRatio: _coverage,
                            qualityRatio: _quality,
                            stabilityRatio: (_readiness.stableQualityFrames / _requiredStableQualityFrames)
                                .clamp(0.0, 1.0),
                            hints: buildReadinessHints(
                              canFinishScan: _canFinish,
                              coverageRatio: _coverage,
                              qualityRatio: _quality,
                              stabilityRatio: (_readiness.stableQualityFrames / _requiredStableQualityFrames)
                                  .clamp(0.0, 1.0),
                              requiredCoverageToFinish: _requiredCoverageToFinish,
                              qualityEnterThreshold: _readiness.qualityEnterThreshold,
                              requiredStableQualityFrames: _requiredStableQualityFrames,
                              stableQualityFrames: _readiness.stableQualityFrames,
                              latestQualityIssues: const [],
                            ),
                            showHints: _showHints,
                            requiredCoverageToFinish: _requiredCoverageToFinish,
                            qualityEnterThreshold: _readiness.qualityEnterThreshold,
                            onToggleHints: () => setState(() => _showHints = !_showHints),
                          ),
                          if (target != null) ...[
                            const SizedBox(height: 8),
                            ScanDirectionCueCard(
                              cue: ScanGuidance.directionCue(
                                target: target,
                                cameraX: _latestCamX,
                                cameraZ: _latestCamZ,
                                yawDegrees: _latestYaw,
                                coverageReadyForFinish: _coverage >= _requiredCoverageToFinish,
                              ),
                              remainingCells: target.remainingCells,
                              scannedCells: target.scannedCells,
                              totalCells: target.totalCells,
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: _isScanning
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Objects $_objects · ${(_coverage * 100).round()}% coverage',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(onPressed: _cancel, child: const Text('Cancel')),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: _canFinish ? _finish : null,
                                child: Text(_canFinish ? 'Finish Scan' : 'Scanning…'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : FilledButton.icon(
                      onPressed: _start,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(state.scanComplete ? 'Rescan (simulated)' : 'Start simulated scan'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
