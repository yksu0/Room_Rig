// lib/screens/rig_customizer_screen.dart
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
import '../models/surface_mount.dart';
import '../services/bench_layouts.dart';
import '../models/scan_layout_model.dart';
import '../services/layout_collision.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm_dialogs.dart';
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

enum _RigViewMode { twoD, threeD }
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

class _RigCustomizerScreenState extends State<RigCustomizerScreen> {
  static const double _minTouchTarget = 46;

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

  /// When true, one-finger drags move the selected item; otherwise they orbit.
  bool _rigMoveMode = false;

  /// Lift preview follows the finger while dragging in 2D or 3D.
  Offset? _dragPointerLocal;

  /// 2D canvas drag — unified pointer handler (matches 3D grab-offset model).
  String? _drag2dItemId;
  Offset? _drag2dGrab;
  Offset? _drag2dPointerDown;
  bool _drag2dGestureStarted = false;
  static const _drag2dSlop = 10.0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final selectedFurniture = state.selectedFurniture;
    final selectedScanObject = state.selectedScanObject;
    final canMoveSelected =
        selectedFurniture != null && !state.selectedIsScanObject;
    if (!canMoveSelected && _rigMoveMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_rigMoveMode) setState(() => _rigMoveMode = false);
      });
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.bg,
      endDrawer: RigRoomItemsDrawer(
        sidebarQuery: _sidebarQuery,
        sidebarCategory: _sidebarCategory,
        sidebarMinConfidence: _sidebarMinConfidence,
        onQueryChanged: (v) => setState(() => _sidebarQuery = v),
        onCategoryChanged: (cat) => setState(() => _sidebarCategory = cat),
        onMinConfidenceChanged: (v) => setState(() => _sidebarMinConfidence = v),
        onReplaceScanObject: (obj) => _showScanReplacePicker(state, obj),
        onDeleteScanObject: (obj) => _deleteScanObjectWithUndo(state, obj),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, state),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: _buildCanvas(state)),
                  if (state.hasPendingPlacement) _buildPlacementBar(state),
                  if (selectedFurniture != null && !state.hasPendingPlacement)
                    _buildFurnitureInfoCard(state, selectedFurniture),
                  if (selectedScanObject != null) _buildScanInfoCard(state, selectedScanObject),
                  _buildOptimizationPanel(state),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
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
                      style: TextStyle(color: AppColors.cyan, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 3),
                    ),
                    Text(
                      state.currentRoomData.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${RoomScale.formatCellsAsMeters(state.currentRoomData.gridCols)} × '
                      '${RoomScale.formatCellsAsMeters(state.currentRoomData.gridRows)} × '
                      '${RoomScale.formatMeters(state.currentRoomData.heightMeters)}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              _HistoryButton(
                icon: Icons.undo_rounded,
                enabled: state.canUndoLayout,
                tooltip: 'Undo layout',
                onTap: state.canUndoLayout ? state.undoLayout : null,
              ),
              const SizedBox(width: 4),
              _HistoryButton(
                icon: Icons.redo_rounded,
                enabled: state.canRedoLayout,
                tooltip: 'Redo layout',
                onTap: state.canRedoLayout ? state.redoLayout : null,
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text(
                    'Items',
                    style: TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          if (state.layoutConflicts.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ConflictBanner(conflicts: state.layoutConflicts),
          ],
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: Row(
              children: [
                Expanded(flex: 5, child: _buildViewToggle()),
                const SizedBox(width: 6),
                _InvasiveEditToggle(
                  invasive: state.invasiveEdit,
                  onChanged: state.setInvasiveEdit,
                ),
                const SizedBox(width: 6),
                _AddItemButton(onTap: _showAddItemSheet),
                const SizedBox(width: 4),
                _IconToolButton(
                  icon: Icons.auto_awesome_rounded,
                  tooltip: 'Auto-Rig',
                  accent: true,
                  onTap: () => _runAutoRig(context, state),
                ),
                if (kDebugMode) ...[
                  const SizedBox(width: 2),
                  _IconToolButton(
                    icon: Icons.science_rounded,
                    tooltip: 'Sample Room on Bench',
                    onTap: () => _openSampleRoom(state),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runAutoRig(BuildContext context, AppState state) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Run Auto-Rig?', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'This will rearrange furniture based on your current optimization goal.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Run'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final beforeFp = BenchLayoutBuilder.fingerprintOf(state.furniture);
    final goal = switch (_optimizeGoal) {
      _OptimizeGoal.airflow => 'airflow',
      _OptimizeGoal.lighting => 'lighting',
      _OptimizeGoal.ergonomics => 'ergonomics',
      _OptimizeGoal.spatial => 'spatial',
      _OptimizeGoal.balanced => null,
    };
    if (goal == null) {
      state.runOptimization();
    } else {
      state.runOptimization(goal: goal);
    }
    if (BenchLayoutBuilder.fingerprintOf(state.furniture) == beforeFp) return;
    if (!mounted) return;

    final mix = state.optimizeWeights.summaryLabel;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SvgIcon(RoomSvg.star, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text('Auto-Rig applied · $mix')),
          ],
        ),
        backgroundColor: AppColors.cyan.withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _openSampleRoom(AppState state) {
    state.focusBenchLayout(BenchLayoutKind.sample);
    state.setTab(benchTabIndex);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Showing the reference room on the Bench. Your Rig is untouched — switch to My Room to bench it.'),
        backgroundColor: AppColors.card,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildViewToggle() {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ViewModeChip(
              label: '2D',
              active: _viewMode == _RigViewMode.twoD,
              onTap: () => setState(() => _viewMode = _RigViewMode.twoD),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: _ViewModeChip(
              label: '3D',
              active: _viewMode == _RigViewMode.threeD,
              onTap: () => setState(() => _viewMode = _RigViewMode.threeD),
            ),
          ),
        ],
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

  ({double gridX, double gridY, double width, double depth}) _scanObjectGridFootprint(
    AppState state,
    ScanObject obj,
  ) {
    final gridCols = state.currentRoomData.gridCols;
    final gridRows = state.currentRoomData.gridRows;
    final roomLayout = state.activeRoomLayout;
    final roomLengthMeters = roomLayout?.dimensions.lengthMeters ?? gridCols.toDouble();
    final roomWidthMeters = roomLayout?.dimensions.widthMeters ?? gridRows.toDouble();
    final metersPerGridX = roomLengthMeters <= 0 ? 1.0 : roomLengthMeters / gridCols;
    final metersPerGridZ = roomWidthMeters <= 0 ? 1.0 : roomWidthMeters / gridRows;
    return (
      gridX: ((obj.center.x - obj.sizeMeters.x * 0.5) / metersPerGridX)
          .clamp(0.0, gridCols.toDouble()),
      gridY: ((obj.center.z - obj.sizeMeters.z * 0.5) / metersPerGridZ)
          .clamp(0.0, gridRows.toDouble()),
      width: (obj.sizeMeters.x / metersPerGridX).clamp(0.35, gridCols.toDouble()),
      depth: (obj.sizeMeters.z / metersPerGridZ).clamp(0.35, gridRows.toDouble()),
    );
  }

  Rect _scanObjectPlanRect(ScanObject obj, Rect roomRect, AppState state) {
    final gridCols = state.currentRoomData.gridCols;
    final gridRows = state.currentRoomData.gridRows;
    final fp = _scanObjectGridFootprint(state, obj);
    final cw = RoomPlanGeometry.cellW(roomRect, gridCols);
    final ch = RoomPlanGeometry.cellH(roomRect, gridRows);
    return Rect.fromLTWH(
      roomRect.left + fp.gridX * cw,
      roomRect.top + fp.gridY * ch,
      fp.width * cw,
      fp.depth * ch,
    );
  }

  ScanObject? _hitScanObject2D(Offset local, Rect roomRect, AppState state) {
    if (!roomRect.contains(local)) return null;
    final furnitureIds = state.furniture.map((f) => f.id).toSet();
    final orphans = state.detectedScanObjects
        .where((obj) => !furnitureIds.contains(obj.id) && !obj.hidden)
        .toList()
      ..sort(
        (a, b) => (a.sizeMeters.x * a.sizeMeters.z).compareTo(b.sizeMeters.x * b.sizeMeters.z),
      );
    for (final obj in orphans) {
      if (_scanObjectPlanRect(obj, roomRect, state).inflate(4).contains(local)) {
        return obj;
      }
    }
    return null;
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

  void _rotateSelected(AppState state, FurnitureItem selected, double delta) {
    if (!state.canMoveFurniture(selected)) {
      _toast('Turn on Invasive to rotate wall fittings', ok: false);
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
              : () => _toast('Unlock or turn on Invasive to resize', ok: false),
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
              : () => _toast('Unlock or turn on Invasive to resize', ok: false),
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
              : () => _toast('Unlock or turn on Invasive to resize', ok: false),
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
              : () => _toast('Unlock or turn on Invasive to resize', ok: false),
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
      if (!state.canMoveFurniture(hit) && SurfaceMounts.isStructuralMount(hit)) {
        _showStructuralLockedHint(context);
      }
    } else {
      final scanHit = _hitScanObject2D(local, roomRect, state);
      if (scanHit != null) {
        state.selectScanObject(scanHit.id, toggle: true);
      } else {
        state.clearSelection();
      }
    }
  }

  Widget _buildCanvas(AppState state) {
    if (_viewMode == _RigViewMode.threeD) {
      return _buildPseudo3DCanvas(state);
    }

    // The floor plan stays axis-aligned: rotating it made every horizontal
    // swipe spin the room and threw off drag deltas. Orbiting lives in 3D.
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
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
                          final cellWidth = itemRect.width * 0.9;
                          final cellHeight = itemRect.height * 0.9;
                          return Positioned(
                            key: ValueKey('rig2d_${item.id}'),
                            left: itemRect.left + itemRect.width * 0.05,
                            top: itemRect.top + itemRect.height * 0.05,
                            width: cellWidth,
                            height: cellHeight,
                            child: IgnorePointer(
                              child: Opacity(
                                opacity: state.isPendingPlacement(item.id)
                                    ? 0.42
                                    : (item.locked ||
                                            (!state.invasiveEdit && SurfaceMounts.isStructuralMount(item))
                                        ? 0.85
                                        : 1),
                                child: RigFurnitureCell(
                                  item: item,
                                  isSelected: isSelected,
                                  hasConflict: conflictIds.contains(item.id) ||
                                      (isSelected && state.dragPoseBlocked),
                                ),
                              ),
                            ),
                          );
                        }),
                        ...() {
                          final furnitureIds = state.furniture.map((f) => f.id).toSet();
                          return state.detectedScanObjects
                              .where((obj) => !furnitureIds.contains(obj.id) && !obj.hidden)
                              .map((obj) {
                            final fp = _scanObjectGridFootprint(state, obj);
                            final itemRect = Rect.fromLTWH(
                              roomRect.left + fp.gridX * cellW,
                              roomRect.top + fp.gridY * cellH,
                              fp.width * cellW,
                              fp.depth * cellH,
                            );
                            final isSelected =
                                state.selectedItemId == obj.id && state.selectedIsScanObject;
                            return Positioned(
                              key: ValueKey('rig2d_scan_${obj.id}'),
                              left: itemRect.left,
                              top: itemRect.top,
                              width: itemRect.width,
                              height: itemRect.height,
                              child: IgnorePointer(
                                child: Opacity(
                                  opacity: obj.locked ? 0.85 : 1,
                                  child: RigScanObject2DCell(
                                    color: _categoryColor(obj.category),
                                    isSelected: isSelected,
                                    label: obj.label,
                                  ),
                                ),
                              ),
                            );
                          });
                        }(),
                      ],
                    );
                  }

                  return Stack(
                    children: [
                      buildScene(),
                      if (_drag2dGestureStarted && _dragPointerLocal != null)
                        RigDragMagnifier(
                          pointerLocal: _dragPointerLocal!,
                          canvasSize: canvasSize,
                          blocked: state.dragPoseBlocked,
                          scene: buildScene(),
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
            final gridCols = state.currentRoomData.gridCols;
            final gridRows = state.currentRoomData.gridRows;
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final roomLayout = state.activeRoomLayout;
            final roomLengthMeters = roomLayout?.dimensions.lengthMeters ?? gridCols.toDouble();
            final roomWidthMeters = roomLayout?.dimensions.widthMeters ?? gridRows.toDouble();
            final metersPerGridX = roomLengthMeters <= 0 ? 1.0 : roomLengthMeters / gridCols;
            final metersPerGridZ = roomWidthMeters <= 0 ? 1.0 : roomWidthMeters / gridRows;

            final roomHeight = _roomHeightMeters(state);

            final presetItems = state.furniture
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

            // Orphan scan detections only (avoid duplicating committed furniture).
            final furnitureIds = state.furniture.map((f) => f.id).toSet();
            final detectedItems = state.detectedScanObjects
                .where((obj) => !furnitureIds.contains(obj.id) && !obj.hidden)
                .map(
                  (obj) => RoomRenderItem(
                    id: 'scan_${obj.id}',
                    x: ((obj.center.x - obj.sizeMeters.x * 0.5) / metersPerGridX)
                        .clamp(0.0, gridCols.toDouble()),
                    z: ((obj.center.z - obj.sizeMeters.z * 0.5) / metersPerGridZ)
                        .clamp(0.0, gridRows.toDouble()),
                    width: (obj.sizeMeters.x / metersPerGridX).clamp(0.35, gridCols.toDouble()),
                    depth: (obj.sizeMeters.z / metersPerGridZ).clamp(0.35, gridRows.toDouble()),
                    color: _categoryColor(obj.category).withValues(alpha: 0.72),
                    selected: state.selectedItemId == obj.id && state.selectedIsScanObject,
                    isScanObject: true,
                    label: obj.label,
                    heightY: obj.sizeMeters.y.clamp(0.4, 2.2),
                  ),
                )
                .toList();

            final renderItems = <RoomRenderItem>[...presetItems, ...detectedItems];

            final showMove = state.selectedFurniture != null && !state.selectedIsScanObject;

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
                      // Pending catalog ghosts must be draggable without tapping MOVE.
                      if (_rigMoveMode || state.hasPendingPlacement) {
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
                          } else {
                            state.selectFurniture(picked.id, toggle: true);
                          }
                        } else if (!state.hasPendingPlacement) {
                          state.clearSelection();
                          if (_rigMoveMode) setState(() => _rigMoveMode = false);
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
                              ),
                            );
                          }

                          return Stack(
                            children: [
                              buildScene(),
                              if (_dragItemId != null && _dragPointerLocal != null)
                                RigDragMagnifier(
                                  pointerLocal: _dragPointerLocal!,
                                  canvasSize: Size(w, h),
                                  blocked: state.dragPoseBlocked,
                                  scene: buildScene(),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 10,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        state.hasPendingPlacement
                            ? 'Drag the ghost to place · tap Place when ready'
                            : _rigMoveMode
                                ? 'MOVE on · drag item · tap empty floor to exit'
                                : '1 finger orbit · tap MOVE to drag · 2 fingers pan + pinch',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                if (showMove)
                  Positioned(
                    top: 8,
                    right: 10,
                    child: Material(
                      color: _rigMoveMode
                          ? AppColors.cyan
                          : AppColors.surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        key: const ValueKey('rig3d_move_mode'),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _rigMoveMode = !_rigMoveMode);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Text(
                            'MOVE',
                            style: TextStyle(
                              color: _rigMoveMode ? Colors.black : AppColors.cyan,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: showMove ? 40 : 8,
                  right: 10,
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
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        state.hasPendingPlacement
                            ? 'Drag the ghost · then Place / Cancel below'
                            : state.selectedFurniture != null
                                ? (_rigMoveMode
                                    ? 'Drag the item · Facing aims jets'
                                    : 'Tap MOVE, then drag · or orbit freely')
                                : 'Select an item, tap MOVE to drag, or orbit empty floor',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

  /// When MOVE mode is on (or a pending ghost is active), pointer-down near a
  /// movable item arms a floor drag. Otherwise one-finger gestures orbit.
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
    } else {
      final picked = _pickItemIn3D(localPos, size, state);
      if (picked == null || picked.isScanObject) return;
      final matches = state.furniture.where((f) => f.id == picked.id);
      if (matches.isEmpty) return;
      item = matches.first;
      if (!state.canMoveFurniture(item) || item.hidden) return;
      state.selectFurniture(item.id);
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

    final roomLayout = state.activeRoomLayout;
    final roomLengthMeters = roomLayout?.dimensions.lengthMeters ?? state.currentRoomData.gridCols.toDouble();
    final roomWidthMeters = roomLayout?.dimensions.widthMeters ?? state.currentRoomData.gridRows.toDouble();
    final metersPerGridX = roomLengthMeters <= 0 ? 1.0 : roomLengthMeters / state.currentRoomData.gridCols;
    final metersPerGridZ = roomWidthMeters <= 0 ? 1.0 : roomWidthMeters / state.currentRoomData.gridRows;

    final furnitureIds = state.furniture.map((f) => f.id).toSet();
    final pickItems = <RoomRenderItem>[
      ...state.furniture.map(
        (item) => furnitureRenderItem(
          item: item,
          gridCols: state.currentRoomData.gridCols,
          gridRows: state.currentRoomData.gridRows,
          furniture: state.furniture,
          color: Colors.white,
          selected: false,
        ),
      ),
      ...state.detectedScanObjects.where((obj) => !furnitureIds.contains(obj.id)).map(
        (obj) => RoomRenderItem(
          id: obj.id,
          x: ((obj.center.x - obj.sizeMeters.x * 0.5) / metersPerGridX)
              .clamp(0.0, state.currentRoomData.gridCols.toDouble()),
          z: ((obj.center.z - obj.sizeMeters.z * 0.5) / metersPerGridZ)
              .clamp(0.0, state.currentRoomData.gridRows.toDouble()),
          width: (obj.sizeMeters.x / metersPerGridX).clamp(0.35, state.currentRoomData.gridCols.toDouble()),
          depth: (obj.sizeMeters.z / metersPerGridZ).clamp(0.35, state.currentRoomData.gridRows.toDouble()),
          heightY: obj.sizeMeters.y.clamp(0.4, 2.2),
          color: Colors.white,
          selected: false,
          isScanObject: true,
          label: obj.label,
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

  void _deleteScanObjectWithUndo(AppState state, ScanObject obj) {
    final layoutBefore = state.activeRoomLayout;
    state.deleteDetectedScanObject(obj.id);

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted "${obj.label}"'),
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
    setState(() => _rigMoveMode = true);
    _showAddResult(sheetContext, '${entry.name} — drag the ghost, then Place');
  }

  Future<void> _addCustomObject(BuildContext sheetContext) async {
    final nameCtrl = TextEditingController(text: 'Custom');
    var cellsW = 1.0;
    var cellsH = 1.0;
    final ok = await showDialog<bool>(
      context: sheetContext,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Custom object', style: TextStyle(color: AppColors.textPrimary)),
          content: StatefulBuilder(
            builder: (ctx, setLocal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Size ${RoomScale.formatCellsAsMeters(cellsW)} × ${RoomScale.formatCellsAsMeters(cellsH)}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  Slider(
                    value: cellsW,
                    min: 0.5,
                    max: 4,
                    divisions: 7,
                    onChanged: (v) => setLocal(() => cellsW = v),
                  ),
                  Slider(
                    value: cellsH,
                    min: 0.5,
                    max: 4,
                    divisions: 7,
                    onChanged: (v) => setLocal(() => cellsH = v),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        );
      },
    );
    if (ok != true) {
      nameCtrl.dispose();
      return;
    }
    final state = context.read<AppState>();
    final id = state.addCustomFurniture(
      name: nameCtrl.text,
      width: cellsW,
      height: cellsH,
      pending: true,
    );
    final label = nameCtrl.text;
    nameCtrl.dispose();
    if (id == null) {
      _showAddResult(sheetContext, 'No free space for that object', ok: false);
      return;
    }
    setState(() => _rigMoveMode = true);
    _showAddResult(sheetContext, '$label — drag the ghost, then Place');
  }

  void _showAddResult(BuildContext sheetContext, String message, {bool ok = true}) {
    Navigator.of(sheetContext).pop();
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
    const band = _minTouchTarget;
    double left;
    double top;
    double width;
    double height;

    switch (span.wall) {
      case RoomWall.north:
        width = math.max((span.x1 - span.x0) * cellW, 34);
        height = band;
        left = roomRect.left + span.x0 * cellW;
        top = roomRect.top;
      case RoomWall.south:
        width = math.max((span.x1 - span.x0) * cellW, 34);
        height = band;
        left = roomRect.left + span.x0 * cellW;
        top = roomRect.bottom - band;
      case RoomWall.west:
        width = band;
        height = math.max((span.z1 - span.z0) * cellH, 34);
        top = roomRect.top + span.z0 * cellH;
        left = roomRect.left;
      case RoomWall.east:
        width = band;
        height = math.max((span.z1 - span.z0) * cellH, 34);
        top = roomRect.top + span.z0 * cellH;
        left = roomRect.right - band;
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
            fixedMount: !state.invasiveEdit && !state.isPendingPlacement(item.id),
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
          content: const Text('Wall and ceiling mounts stay fixed — turn on Invasive to move them.'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
  }

  Widget _buildOptimizationPanel(AppState state) {
    final weights = state.optimizeWeights;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AUTO-RIG GOAL',
            style: TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 2),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
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
                const SizedBox(width: 8),
                _GoalChip(
                  label: 'Airflow',
                  color: AppColors.airflowColor,
                  active: _optimizeGoal == _OptimizeGoal.airflow,
                  onTap: () {
                    setState(() => _optimizeGoal = _OptimizeGoal.airflow);
                    state.applyOptimizeGoalPreset('airflow');
                  },
                ),
                const SizedBox(width: 8),
                _GoalChip(
                  label: 'Lighting',
                  color: AppColors.lightingColor,
                  active: _optimizeGoal == _OptimizeGoal.lighting,
                  onTap: () {
                    setState(() => _optimizeGoal = _OptimizeGoal.lighting);
                    state.applyOptimizeGoalPreset('lighting');
                  },
                ),
                const SizedBox(width: 8),
                _GoalChip(
                  label: 'Ergonomics',
                  color: AppColors.ergonomicsColor,
                  active: _optimizeGoal == _OptimizeGoal.ergonomics,
                  onTap: () {
                    setState(() => _optimizeGoal = _OptimizeGoal.ergonomics);
                    state.applyOptimizeGoalPreset('ergonomics');
                  },
                ),
                const SizedBox(width: 8),
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
          ),
          if (state.lastOptimizeReasons.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...state.lastOptimizeReasons.take(2).map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline, size: 12, color: AppColors.green),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        r,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 4),
            Text(
              weights.dominantGoal == null
                  ? 'Star button runs Auto-Rig for the goal above.'
                  : 'Dominant ${weights.dominantGoal} path.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
            ),
          ],
        ],
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: NeonBorderCard(
        glowColor: AppColors.cyan,
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
                        '${(!state.invasiveEdit && SurfaceMounts.isStructuralMount(item)) ? '  •  FIXED' : ''}',
                        style: TextStyle(color: AppColors.cyan, fontSize: 10, letterSpacing: 0.8),
                      ),
                    ],
                  ),
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
            const SizedBox(height: 8),
            _buildFacingStrip(state, item),
            const SizedBox(height: 8),
            _buildSizeStrip(state, item),
            if (item.iconName != 'door' &&
                item.iconName != 'window' &&
                (state.invasiveEdit || !SurfaceMounts.isStructuralMount(item))) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: RigScanActionButton(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                  color: AppColors.red,
                  onTap: () async {
                    final ok = await confirmAction(
                      context,
                      title: 'Delete ${item.name}?',
                      body:
                          'This removes the item from your Rig. Use Undo in the Rig header if you change your mind.',
                      confirmLabel: 'Delete',
                      danger: true,
                    );
                    if (!ok || !mounted) return;
                    state.deleteFurniture(item.id);
                  },
                ),
              ),
            ],
            if (_furnitureDetailsExpanded) ...[
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
                  label: 'Promote',
                  color: AppColors.green,
                  onTap: () => state.promoteScanObject(obj.id),
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
    return CustomPaint(
      painter: _WallFittingPainter(
        wall: wall,
        style: style,
        color: color,
        selected: isSelected,
      ),
      child: Stack(
        children: [
          Align(
            alignment: _iconAlignment,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: SvgIcon(
                furnitureSvgFor(item.iconName),
                size: isSelected ? 18 : 15,
                color: isSelected || hasConflict ? color : AppColors.textSecondary,
              ),
            ),
          ),
          if (fixedMount)
            const Positioned(
              right: 2,
              top: 2,
              child: Icon(Icons.lock_rounded, size: 11, color: AppColors.amber),
            ),
        ],
      ),
    );
  }

  /// Keeps the glyph on the room side of the band so it never sits on the wall.
  Alignment get _iconAlignment {
    switch (wall) {
      case RoomWall.north:
        return Alignment.bottomCenter;
      case RoomWall.south:
        return Alignment.topCenter;
      case RoomWall.west:
        return Alignment.centerRight;
      case RoomWall.east:
        return Alignment.centerLeft;
    }
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
      ..color = color.withValues(alpha: selected ? 0.95 : 0.6)
      ..strokeWidth = selected ? 3.4 : 2.6
      ..strokeCap = StrokeCap.square;

    switch (style) {
      case MountStyle.window:
        // Plan symbol: the wall face, the glazing line, and end jambs.
        _line(canvas, size, 0, 2, 1, 2, wallFace);
        _line(
          canvas,
          size,
          0,
          8,
          1,
          8,
          Paint()
            ..color = color.withValues(alpha: selected ? 0.8 : 0.45)
            ..strokeWidth = 1.4,
        );
        final jamb = Paint()
          ..color = color.withValues(alpha: 0.7)
          ..strokeWidth = 2;
        _line(canvas, size, 0, 1, 0, 10, jamb);
        _line(canvas, size, 1, 1, 1, 10, jamb);
      case MountStyle.door:
        // Opening shown as a break in the wall, with the leaf swung inward.
        _line(canvas, size, 0, 2, 0.06, 2, wallFace);
        _line(canvas, size, 0.94, 2, 1, 2, wallFace);
        final leafLen = math.min(
          wall == RoomWall.north || wall == RoomWall.south ? size.height : size.width,
          38.0,
        );
        _line(canvas, size, 0.06, 2, 0.06, leafLen, wallFace);
        final arc = Path();
        for (int i = 0; i <= 10; i++) {
          final a = (i / 10) * math.pi / 2;
          final pt = _p(size, 0.06 + 0.88 * math.sin(a), 2 + (leafLen - 2) * math.cos(a));
          if (i == 0) {
            arc.moveTo(pt.dx, pt.dy);
          } else {
            arc.lineTo(pt.dx, pt.dy);
          }
        }
        canvas.drawPath(
          arc,
          Paint()
            ..color = color.withValues(alpha: selected ? 0.6 : 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      case MountStyle.vent:
        // Wall unit with louvers facing into the room.
        _line(canvas, size, 0, 2, 1, 2, wallFace);
        final body = Paint()..color = color.withValues(alpha: selected ? 0.26 : 0.15);
        final a = _p(size, 0, 3);
        final b = _p(size, 1, 13);
        canvas.drawRect(Rect.fromPoints(a, b), body);
        final louver = Paint()
          ..color = color.withValues(alpha: selected ? 0.9 : 0.6)
          ..strokeWidth = 1.3;
        for (final t in const [0.22, 0.5, 0.78]) {
          _line(canvas, size, t, 4, t, 12, louver);
        }
      case MountStyle.intake:
        _line(canvas, size, 0, 2, 1, 2, wallFace);
        final arrow = Paint()
          ..color = color.withValues(alpha: selected ? 0.95 : 0.7)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round;
        _line(canvas, size, 0.5, 6, 0.5, 11, arrow);
        _line(canvas, size, 0.35, 9.5, 0.5, 11.5, arrow);
        _line(canvas, size, 0.65, 9.5, 0.5, 11.5, arrow);
      case MountStyle.exhaust:
        _line(canvas, size, 0, 2, 1, 2, wallFace);
        final arrow = Paint()
          ..color = color.withValues(alpha: selected ? 0.95 : 0.7)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round;
        _line(canvas, size, 0.5, 11, 0.5, 6, arrow);
        _line(canvas, size, 0.35, 7.5, 0.5, 5.5, arrow);
        _line(canvas, size, 0.65, 7.5, 0.5, 5.5, arrow);
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
      child: GestureDetector(
        onTap: () => onChanged(!invasive),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.7)),
          ),
          child: Icon(
            invasive ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
            size: 18,
            color: accent,
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

class _IconToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool accent;

  const _IconToolButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: accent ? AppColors.accentGradient : null,
            color: accent ? null : AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: accent ? null : Border.all(color: AppColors.border),
          ),
          child: Icon(
            icon,
            size: 18,
            color: accent ? Colors.white : AppColors.cyan,
          ),
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
            trailing: entry.cost > 0 ? '\$${entry.cost.toStringAsFixed(0)}' : null,
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


class _ViewModeChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ViewModeChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.cyan.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? AppColors.cyan.withValues(alpha: 0.7) : Colors.transparent),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: active ? AppColors.cyan : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w600,
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

class _GoalChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  const _GoalChip({required this.label, required this.color, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.16) : AppColors.card,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: active ? color : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? color : AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

