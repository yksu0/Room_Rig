// lib/widgets/spatial_bench_panel.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/room_model.dart';
import '../models/room_scale.dart';
import '../services/bench_layouts.dart';
import '../services/benchmark_validator.dart';
import '../services/spatial_analyzer.dart';
import '../theme/app_theme.dart';
import 'bench_panel_scaffold.dart';
import 'bench_room_views.dart';
import 'furniture_shapes.dart';
import 'glass_card.dart';
import 'room_icons.dart';
import 'score_ring.dart';

enum _SpatialStep { layout, analyze, results }
enum _LayoutView { heatmap, room3d }

class SpatialBenchPanel extends StatefulWidget {
  final ValueChanged<bool>? onOrbitDraggingChanged;

  const SpatialBenchPanel({super.key, this.onOrbitDraggingChanged});

  @override
  State<SpatialBenchPanel> createState() => _SpatialBenchPanelState();
}

class _SpatialBenchPanelState extends State<SpatialBenchPanel> {
  _SpatialStep _step = _SpatialStep.layout;
  BenchLayoutKind _layoutVariant = BenchLayoutKind.myRoom;
  BenchLayoutKind _analyzeVariant = BenchLayoutKind.myRoom;
  _LayoutView _layoutView = _LayoutView.heatmap;
  int _layoutOrbitResetNonce = 0;

  static const _defaultYaw = 0.7;
  static const _defaultPitch = 0.4;
  static const _defaultDistance = 16.0;

  bool _showResults = false;
  bool _ready = false;

