// lib/screens/benchmark_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/room_model.dart';
import '../models/sim_room_bounds.dart';
import '../services/airflow_simulator.dart';
import '../services/bench_layouts.dart';
import '../services/benchmark_validator.dart';
import '../services/layout_share_image.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../widgets/active_room_chip.dart';
import '../widgets/airflow_voxel_painter.dart';
import '../widgets/room_status_strip.dart';
import '../widgets/bench_room_views.dart';
import '../widgets/bench_panel_scaffold.dart';
import '../widgets/chrome/bench_results_chrome.dart';
import '../widgets/ergonomics_bench_panel.dart';
import '../widgets/lighting_bench_panel.dart';
import '../widgets/room_icons.dart';
import '../widgets/spatial_bench_panel.dart';

enum _AirflowStep { layout, simulate, results }
enum _RoomViewMode { twoD, threeD, compare }

class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({super.key});

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends State<BenchmarkScreen> {
  bool _showResults = false;

  // Locks page scroll synchronously on pointer down (setState alone is too late on Android).
  final _scrollLocked = ValueNotifier(false);
  int _layoutOrbitResetNonce = 0;
  int _simOrbitResetNonce = 0;

  void _setOrbitDragging(bool dragging) {
    if (_scrollLocked.value != dragging) {
      _scrollLocked.value = dragging;
    }
  }

  _AirflowStep _airflowStep = _AirflowStep.layout;
  BenchLayoutKind _layoutVariant = BenchLayoutKind.myRoom;
  _RoomViewMode _roomViewMode = _RoomViewMode.twoD;
  AirflowVizMode _simVizMode = AirflowVizMode.orbit3D;
  bool _showParticles = true;
  bool _showHeatmap = true;
  BenchLayoutKind _simVariant = BenchLayoutKind.myRoom;

  BenchLayouts? _layouts;
  int _seenFocusToken = 0;
  AirflowSimSnapshot? _myRoomSim;
  AirflowSimSnapshot? _improvedSim;
  AirflowSimSnapshot? _sampleSim;
  bool _prototypeReady = false;
  String? _selectedFurnitureId;

  static const _defaultYaw = 0.75;
  static const _defaultPitch = 0.38;
  static const _defaultDistance = 16.0;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The bench reads the Rig; opening this tab must never write to it.
      _rebuildFromRoom(context.read<AppState>());
    });
  }

  @override
  void dispose() {
    _scrollLocked.dispose();
    super.dispose();
  }

  AirflowSimSnapshot? get _activeSim {
    switch (_simVariant) {
      case BenchLayoutKind.improved:
        return _improvedSim;
      case BenchLayoutKind.sample:
        return _sampleSim;
      case BenchLayoutKind.myRoom:
        return _myRoomSim;
    }
  }

  List<FurnitureItem> _furnitureFor(BenchLayoutKind kind) =>
      _layouts?.forKind(kind) ?? const [];

  List<FurnitureItem> _layoutFurnitureFor(AppState state) => _furnitureFor(_layoutVariant);

  /// Validate the layout the results header is actually showing, so the badge,
  /// the score rings, and the check rows all describe the same furniture.
  BenchmarkValidation _validationForSimVariant(AppState state) {
    final kind = _airflowStep == _AirflowStep.results
        ? BenchLayoutKind.improved
        : _simVariant;
    return BenchmarkValidator.validateLayout(
      furniture: _furnitureFor(kind),
      gridCols: state.currentRoomData.gridCols,
      gridRows: state.currentRoomData.gridRows,
      mode: 'airflow',
    );
  }

  /// Rebuilds every field from the furniture that is actually in the Rig.
  /// Safe to call during build: it only touches fields.
  void _recomputeLayouts(AppState state, {bool resetStep = true}) {
    final room = state.currentRoomData;
    final layouts = BenchLayoutBuilder.build(
      mode: BenchMode.airflow,
      roomFurniture: state.committedFurniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      weights: state.optimizeWeights,
      alternateIndex: state.benchAlternateCursor,
    );
    _layouts = layouts;
    final bounds = SimRoomBounds.fromRoomData(room);
    _myRoomSim = AirflowSimulator.build(
      furniture: layouts.myRoom,
      optimized: false,
      bounds: bounds,
    );
    _improvedSim = AirflowSimulator.build(
      furniture: layouts.improved,
      optimized: true,
      bounds: bounds,
    );
    _sampleSim = AirflowSimulator.build(
      furniture: layouts.sample,
      optimized: false,
      bounds: bounds,
    );
    _prototypeReady = true;
    if (resetStep) {
      _airflowStep = _AirflowStep.layout;
      // A pending focus request (the Rig's "Sim Prototype" button) wins once;
      // after that a reset lands back on the user's own room.
      final pending = state.benchLayoutFocusToken != _seenFocusToken;
      final kind = pending ? state.benchLayoutFocus : BenchLayoutKind.myRoom;
      _seenFocusToken = state.benchLayoutFocusToken;
      _layoutVariant = kind;
      _simVariant = kind;
      _showResults = false;
      if (kind == BenchLayoutKind.sample) {
        _roomViewMode = _RoomViewMode.twoD;
      }
    }
  }

  void _rebuildFromRoom(AppState state, {bool resetStep = true}) {
    _recomputeLayouts(state, resetStep: resetStep);
    if (mounted) setState(() {});
  }

  /// Picks up Rig edits so the particles always describe the current room.
  /// Called from build, so it must not call setState.
  void _syncFromState(AppState state) {
    if (state.currentTab != benchTabIndex) return;
    if (state.benchLayoutFocusToken != _seenFocusToken) {
      _seenFocusToken = state.benchLayoutFocusToken;
      _layoutVariant = state.benchLayoutFocus;
      _simVariant = state.benchLayoutFocus;
      _selectedFurnitureId = null;
      // Sample focus needs the single-pane caption, not the Compare strip.
      if (state.benchLayoutFocus == BenchLayoutKind.sample) {
        _roomViewMode = _RoomViewMode.twoD;
      }
    }
    final fp = BenchLayoutBuilder.fingerprintOf(
      state.committedFurniture.where((f) => !f.hidden).toList(growable: false),
    );
    if (benchLayoutsInSync(
      _layouts,
      furnitureFingerprint: fp,
      weightsCacheKey: state.optimizeWeights.cacheKey,
      alternateCursor: state.benchAlternateCursor,
    )) {
      return;
    }
    _recomputeLayouts(state, resetStep: false);
  }

  void _runBenchmark() {
    // Sims are sync — skip theater and open Results on Improved.
    _rebuildFromRoom(context.read<AppState>(), resetStep: false);
    setState(() {
      _showResults = true;
      _airflowStep = _AirflowStep.results;
      _simVariant = BenchLayoutKind.improved;
      _layoutVariant = BenchLayoutKind.improved;
      _roomViewMode = _RoomViewMode.compare;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final desktop = AppLayout.isDesktop(context);

    if (desktop) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDesktopHeader(state),
              Expanded(child: _buildModeBody(state, desktop: true)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.screen,
                AppSpace.sm,
                AppSpace.screen,
                AppSpace.xs,
              ),
              child: _buildMobileHeader(state),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.screen,
                  AppSpace.sm,
                  AppSpace.screen,
                  AppSpace.md,
                ),
                child: _buildModeBody(state, desktop: false),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeBody(AppState state, {required bool desktop}) {
    switch (state.benchmarkMode) {
      case 'lighting':
        return LightingBenchPanel(onOrbitDraggingChanged: _setOrbitDragging);
      case 'spatial':
        return SpatialBenchPanel(onOrbitDraggingChanged: _setOrbitDragging);
      case 'ergonomics':
        return ErgonomicsBenchPanel(onOrbitDraggingChanged: _setOrbitDragging);
      default:
        return _buildAirflowDesktop(state);
    }
  }

  Widget _buildDesktopHeader(AppState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'BENCH CENTER',
            style: TextStyle(
              color: AppColors.cyan,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.8,
            ),
          ),
          const SizedBox(height: 6),
          const Align(
            alignment: Alignment.centerLeft,
            child: ActiveRoomChip(),
          ),
          const SizedBox(height: 8),
          RoomStatusStrip(
            compact: true,
            onTapScores: () {
              // Stay on Bench — scores already drive the active mode body.
            },
          ),
          const SizedBox(height: 8),
          _buildModeScoreHero(state, expand: true),
          const SizedBox(height: 10),
          _buildModeSelector(state, compact: true),
        ],
      ),
    );
  }

  Widget _buildModeScoreHero(AppState state, {bool expand = false}) {
    final mode = state.benchmarkMode;
    final (label, score, prev, color) = switch (mode) {
      'lighting' => (
          'Lighting',
          state.lightingScore,
          state.baselineLightingScore,
          AppColors.lightingColor,
        ),
      'ergonomics' => (
          'Ergonomics',
          state.ergonomicsScore,
          state.baselineErgonomicsScore,
          AppColors.ergonomicsColor,
        ),
      'spatial' => (
          'Space',
          state.spatialScore,
          null,
          AppColors.spatialColor,
        ),
      _ => (
          'Airflow',
          state.airflowScore,
          state.baselineAirflowScore,
          AppColors.airflowColor,
        ),
    };
    // Only show delta when baseline differs (post-simulate).
    final showDelta = prev != null && (score - prev).abs() >= 0.5;
    return BenchScoreHero(
      label: label,
      score: score,
      previousScore: showDelta ? prev : null,
      color: color,
      expand: expand,
    );
  }

  Widget _buildMobileHeader(AppState state) {
    // Domain View/Tools/Inspect live on BenchPanelScaffold only — do not
    // duplicate Tools/Inspect triggers here.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'BENCH CENTER',
          style: TextStyle(
            color: AppColors.cyan,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.8,
          ),
        ),
        const SizedBox(height: 4),
        const Align(
          alignment: Alignment.centerLeft,
          child: ActiveRoomChip(),
        ),
        const SizedBox(height: 8),
        RoomStatusStrip(compact: true),
        const SizedBox(height: 8),
        _buildModeSelector(state, compact: true),
        const SizedBox(height: 8),
        _buildModeScoreHero(state, expand: true),
      ],
    );
  }

  Widget _buildModeSelector(AppState state, {bool compact = false}) {
    final modes = [
      ('airflow', 'Airflow', AppColors.airflowColor),
      ('lighting', 'Lighting', AppColors.lightingColor),
      ('ergonomics', 'Ergo', AppColors.ergonomicsColor),
      ('spatial', 'Space', AppColors.spatialColor),
    ];

    return BenchSegmentBar(
      gap: compact ? 5 : 6,
      children: [
        for (final mode in modes)
          BenchChip(
            label: mode.$2,
            selected: state.benchmarkMode == mode.$1,
            color: mode.$3,
            compact: compact,
            onTap: () {
              state.setBenchmarkMode(mode.$1);
              _setOrbitDragging(false);
            },
          ),
      ],
    );
  }

  Widget _buildAirflowDesktop(AppState state) {
    _syncFromState(state);
    if (!_prototypeReady) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.cyan),
      );
    }
    final desktop = AppLayout.isDesktop(context);
    if (!desktop) {
      // Same Rig-style View/Tools/Inspect sheets as other Bench domains.
      return BenchPanelScaffold(
        accentColor: AppColors.airflowColor,
        step: _airflowStepIndex,
        stepLabels: const ['1. Layout', '2. Voxel Sim', '3. Results'],
        resultsEnabled: _showResults,
        running: false,
        onStepChanged: (i) => setState(() {
          final next = _airflowStepFromIndex(i);
          if (next == _AirflowStep.results && !_showResults) return;
          _airflowStep = next;
        }),
        layoutRunAction: BenchRunAction(
          buttonLabel: 'RUN VOXEL AIRFLOW BENCH',
          icon: RoomSvg.scan,
          onRun: _runBenchmark,
          hint: _layouts?.fellBackToSample ?? false
              ? 'Rig is empty — My Room / Improved use the reference sample.'
              : 'Coarse voxel airflow on your Rig furniture, then Improved under your weight mix.',
        ),
        middleRunAction: BenchRunAction(
          buttonLabel: 'SEE RESULTS',
          icon: RoomSvg.trendingUp,
          onRun: () {
            setState(() {
              _simVariant = BenchLayoutKind.improved;
              _airflowStep = _AirflowStep.results;
              _showResults = true;
            });
          },
        ),
        desktopControls: _airflowDesktopControls(state),
        desktopViewport: _airflowDesktopViewport(state),
        desktopInspect: _airflowDesktopInspect(state),
        onApply: null,
        onRefresh: () => _rebuildFromRoom(state),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: _buildAirflowStepTabs(),
        ),
        Expanded(
          child: BenchDesktopShell(
            accentColor: AppColors.airflowColor,
            controls: _airflowDesktopControls(state),
            viewport: _airflowDesktopViewport(state),
            inspect: _airflowDesktopInspect(state),
          ),
        ),
      ],
    );
  }

  int get _airflowStepIndex => switch (_airflowStep) {
        _AirflowStep.layout => 0,
        _AirflowStep.simulate => 1,
        _AirflowStep.results => 2,
      };

  _AirflowStep _airflowStepFromIndex(int i) => switch (i) {
        1 => _AirflowStep.simulate,
        2 => _AirflowStep.results,
        _ => _AirflowStep.layout,
      };

  Widget _airflowDesktopControls(AppState state) {
    switch (_airflowStep) {
      case _AirflowStep.layout:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ROOM LAYOUT',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            BenchVariantChips(
              selected: _layoutVariant,
              onChanged: _setLayoutVariant,
              ),
            BenchViewChips(
              children: [
                BenchChip(
                  label: '2D',
                  selected: _roomViewMode == _RoomViewMode.twoD,
                  color: AppColors.cyan,
                  onTap: () => setState(() => _roomViewMode = _RoomViewMode.twoD),
                ),
                BenchChip(
                  label: '3D',
                  selected: _roomViewMode == _RoomViewMode.threeD,
                  color: AppColors.cyan,
                  onTap: () => setState(() => _roomViewMode = _RoomViewMode.threeD),
                ),
                BenchChip(
                  label: 'Compare',
                  selected: _roomViewMode == _RoomViewMode.compare,
                  color: AppColors.cyan,
                  onTap: () =>
                      setState(() => _roomViewMode = _RoomViewMode.compare),
                ),
              ],
            ),
            BenchAutoRigMixBar(
              layouts: _layouts,
              onTryAlternate: () {
                context.read<AppState>().cycleBenchAlternate();
                setState(() {
                  _layoutVariant = BenchLayoutKind.improved;
                  _roomViewMode = _RoomViewMode.compare;
                });
              },
            ),
            if (AppLayout.isDesktop(context)) ...[
              const SizedBox(height: 16),
              _buildPrimaryButton(
                label: 'RUN VOXEL AIRFLOW BENCH',
                icon: RoomSvg.scan,
                onTap: _runBenchmark,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              _layouts?.fellBackToSample ?? false
                  ? 'Rig is empty — My Room / Improved use the reference sample.'
                  : 'Coarse voxel airflow (not CFD) on your Rig furniture.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      case _AirflowStep.simulate:
      case _AirflowStep.results:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'VOXEL AIRFLOW FIELD',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            BenchVariantChips(
              selected: _simVariant,
              onChanged: (v) => setState(() => _simVariant = v),
            ),
            BenchViewChips(
              children: [
                BenchChip(
                  label: '2D',
                  selected: _simVizMode == AirflowVizMode.topDown2D,
                  color: AppColors.cyan,
                  onTap: () =>
                      setState(() => _simVizMode = AirflowVizMode.topDown2D),
                ),
                BenchChip(
                  label: '3D',
                  selected: _simVizMode == AirflowVizMode.orbit3D,
                  color: AppColors.cyan,
                  onTap: () =>
                      setState(() => _simVizMode = AirflowVizMode.orbit3D),
                ),
              ],
            ),
            const SizedBox(height: 8),
            BenchLayerToggles(
              showParticles: _showParticles,
              showHeatmap: _showHeatmap,
              onParticles: (v) => setState(() => _showParticles = v),
              onHeatmap: (v) => setState(() => _showHeatmap = v),
            ),
            const SizedBox(height: 8),
            const BenchLegend(caption: 'Airflow field'),
            if (_airflowStep == _AirflowStep.simulate &&
                AppLayout.isDesktop(context)) ...[
              const SizedBox(height: 16),
              _buildPrimaryButton(
                label: 'SEE RESULTS',
                icon: RoomSvg.trendingUp,
                onTap: () {
                  setState(() {
                    _simVariant = BenchLayoutKind.improved;
                    _airflowStep = _AirflowStep.results;
                    _showResults = true;
                  });
                },
              ),
            ],
          ],
        );
    }
  }

  Widget _airflowDesktopViewport(AppState state) {
    final room = state.currentRoomData;
    if (_airflowStep == _AirflowStep.layout) {
      final furniture = _layoutFurnitureFor(state);
      if (_roomViewMode == _RoomViewMode.compare) {
        return BenchSideBySidePlans(
          gridCols: room.gridCols,
          gridRows: room.gridRows,
          myRoom: _furnitureFor(BenchLayoutKind.myRoom),
          improved: _furnitureFor(BenchLayoutKind.improved),
        );
      }
      return ColoredBox(
        color: AppColors.surface,
        child: KeyedSubtree(
          key: ValueKey(
            '${_layoutVariant.name}_${_roomViewMode.name}_${_layouts?.fingerprint ?? ''}_${_layouts?.requestedAlternateIndex ?? 0}',
          ),
          child: _roomViewMode == _RoomViewMode.twoD
              ? _buildInteractive2DRoom(
                  gridCols: room.gridCols,
                  gridRows: room.gridRows,
                  furniture: furniture,
                )
              : BenchOrbitShell(
                  key: const ValueKey('bench_airflow_layout_orbit_desk'),
                  initialYaw: _defaultYaw,
                  initialPitch: _defaultPitch,
                  initialDistance: _defaultDistance,
                  initialLookAtX: room.gridCols * 0.5,
                  initialLookAtZ: room.gridRows * 0.5,
                  roomWidth: room.gridCols.toDouble(),
                  roomDepth: room.gridRows.toDouble(),
                  roomHeight: room.heightMeters,
                  resetNonce: _layoutOrbitResetNonce,
                  onDoubleTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _layoutOrbitResetNonce++);
                  },
                  onDragChanged: _setOrbitDragging,
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
      );
    }

    final sim = _activeSim;
    if (sim == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.cyan));
    }
    return _AirflowSimCanvas(
      sim: sim,
      furniture: _furnitureFor(_simVariant),
      vizMode: _simVizMode,
      showParticles: _showParticles,
      showHeatmap: _showHeatmap,
      orbitEnabled: _simVizMode == AirflowVizMode.orbit3D,
      roomWidth: sim.field.roomWidth,
      roomDepth: sim.field.roomDepth,
      roomHeight: sim.field.roomHeight,
      gridCols: sim.field.roomWidth.round(),
      gridRows: sim.field.roomDepth.round(),
      lookAtX: sim.field.roomWidth * 0.5,
      lookAtZ: sim.field.roomDepth * 0.5,
      resetNonce: _simOrbitResetNonce,
      animating: state.currentTab == benchTabIndex,
      onDoubleTap: () {
        HapticFeedback.lightImpact();
        setState(() => _simOrbitResetNonce++);
      },
      onDragChanged: _setOrbitDragging,
    );
  }

  Widget _airflowDesktopInspect(AppState state) {
    if (_airflowStep == _AirflowStep.layout) {
      final notes = _notesFor(_layoutVariant);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _roomViewMode == _RoomViewMode.compare
                ? 'My Room vs Improved'
                : switch (_layoutVariant) {
                    BenchLayoutKind.myRoom =>
                      (_layouts?.fellBackToSample ?? false)
                          ? 'Reference sample — Rig is empty (not your room)'
                          : 'Your room — ${_furnitureFor(BenchLayoutKind.myRoom).length} items from the Rig',
                    BenchLayoutKind.improved =>
                      _layouts?.improvedCaption ?? 'Improved · Auto-Rig',
                    BenchLayoutKind.sample =>
                      'Sample room — AC in a corner, weak coverage',
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
              child: Text(
                n,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (_selectedFurnitureId != null) ...[
            const SizedBox(height: 8),
            _buildInspectChip(
              furniture: _layoutFurnitureFor(state),
              mode: 'airflow',
            ),
          ],
        ],
      );
    }

    final metrics = _activeSim?.metrics;
    if (_airflowStep == _AirflowStep.simulate) {
      if (metrics == null) return const SizedBox.shrink();
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: _metricCard('Circulation', metrics.circulationScore, AppColors.cyan)),
              const SizedBox(width: 8),
              Expanded(
                child: _metricCard(
                  'Dead air',
                  metrics.deadZoneRatio * 100,
                  AppColors.red,
                  suffix: '%',
                  invertGood: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _metricCard('Exit flow', metrics.exitChannelScore, AppColors.airflowColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _metricCard(
                  'Heat pockets',
                  metrics.heatPocketRatio * 100,
                  AppColors.orange,
                  suffix: '%',
                  invertGood: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _metricCard('Work cool', metrics.workZoneCooling, AppColors.green)),
              const SizedBox(width: 8),
              Expanded(child: _metricCard('HVAC clear', metrics.hvacClearance, AppColors.cyan)),
            ],
          ),
          const SizedBox(height: 10),
          _buildPressureReadout(_furnitureFor(_simVariant)),
        ],
      );
    }

    // Results
    final validation = _validationForSimVariant(state);
    final noOp = improvedLayoutIsNoOp(_layouts);
    final blocked = noOp || validation.hasHardLayoutConflicts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (noOp)
          benchImprovedNoOpBanner(
            message:
                'Improved layout matches your room — airflow is already as good as the optimizer found.',
          )
        else
          benchWhyWinsCard(
            reasons: _layouts?.improvedReasons ?? const [],
            accentColor: AppColors.airflowColor,
          ),
        const SizedBox(height: 12),
        _buildAirflowResults(state),
        const SizedBox(height: 16),
        BenchApplyRow(
          onApply: blocked
              ? null
              : () async {
                  if (!await confirmBenchApply(
                    context,
                    validation: validation,
                    fellBackToSample: _layouts?.fellBackToSample ?? false,
                  )) {
                    return;
                  }
                  if (!mounted) return;
                  final before = List<FurnitureItem>.from(state.committedFurniture);
                  state.applyFurnitureLayout(
                    _furnitureFor(BenchLayoutKind.improved),
                    markOptimized: true,
                    lockMode: 'airflow',
                  );
                  final diff = summarizeLayoutDiff(before, state.furniture);
                  final why = summarizeWhyWins(_layouts?.improvedReasons ?? const []);
                  final room = state.currentRoomData;
                  final after = List<FurnitureItem>.from(state.furniture);
                  showBenchApplySnackBar(
                    context,
                    message: why.isEmpty
                        ? 'Airflow applied · $diff'
                        : 'Airflow applied · $diff · $why',
                    accentColor: AppColors.cyan,
                    onOpenRig: () => state.setTab(2),
                    onShareImage: () => LayoutShareImage.shareBeforeAfter(
                      gridCols: room.gridCols,
                      gridRows: room.gridRows,
                      before: before,
                      after: after,
                      footer: why.isEmpty ? diff : '$diff · $why',
                    ),
                  );
                },
          onRefresh: () => _rebuildFromRoom(state),
          blockedReason: validation.hasHardLayoutConflicts
              ? 'Fix overlaps or blocked doorways before applying.'
              : (noOp ? 'Improved layout matches your room — nothing to apply.' : null),
        ),
      ],
    );
  }


  Widget _buildAirflowStepTabs() {
    final steps = [
      (_AirflowStep.layout, '1. Layout'),
      (_AirflowStep.simulate, '2. Voxel Sim'),
      (_AirflowStep.results, '3. Results'),
    ];
    return Row(
      children: steps.map((s) {
        final selected = _airflowStep == s.$1;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              if (s.$1 == _AirflowStep.results && !_showResults) return;
              setState(() => _airflowStep = s.$1);
            },
            child: Container(
              margin: EdgeInsets.only(right: s.$1 == _AirflowStep.results ? 0 : 8),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: selected ? AppColors.cyan.withValues(alpha: 0.12) : AppColors.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected ? AppColors.cyan : AppColors.border),
              ),
              child: Text(
                s.$2,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? AppColors.cyan : AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }


  void _setLayoutVariant(BenchLayoutKind next) {
    if (_layoutVariant == next) return;
    HapticFeedback.selectionClick();
    setState(() {
      _layoutVariant = next;
      _selectedFurnitureId = null;
    });
  }

  List<String> _notesFor(BenchLayoutKind kind) {
    switch (kind) {
      case BenchLayoutKind.myRoom:
        if (_layouts?.fellBackToSample ?? false) {
          return const [
            'Rig empty — showing the reference sample room (not yours)',
            'Add furniture on Rig; Bench Improved will use your Auto-Rig sliders',
          ];
        }
        return const [
          'Every AC, fan, blocker and heat source comes from your Rig',
          'Move something on the Rig tab and the field rebuilds here',
        ];
      case BenchLayoutKind.improved:
        final reasons = _layouts?.improvedReasons ?? const <String>[];
        return reasons.isEmpty
            ? const ['No rearrange found that scores better than your current room']
            : reasons;
      case BenchLayoutKind.sample:
        return const [
          'Reference room used to sanity-check the simulator',
          'AC buried in a corner — throw covers only a sliver of the floor',
        ];
    }
  }

  Widget _buildInteractive2DRoom({
    required int gridCols,
    required int gridRows,
    required List<FurnitureItem> furniture,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final hit = BenchRoom2DGeometry.hitTest(
              local: details.localPosition,
              size: size,
              gridCols: gridCols,
              gridRows: gridRows,
              furniture: furniture,
            );
            HapticFeedback.selectionClick();
            setState(() {
              if (hit == null) {
                _selectedFurnitureId = null;
              } else if (_selectedFurnitureId == hit.id) {
                _selectedFurnitureId = null;
              } else {
                _selectedFurnitureId = hit.id;
              }
            });
          },
          child: CustomPaint(
            painter: BenchRoom2DPainter(
              gridCols: gridCols,
              gridRows: gridRows,
              furniture: furniture,
              selectedId: _selectedFurnitureId,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }

  Widget _buildInspectChip({
    required List<FurnitureItem> furniture,
    required String mode,
  }) {
    FurnitureItem? item;
    for (final f in furniture) {
      if (f.id == _selectedFurnitureId) {
        item = f;
        break;
      }
    }
    if (item == null) return const SizedBox.shrink();
    final color = categoryColor(item.category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.touch_app_rounded, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.name.toUpperCase()} · ${item.category}',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  benchInspectBlurb(item, mode: mode),
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildAirflowResults(AppState state) {
    final base = _myRoomSim!.metrics;
    final opt = _improvedSim!.metrics;
    final validation = _validationForSimVariant(state);
    final delta = (opt.circulationScore - base.circulationScore).round();
    final deltaLabel = delta >= 0 ? '+$delta' : '$delta';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'AIRFLOW BENCH RESULTS',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 12),
        BenchResultsCard(
          title: 'Voxel Circulation Bench',
          accentColor: AppColors.airflowColor,
          validation: validation,
          whyReasons: _layouts?.improvedReasons ?? const [],
          rings: [
            BenchScoreRingSpec(score: base.circulationScore, color: AppColors.cyan, label: 'My Room'),
            BenchScoreRingSpec(score: opt.circulationScore, color: AppColors.airflowColor, label: 'Improved'),
          ],
          summaryText:
              'Circulation $deltaLabel · '
              'Dead zones ${((base.deadZoneRatio - opt.deadZoneRatio) * 100).toStringAsFixed(0)} pts · '
              'Heat ${((base.heatPocketRatio - opt.heatPocketRatio) * 100).toStringAsFixed(0)} pts',
        ),
        const SizedBox(height: 12),
        _ComparisonRow(
          label: 'Circulation',
          before: base.circulationScore,
          after: opt.circulationScore,
          color: AppColors.airflowColor,
        ),
        const SizedBox(height: 10),
        _ComparisonRow(
          label: 'Dead zones',
          before: base.deadZoneRatio * 100,
          after: opt.deadZoneRatio * 100,
          color: AppColors.red,
          lowerIsBetter: true,
        ),
        const SizedBox(height: 10),
        _ComparisonRow(
          label: 'Heat pockets',
          before: base.heatPocketRatio * 100,
          after: opt.heatPocketRatio * 100,
          color: AppColors.amber,
          lowerIsBetter: true,
        ),
      ],
    );
  }

  Widget _metricCard(String label, double value, Color color, {String suffix = '', bool invertGood = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            '${value.toStringAsFixed(0)}$suffix',
            style: TextStyle(
              color: invertGood && value > 20 ? AppColors.red : color,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required String icon,
    required VoidCallback? onTap,
  }) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: disabled ? null : AppColors.accentGradient,
          color: disabled ? AppColors.card : null,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: disabled ? AppColors.border : Colors.transparent),
          boxShadow: disabled ? [] : [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.35), blurRadius: 18)],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgIcon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPressureReadout(List<FurnitureItem> furniture) {
    final pressure = AirflowSimulator.summarizePressure(furniture);
    final balanceColor = pressure.isBalanced
        ? AppColors.textSecondary
        : (pressure.delta > 0 ? AppColors.green : AppColors.orange);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ROOM PRESSURE',
            style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _metricCard('Supply (in)', pressure.supplyStrength, AppColors.green),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _metricCard('Extract (out)', pressure.extractStrength, AppColors.orange),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _metricCard('Δ pressure', pressure.delta.abs(), balanceColor, suffix: pressure.isBalanced ? '' : (pressure.delta > 0 ? ' +' : ' −')),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${pressure.balanceLabel} · ${pressure.leakHint}',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  final String label;
  final double before;
  final double after;
  final Color color;
  final bool lowerIsBetter;

  const _ComparisonRow({
    required this.label,
    required this.before,
    required this.after,
    required this.color,
    this.lowerIsBetter = false,
  });

  @override
  Widget build(BuildContext context) {
    final delta = after - before;
    final good = lowerIsBetter ? delta <= 0 : delta >= 0;
    final display = lowerIsBetter ? -delta : delta;
    return Row(
      children: [
        SizedBox(width: 88, child: Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 12))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                Container(height: 8, color: AppColors.border),
                FractionallySizedBox(
                  widthFactor: (before / 100).clamp(0.0, 1.0),
                  child: Container(height: 8, color: AppColors.textMuted),
                ),
                FractionallySizedBox(
                  widthFactor: (after / 100).clamp(0.0, 1.0),
                  child: Container(height: 8, color: color.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${good ? '+' : ''}${display.toStringAsFixed(1)}',
          style: TextStyle(
            color: good ? AppColors.green : AppColors.red,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// Isolated airflow field + orbit — particle ticker rebuilds only this subtree.
class _AirflowSimCanvas extends StatefulWidget {
  final AirflowSimSnapshot sim;
  final List<FurnitureItem> furniture;
  final AirflowVizMode vizMode;
  final bool orbitEnabled;
  final double roomWidth;
  final double roomDepth;
  final double roomHeight;
  final int gridCols;
  final int gridRows;
  final double lookAtX;
  final double lookAtZ;
  final int resetNonce;
  final bool animating;
  final bool showParticles;
  final bool showHeatmap;
  final VoidCallback? onDoubleTap;
  final ValueChanged<bool>? onDragChanged;

  const _AirflowSimCanvas({
    required this.sim,
    required this.furniture,
    required this.vizMode,
    required this.orbitEnabled,
    required this.roomWidth,
    required this.roomDepth,
    required this.roomHeight,
    required this.gridCols,
    required this.gridRows,
    required this.lookAtX,
    required this.lookAtZ,
    required this.resetNonce,
    required this.animating,
    this.showParticles = true,
    this.showHeatmap = true,
    this.onDoubleTap,
    this.onDragChanged,
  });

  @override
  State<_AirflowSimCanvas> createState() => _AirflowSimCanvasState();
}

class _AirflowSimCanvasState extends State<_AirflowSimCanvas>
    with SingleTickerProviderStateMixin {
  static const _defaultYaw = 0.75;
  static const _defaultPitch = 0.38;
  static const _defaultDistance = 16.0;

  late AnimationController _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      duration: const Duration(milliseconds: 16),
      vsync: this,
    )..addListener(_stepParticles);
    if (widget.animating) _ticker.repeat();
  }

  @override
  void didUpdateWidget(_AirflowSimCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animating && !_ticker.isAnimating) {
      _ticker.repeat();
    } else if (!widget.animating && _ticker.isAnimating) {
      _ticker.stop();
    }
  }

  void _stepParticles() {
    if (!mounted || !widget.animating) return;
    AirflowSimulator.stepParticles(
      widget.sim,
      dt: 0.045,
      time: _ticker.lastElapsedDuration?.inMilliseconds.toDouble() ?? 0,
    );
    // Ticker drives CustomPaint.repaint — do not setState (would rebuild orbit shell).
  }

  double get _timeMs => _ticker.lastElapsedDuration?.inMilliseconds.toDouble() ?? 0;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Widget _paintField(BenchOrbitCamera cam) {
    return AnimatedBuilder(
      animation: _ticker,
      builder: (context, child) => CustomPaint(
        painter: AirflowVoxelPainter(
          snapshot: widget.sim,
          furniture: widget.furniture,
          vizMode: widget.vizMode,
          yaw: cam.yaw,
          pitch: cam.pitch,
          distance: cam.distance,
          lookAtX: cam.lookAtX,
          lookAtZ: cam.lookAtZ,
          time: _timeMs,
          gridCols: widget.gridCols,
          gridRows: widget.gridRows,
          showVoxels: widget.showHeatmap,
          showParticles: widget.showParticles,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.vizMode == AirflowVizMode.topDown2D) {
      return RepaintBoundary(
        child: _paintField(
          BenchOrbitCamera(
            yaw: _defaultYaw,
            pitch: _defaultPitch,
            distance: _defaultDistance,
            lookAtX: widget.lookAtX,
            lookAtZ: widget.lookAtZ,
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: BenchOrbitShell(
        key: const ValueKey('bench_airflow_orbit'),
        enabled: widget.orbitEnabled,
        initialYaw: _defaultYaw,
        initialPitch: _defaultPitch,
        initialDistance: _defaultDistance,
        initialLookAtX: widget.lookAtX,
        initialLookAtZ: widget.lookAtZ,
        roomWidth: widget.roomWidth,
        roomDepth: widget.roomDepth,
        roomHeight: widget.roomHeight,
        resetNonce: widget.resetNonce,
        onDoubleTap: widget.onDoubleTap,
        onDragChanged: widget.onDragChanged,
        builder: _paintField,
      ),
    );
  }
}
