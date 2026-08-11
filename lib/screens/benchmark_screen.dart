// lib/screens/benchmark_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/airflow_prototype.dart';
import '../models/app_state.dart';
import '../models/room_model.dart';
import '../services/airflow_simulator.dart';
import '../theme/app_theme.dart';
import '../widgets/airflow_voxel_painter.dart';
import '../widgets/bench_room_views.dart';
import '../widgets/benchmark_validation_card.dart';
import '../widgets/ergonomics_bench_panel.dart';
import '../widgets/glass_card.dart';
import '../widgets/lighting_bench_panel.dart';
import '../widgets/room_icons.dart';
import '../widgets/score_ring.dart';

enum _AirflowStep { layout, simulate, results }
enum _LayoutVariant { current, improved, myRig }
enum _RoomViewMode { twoD, threeD }

class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({super.key});

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends State<BenchmarkScreen> with TickerProviderStateMixin {
  late AnimationController _particleController;
  late AnimationController _heatmapController;
  late AnimationController _ticker;

  bool _isRunning = false;
  double _runProgress = 0.0;
  bool _showResults = false;

  // Shared orbit for lighting/ergo legacy sims + airflow 3D.
  double _yaw = 0.75;
  double _pitch = 0.38;
  double _distance = 16.0;
  bool _orbitDragging = false;
  int? _orbitPointer;
  Offset? _lastOrbitPos;

  // Airflow prototype state.
  _AirflowStep _airflowStep = _AirflowStep.layout;
  _LayoutVariant _layoutVariant = _LayoutVariant.current;
  _RoomViewMode _roomViewMode = _RoomViewMode.twoD;
  AirflowVizMode _simVizMode = AirflowVizMode.orbit3D;
  _LayoutVariant _simVariant = _LayoutVariant.current;

  AirflowSimSnapshot? _baselineSim;
  AirflowSimSnapshot? _optimizedSim;
  AirflowSimSnapshot? _myRigSim;
  String _myRigFingerprint = '';
  /// Working layout seeded from Bench (fan included), then pushed to Rig.
  List<FurnitureItem> _myRigFurniture = const [];
  bool _myRigPushedToRig = false;
  late List<FurnitureItem> _baselineFurniture;
  late List<FurnitureItem> _optimizedFurniture;
  bool _prototypeReady = false;
  String? _selectedFurnitureId;

  static const _defaultYaw = 0.75;
  static const _defaultPitch = 0.38;
  static const _defaultDistance = 16.0;

  @override
  void initState() {
    super.initState();
    _particleController = AnimationController(duration: const Duration(seconds: 3), vsync: this)..repeat();
    _heatmapController = AnimationController(duration: const Duration(seconds: 2), vsync: this)..repeat(reverse: true);
    _ticker = AnimationController(duration: const Duration(milliseconds: 16), vsync: this)..addListener(_onTick);
    _ticker.repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      state.loadSimulatedPrototypeBaseline();
      _rebuildPrototype(state);
    });
  }

  void _onTick() {
    final sim = _activeSim;
    if (sim == null || !mounted) return;
    if (context.read<AppState>().benchmarkMode != 'airflow') return;
    if (_airflowStep != _AirflowStep.simulate && _airflowStep != _AirflowStep.results) return;

    AirflowSimulator.stepParticles(
      sim,
      dt: 0.045,
      time: _ticker.lastElapsedDuration?.inMilliseconds.toDouble() ?? 0,
    );
    setState(() {});
  }

  AirflowSimSnapshot? get _activeSim {
    switch (_simVariant) {
      case _LayoutVariant.improved:
        return _optimizedSim;
      case _LayoutVariant.myRig:
        return _myRigSim;
      case _LayoutVariant.current:
        return _baselineSim;
    }
  }

  List<FurnitureItem> _layoutFurnitureFor(AppState state) {
    switch (_layoutVariant) {
      case _LayoutVariant.improved:
        return _optimizedFurniture;
      case _LayoutVariant.myRig:
        return _myRigFurniture.where((f) => !f.hidden).toList(growable: false);
      case _LayoutVariant.current:
        return _baselineFurniture;
    }
  }

  void _rebuildPrototype(AppState state) {
    final source = RoomPresets.getPreset(RoomPreset.gamingSetup).furniture;
    _baselineFurniture = AirflowPrototypeLayouts.baseline(source);
    _optimizedFurniture = AirflowPrototypeLayouts.optimized(source);
    _baselineSim = AirflowSimulator.build(furniture: _baselineFurniture, optimized: false);
    _optimizedSim = AirflowSimulator.build(furniture: _optimizedFurniture, optimized: true);
    _seedMyRigFromBench(state, pushToRig: false);
    _prototypeReady = true;
    _airflowStep = _AirflowStep.layout;
    _layoutVariant = _LayoutVariant.current;
    _simVariant = _LayoutVariant.current;
    _showResults = false;
    setState(() {});
  }

  String _fingerprint(List<FurnitureItem> items) {
    return items
        .map((f) =>
            '${f.id}:${f.gridX.toStringAsFixed(2)},${f.gridY.toStringAsFixed(2)},'
            '${f.width},${f.height},${f.yawDegrees},${f.hidden},${f.locked}')
        .join('|');
  }

  /// Bench → Rig seed: My Rig starts from Current (includes stand fan).
  void _seedMyRigFromBench(AppState state, {bool pushToRig = true}) {
    _myRigFurniture = _baselineFurniture.map((f) => f.copyWith()).toList(growable: false);
    if (pushToRig) {
      state.applyFurnitureLayout(_myRigFurniture);
      _myRigPushedToRig = true;
    } else {
      _myRigPushedToRig = false;
    }
    _rebuildMyRigSim();
  }

  void _rebuildMyRigSim() {
    final items = _myRigFurniture.where((f) => !f.hidden).toList(growable: false);
    _myRigFingerprint = _fingerprint(items);
    _myRigSim = AirflowSimulator.build(
      furniture: items,
      optimized: false,
      demoBias: false,
    );
  }

  /// After Bench→Rig push, Rig edits can refresh the My Rig working copy for re-sim.
  void _syncMyRigFromState(AppState state) {
    if (_layoutVariant != _LayoutVariant.myRig && _simVariant != _LayoutVariant.myRig) {
      return;
    }
    final items = state.furniture.where((f) => !f.hidden).toList(growable: false);
    final fp = _fingerprint(items);
    if (fp == _myRigFingerprint && _myRigSim != null) return;
    _myRigFurniture = items.map((f) => f.copyWith()).toList(growable: false);
    _rebuildMyRigSim();
  }

  @override
  void dispose() {
    _particleController.dispose();
    _heatmapController.dispose();
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _runBenchmark({bool fromMyRig = false}) async {
    setState(() {
      _isRunning = true;
      _showResults = false;
      _runProgress = 0;
      _airflowStep = _AirflowStep.simulate;
      _simVariant = fromMyRig ? _LayoutVariant.myRig : _LayoutVariant.current;
    });

    if (fromMyRig) {
      _syncMyRigFromState(context.read<AppState>());
      _rebuildMyRigSim();
      for (int i = 1; i <= 16; i++) {
        await Future.delayed(const Duration(milliseconds: 90));
        if (!mounted) return;
        setState(() => _runProgress = i / 16);
      }
      if (!mounted) return;
      setState(() {
        _isRunning = false;
        _showResults = true;
        _airflowStep = _AirflowStep.results;
        _simVariant = _LayoutVariant.myRig;
      });
      return;
    }

    for (int i = 1; i <= 24; i++) {
      await Future.delayed(const Duration(milliseconds: 90));
      if (!mounted) return;
      setState(() {
        _runProgress = i / 24;
        // Flip to improved mid-run so user sees both voxel fields.
        if (i == 12) _simVariant = _LayoutVariant.improved;
      });
    }

    if (!mounted) return;
    final state = context.read<AppState>();
    // Bench → Rig: push the improved prototype (includes stand fan).
    state.applyFurnitureLayout(_optimizedFurniture, markOptimized: true);
    setState(() {
      _isRunning = false;
      _showResults = true;
      _airflowStep = _AirflowStep.results;
      _simVariant = _LayoutVariant.improved;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAirflow = state.benchmarkMode == 'airflow';
    final isLighting = state.benchmarkMode == 'lighting';
    final isErgonomics = state.benchmarkMode == 'ergonomics';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: _orbitDragging ? const NeverScrollableScrollPhysics() : null,
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
                const LightingBenchPanel()
              else if (isErgonomics)
                const ErgonomicsBenchPanel()
              else
                ..._buildLegacyMode(state),
              const SizedBox(height: 32),
            ],
          ),
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
      ('ergonomics', RoomSvg.ergonomics, 'Ergonomics', AppColors.ergonomicsColor),
    ];

    return Row(
      children: modes.map((m) {
        final isSelected = state.benchmarkMode == m.$1;
        return Expanded(
          child: GestureDetector(
            onTap: () => state.setBenchmarkMode(m.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(right: m.$1 == 'ergonomics' ? 0 : 8),
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
    _syncMyRigFromState(state);

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
          label: _layoutVariant == _LayoutVariant.myRig
              ? 'RUN MY RIG AIRFLOW SIM'
              : 'RUN VOXEL AIRFLOW BENCH',
          icon: RoomSvg.scan,
          onTap: _isRunning ? null : () => _runBenchmark(fromMyRig: _layoutVariant == _LayoutVariant.myRig),
        ),
        const SizedBox(height: 8),
        Text(
          _layoutVariant == _LayoutVariant.myRig
              ? 'Starts from the Bench layout (stand fan included), pushes into Rig — edit there, then re-run.'
              : 'Compare the average room vs the improved rearrange, then stress-test cold/hot particle circulation.',
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
        Row(
          children: [
            Expanded(
              child: _buildPrimaryButton(
                label: _simVariant == _LayoutVariant.myRig
                    ? 'APPLY MY RIG TO RIG'
                    : 'APPLY IMPROVED LAYOUT',
                icon: RoomSvg.star,
                onTap: () {
                  if (_simVariant == _LayoutVariant.myRig) {
                    state.applyFurnitureLayout(_myRigFurniture);
                    _showAppliedToRigSnack(state, message: 'My Rig layout applied to Rig');
                  } else {
                    state.applyFurnitureLayout(_optimizedFurniture, markOptimized: true);
                    _showAppliedToRigSnack(state, message: 'Improved airflow layout applied to Rig');
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            _buildIconButton(
              icon: Icons.refresh_rounded,
              onTap: () {
                state.loadSimulatedPrototypeBaseline();
                _rebuildPrototype(state);
              },
            ),
          ],
        ),
      ],
      if (_airflowStep == _AirflowStep.simulate && !_isRunning) ...[
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildPrimaryButton(
                label: _simVariant == _LayoutVariant.myRig ? 'FINISH MY RIG RUN' : 'COMPARE & FINISH',
                icon: RoomSvg.trendingUp,
                onTap: () {
                  setState(() {
                    if (_simVariant != _LayoutVariant.myRig) {
                      _simVariant = _LayoutVariant.improved;
                    }
                    _airflowStep = _AirflowStep.results;
                    _showResults = true;
                  });
                  if (_simVariant != _LayoutVariant.myRig) {
                    state.applyFurnitureLayout(_optimizedFurniture, markOptimized: true);
                    _showAppliedToRigSnack(state, message: 'Improved airflow layout applied to Rig');
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            _buildIconButton(
              icon: Icons.refresh_rounded,
              onTap: () {
                state.loadSimulatedPrototypeBaseline();
                _rebuildPrototype(state);
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
    final notes = switch (_layoutVariant) {
      _LayoutVariant.improved => AirflowPrototypeLayouts.optimizedNotes,
      _LayoutVariant.myRig => const [
          'Seeded from Bench Current — includes the stand fan',
          'Pushed into Rig so you can drag furniture there',
          'Come back and re-run — particles follow your moves',
        ],
      _LayoutVariant.current => AirflowPrototypeLayouts.baselineNotes,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ROOM LAYOUT PROTOTYPE',
          style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(
              'Current',
              _layoutVariant == _LayoutVariant.current,
              AppColors.amber,
              () => _setLayoutVariant(_LayoutVariant.current),
            ),
            _chip(
              'Improved',
              _layoutVariant == _LayoutVariant.improved,
              AppColors.green,
              () => _setLayoutVariant(_LayoutVariant.improved),
            ),
            _chip(
              'My Rig',
              _layoutVariant == _LayoutVariant.myRig,
              AppColors.cyan,
              () => _setLayoutVariant(_LayoutVariant.myRig, state: state),
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
                        _LayoutVariant.current => 'Average room — AC in a corner, weak coverage',
                        _LayoutVariant.improved => 'Improved — AC mid-wall for max throw coverage',
                        _LayoutVariant.myRig => 'Bench → Rig — fan layout seeded, edit on Rig',
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
                        key: ValueKey('${_layoutVariant.name}_${_roomViewMode.name}_$_myRigFingerprint'),
                        child: _roomViewMode == _RoomViewMode.twoD
                            ? _buildInteractive2DRoom(
                                gridCols: room.gridCols,
                                gridRows: room.gridRows,
                                furniture: furniture,
                                showCoverageCone: true,
                              )
                            : _orbitShell(
                                child: CustomPaint(
                                  painter: BenchRoom3DPainter(
                                    roomWidth: room.gridCols.toDouble(),
                                    roomDepth: room.gridRows.toDouble(),
                                    roomHeight: 2.8,
                                    gridCols: room.gridCols,
                                    gridRows: room.gridRows,
                                    yaw: _yaw,
                                    pitch: _pitch,
                                    distance: _distance,
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
                        _layoutVariant == _LayoutVariant.current
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline,
                        size: 14,
                        color: _layoutVariant == _LayoutVariant.current
                            ? AppColors.amber
                            : (_layoutVariant == _LayoutVariant.myRig ? AppColors.cyan : AppColors.green),
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

  void _setLayoutVariant(_LayoutVariant next, {AppState? state}) {
    if (_layoutVariant == next) return;
    HapticFeedback.selectionClick();
    if (next == _LayoutVariant.myRig && state != null) {
      if (!_myRigPushedToRig) {
        // Bench → Rig: push Current (stand fan included) into Rig.
        if (_myRigFurniture.isEmpty) {
          _seedMyRigFromBench(state, pushToRig: true);
        } else {
          state.applyFurnitureLayout(_myRigFurniture);
          _myRigPushedToRig = true;
          _rebuildMyRigSim();
        }
      } else {
        // Pick up Rig edits after the Bench→Rig seed.
        _myRigFurniture = state.furniture.map((f) => f.copyWith()).toList(growable: false);
        _rebuildMyRigSim();
      }
    }
    setState(() {
      _layoutVariant = next;
      _selectedFurnitureId = null;
    });
  }

  Widget _buildInteractive2DRoom({
    required int gridCols,
    required int gridRows,
    required List<FurnitureItem> furniture,
    bool showCoverageCone = true,
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
              showCoverageCone: showCoverageCone,
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

  void _resetOrbitCamera() {
    HapticFeedback.lightImpact();
    setState(() {
      _yaw = _defaultYaw;
      _pitch = _defaultPitch;
      _distance = _defaultDistance;
    });
  }

  Widget _buildSimulationSection(AppState state) {
    _syncMyRigFromState(state);
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
              'Current',
              _simVariant == _LayoutVariant.current,
              AppColors.amber,
              () => setState(() => _simVariant = _LayoutVariant.current),
            ),
            _chip(
              'Improved',
              _simVariant == _LayoutVariant.improved,
              AppColors.green,
              () => setState(() => _simVariant = _LayoutVariant.improved),
            ),
            _chip(
              'My Rig',
              _simVariant == _LayoutVariant.myRig,
              AppColors.cyan,
              () {
                _syncMyRigFromState(state);
                _rebuildMyRigSim();
                setState(() => _simVariant = _LayoutVariant.myRig);
              },
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
                child: _orbitShell(
                  enabled: _simVizMode == AirflowVizMode.orbit3D,
                  child: CustomPaint(
                    painter: AirflowVoxelPainter(
                      snapshot: sim,
                      vizMode: _simVizMode,
                      yaw: _yaw,
                      pitch: _pitch,
                      distance: _distance,
                      time: _particleController.value,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                top: 12,
                child: _badge(
                  switch (_simVariant) {
                    _LayoutVariant.improved => 'IMPROVED CIRCULATION',
                    _LayoutVariant.myRig => 'MY RIG LAYOUT',
                    _LayoutVariant.current => 'BASELINE STRESS',
                  },
                  switch (_simVariant) {
                    _LayoutVariant.improved => AppColors.green,
                    _LayoutVariant.myRig => AppColors.cyan,
                    _LayoutVariant.current => AppColors.amber,
                  },
                ),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: _badge(
                  _simVizMode == AirflowVizMode.orbit3D ? 'ORBIT 3D' : 'TOP-DOWN',
                  AppColors.cyan,
                ),
              ),
              if (_simVizMode == AirflowVizMode.orbit3D)
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Text(
                    'Orbit ${(_yaw * 180 / pi).round()}° · double-tap reset',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600),
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
        Text(
          _simVariant == _LayoutVariant.improved
              ? 'Cold jets wrap furniture and reach heat / return openings.'
              : (_simVariant == _LayoutVariant.myRig
                  ? 'Field rebuilt from your Rig placements — AC throw, fan push, and blockers are live.'
                  : 'Cold air stalls; heat pockets linger; smoke hugs blocked corners.'),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildAirflowResults(AppState state) {
    final base = _baselineSim!.metrics;
    final opt = _optimizedSim!.metrics;
    final mine = _myRigSim?.metrics;

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
          borderColor: AppColors.green.withValues(alpha: 0.4),
          child: Column(
            children: [
              Row(
                children: [
                  SvgIcon(RoomSvg.trophy, size: 22, color: AppColors.amber),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Voxel Circulation Pass',
                      style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('PASS', style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ScoreRing(score: base.circulationScore, size: 78, color: AppColors.amber, label: 'Before'),
                  ScoreRing(score: opt.circulationScore, size: 78, color: AppColors.airflowColor, label: 'After'),
                  if (mine != null)
                    ScoreRing(score: mine.circulationScore, size: 78, color: AppColors.cyan, label: 'My Rig')
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
              BenchmarkValidationCard(
                validation: state.validateActiveLayout(mode: 'airflow'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildLegacyMode(AppState state) {
    return [
      _buildLegacyModelPreview(state),
      const SizedBox(height: 20),
      _buildLegacySimulationCanvas(state),
      const SizedBox(height: 20),
      _buildLegacyControls(state),
      if (_isRunning) ...[
        const SizedBox(height: 16),
        _buildProgressBar(),
      ],
      if (_showResults) ...[
        const SizedBox(height: 24),
        _buildLegacyResults(state),
      ],
    ];
  }

  Widget _buildLegacyModelPreview(AppState state) {
    final room = state.currentRoomData;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LIVE MODEL',
          style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2),
        ),
        const SizedBox(height: 10),
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
                      '${room.name} model',
                      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                  Text(
                    '${state.furniture.length} items',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 180,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: CustomPaint(
                    painter: BenchRoom2DPainter(
                      gridCols: room.gridCols,
                      gridRows: room.gridRows,
                      furniture: state.furniture,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegacySimulationCanvas(AppState state) {
    return Container(
      height: 240,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedBuilder(
        animation: Listenable.merge([_particleController, _heatmapController]),
        builder: (context, _) => CustomPaint(
          painter: _LegacySimulationPainter(
            mode: state.benchmarkMode,
            particleT: _particleController.value,
            heatT: _heatmapController.value,
            optimized: state.isOptimized,
            furniture: state.furniture,
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _badge('${state.benchmarkMode.toUpperCase()} SIMULATION', AppColors.cyan),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegacyControls(AppState state) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildPrimaryButton(
                label: _isRunning ? 'RIGGING ROOM...' : 'RIG ROOM NOW',
                icon: _isRunning ? RoomSvg.scan : RoomSvg.star,
                onTap: _isRunning
                    ? null
                    : () async {
                        setState(() {
                          _isRunning = true;
                          _showResults = false;
                          _runProgress = 0;
                        });
                        for (int i = 1; i <= 20; i++) {
                          await Future.delayed(const Duration(milliseconds: 100));
                          if (!mounted) return;
                          setState(() => _runProgress = i / 20);
                        }
                        if (!mounted) return;
                        state.runOptimization();
                        setState(() {
                          _isRunning = false;
                          _showResults = true;
                        });
                      },
              ),
            ),
            const SizedBox(width: 8),
            _buildIconButton(
              icon: Icons.refresh_rounded,
              onTap: _isRunning
                  ? null
                  : () {
                      state.loadSimulatedPrototypeBaseline();
                      setState(() {
                        _showResults = false;
                        _runProgress = 0;
                      });
                    },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLegacyResults(AppState state) {
    return GlassCard(
      borderColor: AppColors.green.withValues(alpha: 0.4),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ScoreRing(score: state.airflowScore, size: 80, color: AppColors.airflowColor, label: 'Airflow'),
              ScoreRing(score: state.lightingScore, size: 80, color: AppColors.lightingColor, label: 'Lighting'),
              ScoreRing(score: state.ergonomicsScore, size: 80, color: AppColors.ergonomicsColor, label: 'Ergo'),
            ],
          ),
        ],
      ),
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

  Widget _orbitShell({required Widget child, bool enabled = true}) {
    if (!enabled) {
      return SizedBox.expand(child: child);
    }
    // Pointer-driven orbit so the parent ScrollView can't steal the drag.
    // Double-tap resets the camera for demos.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: _resetOrbitCamera,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          _orbitPointer = e.pointer;
          _lastOrbitPos = e.localPosition;
          setState(() => _orbitDragging = true);
        },
        onPointerMove: (e) {
          if (e.pointer != _orbitPointer || _lastOrbitPos == null) return;
          final delta = e.localPosition - _lastOrbitPos!;
          _lastOrbitPos = e.localPosition;
          setState(() {
            _yaw = (_yaw + delta.dx * 0.01).clamp(-pi, pi);
            _pitch = (_pitch - delta.dy * 0.008).clamp(0.08, 1.15);
          });
        },
        onPointerUp: (e) {
          if (e.pointer == _orbitPointer) {
            _orbitPointer = null;
            _lastOrbitPos = null;
            setState(() => _orbitDragging = false);
          }
        },
        onPointerCancel: (e) {
          if (e.pointer == _orbitPointer) {
            _orbitPointer = null;
            _lastOrbitPos = null;
            setState(() => _orbitDragging = false);
          }
        },
        onPointerSignal: (signal) {
          if (signal is PointerScrollEvent) {
            setState(() {
              _distance = (_distance + signal.scrollDelta.dy * 0.02).clamp(10.0, 28.0);
            });
          }
        },
        child: SizedBox.expand(
          child: ColoredBox(
            color: Colors.transparent,
            child: child,
          ),
        ),
      ),
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

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1),
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

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendRow({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// Lightweight lighting / ergonomics painters (airflow uses voxel engine).
class _LegacySimulationPainter extends CustomPainter {
  final String mode;
  final double particleT;
  final double heatT;
  final bool optimized;
  final List<FurnitureItem> furniture;

  _LegacySimulationPainter({
    required this.mode,
    required this.particleT,
    required this.heatT,
    required this.optimized,
    required this.furniture,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (mode == 'lighting') {
      _drawLighting(canvas, size);
    } else {
      _drawErgonomics(canvas, size);
    }
  }

  void _drawLighting(Canvas canvas, Size size) {
    final sources = [
      Offset(size.width * 0.18, 10),
      Offset(size.width * 0.52, 12),
      Offset(size.width * 0.86, size.height * 0.18),
    ];
    final roomGlow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: optimized
            ? [AppColors.lightingColor.withValues(alpha: 0.10), Colors.transparent]
            : [AppColors.red.withValues(alpha: 0.08), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), roomGlow);

    for (final src in sources) {
      canvas.drawCircle(
        src,
        size.width * 0.5,
        Paint()
          ..shader = RadialGradient(
            colors: [
              AppColors.lightingColor.withValues(alpha: 0.45 + heatT * 0.2),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCircle(center: src, radius: size.width * 0.5)),
      );
    }

    for (final f in furniture.take(5)) {
      final x = (f.gridX / 6) * size.width;
      final y = (f.gridY / 8) * size.height;
      final w = (f.width / 6) * size.width;
      final h = (f.height / 8) * size.height;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x + 8, y + 8, w, h), const Radius.circular(6)),
        Paint()..color = AppColors.surfaceAlt.withValues(alpha: 0.7),
      );
    }
  }

  void _drawErgonomics(Canvas canvas, Size size) {
    final entry = Offset(22, size.height * 0.68);
    final chair = optimized
        ? Offset(size.width * 0.44, size.height * 0.57)
        : Offset(size.width * 0.57, size.height * 0.68);
    final desk = optimized
        ? Offset(size.width * 0.46, size.height * 0.32)
        : Offset(size.width * 0.71, size.height * 0.30);

    final lane = Path()
      ..moveTo(entry.dx, entry.dy)
      ..cubicTo(size.width * 0.22, size.height * 0.64, size.width * 0.30, size.height * 0.56, chair.dx, chair.dy)
      ..quadraticBezierTo(size.width * 0.47, size.height * 0.47, desk.dx, desk.dy);

    canvas.drawPath(
      lane,
      Paint()
        ..color = AppColors.ergonomicsColor.withValues(alpha: optimized ? 0.6 : 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = optimized ? 7 : 5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(chair, 16, Paint()..color = AppColors.ergonomicsColor.withValues(alpha: 0.8));
    canvas.drawCircle(desk, 12, Paint()..color = AppColors.purple.withValues(alpha: 0.75));
  }

  @override
  bool shouldRepaint(covariant _LegacySimulationPainter old) =>
      old.particleT != particleT ||
      old.heatT != heatT ||
      old.mode != mode ||
      old.optimized != optimized ||
      old.furniture != furniture;
}