  BenchLayouts? _layouts;
  int _seenFocusToken = 0;
  SpatialMetrics? _myRoomMetrics;
  SpatialMetrics? _improvedMetrics;
  SpatialMetrics? _sampleMetrics;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The bench reads the Rig; opening this tab must never write to it.
      _rebuild();
    });
  }

  void _rebuild() {
    _recompute(context.read<AppState>());
    if (mounted) setState(() {});
  }

  void _recompute(AppState state, {bool resetStep = true}) {
    final room = state.currentRoomData;
    final layouts = BenchLayoutBuilder.build(
      mode: BenchMode.spatial,
      roomFurniture: state.committedFurniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
    );
    _layouts = layouts;
    _myRoomMetrics = SpatialAnalyzer.evaluate(
      furniture: layouts.myRoom,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
    );
    _improvedMetrics = SpatialAnalyzer.evaluate(
      furniture: layouts.improved,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
    );
    _sampleMetrics = SpatialAnalyzer.evaluate(
      furniture: layouts.sample,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
    );
    _ready = true;
    if (resetStep) {
      _step = _SpatialStep.layout;
      final pending = state.benchLayoutFocusToken != _seenFocusToken;
      final kind = pending ? state.benchLayoutFocus : BenchLayoutKind.myRoom;
      _seenFocusToken = state.benchLayoutFocusToken;
      _layoutVariant = kind;
      _analyzeVariant = kind;
      _showResults = false;
    }
  }

  void _syncFromState(AppState state) {
    if (state.currentTab != benchTabIndex) return;
    if (state.benchLayoutFocusToken != _seenFocusToken) {
      _seenFocusToken = state.benchLayoutFocusToken;
      _layoutVariant = state.benchLayoutFocus;
      _analyzeVariant = state.benchLayoutFocus;
    }
    final fp = BenchLayoutBuilder.fingerprintOf(
      state.committedFurniture.where((f) => !f.hidden).toList(growable: false),
    );
    if (_layouts != null && fp == _layouts!.fingerprint) return;
    _recompute(state, resetStep: false);
  }

  List<FurnitureItem> _furnitureFor(BenchLayoutKind kind) =>
      _layouts?.forKind(kind) ?? const [];

  SpatialMetrics? get _activeMetrics {
    switch (_analyzeVariant) {
      case BenchLayoutKind.improved:
        return _improvedMetrics;
      case BenchLayoutKind.sample:
        return _sampleMetrics;
      case BenchLayoutKind.myRoom:
        return _myRoomMetrics;
    }
  }

  bool get _improvedIsNoOp => improvedLayoutIsNoOp(_layouts);

  int get _stepIndex => switch (_step) {
        _SpatialStep.layout => benchStepLayout,
        _SpatialStep.analyze => benchStepMiddle,
        _SpatialStep.results => benchStepResults,
      };

  _SpatialStep _stepFromIndex(int i) => switch (i) {
        benchStepLayout => _SpatialStep.layout,
        benchStepMiddle => _SpatialStep.analyze,
        _ => _SpatialStep.results,
      };

  String get _layoutHint => _layouts?.fellBackToSample ?? false
      ? 'Your Rig is empty, so this runs on the reference room. Add furniture in Rig to bench your own space.'
      : 'Estimates floor use from the furniture in your Rig right now, then compares an optimized rearrange of the same room.';

  List<String> _notesFor(BenchLayoutKind kind) {
    switch (kind) {
      case BenchLayoutKind.myRoom:
        if (_layouts?.fellBackToSample ?? false) {
          return const [
            'Nothing in the Rig yet — showing the reference room',
            'Add furniture on the Rig tab and this bench follows it',
          ];
        }
        return const [
          'Floor occupancy and walkways come from your Rig',
          'Move something on the Rig tab and the heatmap rebuilds here',
        ];
      case BenchLayoutKind.improved:
        final reasons = _layouts?.improvedReasons ?? const <String>[];
        return reasons.isEmpty
            ? const ['No rearrange found that opens the floor more than your current room']
            : reasons;
      case BenchLayoutKind.sample:
        return const [
          'Reference room used to sanity-check the analyzer',
          'Door aisle blocked — floor packed tight against walkways',
        ];
    }
  }

  void _setLayoutVariant(BenchLayoutKind next) {
    if (_layoutVariant == next) return;
    HapticFeedback.selectionClick();
    setState(() => _layoutVariant = next);
  }

  void _runAnalysis() {
    _recompute(context.read<AppState>(), resetStep: false);
    setState(() {
      _showResults = true;
      _step = _SpatialStep.results;
      _analyzeVariant = BenchLayoutKind.improved;
    });
  }

  BenchmarkValidation _validationForAnalyzeVariant(AppState state) {
    return BenchmarkValidator.validateLayout(
      furniture: _furnitureFor(_analyzeVariant),
      gridCols: state.currentRoomData.gridCols,
      gridRows: state.currentRoomData.gridRows,
      mode: 'spatial',
    );
  }

  BenchmarkValidation _validationForImproved(AppState state) {
    return BenchmarkValidator.validateLayout(
      furniture: _furnitureFor(BenchLayoutKind.improved),
      gridCols: state.currentRoomData.gridCols,
      gridRows: state.currentRoomData.gridRows,
      mode: 'spatial',
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (_ready) _syncFromState(state);
    if (!_ready) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator(color: AppColors.spatialColor)),
      );
    }

    final applyValidation = _validationForImproved(state);
    final applyBlocked = _improvedIsNoOp || applyValidation.hasHardLayoutConflicts;

    return BenchPanelScaffold(
      accentColor: AppColors.spatialColor,
      step: _stepIndex,
      stepLabels: const ['1. Layout', '2. Analyze', '3. Results'],
      resultsEnabled: _showResults,
      running: false,
      onStepChanged: (i) => setState(() => _step = _stepFromIndex(i)),
      layoutBody: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _layoutSection(state),
          const SizedBox(height: 8),
          Text(
            _layoutHint,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      middleBody: _analyzeSection(state),
      middleRunAction: BenchRunAction(
        buttonLabel: 'RUN SPATIAL ANALYSIS',
        icon: RoomSvg.scan,
        onRun: _runAnalysis,
      ),
      resultsExtra: _improvedIsNoOp
          ? benchImprovedNoOpBanner(
              message:
                  'Improved layout matches your room — walkways are already clear enough to leave in place.',
            )
          : null,
      resultsBody: _results(state),
      applyEnabled: !applyBlocked,
      applyBlockedReason: applyValidation.hasHardLayoutConflicts
          ? 'Fix overlaps or blocked doorways before applying.'
          : (_improvedIsNoOp ? 'Improved layout matches your room — nothing to apply.' : null),
      onApply: () async {
        if (!await confirmBenchApply(context, validation: applyValidation)) return;
        if (!context.mounted) return;
        state.applyFurnitureLayout(
          _furnitureFor(BenchLayoutKind.improved),
          markOptimized: true,
        );
        showBenchApplySnackBar(
          context,
          message: 'Improved walkway layout applied to Rig',
          accentColor: AppColors.spatialColor,
          onOpenRig: () => state.setTab(2),
        );
      },
      onRefresh: _rebuild,
    );
  }

  Widget _layoutSection(AppState state) {
    final notes = _notesFor(_layoutVariant);
    final room = state.currentRoomData;
    final furniture = _furnitureFor(_layoutVariant);
    final metrics = SpatialAnalyzer.evaluate(
      furniture: furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WALKWAYS',
          style: TextStyle(
            color: AppColors.spatialColor,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Estimated floor use — not a measured survey.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        BenchVariantChips(
          selected: _layoutVariant,
          onChanged: _setLayoutVariant,
          trailing: [
            BenchChip(
              label: 'Map',
              selected: _layoutView == _LayoutView.heatmap,
              color: AppColors.spatialColor,
              onTap: () => setState(() => _layoutView = _LayoutView.heatmap),
            ),
            BenchChip(
              label: '3D',
              selected: _layoutView == _LayoutView.room3d,
              color: AppColors.spatialColor,
              onTap: () => setState(() => _layoutView = _LayoutView.room3d),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                switch (_layoutVariant) {
                  BenchLayoutKind.myRoom => (_layouts?.fellBackToSample ?? false)
                      ? 'Reference room — your Rig is empty'
                      : 'Your room — ${_furnitureFor(BenchLayoutKind.myRoom).length} items from the Rig',
                  BenchLayoutKind.improved => 'Improved — your room, rearranged for walkways',
                  BenchLayoutKind.sample => 'Sample room — door aisle blocked, floor packed',
                },
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 12),
              if (_layoutView == _LayoutView.heatmap)
                _heatmapView(room: room, furniture: furniture, metrics: metrics)
              else
                SizedBox(
                  height: 280,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: ColoredBox(
                      color: AppColors.surface,
                      child: BenchOrbitShell(
                        initialYaw: _defaultYaw,
                        initialPitch: _defaultPitch,
                        initialDistance: _defaultDistance,
                        initialLookAtX: room.gridCols * 0.5,
                        initialLookAtZ: room.gridRows * 0.5,
                        roomWidth: room.gridCols.toDouble(),
                        roomDepth: room.gridRows.toDouble(),
                        resetNonce: _layoutOrbitResetNonce,
                        onDoubleTap: () {
                          HapticFeedback.lightImpact();
                          setState(() => _layoutOrbitResetNonce++);
                        },
                        onDragChanged: widget.onOrbitDraggingChanged,
                        builder: (cam) => CustomPaint(
                          painter: BenchRoom3DPainter(
                            roomWidth: room.gridCols.toDouble(),
                            roomDepth: room.gridRows.toDouble(),
                            roomHeight: 2.8,
                            gridCols: room.gridCols,
                            gridRows: room.gridRows,
                            yaw: cam.yaw,
                            pitch: cam.pitch,
                            distance: cam.distance,
                            lookAtX: cam.lookAtX,
                            lookAtZ: cam.lookAtZ,
                            furniture: furniture,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              ...notes.map(
                (n) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        switch (_layoutVariant) {
                          BenchLayoutKind.improved => Icons.check_circle_outline,
                          BenchLayoutKind.myRoom => Icons.grid_view_rounded,
                          BenchLayoutKind.sample => Icons.warning_amber_rounded,
                        },
                        size: 14,
                        color: switch (_layoutVariant) {
                          BenchLayoutKind.improved => AppColors.green,
                          BenchLayoutKind.myRoom => AppColors.cyan,
                          BenchLayoutKind.sample => AppColors.amber,
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          n,
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _analyzeSection(AppState state) {
    _syncFromState(state);
    final metrics = _activeMetrics;
    if (metrics == null) return const SizedBox.shrink();
    final room = state.currentRoomData;
    final furniture = _furnitureFor(_analyzeVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FLOOR HEATMAP',
          style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2),
        ),
        const SizedBox(height: 10),
        BenchVariantChips(
          selected: _analyzeVariant,
          onChanged: (v) => setState(() => _analyzeVariant = v),
        ),
        const SizedBox(height: 12),
        _heatmapView(room: room, furniture: furniture, metrics: metrics),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ScoreRing(score: metrics.utilizationScore, size: 72, color: AppColors.spatialColor, label: 'Use'),
            ScoreRing(score: metrics.accessibilityScore, size: 88, color: AppColors.cyan, label: 'Access'),
            ScoreRing(score: metrics.overallScore, size: 72, color: AppColors.green, label: 'Space'),
          ],
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Largest aisle ${RoomScale.formatCellsAsMeters(metrics.largestAisleCells)}  ·  '
                '${(metrics.walkableRatio * 100).round()}% walkable',
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(height: 8),
              ...metrics.notes.map(
                (n) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(n, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _heatmapView({
    required RoomData room,
    required List<FurnitureItem> furniture,
    required SpatialMetrics metrics,
  }) {
    return SizedBox(
      height: 280,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: _SpatialHeatPainter(
            occupied: metrics.occupied,
            cols: room.gridCols,
            rows: room.gridRows,
            furniture: furniture,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  Widget _results(AppState state) {
    final validation = _validationForAnalyzeVariant(state);
    final base = _myRoomMetrics!;
    final opt = _improvedMetrics!;
    final sample = _sampleMetrics;

    return BenchResultsCard(
      title: 'Walkway Space Bench',
      validation: validation,
      rings: [
        BenchScoreRingSpec(score: base.overallScore, color: AppColors.cyan, label: 'My Room'),
        BenchScoreRingSpec(score: opt.overallScore, color: AppColors.spatialColor, label: 'Improved'),
        if (sample != null)
          BenchScoreRingSpec(score: sample.overallScore, color: AppColors.amber, label: 'Sample')
        else
          BenchScoreRingSpec(score: state.spatialScore, color: AppColors.green, label: 'Score'),
      ],
      summaryText:
          'Walkable +${((opt.walkableRatio - base.walkableRatio) * 100).toStringAsFixed(0)} pts · '
          'Aisle +${(opt.largestAisleCells - base.largestAisleCells).toStringAsFixed(1)} cells · '
          'Space +${(opt.overallScore - base.overallScore).toStringAsFixed(0)}',
    );
  }

}

class _SpatialHeatPainter extends CustomPainter {
  final List<bool> occupied;
  final int cols;
  final int rows;
  final List<FurnitureItem> furniture;

  _SpatialHeatPainter({
    required this.occupied,
    required this.cols,
    required this.rows,
    required this.furniture,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = BenchRoom2DGeometry.fieldRectFor(
      size: size,
      gridCols: cols,
      gridRows: rows,
    );
    final cellW = rect.width / cols;
    final cellH = rect.height / rows;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      Paint()..color = AppColors.surfaceAlt,
    );

    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        final blocked = occupied[y * cols + x];
        canvas.drawRect(
          Rect.fromLTWH(rect.left + x * cellW, rect.top + y * cellH, cellW - 0.6, cellH - 0.6),
          Paint()
            ..color = blocked
                ? AppColors.red.withValues(alpha: 0.28)
                : AppColors.spatialColor.withValues(alpha: 0.16),
        );
      }
    }

    for (final f in furniture) {
      if (!FurnitureShapes.drawsMesh(f)) continue;
      FurnitureShapes.paintItemPlan(
        canvas,
        f,
        cell: Rect.fromLTWH(
          rect.left + f.gridX * cellW,
          rect.top + f.gridY * cellH,
          f.width * cellW,
          f.height * cellH,
        ),
        color: Colors.white,
        strong: true,
      );
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      Paint()
        ..color = AppColors.spatialColor.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _SpatialHeatPainter old) =>
      old.occupied != occupied || old.furniture != furniture;
}
