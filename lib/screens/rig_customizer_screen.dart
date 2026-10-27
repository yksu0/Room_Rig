// lib/screens/rig_customizer_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/rig_catalog.dart';
import '../models/room_model.dart';
import '../models/room_scale.dart';
import '../models/sim_room_bounds.dart';
import '../models/surface_mount.dart';
import '../services/autorug_ranker.dart';
import '../services/bench_layouts.dart';
import '../models/scan_layout_model.dart';
import '../services/layout_collision.dart';
import '../services/layout_snap_guides.dart';
import '../theme/app_layout.dart';
import '../theme/app_money.dart';
import '../theme/app_theme.dart';
import '../widgets/active_room_chip.dart';
import '../widgets/confirm_dialogs.dart';
import '../widgets/room_status_strip.dart';
import '../widgets/rig_customizer/rig_scan_action_button.dart';
import '../widgets/glass_card.dart';
import '../widgets/furniture_shapes.dart';
import '../widgets/room_icons.dart';
import '../widgets/room_orbit_projection.dart';
import '../widgets/room_plan_geometry.dart';
import '../widgets/rig_customizer/rig_drag_magnifier.dart';
import '../widgets/rig_customizer/rig_furniture_cell.dart';
import '../widgets/rig_customizer/rig_room_items_drawer.dart';
import '../widgets/rig_customizer/room_grid_painter.dart';
import '../widgets/rig_customizer/room_orbit_3d_painter.dart';
import '../widgets/room_model_scene.dart';
import '../widgets/airflow_voxel_painter.dart';
import '../widgets/chrome/adaptive_panel.dart';
import '../widgets/dash_path.dart';
import '../widgets/ergonomics_field_painter.dart';
import '../widgets/lighting_field_painter.dart';
import '../widgets/rig_live_field_overlay.dart';
import '../services/airflow_simulator.dart';

enum _RigViewMode { twoD, threeD, model3D }
enum _OptimizeGoal { balanced, airflow, lighting, ergonomics, spatial }


Color _categoryColor(String cat) {
  switch (cat) {
    case 'airflow':
      return AppColors.airflowColor;
    case 'lighting':
      return AppColors.lightingColor;
    case 'ergonomics':
      return AppColors.ergonomicsColor;
    default:
      return AppColors.textMuted;
  }
}


class RigCustomizerScreen extends StatefulWidget {
  const RigCustomizerScreen({super.key});

  @override
  State<RigCustomizerScreen> createState() => _RigCustomizerScreenState();
}

