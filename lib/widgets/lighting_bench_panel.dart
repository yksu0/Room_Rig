// lib/widgets/lighting_bench_panel.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/room_model.dart';
import '../services/bench_layouts.dart';
import '../services/lighting_simulator.dart';
import '../services/benchmark_validator.dart';
import '../theme/app_theme.dart';
import 'bench_room_views.dart';
import 'benchmark_validation_card.dart';
import 'glass_card.dart';
import 'lighting_field_painter.dart';
import 'room_icons.dart';
import 'score_ring.dart';

enum _LightStep { layout, simulate, results }
enum _View { twoD, threeD }

class LightingBenchPanel extends StatefulWidget {
  const LightingBenchPanel({super.key});

  @override
  State<LightingBenchPanel> createState() => _LightingBenchPanelState();
}

class _LightingBenchPanelState extends State<LightingBenchPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  _LightStep _step = _LightStep.layout;
  BenchLayoutKind _layoutVariant = BenchLayoutKind.myRoom;
  BenchLayoutKind _simVariant = BenchLayoutKind.myRoom;
  _View _roomView = _View.twoD;
  LightingVizMode _simViz = LightingVizMode.topDown2D;

  bool _orbitDragging = false;
  int _layoutOrbitResetNonce = 0;
  int _simOrbitResetNonce = 0;
  String? _selectedFurnitureId;

  static const _defaultYaw = 0.7;
  static const _defaultPitch = 0.4;
  static const _defaultDistance = 16.0;

  bool _running = false;
  double _progress = 0;
  bool _showResults = false;
  bool _ready = false;

  BenchLayouts? _layouts;
  int _seenFocusToken = 0;
  LightingSimSnapshot? _myRoomSim;
  LightingSimSnapshot? _improvedSim;
  LightingSimSnapshot? _sampleSim;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The bench reads the Rig; opening this tab must never write to it.
      _rebuild();
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _rebuild() {
    _recompute(context.read<AppState>());
    if (mounted) setState(() {});
  }

  /// Rebuilds the lighting fields from the furniture that is in the Rig.
  /// Safe to call during build: it only touches fields.
  void _recompute(AppState state, {bool resetStep = true}) {
    final room = state.currentRoomData;
    final layouts = BenchLayoutBuilder.build(
      mode: BenchMode.lighting,
      roomFurniture: state.furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
    );
    _layouts = layouts;
    _myRoomSim = LightingSimulator.build(furniture: layouts.myRoom, optimized: false);
    _improvedSim = LightingSimulator.build(furniture: layouts.improved, optimized: true);
    _sampleSim = LightingSimulator.build(furniture: layouts.sample, optimized: false);
    _ready = true;
    if (resetStep) {
      _step = _LightStep.layout;
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

  /// Picks up Rig edits so the light field always describes the current room.
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
      state.furniture.where((f) => !f.hidden).toList(growable: false),
    );
    if (_layouts != null && fp == _layouts!.fingerprint) return;
    _recompute(state, resetStep: false);
  }

  List<FurnitureItem> _furnitureFor(BenchLayoutKind kind) =>
      _layouts?.forKind(kind) ?? const [];

  List<FurnitureItem> _layoutFurnitureFor(AppState state) => _furnitureFor(_layoutVariant);

  LightingSimSnapshot? get _activeSim {
    switch (_simVariant) {
      case BenchLayoutKind.improved:
        return _improvedSim;
      case BenchLayoutKind.sample:
        return _sampleSim;
      case BenchLayoutKind.myRoom:
        return _myRoomSim;
    }
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
          'Windows, lamps and blockers all come from your Rig',
          'Move something on the Rig tab and the light field rebuilds here',
        ];
      case BenchLayoutKind.improved:
        final reasons = _layouts?.improvedReasons ?? const <String>[];
        return reasons.isEmpty
            ? const ['No rearrange found that lights your room better']
            : reasons;
      case BenchLayoutKind.sample:
        return const [
          'Reference room used to sanity-check the simulator',
          'Dark task zone — daylight blocked, lamp misplaced',
        ];
    }
  }

  Future<void> _runBench() async {
    // Always start from the room as it stands right now.
    _recompute(context.read<AppState>(), resetStep: false);
    setState(() {
      _running = true;
      _showResults = false;
      _progress = 0;
      _step = _LightStep.simulate;
      _simVariant = BenchLayoutKind.myRoom;
    });
    for (int i = 1; i <= 20; i++) {
      await Future.delayed(const Duration(milliseconds: 90));
      if (!mounted) return;
      setState(() {
        _progress = i / 20;
        if (i == 10) _simVariant = BenchLayoutKind.improved;
      });
    }
    if (!mounted) return;
    // Bench → Rig only happens on the explicit Apply action below the results,
    // so finishing a run never silently replaces the user's layout.
    setState(() {
      _running = false;
      _showResults = true;
      _step = _LightStep.results;
      _simVariant = BenchLayoutKind.improved;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (_ready) _syncFromState(state);
    if (!_ready) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator(color: AppColors.lightingColor)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _steps(),
        const SizedBox(height: 16),
        if (_step == _LightStep.layout) ...[
          _layoutSection(state),
          const SizedBox(height: 16),
          _primaryButton(
            'RUN LIGHTING BENCH',
            RoomSvg.scan,
            _running ? null : () => _runBench(),
          ),
          const SizedBox(height: 8),
          Text(
            _layouts?.fellBackToSample ?? false
                ? 'Your Rig is empty, so this runs on the reference room. Add furniture in Rig to bench your own space.'
                : 'Lights the furniture in your Rig right now, then compares it against an optimized rearrange of the same room.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
        if (_step == _LightStep.simulate || (_step == _LightStep.results && _running)) ...[
          _simSection(state),
          if (_running) ...[
            const SizedBox(height: 16),
            _progressBar(),
          ],
        ],
        if (_step == _LightStep.results && !_running) ...[
          _simSection(state),
          const SizedBox(height: 20),
          _results(state),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _primaryButton(
                  'APPLY IMPROVED LAYOUT',
                  RoomSvg.star,
                  () {
                    state.applyFurnitureLayout(
                      _furnitureFor(BenchLayoutKind.improved),
                      markOptimized: true,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Improved lighting layout applied to Rig'),
                        backgroundColor: AppColors.lightingColor.withValues(alpha: 0.9),
                        behavior: SnackBarBehavior.floating,
                        action: SnackBarAction(
                          label: 'OPEN RIG',
                          textColor: Colors.black,
                          onPressed: () => state.setTab(2),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              _iconButton(_rebuild),
            ],
          ),
        ],
      ],
    );
  }

  Widget _steps() {
    final steps = [
      (_LightStep.layout, '1. Layout'),
      (_LightStep.simulate, '2. Light Field'),
      (_LightStep.results, '3. Results'),
    ];
    return Row(
      children: steps.map((s) {
        final selected = _step == s.$1;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              if (s.$1 == _LightStep.results && !_showResults && !_running) return;
              setState(() => _step = s.$1);
            },
            child: Container(
              margin: EdgeInsets.only(right: s.$1 == _LightStep.results ? 0 : 8),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: selected ? AppColors.lightingColor.withValues(alpha: 0.12) : AppColors.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected ? AppColors.lightingColor : AppColors.border),
              ),
              child: Text(
                s.$2,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? AppColors.lightingColor : AppColors.textMuted,
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

  Widget _layoutSection(AppState state) {
    final notes = _notesFor(_layoutVariant);
    final room = state.currentRoomData;
    final furniture = _layoutFurnitureFor(state);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LIGHTING LAYOUT',
          style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _chip('My Room', _layoutVariant == BenchLayoutKind.myRoom, AppColors.cyan,
                () => _setLayoutVariant(BenchLayoutKind.myRoom)),
            const SizedBox(width: 8),
            _chip('Improved', _layoutVariant == BenchLayoutKind.improved, AppColors.green,
                () => _setLayoutVariant(BenchLayoutKind.improved)),
            const SizedBox(width: 8),
            _chip('Sample', _layoutVariant == BenchLayoutKind.sample, AppColors.amber,
                () => _setLayoutVariant(BenchLayoutKind.sample)),
            const Spacer(),
            _chip('2D', _roomView == _View.twoD, AppColors.lightingColor, () {
              setState(() => _roomView = _View.twoD);
            }),
            const SizedBox(width: 6),
            _chip('3D', _roomView == _View.threeD, AppColors.lightingColor, () {
              setState(() => _roomView = _View.threeD);
            }),
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
                  BenchLayoutKind.improved => 'Improved — your room, rearranged for light',
                  BenchLayoutKind.sample => 'Sample room — daylight blocked, lamp misplaced',
                },
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 280,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: ColoredBox(
                    color: AppColors.surface,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: KeyedSubtree(
                        key: ValueKey(
                          '${_layoutVariant.name}_${_roomView.name}_${_layouts?.fingerprint ?? ''}',
                        ),
                        child: _roomView == _View.twoD
                            ? LayoutBuilder(
                                builder: (context, constraints) {
                                  final size = Size(constraints.maxWidth, constraints.maxHeight);
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapDown: (details) {
                                      final hit = BenchRoom2DGeometry.hitTest(
                                        local: details.localPosition,
                                        size: size,
                                        gridCols: room.gridCols,
                                        gridRows: room.gridRows,
                                        furniture: furniture,
                                      );
                                      HapticFeedback.selectionClick();
                                      setState(() {
                                        if (hit == null || _selectedFurnitureId == hit.id) {
                                          _selectedFurnitureId = null;
                                        } else {
                                          _selectedFurnitureId = hit.id;
                                        }
                                      });
                                    },
                                    child: CustomPaint(
                                      painter: BenchRoom2DPainter(
                                        gridCols: room.gridCols,
                                        gridRows: room.gridRows,
                                        furniture: furniture,
                                        showCoverageCone: false,
                                        selectedId: _selectedFurnitureId,
                                      ),
                                      child: const SizedBox.expand(),
                                    ),
                                  );
                                },
                              )
                            : _orbit(
                                key: const ValueKey('lighting_layout_orbit'),
                                resetNonce: _layoutOrbitResetNonce,
                                onDoubleTap: () {
                                  HapticFeedback.lightImpact();
                                  setState(() => _layoutOrbitResetNonce++);
                                },
                                lookAtX: room.gridCols * 0.5,
                                lookAtZ: room.gridRows * 0.5,
                                roomWidth: room.gridCols.toDouble(),
                                roomDepth: room.gridRows.toDouble(),
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
                Builder(
                  builder: (context) {
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
                                  benchInspectBlurb(item, mode: 'lighting'),
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
                  },
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
                        child: Text(n, style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
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

  Widget _simSection(AppState state) {
    _syncFromState(state);
    final sim = _activeSim;
    if (sim == null) return const SizedBox.shrink();
    final m = sim.metrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ILLUMINANCE FIELD',
          style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip('My Room', _simVariant == BenchLayoutKind.myRoom, AppColors.cyan, () {
              setState(() => _simVariant = BenchLayoutKind.myRoom);
            }),
            _chip('Improved', _simVariant == BenchLayoutKind.improved, AppColors.green, () {
              setState(() => _simVariant = BenchLayoutKind.improved);
            }),
            _chip('Sample', _simVariant == BenchLayoutKind.sample, AppColors.amber, () {
              setState(() => _simVariant = BenchLayoutKind.sample);
            }),
            _chip('2D', _simViz == LightingVizMode.topDown2D, AppColors.lightingColor, () {
              setState(() => _simViz = LightingVizMode.topDown2D);
            }),
            _chip('3D', _simViz == LightingVizMode.orbit3D, AppColors.lightingColor, () {
              setState(() => _simViz = LightingVizMode.orbit3D);
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
          child: _simViz == LightingVizMode.topDown2D
              ? AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) => CustomPaint(
                    painter: LightingFieldPainter(
                      snapshot: sim,
                      furniture: _furnitureFor(_simVariant),
                      vizMode: _simViz,
                      yaw: _defaultYaw,
                      pitch: _defaultPitch,
                      distance: _defaultDistance,
                      pulse: _pulse.value,
                    ),
                    child: const SizedBox.expand(),
                  ),
                )
              : _orbit(
                  key: const ValueKey('lighting_sim_orbit'),
                  resetNonce: _simOrbitResetNonce,
                  onDoubleTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _simOrbitResetNonce++);
                  },
                  builder: (cam) => AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, child) => CustomPaint(
                      painter: LightingFieldPainter(
                        snapshot: sim,
                        furniture: _furnitureFor(_simVariant),
                        vizMode: _simViz,
                        yaw: cam.yaw,
                        pitch: cam.pitch,
                        distance: cam.distance,
                        lookAtX: cam.lookAtX,
                        lookAtZ: cam.lookAtZ,
                        pulse: _pulse.value,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _metric('Exposure', m.exposureScore, AppColors.lightingColor)),
            const SizedBox(width: 8),
            Expanded(child: _metric('Task light', m.taskIllumination * 100, AppColors.amber)),
            const SizedBox(width: 8),
            Expanded(child: _metric('Shadows', m.shadowRatio * 100, AppColors.red, invert: true)),
          ],
        ),
      ],
    );
  }

  /// Validate the layout the results header is actually showing, so the badge,
  /// the score rings, and the check rows all describe the same furniture.
  BenchmarkValidation _validationForSimVariant(AppState state) {
    return BenchmarkValidator.validateLayout(
      furniture: _furnitureFor(_simVariant),
      gridCols: state.currentRoomData.gridCols,
      gridRows: state.currentRoomData.gridRows,
      mode: 'lighting',
    );
  }

  Widget _results(AppState state) {
    final validation = _validationForSimVariant(state);
    // Before / after are your room and the optimizer's rearrange of it.
    final base = _myRoomSim!.metrics;
    final opt = _improvedSim!.metrics;
    final sample = _sampleSim?.metrics;
    return GlassCard(
      borderColor: BenchResultBadge.colorFor(validation.verdict).withValues(alpha: 0.4),
      child: Column(
        children: [
          Row(
            children: [
              SvgIcon(RoomSvg.trophy, size: 22, color: AppColors.amber),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Lighting Exposure Bench', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              BenchResultBadge(validation: validation),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ScoreRing(score: base.exposureScore, size: 78, color: AppColors.cyan, label: 'My Room'),
              ScoreRing(score: opt.exposureScore, size: 78, color: AppColors.lightingColor, label: 'Improved'),
              if (sample != null)
                ScoreRing(score: sample.exposureScore, size: 78, color: AppColors.amber, label: 'Sample')
              else
                ScoreRing(score: state.lightingScore, size: 78, color: AppColors.green, label: 'Score'),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Shadows ${((base.shadowRatio - opt.shadowRatio) * 100).toStringAsFixed(0)} pts · '
            'Task light +${((opt.taskIllumination - base.taskIllumination) * 100).toStringAsFixed(0)}',
            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 14),
          BenchmarkValidationCard(validation: validation),
        ],
      ),
    );
  }

  Widget _progressBar() {
    return Column(
      children: [
        Row(
          children: [
            Text('Tracing daylight + task lamps', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const Spacer(),
            Text('${(_progress * 100).toInt()}%', style: TextStyle(color: AppColors.lightingColor, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: _progress,
          backgroundColor: AppColors.border,
          valueColor: const AlwaysStoppedAnimation(AppColors.lightingColor),
          minHeight: 4,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }

  Widget _orbit({
    Key? key,
    required Widget Function(BenchOrbitCamera cam) builder,
    required int resetNonce,
    VoidCallback? onDoubleTap,
    double lookAtX = 3,
    double lookAtZ = 4,
    double roomWidth = 6,
    double roomDepth = 8,
  }) {
    return BenchOrbitShell(
      key: key,
      initialYaw: _defaultYaw,
      initialPitch: _defaultPitch,
      initialDistance: _defaultDistance,
      initialLookAtX: lookAtX,
      initialLookAtZ: lookAtZ,
      roomWidth: roomWidth,
      roomDepth: roomDepth,
      resetNonce: resetNonce,
      onDoubleTap: onDoubleTap,
      onDragChanged: (dragging) {
        if (_orbitDragging != dragging) setState(() => _orbitDragging = dragging);
      },
      builder: builder,
    );
  }

  // Silence unused warning — parent scroll can key off this later if needed.
  bool get isOrbitDragging => _orbitDragging;

  Widget _chip(String label, bool selected, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? color : AppColors.border),
        ),
        child: Text(label, style: TextStyle(color: selected ? color : AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _metric(String label, double value, Color color, {bool invert = false}) {
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
            value.toStringAsFixed(0),
            style: TextStyle(
              color: invert && value > 25 ? AppColors.red : color,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton(String label, String icon, VoidCallback? onTap) {
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
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgIcon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 1.1)),
          ],
        ),
      ),
    );
  }

  Widget _iconButton(VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary, size: 20),
      ),
    );
  }
}
