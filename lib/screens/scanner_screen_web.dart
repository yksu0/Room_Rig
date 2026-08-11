import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../models/scan_layout_model.dart';
import '../services/scan_input_provider.dart';
import '../services/scan_pipeline.dart';
import '../services/scan_pipeline_stubs.dart';
import '../services/scan_readiness.dart';
import '../theme/app_theme.dart';
import '../widgets/room_icons.dart';

/// Web / desktop Chrome path: camera + TFLite are unavailable, so we run the
/// same scan pipeline against a [SimulatedScanInputProvider].
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  static const double _requiredCoverageToFinish = 0.72;
  static const int _requiredStableQualityFrames = 5;

  ScanPipeline? _pipeline;
  SimulatedScanInputProvider? _input;
  late final ScanFinishReadinessController _readiness;

  bool _isScanning = false;
  bool _processing = false;
  String _status = 'Ready for simulated scan';
  double _coverage = 0;
  int _objects = 0;
  bool _canFinish = false;

  @override
  void initState() {
    super.initState();
    _readiness = ScanFinishReadinessController(
      requiredCoverage: _requiredCoverageToFinish,
      requiredStableQualityFrames: _requiredStableQualityFrames,
      qualityEnterThreshold: 0.55,
      qualityExitThreshold: 0.40,
    );
  }

  @override
  void dispose() {
    _input?.dispose();
    _pipeline?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final state = context.read<AppState>();
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
      _status = 'Simulated scan running… walk coverage builds automatically';
    });

    await input.start(_onFrame);
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
      setState(() {
        _coverage = coverage;
        _objects = tick.layout.objects.length;
        _canFinish = snap.canFinish;
        _status = snap.canFinish
            ? 'Coverage stable — tap Finish Scan'
            : 'Covering floor… ${(coverage * 100).round()}%';
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
    setState(() {
      _isScanning = false;
      _status =
          'Scan committed (${((conf?.overallScore ?? 0) * 100).round()}% confidence). Open Rig.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SvgIcon(RoomSvg.scan, size: 22, color: AppColors.cyan),
                  const SizedBox(width: 10),
                  const Text(
                    'Room Scanner',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Web preview uses a simulated camera feed. Mobile builds use the live camera + detector.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_status, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: _isScanning ? _coverage.clamp(0.05, 1.0) : (state.scanComplete ? 1.0 : 0),
                        backgroundColor: AppColors.border,
                        color: AppColors.cyan,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Coverage ${( _coverage * 100).round()}%  ·  Objects $_objects'
                        '${state.lastScanConfidence != null ? '  ·  Confidence ${(state.lastScanConfidence!.overallScore * 100).round()}%' : ''}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      const Spacer(),
                      if (!_isScanning)
                        FilledButton.icon(
                          onPressed: _start,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(state.scanComplete ? 'Rescan (simulated)' : 'Start simulated scan'),
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () async {
                                  await _input?.stop();
                                  await _pipeline?.dispose();
                                  setState(() {
                                    _isScanning = false;
                                    _status = 'Scan cancelled';
                                  });
                                },
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: _canFinish ? _finish : null,
                                child: const Text('Finish Scan'),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