class _RigCustomizerScreenState extends State<RigCustomizerScreen>
    with SingleTickerProviderStateMixin {
  static const double _minTouchTarget = 46;
  static const _liveDebounce = Duration(milliseconds: 300);

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  _RigViewMode _viewMode = _RigViewMode.twoD;
  _OptimizeGoal _optimizeGoal = _OptimizeGoal.balanced;
  double _cameraYawRad = 0;
  double _cameraPitchRad = 0.34;
  double _cameraDistance = 15;
  double _scaleStartDistance = 15;
  /// Orbit pivot on the floor — two-finger drag pans this off room center.
  double? _lookAtX;
  double? _lookAtZ;
  bool _furnitureDetailsExpanded = false;
  bool _scanDetailsExpanded = false;
  String _sidebarQuery = '';
  String? _sidebarCategory; // null = all
  double _sidebarMinConfidence = 0; // 0, 0.5, 0.7, 0.85

  /// Set while a single-finger drag in the 3D view is moving an item rather
  /// than orbiting the camera.
  String? _dragItemId;
  Offset? _dragGrabOffset;
  String? _pendingDragId;
  Offset? _pendingGrabOffset;

  /// Where the finger touched down in the 3D canvas, before touch slop.
  Offset? _pointerDownPos;

  /// Lift preview follows the finger while dragging in 2D or 3D.
  Offset? _dragPointerLocal;

  /// 2D canvas drag — unified pointer handler (matches 3D grab-offset model).
  String? _drag2dItemId;
  Offset? _drag2dGrab;
  Offset? _drag2dPointerDown;
  bool _drag2dGestureStarted = false;
  static const _drag2dSlop = 10.0;

  RigLiveDomain _liveDomain = RigLiveDomain.none;
  final _liveCache = RigLiveFieldCache();
  Timer? _liveDebounceTimer;
  late final AnimationController _liveParticleTicker;

  @override
  void initState() {
    super.initState();
    _liveParticleTicker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_stepLiveParticles);
  }

  @override
  void dispose() {
    _liveDebounceTimer?.cancel();
    _liveParticleTicker.dispose();
    super.dispose();
  }

  void _stepLiveParticles() {
    final snap = _liveCache.airflow;
    if (!mounted ||
        _liveDomain != RigLiveDomain.airflow ||
        snap == null ||
        !_liveParticleTicker.isAnimating) {
      return;
    }
    AirflowSimulator.stepParticles(
      snap,
      dt: 0.045,
      time: _liveParticleTicker.lastElapsedDuration?.inMilliseconds.toDouble() ?? 0,
    );
  }

  void _syncLiveParticleTicker() {
    final want = _liveDomain == RigLiveDomain.airflow && _liveCache.airflow != null;
    if (want && !_liveParticleTicker.isAnimating) {
      _liveParticleTicker.repeat();
    } else if (!want && _liveParticleTicker.isAnimating) {
      _liveParticleTicker.stop();
    }
  }

  /// Adaptive supporting panes (compact sheet; expanded rails later).
  CameraPreset? _pendingPreset;
  // Mini-map / focus UI removed from View; keep Model scene wiring off.
  final bool _showMiniMap = false;
  bool _showDimensions = false;
  final int _focusToken = 0;

  ChromeViewMode _chromeForViewMode(_RigViewMode m) => switch (m) {
        _RigViewMode.twoD => ChromeViewMode.edit,
        _RigViewMode.threeD => ChromeViewMode.orbit,
        _RigViewMode.model3D => ChromeViewMode.check,
      };

  void _applyChromeView(ChromeViewMode mode) {
    setState(() {
      _viewMode = switch (mode) {
        ChromeViewMode.edit => _RigViewMode.twoD,
        ChromeViewMode.orbit => _RigViewMode.threeD,
        ChromeViewMode.check => _RigViewMode.model3D,
      };
    });
  }

  void _maybeOpenToolsAfterLanding(AppState state, {required bool desktop}) {
    // IndexedStack builds Rig even off-tab — only consume when Rig is showing.
    if (state.currentTab != 2) return;
    if (!state.consumeOpenToolsOnRig) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (desktop) {
        // Tools rail is already visible; nudge empty lots toward catalog starters.
        final movable = state.furniture
            .where((f) => f.iconName != 'door' && f.iconName != 'window')
            .isEmpty;
        if (movable) _showAddItemSheet();
        return;
      }
      _adaptivePanelControllerFor(state).openPanel(context, ChromeRegion.tools);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    final desktop = AppLayout.isDesktop(context);
    _maybeOpenToolsAfterLanding(state, desktop: desktop);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.bg,
      endDrawer: desktop
          ? null
          : RigRoomItemsDrawer(
              sidebarQuery: _sidebarQuery,
              sidebarCategory: _sidebarCategory,
              sidebarMinConfidence: _sidebarMinConfidence,
              onQueryChanged: (v) => setState(() => _sidebarQuery = v),
              onCategoryChanged: (cat) => setState(() => _sidebarCategory = cat),
              onMinConfidenceChanged: (v) =>
                  setState(() => _sidebarMinConfidence = v),
            ),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, state, desktop: desktop),
            Expanded(
              child: desktop
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        final toolsW = AppLayout.toolsRailWidthFor(context);
                        final inspectW = AppLayout.inspectRailWidthFor(context);
                        // Keep a usable canvas on landscape-phone / narrow desktop.
                        final maxRail = (constraints.maxWidth - 280).clamp(0.0, constraints.maxWidth);
                        final scale = (toolsW + inspectW) > maxRail && (toolsW + inspectW) > 0
                            ? maxRail / (toolsW + inspectW)
                            : 1.0;
                        final tw = toolsW * scale;
                        final iw = inspectW * scale;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: tw,
                              child: DecoratedBox(
                                decoration: const BoxDecoration(
                                  border: Border(
                                    right: BorderSide(color: AppColors.borderSubtle),
                                  ),
                                ),
                                child: AdaptiveRailPane(
                                  title: 'Workspace',
                                  icon: Icons.tune_rounded,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildViewPanelBody(state, embedded: true),
                                      const SizedBox(height: 20),
                                      const Divider(color: AppColors.borderSubtle),
                                      const SizedBox(height: 12),
                                      _buildToolsPanelBody(context, state, embedded: true),
                                      const SizedBox(height: 20),
                                      const Divider(color: AppColors.borderSubtle),
                                      const SizedBox(height: 12),
                                      _buildSnapshotPanelBody(context, state),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Expanded(child: _buildCanvasWorkspace(state)),
                            SizedBox(
                              width: iw,
                              child: DecoratedBox(
                                decoration: const BoxDecoration(
                                  border: Border(
                                    left: BorderSide(color: AppColors.borderSubtle),
                                  ),
                                ),
                                child: RigRoomItemsDrawer(
                                  embedded: true,
                                  sidebarQuery: _sidebarQuery,
                                  sidebarCategory: _sidebarCategory,
                                  sidebarMinConfidence: _sidebarMinConfidence,
                                  onQueryChanged: (v) =>
                                      setState(() => _sidebarQuery = v),
                                  onCategoryChanged: (cat) =>
                                      setState(() => _sidebarCategory = cat),
                                  onMinConfidenceChanged: (v) =>
                                      setState(() => _sidebarMinConfidence = v),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    )
                  : _buildCanvasWorkspace(state),
            ),
          ],
        ),
      ),
    );
  }

  /// Selected unlocked item (or Place ghost) → drag furniture; otherwise orbit.
  bool _furnitureDragArmed(AppState state) {
    if (state.hasPendingPlacement) return true;
    final sel = state.selectedFurniture;
    return sel != null &&
        !state.selectedIsScanObject &&
        state.canMoveFurniture(sel);
  }

  Widget _buildCanvasWorkspace(AppState state) {
    final selectedFurniture = state.selectedFurniture;
    final selectedScanObject = state.selectedScanObject;
    const topChromeRight = 8.0;
    final topChromeTop = _viewMode == _RigViewMode.model3D ? 40.0 : 8.0;
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildCanvas(state),
              // Selection + conflicts share one top column so they never overlap.
              if (selectedFurniture != null &&
                  !state.hasPendingPlacement &&
                  !_drag2dGestureStarted &&
                  _drag2dItemId == null)
                Positioned(
                  left: 8,
                  right: topChromeRight,
                  top: topChromeTop,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (state.layoutConflicts.isNotEmpty) ...[
                        IgnorePointer(
                          child: _ConflictBanner(conflicts: state.layoutConflicts),
                        ),
                        const SizedBox(height: 6),
                      ],
                      _buildFurnitureInfoCard(state, selectedFurniture),
                    ],
                  ),
                )
              else if (state.layoutConflicts.isNotEmpty)
                Positioned(
                  left: 10,
                  right: topChromeRight,
                  top: topChromeTop,
                  child: IgnorePointer(
                    child: _ConflictBanner(conflicts: state.layoutConflicts),
                  ),
                ),
              if (_showDimensions && _viewMode == _RigViewMode.twoD) ...[
                Positioned(
                  left: 16,
                  bottom: 12,
                  child: _DimensionsHint(room: state.currentRoomData),
                ),
                if (selectedFurniture != null && !state.selectedIsScanObject)
                  Positioned(
                    right: 16,
                    bottom: 12,
                    child: _SelectedItemSizeChip(item: selectedFurniture),
                  ),
              ],
              if (state.hasApplyGhost)
                Positioned(
                  top: _viewMode == _RigViewMode.model3D ? 40 : 56,
                  left: 12,
                  right: 12,
                  child: _ApplyGhostBanner(
                    onDismiss: state.clearApplyGhost,
                  ),
                ),
              if (state.layoutConflicts.isNotEmpty &&
                  (_dragItemId != null || _drag2dItemId != null))
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.red.withValues(alpha: 0.55),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        color: AppColors.red.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (state.hasPendingPlacement) _buildPlacementBar(state),
        if (selectedScanObject != null)
          _buildScanInfoCard(state, selectedScanObject),
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context,
    AppState state, {
    required bool desktop,
  }) {
    final dims = state.activeRoomLayout?.dimensions;
    final lengthMeters = dims != null && dims.lengthMeters > 0
        ? dims.lengthMeters
        : RoomScale.metersFromCells(state.currentRoomData.gridCols);
    final widthMeters = dims != null && dims.widthMeters > 0
        ? dims.widthMeters
        : RoomScale.metersFromCells(state.currentRoomData.gridRows);
    final heightMeters = dims != null && dims.heightMeters > 0
        ? dims.heightMeters
        : state.currentRoomData.heightMeters;
    final sizeLabel =
        '${RoomScale.formatMeters(lengthMeters)} × '
        '${RoomScale.formatMeters(widthMeters)} × '
        '${RoomScale.formatMeters(heightMeters)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.screen, AppSpace.sm, AppSpace.screen, AppSpace.xs),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RIG CUSTOMIZER',
                      style: TextStyle(color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2.8),
                    ),
                    const SizedBox(height: 6),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: ActiveRoomChip(),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sizeLabel,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    // Scores / ROUGH EST. live on Hub + Bench — omit strip here so
                    // mobile Rig header stays short.
                    if (desktop) ...[
                      const SizedBox(height: 8),
                      const RoomStatusStrip(compact: true),
                    ],
                  ],
                ),
              ),
              _HistoryButton(
                icon: Icons.undo_rounded,
                enabled: state.canUndoLayout,
                tooltip: 'Undo layout',
                onTap: state.canUndoLayout ? state.undoLayout : null,
              ),
              const SizedBox(width: AppSpace.xs),
              _HistoryButton(
                icon: Icons.redo_rounded,
                enabled: state.canRedoLayout,
                tooltip: 'Redo layout',
                onTap: state.canRedoLayout ? state.redoLayout : null,
              ),
              if (state.hasCompareSnapshot) ...[
                const SizedBox(width: AppSpace.xs),
                _HistoryButton(
                  icon: Icons.restore_rounded,
                  enabled: true,
                  tooltip: 'Restore original',
                  onTap: () => _confirmRestoreOriginal(state),
                ),
              ],
              const SizedBox(width: AppSpace.xs),
              _AddItemButton(onTap: _showAddItemSheet),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          // 2D / Orbit / Model lives only in the View panel (not duplicated here).
          if (desktop)
            RigLiveDomainBar(
              domain: _liveDomain,
              score: _liveCache.score,
              detail: _liveCache.isStale
                  ? '${_liveCache.detail} · updating…'
                  : _liveCache.detail,
              onChanged: (d) => _setLiveDomain(state, d),
            )
          else
            _RigChromeScrollRow(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AdaptivePanelTriggers(
                    controller: _adaptivePanelControllerFor(state),
                    visible: const [
                      ChromeRegion.view,
                      ChromeRegion.tools,
                      ChromeRegion.snapshot,
                      ChromeRegion.inspect,
                    ],
                    regionLabels: const {
                      ChromeRegion.inspect: 'Items',
                    },
                    regionActions: {
                      ChromeRegion.inspect: () {
                        _scaffoldKey.currentState?.openEndDrawer();
                      },
                    },
                  ),
                  const SizedBox(width: 6),
                  RigLiveDomainBar(
                    compactMenu: true,
                    domain: _liveDomain,
                    score: _liveCache.score,
                    detail: _liveCache.isStale
                        ? '${_liveCache.detail} · updating…'
                        : _liveCache.detail,
                    onChanged: (d) => _setLiveDomain(state, d),
                  ),
                  // Room so the last chip isn't flush against the fade edge.
                  const SizedBox(width: 20),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _setLiveDomain(AppState state, RigLiveDomain d) {
    _liveDebounceTimer?.cancel();
    setState(() {
      _liveDomain = d;
      _refreshLiveFieldNow(state);
      _syncLiveParticleTicker();
    });
  }

  List<RigLiveFieldCell> _liveFieldCells(AppState state) {
    if (_liveDomain == RigLiveDomain.none) return const [];
    _scheduleLiveFieldRefresh(state);
    return sampleRigLiveFieldCells(
      domain: _liveDomain,
      gridCols: state.currentRoomData.gridCols,
      gridRows: state.currentRoomData.gridRows,
      airflow: _liveCache.airflow,
      lighting: _liveCache.lighting,
      ergonomics: _liveCache.ergonomics,
      maxAxis: 36,
    );
  }

  /// Model scene uses metres; convert grid-cell samples for the WebGL floor.
  List<Map<String, dynamic>> _liveFieldCellsMeters(AppState state) {
    final cells = _liveFieldCells(state);
    if (cells.isEmpty) return const [];
    final cols = state.currentRoomData.gridCols;
    final rows = state.currentRoomData.gridRows;
    final cellW = RoomScale.metersFromCells(cols) / cols;
    final cellD = RoomScale.metersFromCells(rows) / rows;
    return [
      for (final c in cells)
        {
          'x0': c.x0 * cellW,
          'z0': c.z0 * cellD,
          'x1': c.x1 * cellW,
          'z1': c.z1 * cellD,
          'r': c.color.r,
          'g': c.color.g,
          'b': c.color.b,
          'a': c.color.a,
        },
    ];
  }

  String _liveFurnitureFingerprint(AppState state) {
    final parts = state.committedFurniture
        .map(
          (f) =>
              '${f.id}:${f.gridX.toStringAsFixed(2)},${f.gridY.toStringAsFixed(2)},'
              '${f.width.toStringAsFixed(2)},${f.height.toStringAsFixed(2)},'
              '${f.yawDegrees.toStringAsFixed(0)}',
        )
        .toList()
      ..sort();
    return parts.join('|');
  }

  SimRoomBounds _boundsFor(AppState state) =>
      SimRoomBounds.fromRoomData(state.currentRoomData);

  void _refreshLiveFieldNow(AppState state) {
    _liveCache.refresh(
      domain: _liveDomain,
      furniture: state.committedFurniture,
      fingerprint: _liveFurnitureFingerprint(state),
      bounds: _boundsFor(state),
    );
    _syncLiveParticleTicker();
  }

  /// Debounce sim rebuild while arranging; keep last snapshot visible.
  void _scheduleLiveFieldRefresh(AppState state) {
    if (_liveDomain == RigLiveDomain.none) return;
    final bounds = _boundsFor(state);
    final fp =
        '${_liveFurnitureFingerprint(state)}|${bounds.width}x${bounds.depth}x${bounds.height}';
    if (_liveCache.domain == _liveDomain && _liveCache.fingerprint == fp) {
      _liveCache.isStale = false;
      return;
    }
    _liveCache.isStale = true;
    _liveDebounceTimer?.cancel();
    _liveDebounceTimer = Timer(_liveDebounce, () {
      if (!mounted) return;
      final latest = context.read<AppState>();
      setState(() => _refreshLiveFieldNow(latest));
    });
  }

  double get _liveParticleTimeMs =>
      _liveParticleTicker.lastElapsedDuration?.inMilliseconds.toDouble() ?? 0;

  Widget? _liveBenchOverlay2D({
    required Size canvasSize,
    required Rect roomRect,
    required int gridCols,
    required int gridRows,
    required List<FurnitureItem> furniture,
  }) {
    if (_liveDomain == RigLiveDomain.none) return null;
    // Field is solved at room size — map 1:1 (no stretch).
    switch (_liveDomain) {
      case RigLiveDomain.airflow:
        final snap = _liveCache.airflow;
        if (snap == null) return null;
        return AnimatedBuilder(
          animation: _liveParticleTicker,
          builder: (context, _) => CustomPaint(
            size: canvasSize,
            painter: AirflowVoxelPainter(
              snapshot: snap,
              furniture: furniture,
              vizMode: AirflowVizMode.topDown2D,
              yaw: 0,
              pitch: 0.5,
              distance: 12,
              time: _liveParticleTimeMs,
              gridCols: gridCols,
              gridRows: gridRows,
              paintScene: false,
              overlayRect: roomRect,
              overlayRoomWidth: snap.field.roomWidth,
              overlayRoomDepth: snap.field.roomDepth,
            ),
          ),
        );
      case RigLiveDomain.lighting:
        final snap = _liveCache.lighting;
        if (snap == null) return null;
        return CustomPaint(
          size: canvasSize,
          painter: LightingFieldPainter(
            snapshot: snap,
            furniture: furniture,
            vizMode: LightingVizMode.topDown2D,
            yaw: 0,
            pitch: 0.5,
            distance: 12,
            paintScene: false,
            overlayRect: roomRect,
            overlayRoomWidth: snap.roomWidth,
            overlayRoomDepth: snap.roomDepth,
          ),
        );
      case RigLiveDomain.ergonomics:
        final snap = _liveCache.ergonomics;
        if (snap == null) return null;
        return CustomPaint(
          size: canvasSize,
          painter: ErgonomicsFieldPainter(
            snapshot: snap,
            vizMode: ErgonomicsVizMode.topDown2D,
            yaw: 0,
            pitch: 0.5,
            distance: 12,
            paintScene: false,
            overlayRect: roomRect,
            overlayRoomWidth: snap.roomWidth,
            overlayRoomDepth: snap.roomDepth,
          ),
        );
      case RigLiveDomain.none:
        return null;
    }
  }

  Widget? _liveBenchOverlayOrbit({
    required Size canvasSize,
    required int gridCols,
    required int gridRows,
    required List<FurnitureItem> furniture,
  }) {
    if (_liveDomain == RigLiveDomain.none) return null;
    switch (_liveDomain) {
      case RigLiveDomain.airflow:
        final snap = _liveCache.airflow;
        if (snap == null) return null;
        return IgnorePointer(
          child: AnimatedBuilder(
            animation: _liveParticleTicker,
            builder: (context, _) => CustomPaint(
              size: canvasSize,
              painter: AirflowVoxelPainter(
                snapshot: snap,
                furniture: furniture,
                vizMode: AirflowVizMode.orbit3D,
                yaw: _cameraYawRad,
                pitch: _cameraPitchRad,
                distance: _cameraDistance,
                lookAtX: _lookAtX,
                lookAtZ: _lookAtZ,
                time: _liveParticleTimeMs,
                gridCols: gridCols,
                gridRows: gridRows,
                paintScene: false,
                overlayRoomWidth: snap.field.roomWidth,
                overlayRoomDepth: snap.field.roomDepth,
              ),
            ),
          ),
        );
      case RigLiveDomain.lighting:
        final snap = _liveCache.lighting;
        if (snap == null) return null;
        return IgnorePointer(
          child: CustomPaint(
            size: canvasSize,
            painter: LightingFieldPainter(
              snapshot: snap,
              furniture: furniture,
              vizMode: LightingVizMode.orbit3D,
              yaw: _cameraYawRad,
              pitch: _cameraPitchRad,
              distance: _cameraDistance,
              lookAtX: _lookAtX,
              lookAtZ: _lookAtZ,
              paintScene: false,
              overlayRoomWidth: snap.roomWidth,
              overlayRoomDepth: snap.roomDepth,
            ),
          ),
        );
      case RigLiveDomain.ergonomics:
        final snap = _liveCache.ergonomics;
        if (snap == null) return null;
        return IgnorePointer(
          child: CustomPaint(
            size: canvasSize,
            painter: ErgonomicsFieldPainter(
              snapshot: snap,
              vizMode: ErgonomicsVizMode.orbit3D,
              yaw: _cameraYawRad,
              pitch: _cameraPitchRad,
              distance: _cameraDistance,
              lookAtX: _lookAtX,
              lookAtZ: _lookAtZ,
              paintScene: false,
              overlayRoomWidth: snap.roomWidth,
              overlayRoomDepth: snap.roomDepth,
            ),
          ),
        );
      case RigLiveDomain.none:
        return null;
    }
  }

  void _maybeCloseSupportingSheet() {
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.maybePop();
  }

  AdaptivePanelController _adaptivePanelControllerFor(AppState state) {
    return AdaptivePanelController([
      AdaptivePanelSpec(
        region: ChromeRegion.view,
        preferTall: true,
        builder: (ctx) => _buildViewPanelBody(state, embedded: false),
      ),
      AdaptivePanelSpec(
        region: ChromeRegion.tools,
        preferTall: true,
        builder: (ctx) => _buildToolsPanelBody(ctx, state, embedded: false),
      ),
      AdaptivePanelSpec(
        region: ChromeRegion.snapshot,
        preferTall: true,
        builder: (ctx) => _buildSnapshotPanelBody(ctx, state),
      ),
      AdaptivePanelSpec(
        region: ChromeRegion.inspect,
        builder: (ctx) => _buildInspectPanelBody(ctx, state, embedded: false),
      ),
    ]);
  }

  Widget _buildViewPanelBody(AppState state, {required bool embedded}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChromeViewModeChips(
          selected: _chromeForViewMode(_viewMode),
          onChanged: (m) {
            _applyChromeView(m);
            if (!embedded) _maybeCloseSupportingSheet();
          },
        ),
        const SizedBox(height: 16),
        Text(
          'CAMERA PRESETS',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        CameraPresetChips(
          onSelect: (p) {
            setState(() {
              if (_viewMode == _RigViewMode.model3D) {
                _pendingPreset = p;
              } else {
                // Stay on Orbit (or open Orbit from 2D) — do not force Model.
                _viewMode = _RigViewMode.threeD;
                _applyOrbitCameraPreset(p, state);
              }
            });
            if (!embedded) _maybeCloseSupportingSheet();
          },
        ),
      ],
    );
  }

  /// Approximate Model camera presets for the Orbit painter (grid-cell space).
  void _applyOrbitCameraPreset(CameraPreset preset, AppState state) {
    final cols = state.currentRoomData.gridCols.toDouble();
    final rows = state.currentRoomData.gridRows.toDouble();
    final cx = cols * 0.5;
    final cz = rows * 0.5;
    final span = math.max(cols, rows);
    switch (preset) {
      case CameraPreset.birdseye:
        _lookAtX = cx;
        _lookAtZ = cz;
        _cameraYawRad = 0;
        _cameraPitchRad = 1.15;
        _cameraDistance = (span * 1.15).clamp(8.0, 28.0);
        break;
      case CameraPreset.cornerA:
        _lookAtX = cx;
        _lookAtZ = cz;
        _cameraYawRad = 0.75;
        _cameraPitchRad = 0.38;
        _cameraDistance = (span * 0.95).clamp(8.0, 24.0);
        break;
      case CameraPreset.cornerB:
        _lookAtX = cx;
        _lookAtZ = cz;
        _cameraYawRad = -2.35;
        _cameraPitchRad = 0.38;
        _cameraDistance = (span * 0.95).clamp(8.0, 24.0);
        break;
      case CameraPreset.eyeLevel:
        _lookAtX = cx;
        _lookAtZ = cz;
        _cameraYawRad = 0;
        _cameraPitchRad = 0.18;
        _cameraDistance = (span * 0.85).clamp(7.0, 22.0);
        break;
      case CameraPreset.door:
        _lookAtX = cx;
        _lookAtZ = cz;
        _cameraYawRad = math.pi;
        _cameraPitchRad = 0.28;
        _cameraDistance = (span * 0.9).clamp(7.0, 22.0);
        break;
      case CameraPreset.ceiling:
        _lookAtX = cx;
        _lookAtZ = cz;
        _cameraYawRad = 0.4;
        _cameraPitchRad = -0.35;
        _cameraDistance = (span * 0.7).clamp(6.0, 18.0);
        break;
    }
  }

  Widget _buildSnapshotPanelBody(BuildContext ctx, AppState state) {
    return _RigSnapshotPanel(
      state: state,
      onCloseSheet: _maybeCloseSupportingSheet,
    );
  }

  Widget _buildToolsPanelBody(
    BuildContext ctx,
    AppState state, {
    required bool embedded,
  }) {
    final selected = state.selectedFurniture;
    final canEdit = selected != null && !state.selectedIsScanObject && state.canMoveFurniture(selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'EDIT',
          style: TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.4),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _ToolActionChip(
              label: 'Rotate −90°',
              icon: Icons.rotate_left_rounded,
              enabled: canEdit,
              onTap: () {
                if (selected != null) _rotateSelected(state, selected, -90);
              },
            ),
            _ToolActionChip(
              label: 'Rotate +90°',
              icon: Icons.rotate_right_rounded,
              enabled: canEdit,
              onTap: () {
                if (selected != null) _rotateSelected(state, selected, 90);
              },
            ),
            _ToolActionChip(
              label: 'Flip',
              icon: Icons.flip_rounded,
              enabled: canEdit,
              onTap: () {
                if (selected != null) _rotateSelected(state, selected, 180);
              },
            ),
            _ToolActionChip(
              label: 'Duplicate',
              icon: Icons.copy_rounded,
              enabled: canEdit,
              onTap: () {
                if (selected != null) state.duplicateFurniture(selected.id);
              },
            ),
            _ToolActionChip(
              label: 'Align wall',
              icon: Icons.align_horizontal_left_rounded,
              enabled: canEdit,
              onTap: () {
                if (selected != null) _alignSelectedToNearestWall(state, selected);
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Material Switch (not adaptive): Cupertino thumb is drag-first and
        // modal sheets do not rebuild on parent setState without setLocal.
        StatefulBuilder(
          builder: (context, setLocal) {
            return SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              title: const Text('Dimensions', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              subtitle: const Text('Show cm labels on the plan', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              value: _showDimensions,
              activeThumbColor: AppColors.cyan,
              onChanged: (v) {
                setLocal(() => _showDimensions = v);
                setState(() {});
              },
            );
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _InvasiveEditToggle(
              invasive: state.invasiveEdit,
              onChanged: state.setInvasiveEdit,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                state.invasiveEdit
                    ? 'Invasive — wall mounts can be deleted/duplicated freely'
                    : 'Unlock items to move. Wall openings stay on walls when dragged.',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          'AUTO-RIG — REARRANGE MY INVENTORY',
          style: TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.4),
        ),
        const SizedBox(height: 6),
        const Text(
          'Moves items already on this Rig. Does not add catalog stock.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _GoalChip(
              label: 'Balanced',
              color: AppColors.cyan,
              active: _optimizeGoal == _OptimizeGoal.balanced,
              onTap: () {
                setState(() => _optimizeGoal = _OptimizeGoal.balanced);
                state.applyOptimizeGoalPreset('balanced');
              },
            ),
            _GoalChip(
              label: 'Airflow',
              color: AppColors.airflowColor,
              active: _optimizeGoal == _OptimizeGoal.airflow,
              onTap: () {
                setState(() => _optimizeGoal = _OptimizeGoal.airflow);
                state.applyOptimizeGoalPreset('airflow');
              },
            ),
            _GoalChip(
              label: 'Lighting',
              color: AppColors.lightingColor,
              active: _optimizeGoal == _OptimizeGoal.lighting,
              onTap: () {
                setState(() => _optimizeGoal = _OptimizeGoal.lighting);
                state.applyOptimizeGoalPreset('lighting');
              },
            ),
            _GoalChip(
              label: 'Ergonomics',
              color: AppColors.ergonomicsColor,
              active: _optimizeGoal == _OptimizeGoal.ergonomics,
              onTap: () {
                setState(() => _optimizeGoal = _OptimizeGoal.ergonomics);
                state.applyOptimizeGoalPreset('ergonomics');
              },
            ),
            _GoalChip(
              label: 'Space',
              color: AppColors.spatialColor,
              active: _optimizeGoal == _OptimizeGoal.spatial,
              onTap: () {
                setState(() => _optimizeGoal = _OptimizeGoal.spatial);
                state.applyOptimizeGoalPreset('spatial');
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        StatefulBuilder(
          builder: (context, setLocal) {
            return SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              secondary: const Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.cyan,
                size: 22,
              ),
              title: const Text('AI layout sort', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              subtitle: Text(
                AutoRigRanker.isLoaded
                    ? 'Rank Auto-Rig candidates with on-device weights (off by default)'
                    : 'Ranker weights not loaded — toggle has no effect yet',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              value: AutoRigRanker.enabled,
              activeThumbColor: AppColors.cyan,
              onChanged: AutoRigRanker.isLoaded
                  ? (v) {
                      AutoRigRanker.enabled = v;
                      setLocal(() {});
                      setState(() {});
                    }
                  : null,
            );
          },
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(64, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                onPressed: () {
                  Navigator.of(ctx).maybePop();
                  _runAutoRig(context, state);
                },
                child: const Text('Auto-Rig'),
              ),
            ),
          ],
        ),
        if (state.lastOptimizeReasons.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...state.lastOptimizeReasons.take(2).map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(r, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInspectPanelBody(
    BuildContext ctx,
    AppState state, {
    required bool embedded,
  }) {
    final selected = state.selectedFurniture;
    final scanObj = state.selectedScanObject;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selected != null) ...[
          Text(
            selected.name,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _InspectImpactChip(
                label: 'Air',
                value: selected.airflowImpact,
                color: AppColors.airflowColor,
              ),
              const SizedBox(width: 8),
              _InspectImpactChip(
                label: 'Light',
                value: selected.lightingImpact,
                color: AppColors.lightingColor,
              ),
              const SizedBox(width: 8),
              _InspectImpactChip(
                label: 'Ergo',
                value: selected.ergonomicsImpact,
                color: AppColors.ergonomicsColor,
              ),
            ],
          ),
          if (selected.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              selected.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 14),
        ] else if (scanObj != null) ...[
          Text(
            scanObj.label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Scan object · ${scanObj.category}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 14),
        ],
        Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.of(ctx).maybePop();
              _scaffoldKey.currentState?.openEndDrawer();
            },
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minVerticalPadding: 12,
              leading: const Icon(Icons.list_alt_rounded, color: AppColors.cyan, size: 26),
              title: const Text(
                'Room items',
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15),
              ),
              subtitle: Text(
                '${state.furniture.length} pieces',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 26),
            ),
          ),
        ),
        if (state.layoutConflicts.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '${state.layoutConflicts.length} layout warning(s)',
            style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 6),
          ...state.layoutConflicts.take(4).map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                c.message,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _alignSelectedToNearestWall(AppState state, FurnitureItem item) {
    final room = state.currentRoomData;
    final cx = item.gridX + item.width * 0.5;
    final cy = item.gridY + item.height * 0.5;
    final distLeft = cx;
    final distRight = room.gridCols - cx;
    final distTop = cy;
    final distBottom = room.gridRows - cy;
    final minD = [distLeft, distRight, distTop, distBottom].reduce((a, b) => a < b ? a : b);
    double nx = item.gridX;
    double ny = item.gridY;
    if (minD == distLeft) {
      nx = 0;
    } else if (minD == distRight) {
      nx = (room.gridCols - item.width).toDouble();
    } else if (minD == distTop) {
      ny = 0;
    } else {
      ny = (room.gridRows - item.height).toDouble();
    }
    state.moveFurniture(item.id, nx, ny);
  }

  Future<void> _runAutoRig(BuildContext context, AppState state) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Run Auto-Rig?', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Auto-Rig rearranges items already on this Rig — it does not add '
          'catalog pieces. Run best picks the top layout; Try alternate cycles '
          'other ranked layouts for the same set.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
            onPressed: () =>
                Navigator.of(ctx, rootNavigator: true).pop('alternate'),
            child: const Text('Try alternate'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () =>
                Navigator.of(ctx, rootNavigator: true).pop('best'),
            child: const Text('Run best'),
          ),
        ],
      ),
    );
    if (confirmed != 'best' && confirmed != 'alternate' || !mounted) return;

    final beforeFp = BenchLayoutBuilder.fingerprintOf(state.furniture);
    final goal = switch (_optimizeGoal) {
      _OptimizeGoal.airflow => 'airflow',
      _OptimizeGoal.lighting => 'lighting',
      _OptimizeGoal.ergonomics => 'ergonomics',
      _OptimizeGoal.spatial => 'spatial',
      _OptimizeGoal.balanced => null,
    };
    final tryAlternate = confirmed == 'alternate';
    if (goal == null) {
      state.runOptimization(tryAlternate: tryAlternate);
    } else {
      state.runOptimization(goal: goal, tryAlternate: tryAlternate);
    }
    if (BenchLayoutBuilder.fingerprintOf(state.furniture) == beforeFp) return;
    if (!mounted) return;

    final mix = state.optimizeWeights.summaryLabel;
    final rank = state.lastAutoRigRankLabel;
    final headline = rank.isEmpty ? 'Auto-Rig applied · $mix' : '$rank · $mix';
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SvgIcon(RoomSvg.star, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(headline)),
          ],
        ),
        backgroundColor: AppColors.cyan.withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  int _orbitYawDegrees() {
    var deg = (_cameraYawRad * 180 / math.pi) % 360;
    if (deg < 0) deg += 360;
    return deg.round() % 360;
  }

  double _roomHeightMeters(AppState state) {
    final layout = state.activeRoomLayout;
    if (layout != null && layout.dimensions.heightMeters > 0) {
      return layout.dimensions.heightMeters;
    }
    return state.currentRoomData.heightMeters;
  }

  void _toast(String message, {bool ok = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: (ok ? AppColors.cyan : AppColors.red).withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _confirmRestoreOriginal(AppState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Restore original layout?', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'This reverts to the layout saved before your last optimization. Scores become ROUGH EST. until Bench.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    state.restoreOriginalLayout();
    _toast('Original layout restored');
  }

  void _rotateSelected(AppState state, FurnitureItem selected, double delta) {
    if (!state.canMoveFurniture(selected)) {
      _toast('Unlock to rotate', ok: false);
      return;
    }
    if (!state.rotateFurniture(selected.id, deltaDegrees: delta)) {
      _toast('No room to rotate here', ok: false);
    }
  }

  /// Compact facing controls for the selected furniture card.
  Widget _buildFacingStrip(AppState state, FurnitureItem item) {
    return Row(
      children: [
        Icon(Icons.crop_rotate_rounded, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Text(
          'Facing ${item.yawDegrees.round()}°',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        _RotationButton(
          icon: Icons.rotate_left_rounded,
          tooltip: 'Face left 90°',
          onTap: () => _rotateSelected(state, item, -90),
        ),
        const SizedBox(width: 4),
        _RotationButton(
          icon: Icons.center_focus_strong_rounded,
          tooltip: 'Reset facing',
          onTap: () {
            if (item.yawDegrees.abs() > 0.01) {
              _rotateSelected(state, item, -item.yawDegrees);
            }
          },
        ),
        const SizedBox(width: 4),
        _RotationButton(
          icon: Icons.rotate_right_rounded,
          tooltip: 'Face right 90°',
          onTap: () => _rotateSelected(state, item, 90),
        ),
      ],
    );
  }

  Widget _buildSizeStrip(AppState state, FurnitureItem item) {
    final canResize = state.canMoveFurniture(item);
    return Row(
      children: [
        Icon(Icons.straighten_rounded, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Text(
          '${RoomScale.formatCellsAsMeters(item.width)} × ${RoomScale.formatCellsAsMeters(item.height)}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        _RotationButton(
          icon: Icons.remove_rounded,
          tooltip: 'Narrower',
          onTap: canResize
              ? () {
                  if (!state.resizeFurniture(item.id, dWidth: -0.25)) {
                    _toast('No room to shrink here', ok: false);
                  }
                }
              : () => _toast('Unlock to resize', ok: false),
        ),
        const SizedBox(width: 4),
        _RotationButton(
          icon: Icons.add_rounded,
          tooltip: 'Wider',
          onTap: canResize
              ? () {
                  if (!state.resizeFurniture(item.id, dWidth: 0.25)) {
                    _toast('No room to grow here', ok: false);
                  }
                }
              : () => _toast('Unlock to resize', ok: false),
        ),
        const SizedBox(width: 8),
        _RotationButton(
          icon: Icons.expand_more_rounded,
          tooltip: 'Shorter',
          onTap: canResize
              ? () {
                  if (!state.resizeFurniture(item.id, dHeight: -0.25)) {
                    _toast('No room to shrink here', ok: false);
                  }
                }
              : () => _toast('Unlock to resize', ok: false),
        ),
        const SizedBox(width: 4),
        _RotationButton(
          icon: Icons.expand_less_rounded,
          tooltip: 'Deeper',
          onTap: canResize
              ? () {
                  if (!state.resizeFurniture(item.id, dHeight: 0.25)) {
                    _toast('No room to grow here', ok: false);
                  }
                }
              : () => _toast('Unlock to resize', ok: false),
        ),
      ],
    );
  }

  void _armDrag2D(Offset local, Rect roomRect, AppState state, Map<String, SurfaceMount> mounts) {
    _drag2dItemId = null;
    _drag2dGrab = null;
    _drag2dPointerDown = local;
    _drag2dGestureStarted = false;
    final gridCols = state.currentRoomData.gridCols;
    final gridRows = state.currentRoomData.gridRows;
    final visible = state.furniture.where((f) => !f.hidden).toList();

    final hit = RoomPlanGeometry.hitTest(
      local: local,
      roomRect: roomRect,
      gridCols: gridCols,
      gridRows: gridRows,
      furniture: visible,
      mounts: mounts,
    );
    if (hit == null) return;
    if (!state.canMoveFurniture(hit)) return;
    final grid = RoomPlanGeometry.gridFromLocal(local, roomRect, gridCols, gridRows);
    _drag2dItemId = hit.id;
    _drag2dGrab = Offset(grid.dx - hit.gridX, grid.dy - hit.gridY);
  }

  void _commitDrag2D(AppState state) {
    if (_drag2dItemId == null || _drag2dGrab == null || _drag2dGestureStarted) return;
    _drag2dGestureStarted = true;
    state.selectFurniture(_drag2dItemId!);
    state.beginFurnitureGesture();
  }

  void _updateDrag2D(Offset local, Rect roomRect, AppState state) {
    final id = _drag2dItemId;
    final grab = _drag2dGrab;
    if (id == null || grab == null) return;
    final grid = RoomPlanGeometry.gridFromLocal(
      local,
      roomRect,
      state.currentRoomData.gridCols,
      state.currentRoomData.gridRows,
    );
    setState(() => _dragPointerLocal = local);
    state.moveFurniture(id, grid.dx - grab.dx, grid.dy - grab.dy);
  }

  void _endDrag2D(AppState state) {
    if (_drag2dGestureStarted) {
      state.endFurnitureGesture();
    }
    _drag2dItemId = null;
    _drag2dGrab = null;
    _drag2dPointerDown = null;
    _drag2dGestureStarted = false;
    _dragPointerLocal = null;
    if (_liveDomain != RigLiveDomain.none) {
      _liveDebounceTimer?.cancel();
      setState(() => _refreshLiveFieldNow(state));
    }
  }

  void _finishPointer2D(
    Offset local,
    Rect roomRect,
    AppState state,
    Map<String, SurfaceMount> mounts,
  ) {
    final wasDrag = _drag2dGestureStarted;
    final down = _drag2dPointerDown;
    _endDrag2D(state);
    if (wasDrag || down == null) return;
    if ((local - down).distance >= _drag2dSlop) return;
    _tapSelect2D(local, roomRect, state, mounts);
  }

  void _tapSelect2D(Offset local, Rect roomRect, AppState state, Map<String, SurfaceMount> mounts) {
    if (state.hasPendingPlacement) return;
    final gridCols = state.currentRoomData.gridCols;
    final gridRows = state.currentRoomData.gridRows;
    final visible = state.furniture.where((f) => !f.hidden).toList();
    final hit = RoomPlanGeometry.hitTest(
      local: local,
      roomRect: roomRect,
      gridCols: gridCols,
      gridRows: gridRows,
      furniture: visible,
      mounts: mounts,
    );
    if (hit != null) {
      state.selectFurniture(hit.id, toggle: true);
      setState(() => _furnitureDetailsExpanded = false);
      if (!state.canMoveFurniture(hit)) {
        _showStructuralLockedHint(context);
      }
    } else {
      state.clearSelection();
    }
  }

  Widget _buildCanvas(AppState state) {
    if (_viewMode == _RigViewMode.model3D) {
      final desktop = AppLayout.isDesktop(context);
      return Container(
        margin: EdgeInsets.symmetric(horizontal: desktop ? 0 : 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(desktop ? 0 : AppRadius.lg),
          border: desktop ? null : Border.all(color: AppColors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Stack(
            fit: StackFit.expand,
            children: [
              RoomModelScene(
                room: state.currentRoomData,
                furniture: state.furniture,
                selectedId: state.selectedIsScanObject
                    ? null
                    : state.selectedFurniture?.id,
                yaw: _cameraYawRad,
                pitch: _cameraPitchRad,
                distance: _cameraDistance.clamp(4.0, 20.0),
                exploreChrome: ChromeViewMode.check,
                pendingPreset: _pendingPreset,
                showMiniMap: _showMiniMap,
                focusToken: _focusToken,
                moveMode: _furnitureDragArmed(state),
                liveDrag: _dragItemId != null,
                pendingPlacementId: state.pendingPlacementId,
                dragBlocked: _dragItemId != null && state.dragPoseBlocked,
                liveFieldCells: _liveFieldCellsMeters(state),
                onPresetApplied: () {
                  if (_pendingPreset != null) {
                    setState(() => _pendingPreset = null);
                  }
                },
                onSelect: (id) {
                  state.selectFurniture(id);
                  if (!state.canMoveFurnitureId(id)) {
                    _showStructuralLockedHint(context);
                  }
                },
                onDeselect: () {
                  if (state.hasPendingPlacement) return;
                  state.clearSelection();
                },
                onDragStart: (id) {
                  if (!state.canMoveFurnitureId(id)) return;
                  state.selectFurniture(id);
                  _dragItemId = id;
                  _dragGrabOffset = null;
                  state.beginFurnitureGesture();
                },
                onDrag: (id, floorX, floorY) {
                  if (_dragItemId != id) return;
                  if (!state.canMoveFurnitureId(id)) return;
                  final matches = state.furniture.where((f) => f.id == id);
                  if (matches.isEmpty) return;
                  final item = matches.first;
                  _dragGrabOffset ??=
                      Offset(floorX - item.gridX, floorY - item.gridY);
                  final grab = _dragGrabOffset!;
                  state.moveFurniture(
                    id,
                    floorX - grab.dx,
                    floorY - grab.dy,
                  );
                },
                onDragEnd: (id) {
                  if (_dragItemId != null) {
                    state.endFurnitureGesture();
                  }
                  setState(() {
                    _dragItemId = null;
                    _dragGrabOffset = null;
                  });
                },
              ),
            ],
          ),
        ),
      );
    }
    if (_viewMode == _RigViewMode.threeD) {
      return _buildPseudo3DCanvas(state);
    }

    // The floor plan stays axis-aligned: rotating it made every horizontal
    // swipe spin the room and threw off drag deltas. Orbiting lives in 3D.
    final desktop = AppLayout.isDesktop(context);
    return Container(
      margin: EdgeInsets.symmetric(horizontal: desktop ? 0 : 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(desktop ? 0 : 16),
        border: desktop ? null : Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(desktop ? 0 : 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final coverage = state.activeRoomLayout?.coverageGrid;
            final conflictIds = <String>{
              for (final c in state.layoutConflicts) ...c.itemIds,
            };
            final gridCols = state.currentRoomData.gridCols;
            final gridRows = state.currentRoomData.gridRows;
            final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
            final roomRect = RoomPlanGeometry.roomRectFor(
              size: canvasSize,
              gridCols: gridCols,
              gridRows: gridRows,
              pad: 10,
            );
            final cellW = RoomPlanGeometry.cellW(roomRect, gridCols);
            final cellH = RoomPlanGeometry.cellH(roomRect, gridRows);
            final visible = state.furniture.where((item) => !item.hidden).toList();
            final mounts = {
              for (final item in visible)
                item.id: SurfaceMounts.of(
                  item,
                  gridCols: gridCols,
                  gridRows: gridRows,
                  furniture: visible,
                ),
            };

            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _armDrag2D(e.localPosition, roomRect, state, mounts),
              onPointerMove: (e) {
                if (_drag2dItemId == null && _drag2dPointerDown == null) return;
                if (_drag2dItemId == null) {
                  if (_drag2dPointerDown != null &&
                      (e.localPosition - _drag2dPointerDown!).distance < _drag2dSlop) {
                    return;
                  }
                  _commitDrag2D(state);
                }
                _updateDrag2D(e.localPosition, roomRect, state);
              },
              onPointerUp: (e) => _finishPointer2D(e.localPosition, roomRect, state, mounts),
              onPointerCancel: (e) => _finishPointer2D(e.localPosition, roomRect, state, mounts),
              child: Builder(
                builder: (context) {
                  Widget buildScene() {
                    return Stack(
                      children: [
                        CustomPaint(
                          size: canvasSize,
                          painter: RoomGridPainter(
                            gridCols: gridCols,
                            gridRows: gridRows,
                            roomRect: roomRect,
                            coverage: coverage,
                            lengthMeters: state.activeRoomLayout?.dimensions.lengthMeters ??
                                RoomScale.metersFromCells(gridCols),
                            widthMeters: state.activeRoomLayout?.dimensions.widthMeters ??
                                RoomScale.metersFromCells(gridRows),
                            fittings: [
                              for (final item in visible)
                                if (mounts[item.id]!.isWall)
                                  (
                                    mount: mounts[item.id]!,
                                    selected: state.selectedItemId == item.id && !state.selectedIsScanObject,
                                  ),
                            ],
                          ),
                        ),
                        if (_liveDomain != RigLiveDomain.none) ...[
                          Builder(
                            builder: (_) {
                              _scheduleLiveFieldRefresh(state);
                              return _liveBenchOverlay2D(
                                    canvasSize: canvasSize,
                                    roomRect: roomRect,
                                    gridCols: gridCols,
                                    gridRows: gridRows,
                                    furniture: state.committedFurniture,
                                  ) ??
                                  const SizedBox.shrink();
                            },
                          ),
                        ],
                        ...visible.map((item) {
                          final isSelected = state.selectedItemId == item.id && !state.selectedIsScanObject;
                          final mount = mounts[item.id]!;
                          if (mount.isWall && mount.span != null) {
                            return _buildWallFitting2D(
                              state: state,
                              item: item,
                              mount: mount,
                              isSelected: isSelected,
                              hasConflict: conflictIds.contains(item.id),
                              roomRect: roomRect,
                              cellW: cellW,
                              cellH: cellH,
                            );
                          }
                          final itemRect = RoomPlanGeometry.itemRect(item, roomRect, gridCols, gridRows);
                          return Positioned(
                            key: ValueKey('rig2d_${item.id}'),
                            left: itemRect.left,
                            top: itemRect.top,
                            width: itemRect.width,
                            height: itemRect.height,
                            child: IgnorePointer(
                              child: Opacity(
                                opacity: state.isPendingPlacement(item.id)
                                    ? 0.42
                                    : (item.locked ? 0.85 : 1),
                                child: RigFurnitureCell(
                                  item: item,
                                  isSelected: isSelected,
                                  isPending: state.isPendingPlacement(item.id),
                                  hasConflict: conflictIds.contains(item.id) ||
                                      (isSelected && state.dragPoseBlocked),
                                ),
                              ),
                            ),
                          );
                        }),
                        if (state.activeSnapGuides.isNotEmpty)
                          CustomPaint(
                            size: canvasSize,
                            painter: _SnapGuidesPainter(
                              roomRect: roomRect,
                              gridCols: gridCols,
                              gridRows: gridRows,
                              guides: state.activeSnapGuides,
                            ),
                          ),
                      ],
                    );
                  }

                  return Stack(
                    children: [
                      buildScene(),
                      if (_drag2dGestureStarted &&
                          _dragPointerLocal != null &&
                          _drag2dItemId != null)
                        Builder(
                          builder: (context) {
                            final matches =
                                state.furniture.where((f) => f.id == _drag2dItemId);
                            if (matches.isEmpty) {
                              return RigDragMagnifier(
                                pointerLocal: _dragPointerLocal!,
                                focalPoint: _dragPointerLocal!,
                                canvasSize: canvasSize,
                                blocked: state.dragPoseBlocked,
                                scene: buildScene(),
                              );
                            }
                            final focal = RoomPlanGeometry.itemRect(
                              matches.first,
                              roomRect,
                              gridCols,
                              gridRows,
                            ).center;
                            return RigDragMagnifier(
                              pointerLocal: _dragPointerLocal!,
                              focalPoint: focal,
                              canvasSize: canvasSize,
                              blocked: state.dragPoseBlocked,
                              scene: buildScene(),
                            );
                          },
                        ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPseudo3DCanvas(AppState state) {
    final desktop = AppLayout.isDesktop(context);
    return Container(
      margin: EdgeInsets.symmetric(horizontal: desktop ? 0 : 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(desktop ? 0 : 16),
        border: desktop ? null : Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(desktop ? 0 : 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
            final gridCols = state.currentRoomData.gridCols;
            final gridRows = state.currentRoomData.gridRows;
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;

            final roomHeight = _roomHeightMeters(state);

            final renderItems = state.furniture
                .where((item) => !item.hidden)
                .map(
                  (item) => furnitureRenderItem(
                    item: item,
                    gridCols: gridCols,
                    gridRows: gridRows,
                    furniture: state.furniture,
                    color: _categoryColor(item.category),
                    selected: state.selectedItemId == item.id && !state.selectedIsScanObject,
                    ghost: state.isPendingPlacement(item.id),
                  ),
                )
                .toList();

            return Stack(
              children: [
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    // Item drags are driven from pointer events so a competing
                    // double-tap recognizer cannot swallow ScaleUpdate.
                    onPointerDown: (event) {
                      _pointerDownPos = event.localPosition;
                      _pendingDragId = null;
                      _pendingGrabOffset = null;
                      // Selected unlocked item or Place ghost → drag; else orbit.
                      if (_furnitureDragArmed(state)) {
                        _armItemDrag3D(event.localPosition, canvasSize, state);
                      }
                    },
                    onPointerMove: (event) {
                      if (_pendingDragId == null && _dragItemId == null) return;
                      final pos = event.localPosition;
                      if (_dragItemId == null) {
                        if (_pointerDownPos != null && (pos - _pointerDownPos!).distance < 12) {
                          return;
                        }
                        _commitItemDrag3D(state);
                      }
                      final dragId = _dragItemId;
                      if (dragId != null) {
                        setState(() => _dragPointerLocal = pos);
                        _updateDrag3D(dragId, pos, canvasSize, state);
                      }
                    },
                    onPointerUp: (_) {
                      _pendingDragId = null;
                      _pendingGrabOffset = null;
                      _endDrag3D(state);
                    },
                    onPointerCancel: (_) {
                      _pendingDragId = null;
                      _pendingGrabOffset = null;
                      _endDrag3D(state);
                    },
                    onPointerSignal: (signal) {
                      if (signal is PointerScrollEvent) {
                        setState(() {
                          _cameraDistance =
                              (_cameraDistance + signal.scrollDelta.dy * 0.02).clamp(6.0, 32.0);
                        });
                      }
                    },
                    child: GestureDetector(
                      key: const ValueKey('rig3d_canvas'),
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) {
                        if (_dragItemId != null || _pendingDragId != null) return;
                        final picked = _pickItemIn3D(details.localPosition, canvasSize, state);
                        if (picked != null) {
                          if (picked.isScanObject) {
                            state.selectScanObject(picked.id, toggle: true);
                            setState(() => _scanDetailsExpanded = false);
                          } else {
                            state.selectFurniture(picked.id, toggle: true);
                            setState(() => _furnitureDetailsExpanded = false);
                            final match = state.furniture.where((f) => f.id == picked.id);
                            if (match.isNotEmpty && !state.canMoveFurniture(match.first)) {
                              _showStructuralLockedHint(context);
                            }
                          }
                        } else if (!state.hasPendingPlacement) {
                          state.clearSelection();
                        }
                      },
                      onScaleStart: (details) {
                        _scaleStartDistance = _cameraDistance;
                      },
                      onScaleUpdate: (details) {
                        if (details.pointerCount >= 2) {
                          _pendingDragId = null;
                          _pendingGrabOffset = null;
                          if (_dragItemId != null) {
                            _endDrag3D(state);
                          }
                        } else if (_dragItemId != null || _pendingDragId != null) {
                          return;
                        }
                        setState(() {
                          if (details.pointerCount >= 2) {
                            // Two fingers: pinch zoom + pan the orbit pivot.
                            final next = _scaleStartDistance / details.scale.clamp(0.15, 6.0);
                            _cameraDistance = next.clamp(6.0, 32.0);
                            final cols = state.currentRoomData.gridCols.toDouble();
                            final rows = state.currentRoomData.gridRows.toDouble();
                            final pose = CameraPose(
                              roomWidth: cols,
                              roomDepth: rows,
                              roomHeight: roomHeight,
                              yaw: _cameraYawRad,
                              pitch: _cameraPitchRad,
                              distance: _cameraDistance,
                              lookAtX: _lookAtX,
                              lookAtZ: _lookAtZ,
                            );
                            final (right, fwd) = RoomProjection.floorPanAxes(pose);
                            final pan = _cameraDistance * 0.00165;
                            final dx = -details.focalPointDelta.dx * pan;
                            final dz = details.focalPointDelta.dy * pan;
                            _lookAtX =
                                (pose.pivotX + right.x * dx + fwd.x * dz).clamp(-2.0, cols + 2.0);
                            _lookAtZ =
                                (pose.pivotZ + right.z * dx + fwd.z * dz).clamp(-2.0, rows + 2.0);
                          } else {
                            _cameraYawRad = _cameraYawRad + details.focalPointDelta.dx * 0.008;
                            _cameraPitchRad = (_cameraPitchRad - details.focalPointDelta.dy * 0.006)
                                .clamp(-0.1, 1.0);
                          }
                        });
                      },
                      onDoubleTap: () {
                        setState(() {
                          _cameraYawRad = 0;
                          _cameraPitchRad = 0.34;
                          _cameraDistance = 15;
                          _lookAtX = null;
                          _lookAtZ = null;
                        });
                      },
                      child: Builder(
                        builder: (context) {
                          Widget buildScene() {
                            _scheduleLiveFieldRefresh(state);
                            // Bench field overlay paints voxels/particles; skip cell wash.
                            return CustomPaint(
                              size: Size(w, h),
                              painter: RoomOrbit3DPainter(
                                roomWidth: gridCols.toDouble(),
                                roomDepth: gridRows.toDouble(),
                                roomHeight: roomHeight,
                                gridCols: gridCols,
                                gridRows: gridRows,
                                yaw: _cameraYawRad,
                                pitch: _cameraPitchRad,
                                distance: _cameraDistance,
                                lookAtX: _lookAtX,
                                lookAtZ: _lookAtZ,
                                items: renderItems,
                                liveFieldCells: const [],
                              ),
                            );
                          }

                          return Stack(
                            children: [
                              buildScene(),
                              if (_liveDomain != RigLiveDomain.none)
                                Positioned.fill(
                                  child: _liveBenchOverlayOrbit(
                                        canvasSize: Size(w, h),
                                        gridCols: gridCols,
                                        gridRows: gridRows,
                                        furniture: state.committedFurniture,
                                      ) ??
                                      const SizedBox.shrink(),
                                ),
                              if (_dragItemId != null && _dragPointerLocal != null)
                                Builder(
                                  builder: (context) {
                                    final canvas = Size(w, h);
                                    final matches = state.furniture
                                        .where((f) => f.id == _dragItemId);
                                    Offset focal = _dragPointerLocal!;
                                    if (matches.isNotEmpty) {
                                      final item = matches.first;
                                      final projected = RoomProjection.project(
                                        OrbitVec3(
                                          item.gridX + item.width * 0.5,
                                          0,
                                          item.gridY + item.height * 0.5,
                                        ),
                                        canvas,
                                        _cameraFor(state),
                                      );
                                      if (projected != null) {
                                        focal = projected.offset;
                                      }
                                    }
                                    return RigDragMagnifier(
                                      pointerLocal: _dragPointerLocal!,
                                      focalPoint: focal,
                                      canvasSize: canvas,
                                      blocked: state.dragPoseBlocked,
                                      scene: buildScene(),
                                    );
                                  },
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  bottom: 10,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        'yaw ${_orbitYawDegrees()}°  pitch ${(_cameraPitchRad * 180 / math.pi).round()}°',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_showMiniMap)
                  Positioned(
                    right: 10,
                    bottom: 48,
                    child: IgnorePointer(
                      child: _OrbitMiniMap(
                        room: state.currentRoomData,
                        furniture: state.furniture,
                        selectedId: state.selectedIsScanObject
                            ? null
                            : state.selectedFurniture?.id,
                        lookAtX: _lookAtX ??
                            state.currentRoomData.gridCols * 0.5,
                        lookAtZ: _lookAtZ ??
                            state.currentRoomData.gridRows * 0.5,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// When a movable item is selected (or a Place ghost is active), pointer-down
  /// near furniture arms a floor drag. Otherwise one-finger gestures orbit.
  void _armItemDrag3D(Offset localPos, Size size, AppState state) {
    _pendingDragId = null;
    _pendingGrabOffset = null;
    _dragItemId = null;
    _dragGrabOffset = null;

    FurnitureItem? item;
    final selected = state.selectedFurniture;
    if (selected != null &&
        !state.selectedIsScanObject &&
        !selected.hidden &&
        state.canMoveFurniture(selected) &&
        _pointerNearSelected(selected, localPos, size, state)) {
      item = selected;
    } else if (state.hasPendingPlacement) {
      // Place ghosts stay draggable; other hits stay orbit/tap-select.
      final picked = _pickItemIn3D(localPos, size, state);
      if (picked == null || picked.isScanObject) return;
      if (!state.isPendingPlacement(picked.id)) return;
      final matches = state.furniture.where((f) => f.id == picked.id);
      if (matches.isEmpty) return;
      item = matches.first;
    } else {
      return;
    }

    final floor = RoomProjection.unprojectToFloor(localPos, size, _cameraFor(state));
    if (floor == null) return;

    _pendingDragId = item.id;
    _pendingGrabOffset = Offset(floor.dx - item.gridX, floor.dy - item.gridY);
  }

  void _commitItemDrag3D(AppState state) {
    final id = _pendingDragId;
    final grab = _pendingGrabOffset;
    if (id == null || grab == null || _dragItemId != null) return;
    _dragItemId = id;
    _dragGrabOffset = grab;
    _pendingDragId = null;
    _pendingGrabOffset = null;
    state.beginFurnitureGesture();
  }

  /// Selected-item grab is generous: perspective can put the volume center
  /// outside a tiny face, and a neighbor in front can win the strict pick.
  bool _pointerNearSelected(FurnitureItem item, Offset localPos, Size size, AppState state) {
    final cam = _cameraFor(state);
    final render = furnitureRenderItem(
      item: item,
      gridCols: state.currentRoomData.gridCols,
      gridRows: state.currentRoomData.gridRows,
      furniture: state.furniture,
      color: const Color(0x00000000),
      selected: true,
    );
    for (final face in _pickFaces(render, size, cam)) {
      if ((Path()..addPolygon(face.points, true)).contains(localPos)) return true;
    }
    final anchor = RoomProjection.project(_pickAnchor(render), size, cam);
    if (anchor != null && (anchor.offset - localPos).distance <= 48) return true;
    final floor = RoomProjection.unprojectToFloor(localPos, size, cam);
    if (floor == null) return false;
    const pad = 0.85;
    return floor.dx >= item.gridX - pad &&
        floor.dx <= item.gridX + item.width + pad &&
        floor.dy >= item.gridY - pad &&
        floor.dy <= item.gridY + item.height + pad;
  }

  void _updateDrag3D(String id, Offset localPos, Size size, AppState state) {
    final grab = _dragGrabOffset;
    if (grab == null) return;
    final floor = RoomProjection.unprojectToFloor(localPos, size, _cameraFor(state));
    if (floor == null) return;
    state.moveFurniture(id, floor.dx - grab.dx, floor.dy - grab.dy);
  }

  void _endDrag3D(AppState state) {
    if (_dragItemId != null) {
      state.endFurnitureGesture();
    }
    _dragItemId = null;
    _dragGrabOffset = null;
    _pointerDownPos = null;
    _dragPointerLocal = null;
    if (_liveDomain != RigLiveDomain.none) {
      _liveDebounceTimer?.cancel();
      setState(() => _refreshLiveFieldNow(state));
    }
  }

  CameraPose _cameraFor(AppState state) => CameraPose(
        roomWidth: state.currentRoomData.gridCols.toDouble(),
        roomDepth: state.currentRoomData.gridRows.toDouble(),
        roomHeight: _roomHeightMeters(state),
        yaw: _cameraYawRad,
        pitch: _cameraPitchRad,
        distance: _cameraDistance,
        lookAtX: _lookAtX,
        lookAtZ: _lookAtZ,
      );

  PickedEntity? _pickItemIn3D(Offset localPos, Size size, AppState state) {
    final cam = _cameraFor(state);

    PickedEntity? best;
    double bestDepth = double.infinity;

    final pickItems = <RoomRenderItem>[
      ...state.furniture.where((item) => !item.hidden).map(
        (item) => furnitureRenderItem(
          item: item,
          gridCols: state.currentRoomData.gridCols,
          gridRows: state.currentRoomData.gridRows,
          furniture: state.furniture,
          color: Colors.white,
          selected: false,
        ),
      ),
    ];

    for (final item in pickItems) {
      for (final face in _pickFaces(item, size, cam)) {
        final path = Path()..addPolygon(face.points, true);
        if (path.contains(localPos) && face.depth < bestDepth) {
          bestDepth = face.depth;
          best = PickedEntity(id: item.id, isScanObject: item.isScanObject);
        }
      }
    }

    if (best != null) return best;

    PickedEntity? fallback;
    double fallbackDist = 24;
    for (final item in pickItems) {
      final point = RoomProjection.project(_pickAnchor(item), size, cam);
      if (point == null) continue;
      final distance = (point.offset - localPos).distance;
      if (distance < fallbackDist) {
        fallbackDist = distance;
        fallback = PickedEntity(id: item.id, isScanObject: item.isScanObject);
      }
    }
    return fallback;
  }

  /// Tap targets follow the same geometry the painter uses, so a wall AC is
  /// tappable where it is drawn rather than where its floor cell would be.
  List<ProjectedFace> _pickFaces(RoomRenderItem item, Size size, CameraPose cam) {
    final mount = item.mount;
    final span = mount.span;
    final faces = <RoomFace>[];

    if (mount.isWall && span != null) {
      final inner = fittingFace(span, mount.bottomY, mount.topY, mount.protrusion);
      final outer = fittingFace(span, mount.bottomY, mount.topY, 0);
      faces.add(RoomFace(inner, Colors.white));
      faces.add(RoomFace([outer[0], inner[0], inner[1], outer[1]], Colors.white));
      faces.add(RoomFace([outer[3], inner[3], inner[2], outer[2]], Colors.white));
    } else if (mount.isCeiling) {
      final cx = item.x + item.width / 2;
      final cz = item.z + item.depth / 2;
      const r = 0.35;
      faces.add(RoomFace([
        OrbitVec3(cx - r, mount.bottomY, cz - r),
        OrbitVec3(cx + r, mount.bottomY, cz - r),
        OrbitVec3(cx + r, mount.bottomY, cz + r),
        OrbitVec3(cx - r, mount.bottomY, cz + r),
      ], Colors.white));
    } else if (item.isScanObject) {
      final yTop = item.heightY;
      final a = OrbitVec3(item.x, 0, item.z);
      final b = OrbitVec3(item.x + item.width, 0, item.z);
      final c = OrbitVec3(item.x + item.width, 0, item.z + item.depth);
      final d = OrbitVec3(item.x, 0, item.z + item.depth);
      final a2 = OrbitVec3(item.x, yTop, item.z);
      final b2 = OrbitVec3(item.x + item.width, yTop, item.z);
      final c2 = OrbitVec3(item.x + item.width, yTop, item.z + item.depth);
      final d2 = OrbitVec3(item.x, yTop, item.z + item.depth);
      faces.addAll([
        RoomFace([a2, b2, c2, d2], Colors.white),
        RoomFace([a, b, b2, a2], Colors.white),
        RoomFace([b, c, c2, b2], Colors.white),
        RoomFace([c, d, d2, c2], Colors.white),
        RoomFace([d, a, a2, d2], Colors.white),
      ]);
    } else {
      final yBase = mount.isDesk ? mount.bottomY : 0.0;
      faces.addAll(
        FurnitureShapes.facesFor(
          FurnitureShapes.boxes(
            kind: item.kind,
            x: item.x,
            z: item.z,
            width: item.width,
            depth: item.depth,
            color: Colors.white,
            yBase: yBase,
            yawDegrees: item.yawDegrees,
          ),
        ),
      );
    }

    final out = <ProjectedFace>[];
    for (final f in faces) {
      final p = RoomProjection.projectFace(f, size, cam);
      if (p != null) out.add(p);
    }
    return out;
  }

  OrbitVec3 _pickAnchor(RoomRenderItem item) {
    final mount = item.mount;
    final span = mount.span;
    if (mount.isWall && span != null) {
      return OrbitVec3(
        (span.x0 + span.x1) / 2 + span.inwardX * mount.protrusion * 0.5,
        (mount.bottomY + mount.topY) / 2,
        (span.z0 + span.z1) / 2 + span.inwardZ * mount.protrusion * 0.5,
      );
    }
    if (mount.isCeiling) {
      return OrbitVec3(item.x + item.width * 0.5, mount.bottomY, item.z + item.depth * 0.5);
    }
    if (mount.isDesk) {
      return OrbitVec3(
        item.x + item.width * 0.5,
        (mount.bottomY + mount.topY) / 2,
        item.z + item.depth * 0.5,
      );
    }
    return OrbitVec3(item.x + item.width * 0.5, item.heightY * 0.5, item.z + item.depth * 0.5);
  }



  Future<void> _showScanReplacePicker(AppState state, ScanObject obj) async {
    final catalog = RigCatalog.items.where((e) => e.category == obj.category).toList();
    if (catalog.isEmpty) {
      _toast('No catalog items for ${obj.category}', ok: false);
      return;
    }

    final selected = await showModalBottomSheet<RigCatalogEntry>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'REPLACE SCAN OBJECT',
                  style: TextStyle(color: AppColors.cyan, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2),
                ),
                const SizedBox(height: 6),
                Text(
                  obj.label,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: catalog
                        .map(
                          (entry) => ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                            leading: Icon(Icons.swap_horiz_rounded, color: AppColors.cyan),
                            title: Text(entry.name, style: const TextStyle(color: AppColors.textPrimary)),
                            onTap: () => Navigator.of(context).pop(entry),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || !mounted) return;
    state.replaceScanObjectWithCatalog(obj.id, selected);
  }

  void _deleteFurnitureWithUndo(AppState state, FurnitureItem item) {
    final name = item.name;
    if (!state.deleteFurniture(item.id)) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted "$name"'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              if (state.canUndoLayout) state.undoLayout();
            },
          ),
        ),
      );
  }

  void _deleteScanObjectWithUndo(AppState state, ScanObject obj) {
    final layoutBefore = state.activeRoomLayout;
    state.deleteDetectedScanObject(obj.id);

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted "${obj.label}"'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              if (layoutBefore != null) {
                state.applyScannedRoomLayout(layoutBefore);
              }
            },
          ),
        ),
      );
  }

  void _showAddItemSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          maxChildSize: 0.92,
          minChildSize: 0.45,
          builder: (context, scrollController) {
            return _AddItemSheetBody(
              scrollController: scrollController,
              onAddCatalog: (entry) => _addCatalogEntry(sheetContext, entry),
              onAddCustom: () => _addCustomObject(sheetContext),
            );
          },
        );
      },
    );
  }

  void _addCatalogEntry(BuildContext sheetContext, RigCatalogEntry entry) {
    final state = context.read<AppState>();
    final id = state.addCatalogFurniture(entry, pending: true);
    if (id == null) {
      _showAddResult(sheetContext, 'No free space for a ${entry.name}', ok: false);
      return;
    }
    _showAddResult(sheetContext, '${entry.name} — drag the ghost, then Place');
  }

  Future<void> _addCustomObject(BuildContext sheetContext) async {
    final nameCtrl = TextEditingController(text: 'Custom');
    final widthMCtrl = TextEditingController(text: '0.6');
    final depthMCtrl = TextEditingController(text: '0.6');
    String? sizeError;
    final host = context;
    final messenger = ScaffoldMessenger.of(host);
    final state = host.read<AppState>();
    final sheetNav = Navigator.of(sheetContext);
    final ok = await showDialog<bool>(
      context: sheetContext,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              title: const Text('Custom object', style: TextStyle(color: AppColors.textPrimary)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: widthMCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Width (m)',
                      labelStyle: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: depthMCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Depth (m)',
                      labelStyle: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                  if (sizeError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      sizeError!,
                      style: const TextStyle(color: AppColors.amber, fontSize: 12),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                TextButton(
                  onPressed: () {
                    final wM = double.tryParse(widthMCtrl.text.trim());
                    final dM = double.tryParse(depthMCtrl.text.trim());
                    if (wM == null || dM == null || wM < 0.3 || dM < 0.3 || wM > 4.0 || dM > 4.0) {
                      setLocal(() => sizeError = 'Enter width/depth between 0.3 m and 4.0 m.');
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true) {
      nameCtrl.dispose();
      widthMCtrl.dispose();
      depthMCtrl.dispose();
      return;
    }
    if (!mounted) {
      nameCtrl.dispose();
      widthMCtrl.dispose();
      depthMCtrl.dispose();
      return;
    }
    final wM = double.tryParse(widthMCtrl.text.trim()) ?? 0.6;
    final dM = double.tryParse(depthMCtrl.text.trim()) ?? 0.6;
    final cellsW = RoomScale.cellsFromPhysicalMeters(wM).clamp(0.5, 4.0);
    final cellsH = RoomScale.cellsFromPhysicalMeters(dM).clamp(0.5, 4.0);
    final id = state.addCustomFurniture(
      name: nameCtrl.text,
      width: cellsW,
      height: cellsH,
      pending: true,
    );
    final label = nameCtrl.text;
    nameCtrl.dispose();
    widthMCtrl.dispose();
    depthMCtrl.dispose();
    sheetNav.pop();
    if (id == null) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('No free space for that object'),
          backgroundColor: AppColors.red.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text('$label — drag the ghost, then Place'),
        backgroundColor: AppColors.cyan.withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showAddResult(BuildContext sheetContext, String message, {bool ok = true}) {
    final rootContext = context;
    Navigator.of(sheetContext).pop();
    if (!rootContext.mounted) return;
    ScaffoldMessenger.of(rootContext).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: (ok ? AppColors.cyan : AppColors.red).withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// Inward depth (px) for a wall fitting — doors need room for a full leaf swing.
  static double _wallFittingInwardPx({
    required MountStyle style,
    required double alongPx,
  }) {
    if (style == MountStyle.door) {
      // Leaf ≈ opening length; +pad for stroke. Never smaller than touch target.
      return math.max(_minTouchTarget.toDouble(), alongPx * 0.94 + 10);
    }
    // Window / vent / etc.: compact strip flush on the wall (not a floating card).
    return 22;
  }

  /// Places a wall fitting as a band along its wall instead of a floor cell.
  Widget _buildWallFitting2D({
    required AppState state,
    required FurnitureItem item,
    required SurfaceMount mount,
    required bool isSelected,
    required bool hasConflict,
    required Rect roomRect,
    required double cellW,
    required double cellH,
  }) {
    final span = mount.span!;
    final alongPx = switch (span.wall) {
      RoomWall.north || RoomWall.south => math.max((span.x1 - span.x0) * cellW, 34.0),
      RoomWall.west || RoomWall.east => math.max((span.z1 - span.z0) * cellH, 34.0),
    };
    final inward = _wallFittingInwardPx(style: mount.style, alongPx: alongPx);
    late final double left;
    late final double top;
    late final double width;
    late final double height;

    switch (span.wall) {
      case RoomWall.north:
        width = alongPx;
        height = inward;
        left = roomRect.left + span.x0 * cellW;
        top = roomRect.top;
      case RoomWall.south:
        width = alongPx;
        height = inward;
        left = roomRect.left + span.x0 * cellW;
        top = roomRect.bottom - inward;
      case RoomWall.west:
        width = inward;
        height = alongPx;
        top = roomRect.top + span.z0 * cellH;
        left = roomRect.left;
      case RoomWall.east:
        width = inward;
        height = alongPx;
        top = roomRect.top + span.z0 * cellH;
        left = roomRect.right - inward;
    }

    return Positioned(
      key: ValueKey('rig2d_${item.id}'),
      left: left,
      top: top,
      width: width,
      height: height,
      child: IgnorePointer(
        child: Opacity(
          opacity: state.isPendingPlacement(item.id) ? 0.42 : 1,
          child: _WallFittingCell(
            item: item,
            wall: span.wall,
            style: mount.style,
            isSelected: isSelected,
            hasConflict: hasConflict || (isSelected && state.dragPoseBlocked),
            fixedMount: item.locked && !state.isPendingPlacement(item.id),
          ),
        ),
      ),
    );
  }

  void _showStructuralLockedHint(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Unlock the item in Layout Items to move it.'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
  }

  Widget _buildPlacementBar(AppState state) {
    final blocked = state.selectedFurniture != null &&
        state.isPendingPlacement(state.selectedFurniture!.id) &&
        LayoutCollision.itemCollides(state.selectedFurniture!, state.furniture);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: blocked ? AppColors.red : AppColors.cyan),
        ),
        child: Row(
          children: [
            Icon(Icons.open_with_rounded, size: 16, color: blocked ? AppColors.red : AppColors.cyan),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                blocked ? 'Overlapping — drag it clear, then Place' : 'Ghost in the centre — drag, then Place',
                style: TextStyle(
                  color: blocked ? AppColors.red : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: state.cancelPendingPlacement,
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: () {
                if (!state.confirmPendingPlacement()) {
                  _toast('Move it off other items first', ok: false);
                }
              },
              child: const Text('Place'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFurnitureInfoCard(AppState state, FurnitureItem item) {
    return NeonBorderCard(
        glowColor: AppColors.cyan,
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.cyan.withValues(alpha: 0.3)),
                  ),
                  child: Center(child: SvgIcon(furnitureSvgFor(item.iconName), size: 18, color: AppColors.cyan)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
                      Text(
                        '${item.category.toUpperCase()}'
                        '${item.locked ? '  •  LOCKED' : ''}'
                        '${SurfaceMounts.isStructuralMount(item) ? '  •  WALL' : ''}',
                        style: TextStyle(color: AppColors.cyan, fontSize: 10, letterSpacing: 0.8),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'Rotate −90°',
                  onPressed: () => _rotateSelected(state, item, -90),
                  icon: const Icon(Icons.rotate_left_rounded, size: 20, color: AppColors.cyan),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'Rotate +90°',
                  onPressed: () => _rotateSelected(state, item, 90),
                  icon: const Icon(Icons.rotate_right_rounded, size: 20, color: AppColors.cyan),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: _furnitureDetailsExpanded ? 'Hide details' : 'Show details',
                  onPressed: () => setState(() => _furnitureDetailsExpanded = !_furnitureDetailsExpanded),
                  icon: Icon(
                    _furnitureDetailsExpanded ? Icons.expand_more_rounded : Icons.info_outline_rounded,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'Deselect',
                  onPressed: state.clearSelection,
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                ),
              ],
            ),
            if (_furnitureDetailsExpanded) ...[
              const SizedBox(height: 8),
              _buildFacingStrip(state, item),
              const SizedBox(height: 8),
              _buildSizeStrip(state, item),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  RigScanActionButton(
                    expand: false,
                    icon: item.hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                    label: item.hidden ? 'Show' : 'Hide',
                    color: AppColors.textSecondary,
                    onTap: () => state.toggleFurnitureHidden(item.id),
                  ),
                  RigScanActionButton(
                    expand: false,
                    icon: item.locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                    label: item.locked ? 'Unlock' : 'Lock',
                    color: item.locked ? AppColors.amber : AppColors.textSecondary,
                    onTap: () => state.toggleFurnitureLock(item.id),
                  ),
                  if (state.invasiveEdit || !SurfaceMounts.isStructuralMount(item))
                    RigScanActionButton(
                      expand: false,
                      icon: Icons.copy_rounded,
                      label: 'Dup',
                      color: AppColors.cyan,
                      onTap: () {
                        if (state.duplicateFurniture(item.id) && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Duplicated ${item.name}'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                    ),
                  if (item.iconName != 'door' &&
                      item.iconName != 'window' &&
                      (state.invasiveEdit || !SurfaceMounts.isStructuralMount(item)))
                    RigScanActionButton(
                      expand: false,
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete',
                      color: AppColors.red,
                      onTap: () async {
                        final ok = await confirmAction(
                          context,
                          title: 'Delete ${item.name}?',
                          body: 'You can undo from the snackbar after delete.',
                          confirmLabel: 'Delete',
                          danger: true,
                        );
                        if (!ok || !mounted) return;
                        _deleteFurnitureWithUndo(state, item);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _ImpactChip(label: 'Airflow', value: item.airflowImpact, color: AppColors.airflowColor),
                  const SizedBox(width: 8),
                  _ImpactChip(label: 'Lighting', value: item.lightingImpact, color: AppColors.lightingColor),
                  const SizedBox(width: 8),
                  _ImpactChip(label: 'Ergo', value: item.ergonomicsImpact, color: AppColors.ergonomicsColor),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Drag to move  •  Facing aims fans / coolers / heaters',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ],
        ),
    );
  }

  Widget _buildScanInfoCard(AppState state, ScanObject obj) {
    final color = _categoryColor(obj.category);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: NeonBorderCard(
        glowColor: color,
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Center(child: Icon(Icons.view_in_ar_rounded, size: 18, color: color)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(obj.label, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
                      Text(obj.category.toUpperCase(), style: TextStyle(color: color, fontSize: 10, letterSpacing: 1.2)),
                    ],
                  ),
                ),
                if (obj.locked) const Icon(Icons.lock_rounded, color: AppColors.amber, size: 16),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: _scanDetailsExpanded ? 'Hide details' : 'Show details',
                  onPressed: () => setState(() => _scanDetailsExpanded = !_scanDetailsExpanded),
                  icon: Icon(
                    _scanDetailsExpanded ? Icons.expand_more_rounded : Icons.info_outline_rounded,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'Deselect',
                  onPressed: state.clearSelection,
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                ),
              ],
            ),
            if (_scanDetailsExpanded) ...[
              const SizedBox(height: 8),
              Text(
                '${obj.sizeMeters.x.toStringAsFixed(2)}m × ${obj.sizeMeters.z.toStringAsFixed(2)}m × ${obj.sizeMeters.y.toStringAsFixed(2)}m'
                '  •  ${(obj.confidence * 100).round()}% confidence',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                RigScanActionButton(
                  icon: Icons.upload_rounded,
                  label: 'Add to Rig',
                  color: AppColors.green,
                  onTap: () {
                    final ok = state.promoteScanObject(obj.id);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? '${obj.label} added to Rig layout'
                              : 'Could not add ${obj.label}',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 6),
                RigScanActionButton(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Replace',
                  color: AppColors.cyan,
                  onTap: () => _showScanReplacePicker(state, obj),
                ),
                const SizedBox(width: 6),
                RigScanActionButton(
                  icon: obj.hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                  label: obj.hidden ? 'Show' : 'Hide',
                  color: AppColors.textSecondary,
                  onTap: () => state.toggleDetectedScanObjectHidden(obj.id),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                RigScanActionButton(
                  icon: obj.locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                  label: obj.locked ? 'Unlock' : 'Lock',
                  color: obj.locked ? AppColors.amber : AppColors.textSecondary,
                  onTap: () => state.toggleDetectedScanObjectLock(obj.id),
                ),
                const SizedBox(width: 6),
                RigScanActionButton(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                  color: AppColors.red,
                  onTap: () async {
                    final ok = await confirmAction(
                      context,
                      title: 'Delete ${obj.label}?',
                      body: 'You can undo from the snackbar after delete.',
                      confirmLabel: 'Delete',
                      danger: true,
                    );
                    if (!ok || !mounted) return;
                    _deleteScanObjectWithUndo(state, obj);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


/// Plan symbol for a window, door, or wall vent, drawn against its wall.
class _WallFittingCell extends StatelessWidget {
  final FurnitureItem item;
  final RoomWall wall;
  final MountStyle style;
  final bool isSelected;
  final bool hasConflict;
  final bool fixedMount;

  const _WallFittingCell({
    required this.item,
    required this.wall,
    required this.style,
    required this.isSelected,
    required this.hasConflict,
    this.fixedMount = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = hasConflict ? AppColors.red : _wallFittingColor(style);
    return Semantics(
      label: item.name,
      child: CustomPaint(
        painter: _WallFittingPainter(
          wall: wall,
          style: style,
          color: color,
          selected: isSelected,
        ),
        child: fixedMount
            ? const Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.lock_rounded, size: 11, color: AppColors.amber),
                ),
              )
            : null,
      ),
    );
  }
}

Color _wallFittingColor(MountStyle style) {
  switch (style) {
    case MountStyle.window:
      return AppColors.lightingColor;
    case MountStyle.vent:
      return AppColors.airflowColor;
    case MountStyle.intake:
      return AppColors.green;
    case MountStyle.exhaust:
      return AppColors.orange;
    case MountStyle.door:
    case MountStyle.floorItem:
    case MountStyle.deskItem:
    case MountStyle.ceilingFixture:
      return AppColors.textSecondary;
  }
}

class _SnapGuidesPainter extends CustomPainter {
  final Rect roomRect;
  final int gridCols;
  final int gridRows;
  final List<SnapGuideLine> guides;

  _SnapGuidesPainter({
    required this.roomRect,
    required this.gridCols,
    required this.gridRows,
    required this.guides,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (guides.isEmpty) return;
    final cellW = roomRect.width / gridCols;
    final cellH = roomRect.height / gridRows;
    final paint = Paint()
      ..color = AppColors.cyan.withValues(alpha: 0.85)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final g in guides) {
      if (g.axis == SnapGuideAxis.vertical) {
        final x = roomRect.left + g.position * cellW;
        _dashLine(canvas, Offset(x, roomRect.top), Offset(x, roomRect.bottom), paint);
      } else {
        final y = roomRect.top + g.position * cellH;
        _dashLine(canvas, Offset(roomRect.left, y), Offset(roomRect.right, y), paint);
      }
    }
  }

  void _dashLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 6.0;
    const gap = 4.0;
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    var drawn = 0.0;
    while (drawn < total) {
      final start = a + dir * drawn;
      final end = a + dir * (drawn + dash).clamp(0, total);
      canvas.drawLine(start, end, paint);
      drawn += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _SnapGuidesPainter oldDelegate) {
    return oldDelegate.roomRect != roomRect ||
        oldDelegate.gridCols != gridCols ||
        oldDelegate.gridRows != gridRows ||
        !listEquals(oldDelegate.guides, guides);
  }
}

class _WallFittingPainter extends CustomPainter {
  final RoomWall wall;
  final MountStyle style;
  final Color color;
  final bool selected;

  _WallFittingPainter({
    required this.wall,
    required this.style,
    required this.color,
    required this.selected,
  });

  /// Maps a position along the wall (0..1) and a depth inward from it, in
  /// pixels, onto the band's local coordinates.
  Offset _p(Size size, double t, double depth) {
    switch (wall) {
      case RoomWall.north:
        return Offset(t * size.width, depth);
      case RoomWall.south:
        return Offset(t * size.width, size.height - depth);
      case RoomWall.west:
        return Offset(depth, t * size.height);
      case RoomWall.east:
        return Offset(size.width - depth, t * size.height);
    }
  }

  void _line(Canvas canvas, Size size, double t0, double d0, double t1, double d1, Paint p) {
    canvas.drawLine(_p(size, t0, d0), _p(size, t1, d1), p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final wallFace = Paint()
      ..color = color.withValues(alpha: selected ? 0.95 : 0.7)
      ..strokeWidth = selected ? 3.2 : 2.4
      ..strokeCap = StrokeCap.square;

    final alongPx = wall == RoomWall.north || wall == RoomWall.south
        ? size.width
        : size.height;
    final inwardPx = wall == RoomWall.north || wall == RoomWall.south
        ? size.height
        : size.width;

    // Flush strip on the wall edge (depth 0) — no floating rounded card.
    final stripDepth = style == MountStyle.door ? 5.0 : math.min(inwardPx, 16.0);
    final stripFill = Paint()..color = color.withValues(alpha: selected ? 0.34 : 0.2);
    canvas.drawRect(
      Rect.fromPoints(_p(size, 0, 0), _p(size, 1, stripDepth)),
      stripFill,
    );
    // Hard edge on the wall so the opening reads flush with the room outline.
    _line(canvas, size, 0, 0.5, 1, 0.5, wallFace);

    switch (style) {
      case MountStyle.window:
        final paneDepth = math.min(inwardPx - 1, 15.0);
        final pane = Paint()..color = color.withValues(alpha: selected ? 0.3 : 0.16);
        canvas.drawRect(
          Rect.fromPoints(_p(size, 0.02, 1), _p(size, 0.98, paneDepth)),
          pane,
        );
        final mullion = Paint()
          ..color = color.withValues(alpha: selected ? 0.95 : 0.7)
          ..strokeWidth = 1.4;
        _line(canvas, size, 0.5, 1, 0.5, paneDepth, mullion);
        _line(canvas, size, 0.02, paneDepth * 0.55, 0.98, paneDepth * 0.55, mullion);
        final jamb = Paint()
          ..color = color.withValues(alpha: 0.8)
          ..strokeWidth = 2;
        _line(canvas, size, 0.02, 0.5, 0.02, paneDepth, jamb);
        _line(canvas, size, 0.98, 0.5, 0.98, paneDepth, jamb);
      case MountStyle.door:
        // Opening break on the wall; leaf length = opening (alongPx).
        _line(canvas, size, 0, 0.5, 0.05, 0.5, wallFace);
        _line(canvas, size, 0.95, 0.5, 1, 0.5, wallFace);
        final leaf = alongPx * 0.9;
        final radius = math.min(leaf, math.max(inwardPx - 4, 8.0));
        const hingeT = 0.05;
        final hinge = _p(size, hingeT, 0.5);
        Offset tip(double angle) {
          // 0 = closed along wall; π/2 = open into room.
          final alongT = hingeT + (radius / alongPx) * math.cos(angle);
          final depth = 0.5 + radius * math.sin(angle);
          return _p(size, alongT, depth);
        }
        final closed = tip(0);
        final open = tip(math.pi / 2);
        // Open leaf line (hinge → into room).
        canvas.drawLine(
          hinge,
          open,
          Paint()
            ..color = color.withValues(alpha: selected ? 0.95 : 0.7)
            ..strokeWidth = selected ? 2.6 : 2.0
            ..strokeCap = StrokeCap.square,
        );
        final sector = Path()
          ..moveTo(hinge.dx, hinge.dy)
          ..lineTo(closed.dx, closed.dy);
        for (int i = 1; i <= 28; i++) {
          final pt = tip((i / 28) * math.pi / 2);
          sector.lineTo(pt.dx, pt.dy);
        }
        sector.close();
        canvas.drawPath(
          sector,
          Paint()..color = color.withValues(alpha: selected ? 0.18 : 0.1),
        );
        final stroke = Paint()
          ..color = color.withValues(alpha: selected ? 0.85 : 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3;
        final arc = Path()..moveTo(closed.dx, closed.dy);
        for (int i = 1; i <= 28; i++) {
          final pt = tip((i / 28) * math.pi / 2);
          arc.lineTo(pt.dx, pt.dy);
        }
        canvas.drawPath(arc, stroke);
        canvas.drawLine(hinge, closed, stroke);
        final dashedPts = <Offset>[
          for (int i = 0; i <= 28; i++) tip(math.pi / 2 + (i / 28) * math.pi / 2),
        ];
        drawDashedPolyline(
          canvas,
          dashedPts,
          Paint()
            ..color = color.withValues(alpha: selected ? 0.45 : 0.25)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.1,
        );
      case MountStyle.vent:
        _line(canvas, size, 0, 0.5, 1, 0.5, wallFace);
        final body = Paint()..color = color.withValues(alpha: selected ? 0.28 : 0.16);
        canvas.drawRect(
          Rect.fromPoints(_p(size, 0, 1), _p(size, 1, math.min(inwardPx, 14))),
          body,
        );
        final louver = Paint()
          ..color = color.withValues(alpha: selected ? 0.9 : 0.6)
          ..strokeWidth = 1.3;
        final louDepth = math.min(inwardPx, 13.0);
        for (final t in const [0.22, 0.5, 0.78]) {
          _line(canvas, size, t, 2, t, louDepth, louver);
        }
      case MountStyle.intake:
        _line(canvas, size, 0, 0.5, 1, 0.5, wallFace);
        final arrow = Paint()
          ..color = color.withValues(alpha: selected ? 0.95 : 0.7)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round;
        final tipD = math.min(inwardPx - 2, 14.0);
        _line(canvas, size, 0.5, 3, 0.5, tipD, arrow);
        _line(canvas, size, 0.35, tipD - 3, 0.5, tipD, arrow);
        _line(canvas, size, 0.65, tipD - 3, 0.5, tipD, arrow);
      case MountStyle.exhaust:
        _line(canvas, size, 0, 0.5, 1, 0.5, wallFace);
        final arrow = Paint()
          ..color = color.withValues(alpha: selected ? 0.95 : 0.7)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round;
        final tipD = math.min(inwardPx - 2, 14.0);
        _line(canvas, size, 0.5, tipD, 0.5, 3, arrow);
        _line(canvas, size, 0.35, 5, 0.5, 3, arrow);
        _line(canvas, size, 0.65, 5, 0.5, 3, arrow);
      case MountStyle.floorItem:
      case MountStyle.deskItem:
      case MountStyle.ceilingFixture:
        break;
    }
  }

  @override
  bool shouldRepaint(_WallFittingPainter old) =>
      old.wall != wall || old.style != style || old.color != color || old.selected != selected;
}

class _HistoryButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final String tooltip;
  final VoidCallback? onTap;

  const _HistoryButton({
    required this.icon,
    required this.enabled,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: enabled ? AppColors.border : AppColors.border.withValues(alpha: 0.5)),
          ),
          child: Icon(
            icon,
            size: 18,
            color: enabled ? AppColors.textPrimary : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _ConflictBanner extends StatelessWidget {
  final List<LayoutConflict> conflicts;

  const _ConflictBanner({required this.conflicts});

  @override
  Widget build(BuildContext context) {
    final top = conflicts.take(2).map((c) => c.message).join(' · ');
    final extra = conflicts.length > 2 ? ' (+${conflicts.length - 2} more)' : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$top$extra',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImpactChip extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _ImpactChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final isPositive = value >= 0;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            Text(
              '${isPositive ? '+' : ''}${(value * 100).toInt()}%',
              style: TextStyle(
                color: isPositive ? AppColors.green : AppColors.red,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _InvasiveEditToggle extends StatelessWidget {
  final bool invasive;
  final ValueChanged<bool> onChanged;

  const _InvasiveEditToggle({
    required this.invasive,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final accent = invasive ? AppColors.amber : AppColors.cyan;
    return Tooltip(
      message: invasive
          ? 'Invasive — wall mounts can move'
          : 'Non-invasive — wall mounts locked',
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => onChanged(!invasive),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.7)),
            ),
            child: Icon(
              invasive ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
              size: 22,
              color: accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _AddItemButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddItemButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.cyan.withValues(alpha: 0.55)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 18, color: AppColors.cyan),
            SizedBox(width: 4),
            Text(
              'Add Item',
              style: TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddItemSheetBody extends StatefulWidget {
  final ScrollController scrollController;
  final void Function(RigCatalogEntry entry) onAddCatalog;
  final VoidCallback onAddCustom;

  const _AddItemSheetBody({
    required this.scrollController,
    required this.onAddCatalog,
    required this.onAddCustom,
  });

  @override
  State<_AddItemSheetBody> createState() => _AddItemSheetBodyState();
}

class _AddItemSheetBodyState extends State<_AddItemSheetBody> {
  String? _filter;

  bool _matches(String category) => _filter == null || category == _filter;

  @override
  Widget build(BuildContext context) {
    final catalog = RigCatalog.items.where((e) => _matches(e.category)).toList();
    final airflow = catalog.where((e) => e.category == 'airflow');
    final lighting = catalog.where((e) => e.category == 'lighting');
    final ergo = catalog.where((e) => e.category == 'ergonomics');
    final furniture = catalog.where((e) => e.category == 'neutral');
    final showCustom = _filter == null || _filter == 'neutral';

    List<Widget> section(String label, Iterable<RigCatalogEntry> entries) {
      final list = entries.toList();
      if (list.isEmpty) return const [];
      return [
        _AddSectionHeader(label: label),
        const SizedBox(height: 8),
        ...list.map(
          (entry) => _AddCatalogTile(
            icon: furnitureSvgFor(entry.iconName),
            name: entry.name,
            detail: entry.description,
            category: entry.category,
            trailing: entry.cost > 0 ? AppMoney.format(entry.cost) : null,
            onTap: () => widget.onAddCatalog(entry),
          ),
        ),
        const SizedBox(height: 18),
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ADD TO RIG',
                style: TextStyle(
                  color: AppColors.cyan,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Ghost in the centre until you Place it',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _CatalogFilterChip(
                      label: 'All',
                      color: AppColors.cyan,
                      active: _filter == null,
                      onTap: () => setState(() => _filter = null),
                    ),
                    const SizedBox(width: 6),
                    _CatalogFilterChip(
                      label: 'Airflow',
                      color: AppColors.airflowColor,
                      active: _filter == 'airflow',
                      onTap: () => setState(() => _filter = 'airflow'),
                    ),
                    const SizedBox(width: 6),
                    _CatalogFilterChip(
                      label: 'Lighting',
                      color: AppColors.lightingColor,
                      active: _filter == 'lighting',
                      onTap: () => setState(() => _filter = 'lighting'),
                    ),
                    const SizedBox(width: 6),
                    _CatalogFilterChip(
                      label: 'Ergo',
                      color: AppColors.ergonomicsColor,
                      active: _filter == 'ergonomics',
                      onTap: () => setState(() => _filter = 'ergonomics'),
                    ),
                    const SizedBox(width: 6),
                    _CatalogFilterChip(
                      label: 'Furniture',
                      color: AppColors.textMuted,
                      active: _filter == 'neutral',
                      onTap: () => setState(() => _filter = 'neutral'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              ...section('AIRFLOW', airflow),
              ...section('LIGHTING', lighting),
              ...section('ERGONOMICS', ergo),
              ...section('FURNITURE', furniture),
              if (showCustom) ...[
                _AddCatalogTile(
                  icon: furnitureSvgFor('shelf'),
                  name: 'Custom object',
                  detail: 'Name + size in metres — ghost until you Place it',
                  category: 'neutral',
                  onTap: widget.onAddCustom,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CatalogFilterChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  const _CatalogFilterChip({
    required this.label,
    required this.color,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.2) : AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? color : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? color : AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _AddSectionHeader extends StatelessWidget {
  final String label;

  const _AddSectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: AppColors.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 2,
      ),
    );
  }
}

class _AddCatalogTile extends StatelessWidget {
  final String icon;
  final String name;
  final String detail;
  final String category;
  final String? trailing;
  final VoidCallback? onTap;

  const _AddCatalogTile({
    required this.icon,
    required this.name,
    required this.detail,
    required this.category,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tint = _categoryColor(category);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Opacity(
            opacity: onTap == null ? 0.55 : 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(child: SvgIcon(icon, size: 20, color: tint)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        if (detail.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            detail,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (trailing != null)
                    Text(
                      trailing!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(width: 8),
                  const Icon(Icons.add_circle_outline_rounded, size: 20, color: AppColors.cyan),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class _RotationButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _RotationButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surfaceAlt.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(icon, size: 14, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _ToolActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _ToolActionChip({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: AppColors.cyan),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ApplyGhostBanner extends StatelessWidget {
  final VoidCallback onDismiss;
  const _ApplyGhostBanner({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.green.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.compare_rounded, size: 18, color: AppColors.green),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Before/after · layout just applied from Bench',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _DimensionsHint extends StatelessWidget {
  final RoomData room;
  const _DimensionsHint({required this.room});

  @override
  Widget build(BuildContext context) {
    final w = RoomScale.metersFromCells(room.gridCols);
    final d = RoomScale.metersFromCells(room.gridRows);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        '${RoomScale.formatMeters(w)} × ${RoomScale.formatMeters(d)} · cell ${(RoomScale.metersFromCells(1) * 100).round()} cm',
        style: const TextStyle(
          color: AppColors.cyan,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SelectedItemSizeChip extends StatelessWidget {
  final FurnitureItem item;
  const _SelectedItemSizeChip({required this.item});

  @override
  Widget build(BuildContext context) {
    final wCm = (RoomScale.metersFromCells(item.width) * 100).round();
    final dCm = (RoomScale.metersFromCells(item.height) * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.5)),
      ),
      child: Text(
        '${item.name} · $wCm×$dCm cm',
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Top-down floor plan overlay for Orbit (mirrors Model HTML minimap).
class _OrbitMiniMap extends StatelessWidget {
  final RoomData room;
  final List<FurnitureItem> furniture;
  final String? selectedId;
  final double lookAtX;
  final double lookAtZ;

  const _OrbitMiniMap({
    required this.room,
    required this.furniture,
    required this.selectedId,
    required this.lookAtX,
    required this.lookAtZ,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 108,
      height: 86,
      decoration: BoxDecoration(
        color: const Color(0xD111141C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _OrbitMiniMapPainter(
          cols: room.gridCols.toDouble(),
          rows: room.gridRows.toDouble(),
          furniture: furniture,
          selectedId: selectedId,
          lookAtX: lookAtX,
          lookAtZ: lookAtZ,
        ),
      ),
    );
  }
}

class _OrbitMiniMapPainter extends CustomPainter {
  final double cols;
  final double rows;
  final List<FurnitureItem> furniture;
  final String? selectedId;
  final double lookAtX;
  final double lookAtZ;

  _OrbitMiniMapPainter({
    required this.cols,
    required this.rows,
    required this.furniture,
    required this.selectedId,
    required this.lookAtX,
    required this.lookAtZ,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF1B2030);
    canvas.drawRect(Offset.zero & size, bg);

    const pad = 8.0;
    final sx = (size.width - pad * 2) / math.max(cols, 0.1);
    final sz = (size.height - pad * 2) / math.max(rows, 0.1);
    final s = math.min(sx, sz);
    final ox = (size.width - cols * s) * 0.5;
    final oz = (size.height - rows * s) * 0.5;

    final roomRect = Rect.fromLTWH(ox, oz, cols * s, rows * s);
    canvas.drawRect(
      roomRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = AppColors.border
        ..strokeWidth = 1,
    );

    for (final f in furniture) {
      if (f.hidden) continue;
      final r = Rect.fromLTWH(
        ox + f.gridX * s,
        oz + f.gridY * s,
        math.max(0.15, f.width) * s,
        math.max(0.15, f.height) * s,
      );
      canvas.drawRect(
        r,
        Paint()
          ..color = f.id == selectedId
              ? AppColors.cyan
              : const Color(0xFF5A6280),
      );
    }

    canvas.drawCircle(
      Offset(ox + lookAtX * s, oz + lookAtZ * s),
      3.5,
      Paint()..color = const Color(0xFF2EE68A),
    );
  }

  @override
  bool shouldRepaint(covariant _OrbitMiniMapPainter old) {
    return old.cols != cols ||
        old.rows != rows ||
        old.furniture != furniture ||
        old.selectedId != selectedId ||
        old.lookAtX != lookAtX ||
        old.lookAtZ != lookAtZ;
  }
}

class _GoalChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  const _GoalChip({required this.label, required this.color, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? color.withValues(alpha: 0.16) : AppColors.card,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? color : AppColors.border),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: active ? color : AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _InspectImpactChip extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _InspectImpactChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (value * 100).clamp(0, 999).round();
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$pct',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal chrome strip: swipe sideways when View/Tools/Snapshot/Items/Live
/// do not fit. Right-edge fade hints that more chips are off-screen.
class _RigChromeScrollRow extends StatefulWidget {
  final Widget child;

  const _RigChromeScrollRow({required this.child});

  @override
  State<_RigChromeScrollRow> createState() => _RigChromeScrollRowState();
}

class _RigChromeScrollRowState extends State<_RigChromeScrollRow> {
  final _controller = ScrollController();
  bool _canScrollMore = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateFade);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFade());
  }

  @override
  void dispose() {
    _controller.removeListener(_updateFade);
    _controller.dispose();
    super.dispose();
  }

  void _updateFade() {
    if (!_controller.hasClients) return;
    final more = _controller.position.maxScrollExtent > 2 &&
        _controller.offset < _controller.position.maxScrollExtent - 2;
    if (more != _canScrollMore && mounted) {
      setState(() => _canScrollMore = more);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                _updateFade();
                return false;
              },
              child: SingleChildScrollView(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                clipBehavior: Clip.hardEdge,
                child: widget.child,
              ),
            ),
          ),
          if (_canScrollMore)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 28,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        AppColors.bg.withValues(alpha: 0),
                        AppColors.bg.withValues(alpha: 0.92),
                      ],
                    ),
                  ),
                  child: const Align(
                    alignment: Alignment.centerRight,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RigSnapshotPanel extends StatefulWidget {
  final AppState state;
  final VoidCallback onCloseSheet;

  const _RigSnapshotPanel({
    required this.state,
    required this.onCloseSheet,
  });

  @override
  State<_RigSnapshotPanel> createState() => _RigSnapshotPanelState();
}

class _RigSnapshotPanelState extends State<_RigSnapshotPanel> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _nameCtrl = TextEditingController(
      text: 'Snapshot ${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final revs = widget.state.activeRoomRevisions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'SNAPSHOT',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Save the current Rig layout as a Hub checkpoint. Bench Compare can pick it as Left or Right.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.35),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameCtrl,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: const InputDecoration(
            labelText: 'Name',
            labelStyle: TextStyle(color: AppColors.textMuted),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.tonal(
          onPressed: () {
            final label =
                _nameCtrl.text.trim().isEmpty ? 'Snapshot' : _nameCtrl.text.trim();
            final ok = widget.state.checkpointActiveRoom(label);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(ok ? 'Saved “$label”' : 'Nothing to snapshot yet'),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ),
            );
            if (ok) {
              setState(() {});
              widget.onCloseSheet();
            }
          },
          child: const Text('Save snapshot'),
        ),
        if (revs.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Recent',
            style: TextStyle(
              color: AppColors.cyan,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          for (final r in revs.reversed.take(8))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                r.label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                '${r.furniture.length} items',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              trailing: TextButton(
                onPressed: () {
                  final ok = widget.state.restoreRoomRevision(r.id);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok ? 'Restored “${r.label}”' : 'Could not restore'),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                  if (ok) widget.onCloseSheet();
                },
                child: const Text('Restore'),
              ),
            ),
        ],
      ],
    );
  }
}

