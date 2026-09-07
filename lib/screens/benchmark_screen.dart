// lib/screens/benchmark_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/room_model.dart';
import '../services/airflow_simulator.dart';
import '../services/bench_layouts.dart';
import '../services/benchmark_validator.dart';
import '../theme/app_theme.dart';
import '../widgets/airflow_voxel_painter.dart';
import '../widgets/bench_room_views.dart';
import '../widgets/bench_panel_scaffold.dart';
import '../widgets/benchmark_validation_card.dart';
import '../widgets/ergonomics_bench_panel.dart';
import '../widgets/glass_card.dart';
import '../widgets/lighting_bench_panel.dart';
import '../widgets/room_icons.dart';
import '../widgets/score_ring.dart';
import '../widgets/spatial_bench_panel.dart';

enum _AirflowStep { layout, simulate, results }
enum _RoomViewMode { twoD, threeD }

class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({super.key});

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends State<BenchmarkScreen> {

  bool _isRunning = false;
  double _runProgress = 0.0;
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
    );
    _layouts = layouts;
    _myRoomSim = AirflowSimulator.build(furniture: layouts.myRoom, optimized: false);
    _improvedSim = AirflowSimulator.build(furniture: layouts.improved, optimized: true);
    _sampleSim = AirflowSimulator.build(furniture: layouts.sample, optimized: false);
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
    }
    final fp = BenchLayoutBuilder.fingerprintOf(
      state.committedFurniture.where((f) => !f.hidden).toList(growable: false),
    );
    if (_layouts != null && fp == _layouts!.fingerprint) return;
    _recomputeLayouts(state, resetStep: false);
  }

  Future<void> _runBenchmark() async {
    // Always start from the room as it stands right now.
    _rebuildFromRoom(context.read<AppState>(), resetStep: false);
    setState(() {
      _isRunning = true;
      _showResults = false;
      _runProgress = 0;
      _airflowStep = _AirflowStep.simulate;
      _simVariant = BenchLayoutKind.myRoom;
    });

    for (int i = 1; i <= 24; i++) {
      await Future.delayed(const Duration(milliseconds: 90));
      if (!mounted) return;
      setState(() {
        _runProgress = i / 24;
        // Flip to the improved field mid-run so both are seen.
        if (i == 12) _simVariant = BenchLayoutKind.improved;
      });
    }

    if (!mounted) return;
    // Bench → Rig only happens on the explicit Apply action below the results,
    // so finishing a run never silently replaces the user's layout.
    setState(() {
      _isRunning = false;
      _showResults = true;
      _airflowStep = _AirflowStep.results;
      _simVariant = BenchLayoutKind.improved;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAirflow = state.benchmarkMode == 'airflow';
    final isLighting = state.benchmarkMode == 'lighting';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ValueListenableBuilder<bool>(
          valueListenable: _scrollLocked,
          builder: (context, scrollLocked, _) {
            return SingleChildScrollView(
              physics: scrollLocked ? const NeverScrollableScrollPhysics() : null,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 20),
                  _buildModeSelector(state),
                  const SizedBox(height: 20),
                  if (isAirflow)
                    ..._buildAirflowPrototype(state)
                  else if (isLighting)
                    LightingBenchPanel(onOrbitDraggingChanged: _setOrbitDragging)
                  else if (state.benchmarkMode == 'spatial')
                    SpatialBenchPanel(onOrbitDraggingChanged: _setOrbitDragging)
                  else
                    ErgonomicsBenchPanel(onOrbitDraggingChanged: _setOrbitDragging),
                  const SizedBox(height: 32),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'BENCHMARK CENTER',
          style: TextStyle(color: AppColors.cyan, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 3),
        ),
        const Text(
          'Room Stress Tests',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 26, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  Widget _buildModeSelector(AppState state) {
    final modes = [
      ('airflow', RoomSvg.airflow, 'Airflow', AppColors.airflowColor),
      ('lighting', RoomSvg.lightbulb, 'Lighting', AppColors.lightingColor),
      ('ergonomics', RoomSvg.ergonomics, 'Ergo', AppColors.ergonomicsColor),
      ('spatial', RoomSvg.home, 'Space', AppColors.spatialColor),
    ];

    return Row(
      children: modes.map((m) {
        final isSelected = state.benchmarkMode == m.$1;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              state.setBenchmarkMode(m.$1);
              _setOrbitDragging(false);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(right: m.$1 == 'spatial' ? 0 : 6),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? m.$4.withValues(alpha: 0.15) : AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isSelected ? m.$4 : AppColors.border, width: isSelected ? 1.5 : 1),
                boxShadow: isSelected ? [BoxShadow(color: m.$4.withValues(alpha: 0.2), blurRadius: 12)] : [],
              ),
              child: Column(
                children: [
                  SvgIcon(m.$2, size: 22, color: isSelected ? m.$4 : AppColors.textMuted),
                  const SizedBox(height: 5),
                  Text(
                    m.$3,
                    style: TextStyle(
                      color: isSelected ? m.$4 : AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  List<Widget> _buildAirflowPrototype(AppState state) {
    _syncFromState(state);

    if (!_prototypeReady) {
      return [
        const Center(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: CircularProgressIndicator(color: AppColors.cyan),
          ),
        ),
      ];
    }

    return [
      _buildAirflowStepTabs(),
      const SizedBox(height: 16),
      if (_airflowStep == _AirflowStep.layout) ...[
        _buildLayoutSection(state),
        const SizedBox(height: 16),
        _buildPrimaryButton(
          label: 'RUN VOXEL AIRFLOW BENCH',
          icon: RoomSvg.scan,
          onTap: _isRunning ? null : () => _runBenchmark(),
        ),
        const SizedBox(height: 8),
        Text(
          _layouts?.fellBackToSample ?? false
              ? 'Your Rig is empty, so this runs on the reference room. Add furniture in Rig to bench your own space.'
              : 'Simulates the furniture in your Rig right now, then compares it against an optimized rearrange of the same room.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
      if (_airflowStep == _AirflowStep.simulate || (_airflowStep == _AirflowStep.results && _isRunning)) ...[
        _buildSimulationSection(state),
        if (_isRunning) ...[
          const SizedBox(height: 16),
          _buildProgressBar(),
        ],
      ],
      if (_airflowStep == _AirflowStep.results && !_isRunning) ...[
        _buildSimulationSection(state),
        const SizedBox(height: 20),
        _buildAirflowResults(state),
        const SizedBox(height: 16),
        Builder(
          builder: (context) {
            final validation = _validationForSimVariant(state);
            final noOp = improvedLayoutIsNoOp(_layouts);
            final blocked = noOp || validation.hasHardLayoutConflicts;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (noOp) ...[
                  benchImprovedNoOpBanner(
                    message:
                        'Improved layout matches your room — airflow is already as good as the optimizer found.',
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: _buildPrimaryButton(
                        label: 'APPLY IMPROVED LAYOUT',
                        icon: RoomSvg.star,
                        onTap: blocked
                            ? null
                            : () async {
                                if (!await confirmBenchApply(context, validation: validation)) return;
                                if (!context.mounted) return;
                                state.applyFurnitureLayout(
                                  _furnitureFor(BenchLayoutKind.improved),
                                  markOptimized: true,
                                );
                                _showAppliedToRigSnack(
                                  state,
                                  message: 'Improved airflow layout applied to Rig',
                                );
                              },
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildIconButton(
                      icon: Icons.refresh_rounded,
                      onTap: () {
                        _rebuildFromRoom(state);
                      },
                    ),
                  ],
                ),
                if (blocked) ...[
                  const SizedBox(height: 8),
                  Text(
                    validation.hasHardLayoutConflicts
                        ? 'Fix overlaps or blocked doorways before applying.'
                        : 'Improved layout matches your room — nothing to apply.',
                    style: TextStyle(
                      color: AppColors.amber.withValues(alpha: 0.95),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
      if (_airflowStep == _AirflowStep.simulate && !_isRunning) ...[
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildPrimaryButton(
                label: 'COMPARE & FINISH',
                icon: RoomSvg.trendingUp,
                onTap: () {
                  setState(() {
                    _simVariant = BenchLayoutKind.improved;
                    _airflowStep = _AirflowStep.results;
                    _showResults = true;
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            _buildIconButton(
              icon: Icons.refresh_rounded,
              onTap: () {
                _rebuildFromRoom(state);
              },
            ),
          ],
        ),
      ],
    ];
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
              if (s.$1 == _AirflowStep.results && !_showResults && !_isRunning) return;
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

  Widget _buildLayoutSection(AppState state) {
    final furniture = _layoutFurnitureFor(state);
    final room = state.currentRoomData;
    final notes = _notesFor(_layoutVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ROOM LAYOUT',
          style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(
              'My Room',
              _layoutVariant == BenchLayoutKind.myRoom,
              AppColors.cyan,
              () => _setLayoutVariant(BenchLayoutKind.myRoom),
            ),
            _chip(
              'Improved',
              _layoutVariant == BenchLayoutKind.improved,
              AppColors.green,
              () => _setLayoutVariant(BenchLayoutKind.improved),
            ),
            _chip(
              'Sample',
              _layoutVariant == BenchLayoutKind.sample,
              AppColors.amber,
              () => _setLayoutVariant(BenchLayoutKind.sample),
            ),
            _chip('2D', _roomViewMode == _RoomViewMode.twoD, AppColors.cyan, () {
              setState(() => _roomViewMode = _RoomViewMode.twoD);
            }),
            _chip('3D', _roomViewMode == _RoomViewMode.threeD, AppColors.cyan, () {
              setState(() => _roomViewMode = _RoomViewMode.threeD);
            }),
          ],
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SvgIcon(RoomSvg.house, size: 18, color: AppColors.cyan),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      switch (_layoutVariant) {
                        BenchLayoutKind.myRoom => (_layouts?.fellBackToSample ?? false)
                            ? 'Reference room — your Rig is empty'
                            : 'Your room — ${_furnitureFor(BenchLayoutKind.myRoom).length} items from the Rig',
                        BenchLayoutKind.improved => 'Improved — your room, rearranged for airflow',
                        BenchLayoutKind.sample => 'Sample room — AC in a corner, weak coverage',
                      },
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 300,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: ColoredBox(
                    color: AppColors.surface,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: KeyedSubtree(
                        key: ValueKey(
                          '${_layoutVariant.name}_${_roomViewMode.name}_${_layouts?.fingerprint ?? ''}',
                        ),
                        child: _roomViewMode == _RoomViewMode.twoD
                            ? _buildInteractive2DRoom(
                                gridCols: room.gridCols,
                                gridRows: room.gridRows,
                                furniture: furniture,
                              )
                            : BenchOrbitShell(
                                key: const ValueKey('bench_airflow_layout_orbit'),
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
                                onDragChanged: _setOrbitDragging,
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
                ),
              ),
              if (_selectedFurnitureId != null) ...[
                const SizedBox(height: 10),
                _buildInspectChip(
                  furniture: furniture,
                  mode: 'airflow',
                ),
              ],
              const SizedBox(height: 12),
              ...notes.map(
                (n) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _layoutVariant == BenchLayoutKind.sample
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline,
                        size: 14,
                        color: switch (_layoutVariant) {
                          BenchLayoutKind.sample => AppColors.amber,
                          BenchLayoutKind.myRoom => AppColors.cyan,
                          BenchLayoutKind.improved => AppColors.green,
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

  /// Switching layouts only changes what is displayed — it never writes to the
  /// Rig. Pushing a layout back is the explicit Apply action under the results.
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
            'Nothing in the Rig yet — showing the reference room',
            'Add furniture on the Rig tab and this bench follows it',
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

  void _showAppliedToRigSnack(AppState state, {required String message}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.cyan.withValues(alpha: 0.92),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'OPEN RIG',
          textColor: Colors.black,
          onPressed: () => state.setTab(2),
        ),
      ),
    );
  }

  Widget _buildSimulationSection(AppState state) {
    _syncFromState(state);
    final sim = _activeSim;
    if (sim == null) return const SizedBox.shrink();
    final metrics = sim.metrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'VOXEL AIRFLOW FIELD',
          style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(
              'My Room',
              _simVariant == BenchLayoutKind.myRoom,
              AppColors.cyan,
              () => setState(() => _simVariant = BenchLayoutKind.myRoom),
            ),
            _chip(
              'Improved',
              _simVariant == BenchLayoutKind.improved,
              AppColors.green,
              () => setState(() => _simVariant = BenchLayoutKind.improved),
            ),
            _chip(
              'Sample',
              _simVariant == BenchLayoutKind.sample,
              AppColors.amber,
              () => setState(() => _simVariant = BenchLayoutKind.sample),
            ),
            _chip('2D', _simVizMode == AirflowVizMode.topDown2D, AppColors.cyan, () {
              setState(() => _simVizMode = AirflowVizMode.topDown2D);
            }),
            _chip('3D', _simVizMode == AirflowVizMode.orbit3D, AppColors.cyan, () {
              setState(() => _simVizMode = AirflowVizMode.orbit3D);
            }),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 300,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: _simVizMode == AirflowVizMode.orbit3D
                    ? _AirflowSimCanvas(
                        sim: sim,
                        furniture: _furnitureFor(_simVariant),
                        vizMode: _simVizMode,
                        orbitEnabled: true,
                        roomWidth: sim.field.roomWidth,
                        roomDepth: sim.field.roomDepth,
                        gridCols: sim.field.roomWidth.round(),
                        gridRows: sim.field.roomDepth.round(),
                        lookAtX: sim.field.roomWidth * 0.5,
                        lookAtZ: sim.field.roomDepth * 0.5,
                        resetNonce: _simOrbitResetNonce,
                        animating: state.currentTab == benchTabIndex &&
                            (_airflowStep == _AirflowStep.simulate ||
                                _airflowStep == _AirflowStep.results),
                        onDoubleTap: () {
                          HapticFeedback.lightImpact();
                          setState(() => _simOrbitResetNonce++);
                        },
                        onDragChanged: _setOrbitDragging,
                      )
                    : _AirflowSimCanvas(
                        sim: sim,
                        furniture: _furnitureFor(_simVariant),
                        vizMode: _simVizMode,
                        orbitEnabled: false,
                        roomWidth: sim.field.roomWidth,
                        roomDepth: sim.field.roomDepth,
                        gridCols: sim.field.roomWidth.round(),
                        gridRows: sim.field.roomDepth.round(),
                        lookAtX: sim.field.roomWidth * 0.5,
                        lookAtZ: sim.field.roomDepth * 0.5,
                        resetNonce: _simOrbitResetNonce,
                        animating: state.currentTab == benchTabIndex &&
                            (_airflowStep == _AirflowStep.simulate ||
                                _airflowStep == _AirflowStep.results),
                        onDoubleTap: () {
                          HapticFeedback.lightImpact();
                          setState(() => _simOrbitResetNonce++);
                        },
                        onDragChanged: (dragging) {
                          _setOrbitDragging(dragging);
                        },
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _metricCard('Circulation', metrics.circulationScore, AppColors.cyan)),
            const SizedBox(width: 8),
            Expanded(
              child: _metricCard(
                'Dead zones',
                metrics.deadZoneRatio * 100,
                AppColors.red,
                suffix: '%',
                invertGood: true,
              ),
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
        _buildPressureReadout(_furnitureFor(_simVariant)),
        const SizedBox(height: 8),
        Text(
          switch (_simVariant) {
            BenchLayoutKind.improved =>
              'Same furniture, rearranged — cold jets wrap obstacles and reach the heat sources.',
            BenchLayoutKind.myRoom =>
              'Field built from your Rig placements — AC throw, fan push and blockers are all live.',
            BenchLayoutKind.sample =>
              'Reference room: cold air stalls, heat pockets linger, smoke hugs blocked corners.',
          },
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildAirflowResults(AppState state) {
    // Before / after are your room and the optimizer's rearrange of it, so the
    // deltas describe a change you can actually make.
    final base = _myRoomSim!.metrics;
    final opt = _improvedSim!.metrics;
    final sample = _sampleSim?.metrics;
    final validation = _validationForSimVariant(state);
    final verdictColor = BenchResultBadge.colorFor(validation.verdict);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AIRFLOW BENCH RESULTS',
          style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2),
        ),
        const SizedBox(height: 12),
        GlassCard(
          gradient: const LinearGradient(
            colors: [Color(0xFF0D1A14), Color(0xFF0A1018)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderColor: verdictColor.withValues(alpha: 0.4),
          child: Column(
            children: [
              Row(
                children: [
                  SvgIcon(RoomSvg.trophy, size: 22, color: AppColors.amber),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Voxel Circulation Bench',
                      style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                  BenchResultBadge(validation: validation),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ScoreRing(score: base.circulationScore, size: 78, color: AppColors.cyan, label: 'My Room'),
                  ScoreRing(score: opt.circulationScore, size: 78, color: AppColors.airflowColor, label: 'Improved'),
                  if (sample != null)
                    ScoreRing(score: sample.circulationScore, size: 78, color: AppColors.amber, label: 'Sample')
                  else
                    ScoreRing(score: state.airflowScore, size: 78, color: AppColors.green, label: 'Score'),
                ],
              ),
              const SizedBox(height: 18),
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
              const SizedBox(height: 18),
              _ComparisonRow(
                label: 'Heat pockets',
                before: base.heatPocketRatio * 100,
                after: opt.heatPocketRatio * 100,
                color: AppColors.amber,
                lowerIsBetter: true,
              ),
              const SizedBox(height: 16),
              BenchmarkValidationCard(validation: validation),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    final steps = [
      'Seeding voxel grid',
      'Solving velocity field',
      'Advecting cold / hot particles',
      'Scoring dead zones',
    ];
    final stepIdx = (_runProgress * steps.length).floor().clamp(0, steps.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(steps[stepIdx], style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const Spacer(),
            Text(
              '${(_runProgress * 100).toInt()}%',
              style: TextStyle(color: AppColors.cyan, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: _runProgress,
          backgroundColor: AppColors.border,
          valueColor: const AlwaysStoppedAnimation(AppColors.cyan),
          minHeight: 4,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }


  Widget _chip(String label, bool selected, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? color : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
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
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton({required IconData icon, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, color: AppColors.textSecondary, size: 20),
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
  final int gridCols;
  final int gridRows;
  final double lookAtX;
  final double lookAtZ;
  final int resetNonce;
  final bool animating;
  final VoidCallback? onDoubleTap;
  final ValueChanged<bool>? onDragChanged;

  const _AirflowSimCanvas({
    required this.sim,
    required this.furniture,
    required this.vizMode,
    required this.orbitEnabled,
    required this.roomWidth,
    required this.roomDepth,
    required this.gridCols,
    required this.gridRows,
    required this.lookAtX,
    required this.lookAtZ,
    required this.resetNonce,
    required this.animating,
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
        resetNonce: widget.resetNonce,
        onDoubleTap: widget.onDoubleTap,
        onDragChanged: widget.onDragChanged,
        builder: _paintField,
      ),
    );
  }
}
