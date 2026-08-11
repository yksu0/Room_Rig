// lib/widgets/lighting_bench_panel.dart
import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/lighting_prototype.dart';
import '../models/room_model.dart';
import '../services/lighting_simulator.dart';
import '../theme/app_theme.dart';
import 'bench_room_views.dart';
import 'benchmark_validation_card.dart';
import 'glass_card.dart';
import 'lighting_field_painter.dart';
import 'room_icons.dart';
import 'score_ring.dart';

enum _LightStep { layout, simulate, results }
enum _Variant { current, improved, myRig }
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
  _Variant _layoutVariant = _Variant.current;
  _Variant _simVariant = _Variant.current;
  _View _roomView = _View.twoD;
  LightingVizMode _simViz = LightingVizMode.topDown2D;

  double _yaw = 0.7;
  double _pitch = 0.4;
  double _distance = 16;
  bool _orbitDragging = false;
  int? _orbitPointer;
  Offset? _lastOrbitPos;
  String? _selectedFurnitureId;

  static const _defaultYaw = 0.7;
  static const _defaultPitch = 0.4;
  static const _defaultDistance = 16.0;

  bool _running = false;
  double _progress = 0;
  bool _showResults = false;
  bool _ready = false;

  late List<FurnitureItem> _baseline;
  late List<FurnitureItem> _improved;
  LightingSimSnapshot? _baseSim;
  LightingSimSnapshot? _optSim;
  LightingSimSnapshot? _myRigSim;
  String _myRigFingerprint = '';
  List<FurnitureItem> _myRigFurniture = const [];
  bool _myRigPushedToRig = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadSimulatedPrototypeBaseline(mode: 'lighting');
      _rebuild();
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _rebuild() {
    final source = RoomPresets.getPreset(RoomPreset.gamingSetup).furniture;
    _baseline = LightingPrototypeLayouts.baseline(source);
    _improved = LightingPrototypeLayouts.optimized(source);
    _baseSim = LightingSimulator.build(furniture: _baseline, optimized: false);
    _optSim = LightingSimulator.build(furniture: _improved, optimized: true);
    _seedMyRigFromBench(context.read<AppState>(), pushToRig: false);
    _ready = true;
    _step = _LightStep.layout;
    _layoutVariant = _Variant.current;
    _simVariant = _Variant.current;
    _showResults = false;
    setState(() {});
  }

  String _fingerprint(List<FurnitureItem> items) {
    return items
        .map((f) =>
            '${f.id}:${f.gridX.toStringAsFixed(2)},${f.gridY.toStringAsFixed(2)},'
            '${f.width},${f.height},${f.hidden}')
        .join('|');
  }

  void _seedMyRigFromBench(AppState state, {bool pushToRig = true}) {
    _myRigFurniture = _baseline.map((f) => f.copyWith()).toList(growable: false);
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
    _myRigSim = LightingSimulator.build(furniture: items, optimized: false);
  }

  void _syncMyRig(AppState state) {
    if (_layoutVariant != _Variant.myRig && _simVariant != _Variant.myRig) return;
    final items = state.furniture.where((f) => !f.hidden).toList(growable: false);
    final fp = _fingerprint(items);
    if (fp == _myRigFingerprint && _myRigSim != null) return;
    _myRigFurniture = items.map((f) => f.copyWith()).toList(growable: false);
    _rebuildMyRigSim();
  }

  List<FurnitureItem> _layoutFurnitureFor(AppState state) {
    switch (_layoutVariant) {
      case _Variant.improved:
        return _improved;
      case _Variant.myRig:
        return _myRigFurniture.where((f) => !f.hidden).toList(growable: false);
      case _Variant.current:
        return _baseline;
    }
  }

  LightingSimSnapshot? get _activeSim {
    switch (_simVariant) {
      case _Variant.improved:
        return _optSim;
      case _Variant.myRig:
        return _myRigSim;
      case _Variant.current:
        return _baseSim;
    }
  }

  Future<void> _runBench({bool fromMyRig = false}) async {
    setState(() {
      _running = true;
      _showResults = false;
      _progress = 0;
      _step = _LightStep.simulate;
      _simVariant = fromMyRig ? _Variant.myRig : _Variant.current;
    });
    if (fromMyRig) {
      _syncMyRig(context.read<AppState>());
      _rebuildMyRigSim();
      for (int i = 1; i <= 14; i++) {
        await Future.delayed(const Duration(milliseconds: 90));
        if (!mounted) return;
        setState(() => _progress = i / 14);
      }
      if (!mounted) return;
      setState(() {
        _running = false;
        _showResults = true;
        _step = _LightStep.results;
        _simVariant = _Variant.myRig;
      });
      return;
    }
    for (int i = 1; i <= 20; i++) {
      await Future.delayed(const Duration(milliseconds: 90));
      if (!mounted) return;
      setState(() {
        _progress = i / 20;
        if (i == 10) _simVariant = _Variant.improved;
      });
    }
    if (!mounted) return;
    context.read<AppState>().applyFurnitureLayout(_improved, markOptimized: true);
    setState(() {
      _running = false;
      _showResults = true;
      _step = _LightStep.results;
      _simVariant = _Variant.improved;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _syncMyRig(state);
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
            _layoutVariant == _Variant.myRig ? 'RUN MY RIG LIGHTING' : 'RUN LIGHTING BENCH',
            RoomSvg.scan,
            _running ? null : () => _runBench(fromMyRig: _layoutVariant == _Variant.myRig),
          ),
          const SizedBox(height: 8),
          Text(
            _layoutVariant == _Variant.myRig
                ? 'Starts from Bench lighting layout (fan included), pushes into Rig — edit there, then re-run.'
                : 'Compare a dark task zone vs a daylight + task-lamp rearrange, then score exposure.',
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
                  _simVariant == _Variant.myRig ? 'APPLY MY RIG TO RIG' : 'APPLY IMPROVED LAYOUT',
                  RoomSvg.star,
                  () {
                    if (_simVariant == _Variant.myRig) {
                      state.applyFurnitureLayout(_myRigFurniture);
                    } else {
                      state.applyFurnitureLayout(_improved, markOptimized: true);
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _simVariant == _Variant.myRig
                              ? 'My Rig layout applied to Rig'
                              : 'Improved lighting layout applied to Rig',
                        ),
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
              _iconButton(() {
                state.loadSimulatedPrototypeBaseline(mode: 'lighting');
                _rebuild();
              }),
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

  Widget _layoutSection(AppState state) {
    final notes = switch (_layoutVariant) {
      _Variant.improved => LightingPrototypeLayouts.optimizedNotes,
      _Variant.myRig => const [
          'Seeded from Bench Current — includes the stand fan',
          'Pushed into Rig so you can drag furniture there',
        ],
      _Variant.current => LightingPrototypeLayouts.baselineNotes,
    };
    final room = state.currentRoomData;
    final furniture = _layoutFurnitureFor(state);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LIGHTING LAYOUT PROTOTYPE',
          style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _chip('Current', _layoutVariant == _Variant.current, AppColors.amber, () {
              if (_layoutVariant == _Variant.current) return;
              HapticFeedback.selectionClick();
              setState(() {
                _layoutVariant = _Variant.current;
                _selectedFurnitureId = null;
              });
            }),
            const SizedBox(width: 8),
            _chip('Improved', _layoutVariant == _Variant.improved, AppColors.green, () {
              if (_layoutVariant == _Variant.improved) return;
              HapticFeedback.selectionClick();
              setState(() {
                _layoutVariant = _Variant.improved;
                _selectedFurnitureId = null;
              });
            }),
            const SizedBox(width: 8),
            _chip('My Rig', _layoutVariant == _Variant.myRig, AppColors.cyan, () {
              if (_layoutVariant == _Variant.myRig) return;
              HapticFeedback.selectionClick();
              if (!_myRigPushedToRig) {
                if (_myRigFurniture.isEmpty) {
                  _seedMyRigFromBench(state, pushToRig: true);
                } else {
                  state.applyFurnitureLayout(_myRigFurniture);
                  _myRigPushedToRig = true;
                  _rebuildMyRigSim();
                }
              } else {
                _myRigFurniture = state.furniture.map((f) => f.copyWith()).toList(growable: false);
                _rebuildMyRigSim();
              }
              setState(() {
                _layoutVariant = _Variant.myRig;
                _selectedFurnitureId = null;
              });
            }),
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
                  _Variant.current => 'Dark task zone — daylight blocked, lamp misplaced',
                  _Variant.improved => 'Daylight desk + task lamp — shelf cleared from the window path',
                  _Variant.myRig => 'Bench → Rig — fan layout seeded, edit on Rig',
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
                        key: ValueKey('${_layoutVariant.name}_${_roomView.name}_$_myRigFingerprint'),
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
                                child: CustomPaint(
                                  painter: BenchRoom3DPainter(
                                    roomWidth: 6,
                                    roomDepth: 8,
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
                        _layoutVariant == _Variant.improved
                            ? Icons.check_circle_outline
                            : Icons.warning_amber_rounded,
                        size: 14,
                        color: _layoutVariant == _Variant.improved ? AppColors.green : AppColors.amber,
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
    _syncMyRig(state);
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
            _chip('Current', _simVariant == _Variant.current, AppColors.amber, () {
              setState(() => _simVariant = _Variant.current);
            }),
            _chip('Improved', _simVariant == _Variant.improved, AppColors.green, () {
              setState(() => _simVariant = _Variant.improved);
            }),
            _chip('My Rig', _simVariant == _Variant.myRig, AppColors.cyan, () {
              _syncMyRig(state);
              _rebuildMyRigSim();
              setState(() => _simVariant = _Variant.myRig);
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
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) => _orbit(
              enabled: _simViz == LightingVizMode.orbit3D,
              child: CustomPaint(
                painter: LightingFieldPainter(
                  snapshot: sim,
                  vizMode: _simViz,
                  yaw: _yaw,
                  pitch: _pitch,
                  distance: _distance,
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

  Widget _results(AppState state) {
    final base = _baseSim!.metrics;
    final opt = _optSim!.metrics;
    final mine = _myRigSim?.metrics;
    return GlassCard(
      borderColor: AppColors.green.withValues(alpha: 0.4),
      child: Column(
        children: [
          Row(
            children: [
              SvgIcon(RoomSvg.trophy, size: 22, color: AppColors.amber),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Lighting Exposure Pass', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
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
              ScoreRing(score: base.exposureScore, size: 78, color: AppColors.amber, label: 'Before'),
              ScoreRing(score: opt.exposureScore, size: 78, color: AppColors.lightingColor, label: 'After'),
              if (mine != null)
                ScoreRing(score: mine.exposureScore, size: 78, color: AppColors.cyan, label: 'My Rig')
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
          BenchmarkValidationCard(
            validation: state.validateActiveLayout(mode: 'lighting'),
          ),
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

  Widget _orbit({required Widget child, bool enabled = true}) {
    if (!enabled) return SizedBox.expand(child: child);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          _yaw = _defaultYaw;
          _pitch = _defaultPitch;
          _distance = _defaultDistance;
        });
      },
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
        onPointerUp: (_) => setState(() {
          _orbitDragging = false;
          _orbitPointer = null;
        }),
        onPointerCancel: (_) => setState(() {
          _orbitDragging = false;
          _orbitPointer = null;
        }),
        onPointerSignal: (signal) {
          if (signal is PointerScrollEvent) {
            setState(() => _distance = (_distance + signal.scrollDelta.dy * 0.02).clamp(10.0, 28.0));
          }
        },
        child: SizedBox.expand(child: ColoredBox(color: Colors.transparent, child: child)),
      ),
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
