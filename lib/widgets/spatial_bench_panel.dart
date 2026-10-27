// lib/widgets/spatial_bench_panel.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/room_model.dart';
import '../models/room_scale.dart';
import '../services/bench_layouts.dart';
import '../services/benchmark_validator.dart';
import '../services/layout_share_image.dart';
import '../services/spatial_analyzer.dart';
import '../services/furniture_sprites.dart';
import '../theme/app_theme.dart';
import 'bench_panel_scaffold.dart';
import 'bench_room_views.dart';
import 'glass_card.dart';
import 'room_icons.dart';
import 'room_model_scene.dart';
import 'score_ring.dart';

enum _SpatialStep { layout, analyze, results }
enum _LayoutView { heatmap, room3d, model3d, compare }

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
  String? _layoutSyncKey;
  int _seenFocusToken = 0;
  SpatialMetrics? _myRoomMetrics;
  SpatialMetrics? _improvedMetrics;

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
    final left =
        state.resolveBenchCompareFurniture(state.benchCompareLeft) ?? const [];
    final rightIsAuto = state.benchCompareRight.isAutoRig;
    final right = rightIsAuto
        ? null
        : state.resolveBenchCompareFurniture(state.benchCompareRight);
    final layouts = BenchLayoutBuilder.build(
      mode: BenchMode.spatial,
      roomFurniture: state.committedFurniture,
      leftFurniture: left,
      rightFurniture: right,
      rightIsAutoRig: rightIsAuto,
      autoRigSeed: state.benchAutoRigSeedFurniture(forRight: true),
      leftCaption: state.benchCompareSourceLabel(state.benchCompareLeft),
      rightCaption: state.benchCompareSourceLabel(state.benchCompareRight),
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: state.optimizeWeights,
      alternateIndex: state.benchAlternateCursor,
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
    _ready = true;
    if (resetStep) {
      _step = _SpatialStep.layout;
      final pending = state.benchLayoutFocusToken != _seenFocusToken;
      var kind = pending ? state.benchLayoutFocus : BenchLayoutKind.myRoom;
      if (kind == BenchLayoutKind.sample) kind = BenchLayoutKind.myRoom;
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
      var kind = state.benchLayoutFocus;
      if (kind == BenchLayoutKind.sample) kind = BenchLayoutKind.myRoom;
      _layoutVariant = kind;
      _analyzeVariant = kind;
    }
    final key =
        '${benchCompareFingerprint(state)}|${state.optimizeWeights.cacheKey}|${state.benchAlternateCursor}';
    if (_layouts != null && _layoutSyncKey == key) return;
    _layoutSyncKey = key;
    _recompute(state, resetStep: false);
  }

  List<FurnitureItem> _furnitureFor(BenchLayoutKind kind) =>
      _layouts?.forKind(kind) ?? const [];

  SpatialMetrics? get _activeMetrics {
    switch (_analyzeVariant) {
      case BenchLayoutKind.improved:
        return _improvedMetrics;
      case BenchLayoutKind.sample:
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
      ? 'No baseline — this runs on the reference room. Add furniture in Rig, then Set baseline.'
      : 'Scores Baseline vs Auto-Rig (same engine as Rig Tools → Auto-Rig). Apply writes Auto-Rig onto your Rig.';

  List<String> _notesFor(BenchLayoutKind kind) {
    switch (kind) {
      case BenchLayoutKind.myRoom:
        if (_layouts?.fellBackToSample ?? false) {
          return const [
            'No baseline — showing the reference room',
            'Add furniture on Rig, then Set baseline (Compare)',
          ];
        }
        return const [
          'Pinned Baseline inventory for this lot',
          'Rig edits do not move Baseline until you Set baseline again',
        ];
      case BenchLayoutKind.improved:
        final reasons = _layouts?.improvedReasons ?? const <String>[];
        return reasons.isEmpty
            ? const ['No rearrange found that opens the floor more than Baseline']
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
      _layoutVariant = BenchLayoutKind.improved;
      _layoutView = _LayoutView.compare;
    });
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

    Future<void> applyImproved() async {
      if (!await confirmBenchApply(
        context,
        validation: applyValidation,
        fellBackToSample: _layouts?.fellBackToSample ?? false,
      )) {
        return;
      }
      if (!context.mounted) return;
      final before = List<FurnitureItem>.from(state.committedFurniture);
      state.applyFurnitureLayout(
        _furnitureFor(BenchLayoutKind.improved),
        markOptimized: true,
        lockMode: 'spatial',
      );
      final diff = summarizeLayoutDiff(before, state.furniture);
      final why = summarizeWhyWins(_layouts?.improvedReasons ?? const []);
      final room = state.currentRoomData;
      final after = List<FurnitureItem>.from(state.furniture);
      showBenchApplySnackBar(
        context,
        message: why.isEmpty ? 'Spatial applied · $diff' : 'Spatial applied · $diff · $why',
        accentColor: AppColors.spatialColor,
        onOpenRig: () => state.setTab(2),
        onKeepAsBaseline: () => state.keepAppliedAsBenchBaseline(),
        onShareImage: () => LayoutShareImage.shareBeforeAfter(
          gridCols: room.gridCols,
          gridRows: room.gridRows,
          before: before,
          after: after,
          footer: why.isEmpty ? diff : '$diff · $why',
        ),
      );
    }

    final resultsExtra = _improvedIsNoOp
        ? benchImprovedNoOpBanner(
            message:
                'Auto-Rig matches Baseline — walkways are already clear enough to leave in place.',
          )
        : benchWhyWinsCard(
            reasons: _layouts?.improvedReasons ?? const [],
            accentColor: AppColors.spatialColor,
          );

    return BenchPanelScaffold(
      accentColor: AppColors.spatialColor,
      step: _stepIndex,
      stepLabels: kBenchStepLabels,
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
      layoutRunAction: BenchRunAction(
        buttonLabel: 'RUN SPATIAL ANALYSIS',
        icon: RoomSvg.scan,
        onRun: _runAnalysis,
      ),
      middleBody: _analyzeSection(state),
      middleRunAction: BenchRunAction(
        buttonLabel: 'RUN SPATIAL ANALYSIS',
        icon: RoomSvg.scan,
        onRun: _runAnalysis,
      ),
      resultsExtra: resultsExtra,
      resultsBody: _results(state),
      applyEnabled: !applyBlocked && (_layouts?.rightIsAutoRig ?? true),
      applyBlockedReason: applyValidation.hasHardLayoutConflicts
          ? 'Fix overlaps or blocked doorways before applying.'
          : (_improvedIsNoOp ? 'Auto-Rig matches Baseline — nothing to apply.' : null),
      onApply: applyImproved,
      onRefresh: _rebuild,
      compareLayouts: _layouts,
      onTryAlternate: () => state.cycleBenchAlternate(),
      desktopControls: _desktopControls(state),
      desktopViewport: _desktopViewport(state),
      desktopInspect: _desktopInspect(
        state,
        resultsExtra: resultsExtra,
        onApply: applyBlocked ? null : applyImproved,
        applyBlockedReason: applyValidation.hasHardLayoutConflicts
            ? 'Fix overlaps or blocked doorways before applying.'
            : (_improvedIsNoOp ? 'Auto-Rig matches Baseline — nothing to apply.' : null),
      ),
    );
  }

  Widget _desktopControls(AppState state) {
    switch (_step) {
      case _SpatialStep.layout:
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
              ),
            BenchViewChips(
              children: [
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
                BenchChip(
                  label: 'Model',
                  selected: _layoutView == _LayoutView.model3d,
                  color: AppColors.spatialColor,
                  onTap: () => setState(() => _layoutView = _LayoutView.model3d),
                ),
                BenchChip(
                  label: 'Compare',
                  selected: _layoutView == _LayoutView.compare,
                  color: AppColors.spatialColor,
                  onTap: () => setState(() => _layoutView = _LayoutView.compare),
                ),
              ],
            ),
            BenchAutoRigMixBar(
              layouts: _layouts,
              onTryAlternate: () {
                context.read<AppState>().cycleBenchAlternate();
                setState(() {
                  _layoutVariant = BenchLayoutKind.improved;
                  _layoutView = _LayoutView.compare;
                });
              },
            ),
            const SizedBox(height: 12),
            Text(
              _layoutHint,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        );
      case _SpatialStep.analyze:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'FLOOR HEATMAP',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            BenchVariantChips(
              selected: _analyzeVariant,
              onChanged: (v) => setState(() => _analyzeVariant = v),
            ),
            const SizedBox(height: 8),
          ],
        );
      case _SpatialStep.results:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RESULTS',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Baseline vs Auto-Rig under your Rig Auto-Rig mix.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            BenchVariantChips(
              selected: _analyzeVariant,
              onChanged: (v) => setState(() => _analyzeVariant = v),
            ),
          ],
        );
    }
  }

  Widget _desktopViewport(AppState state) {
    switch (_step) {
      case _SpatialStep.layout:
        return _layoutViewportCanvas(state);
      case _SpatialStep.analyze:
      case _SpatialStep.results:
        return _analyzeViewportCanvas(state);
    }
  }

  Widget _desktopInspect(
    AppState state, {
    required Widget resultsExtra,
    required VoidCallback? onApply,
    required String? applyBlockedReason,
  }) {
    switch (_step) {
      case _SpatialStep.layout:
        final notes = _notesFor(_layoutVariant);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BenchInspectLockBlock(furniture: _furnitureFor(BenchLayoutKind.myRoom)),
            Text(
              _layoutView == _LayoutView.compare
                  ? 'Baseline vs Auto-Rig — same Auto-Rig mix as Rig'
                  : switch (_layoutVariant) {
                      BenchLayoutKind.myRoom =>
                        (_layouts?.fellBackToSample ?? false)
                            ? 'Reference room — no baseline inventory'
                            : 'Baseline — ${_furnitureFor(BenchLayoutKind.myRoom).length} pinned items',
                      BenchLayoutKind.improved =>
                        _layouts?.improvedCaption ?? 'Auto-Rig · from Baseline',
                      BenchLayoutKind.sample => 'Sample room — door aisle blocked, floor packed',
                    },
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            ...notes.map(
              (n) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
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
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      case _SpatialStep.analyze:
        final metrics = _activeMetrics;
        if (metrics == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
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
      case _SpatialStep.results:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            resultsExtra,
            const SizedBox(height: 12),
            _results(state),
            const SizedBox(height: 16),
            BenchApplyRow(
              onApply: onApply,
              onRefresh: _rebuild,
              blockedReason: applyBlockedReason,
            ),
          ],
        );
    }
  }

  Widget _layoutViewportCanvas(AppState state) {
    final room = state.currentRoomData;
    final furniture = _furnitureFor(_layoutVariant);
    final metrics = SpatialAnalyzer.evaluate(
      furniture: furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
    );

    if (_layoutView == _LayoutView.compare) {
      return BenchSideBySidePlans(
        gridCols: room.gridCols,
        gridRows: room.gridRows,
        myRoom: _furnitureFor(BenchLayoutKind.myRoom),
        improved: _furnitureFor(BenchLayoutKind.improved),
        accentColor: AppColors.spatialColor,
      );
    }
    if (_layoutView == _LayoutView.heatmap) {
      return _heatmapCanvas(room: room, furniture: furniture, metrics: metrics, expand: true);
    }
    if (_layoutView == _LayoutView.model3d) {
      return ColoredBox(
        color: AppColors.surface,
        child: RoomModelScene(room: room, furniture: furniture),
      );
    }
    return ColoredBox(
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
            roomHeight: room.heightMeters,
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
    );
  }

  Widget _analyzeViewportCanvas(AppState state) {
    final metrics = _activeMetrics;
    if (metrics == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.spatialColor));
    }
    final room = state.currentRoomData;
    final furniture = _furnitureFor(_analyzeVariant);
    return _heatmapCanvas(room: room, furniture: furniture, metrics: metrics, expand: true);
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
          ),
        BenchViewChips(
          children: [
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
            BenchChip(
              label: 'Model',
              selected: _layoutView == _LayoutView.model3d,
              color: AppColors.spatialColor,
              onTap: () => setState(() => _layoutView = _LayoutView.model3d),
            ),
            BenchChip(
              label: 'Compare',
              selected: _layoutView == _LayoutView.compare,
              color: AppColors.spatialColor,
              onTap: () => setState(() => _layoutView = _LayoutView.compare),
            ),
          ],
        ),
        BenchAutoRigMixBar(
          layouts: _layouts,
          onTryAlternate: () {
            context.read<AppState>().cycleBenchAlternate();
            setState(() {
              _layoutVariant = BenchLayoutKind.improved;
              _layoutView = _LayoutView.compare;
            });
          },
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _layoutView == _LayoutView.compare
                    ? 'Baseline vs Auto-Rig — same Auto-Rig mix as Rig'
                    : switch (_layoutVariant) {
                        BenchLayoutKind.myRoom =>
                          (_layouts?.fellBackToSample ?? false)
                              ? 'Reference room — no baseline inventory'
                              : 'Baseline — ${_furnitureFor(BenchLayoutKind.myRoom).length} pinned items',
                        BenchLayoutKind.improved =>
                          _layouts?.improvedCaption ??
                              'Auto-Rig · from Baseline',
                        BenchLayoutKind.sample =>
                          'Sample room — door aisle blocked, floor packed',
                      },
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              if (_layoutView == _LayoutView.compare)
                BenchSideBySidePlans(
                  gridCols: room.gridCols,
                  gridRows: room.gridRows,
                  myRoom: _furnitureFor(BenchLayoutKind.myRoom),
                  improved: _furnitureFor(BenchLayoutKind.improved),
                  accentColor: AppColors.spatialColor,
                )
              else if (_layoutView == _LayoutView.heatmap)
                _heatmapView(room: room, furniture: furniture, metrics: metrics)
              else if (_layoutView == _LayoutView.model3d)
                SizedBox(
                  height: 300,
                  child: RoomModelScene(
                    room: room,
                    furniture: furniture,
                  ),
                )
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
                            roomHeight: room.heightMeters,
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
        const SizedBox(height: 8),
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
      child: _heatmapCanvas(room: room, furniture: furniture, metrics: metrics),
    );
  }

  Widget _heatmapCanvas({
    required RoomData room,
    required List<FurnitureItem> furniture,
    required SpatialMetrics metrics,
    bool expand = false,
  }) {
    final canvas = Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(expand ? 0 : 16),
        border: expand ? null : Border.all(color: AppColors.border),
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
    );
    if (expand) {
      return ColoredBox(color: AppColors.surface, child: canvas);
    }
    return canvas;
  }

  Widget _results(AppState state) {
    final validation = _validationForImproved(state);
    final base = _myRoomMetrics!;
    final opt = _improvedMetrics!;
    final left = _layouts?.leftCaption ?? 'Left';
    final right = _layouts?.rightCaption ?? 'Right';

    final spaceDelta = (opt.overallScore - base.overallScore).round();
    final spaceLabel = spaceDelta >= 0 ? '+$spaceDelta' : '$spaceDelta';
    final why = (_layouts?.rightIsAutoRig ?? false)
        ? (_layouts?.improvedReasons ?? const <String>[])
        : const <String>[];
    return BenchResultsCard(
      title: 'Walkway Space Bench',
      accentColor: AppColors.spatialColor,
      validation: validation,
      compareHeader: 'Now comparing: $left vs $right',
      whyReasons: why,
      rings: [
        BenchScoreRingSpec(
          score: base.overallScore,
          color: AppColors.cyan,
          label: left,
        ),
        BenchScoreRingSpec(
          score: opt.overallScore,
          color: AppColors.spatialColor,
          label: right,
        ),
      ],
      summaryText:
          'Space $spaceLabel · '
          'Walkable +${((opt.walkableRatio - base.walkableRatio) * 100).toStringAsFixed(0)} pts · '
          'Aisle +${(opt.largestAisleCells - base.largestAisleCells).toStringAsFixed(1)} cells',
      metricRows: [
        BenchMetricComparisonRow(
          label: 'Space',
          left: base.overallScore,
          right: opt.overallScore,
          color: AppColors.spatialColor,
        ),
        BenchMetricComparisonRow(
          label: 'Walkable',
          left: base.walkableRatio * 100,
          right: opt.walkableRatio * 100,
          color: AppColors.cyan,
        ),
        BenchMetricComparisonRow(
          label: 'Aisle cells',
          left: (base.largestAisleCells / 20.0 * 100).clamp(0.0, 100.0),
          right: (opt.largestAisleCells / 20.0 * 100).clamp(0.0, 100.0),
          leftDisplay: base.largestAisleCells,
          rightDisplay: opt.largestAisleCells,
          color: AppColors.amber,
        ),
      ],
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
  }) : super(repaint: FurnitureSprites.revision);

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

    BenchFurnitureRenderer.paint2D(
      canvas,
      roomRect: rect,
      gridCols: cols,
      gridRows: rows,
      furniture: furniture,
    );

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
