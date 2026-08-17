// lib/screens/rig_customizer_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/rig_catalog.dart';
import '../models/room_model.dart';
import '../models/room_scale.dart';
import '../models/surface_mount.dart';
import '../services/bench_layouts.dart';
import '../services/lighting_simulator.dart';
import '../models/scan_layout_model.dart';
import '../services/layout_collision.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/glass_card.dart';
import '../widgets/furniture_shapes.dart';
import '../widgets/room_icons.dart';
import '../widgets/room_orbit_projection.dart';
import '../widgets/room_plan_geometry.dart';

enum _RigViewMode { twoD, threeD }
enum _OptimizeGoal { balanced, airflow, lighting, ergonomics, spatial }

/// Corners of the room-facing surface of a wall fitting, inset from the wall by
/// [inset] grid units. Ordered bottom-start, bottom-end, top-end, top-start.
List<OrbitVec3> _fittingFace(WallSpan span, double bottomY, double topY, double inset) {
  final ix = span.inwardX * inset;
  final iz = span.inwardZ * inset;
  return [
    OrbitVec3(span.x0 + ix, bottomY, span.z0 + iz),
    OrbitVec3(span.x1 + ix, bottomY, span.z1 + iz),
    OrbitVec3(span.x1 + ix, topY, span.z1 + iz),
    OrbitVec3(span.x0 + ix, topY, span.z0 + iz),
  ];
}

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

_RoomRenderItem _furnitureRenderItem({
  required FurnitureItem item,
  required int gridCols,
  required int gridRows,
  required List<FurnitureItem> furniture,
  required Color color,
  required bool selected,
  bool ghost = false,
}) {
  final kind = FurnitureShapes.kindOf(item);
  final mount = SurfaceMounts.of(
    item,
    gridCols: gridCols,
    gridRows: gridRows,
    furniture: furniture,
  );
  final yBase = (mount.isDesk || mount.isCeiling) ? mount.bottomY : 0.0;
  return _RoomRenderItem(
    id: item.id,
    x: item.gridX,
    z: item.gridY,
    width: item.width,
    depth: item.height,
    yawDegrees: item.yawDegrees,
    color: color,
    selected: selected,
    ghost: ghost,
    isScanObject: false,
    label: item.name,
    heightY: yBase + FurnitureShapes.meshHeight(kind),
    kind: kind,
    mount: mount,
  );
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
  bool _detailsExpanded = false;
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

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.bg,
      endDrawer: _buildDetectedItemsDrawer(state),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, state),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: _buildCanvas(state)),
                  if (state.hasPendingPlacement) _buildPlacementBar(state),
                  if (selectedFurniture != null) _buildFurnitureInfoCard(state, selectedFurniture),
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
                const SizedBox(width: 2),
                _IconToolButton(
                  icon: Icons.science_rounded,
                  tooltip: 'Sample Room on Bench',
                  onTap: () => _openSampleRoom(state),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _runAutoRig(BuildContext context, AppState state) {
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
      state.clearSelection();
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
              child: Stack(
                  children: [
                    CustomPaint(
                      size: canvasSize,
                      painter: _RoomGridPainter(
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
                            child: _FurnitureCell(
                              item: item,
                              isSelected: isSelected,
                              hasConflict: conflictIds.contains(item.id) ||
                                  (isSelected && state.dragPoseBlocked),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
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

            final presetItems = state.furniture
                .where((item) => !item.hidden)
                .map(
                  (item) => _furnitureRenderItem(
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
                  (obj) => _RoomRenderItem(
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

            final renderItems = <_RoomRenderItem>[...presetItems, ...detectedItems];

            return Listener(
              behavior: HitTestBehavior.opaque,
              // Item drags are driven from pointer events so a competing
              // double-tap recognizer cannot swallow ScaleUpdate.
              onPointerDown: (event) {
                _pointerDownPos = event.localPosition;
                _armItemDrag3D(event.localPosition, canvasSize, state);
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
                    _cameraDistance = (_cameraDistance + signal.scrollDelta.dy * 0.02).clamp(6.0, 32.0);
                  });
                }
              },
              child: GestureDetector(
                key: const ValueKey('rig3d_canvas'),
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  final picked = _pickItemIn3D(details.localPosition, canvasSize, state);
                  if (picked != null) {
                    if (picked.isScanObject) {
                      state.selectScanObject(picked.id, toggle: true);
                    } else {
                      state.selectFurniture(picked.id, toggle: true);
                    }
                  } else if (!state.hasPendingPlacement) {
                    state.clearSelection();
                  }
                },
                onScaleStart: (details) {
                  _scaleStartDistance = _cameraDistance;
                },
                onScaleUpdate: (details) {
                  if (_dragItemId != null || _pendingDragId != null) return;
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
                        roomHeight: 2.8,
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
                      _lookAtX = (pose.pivotX + right.x * dx + fwd.x * dz).clamp(-2.0, cols + 2.0);
                      _lookAtZ = (pose.pivotZ + right.z * dx + fwd.z * dz).clamp(-2.0, rows + 2.0);
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
                child: Stack(
                children: [
                  CustomPaint(
                    size: Size(w, h),
                    painter: _RoomOrbit3DPainter(
                      roomWidth: gridCols.toDouble(),
                      roomDepth: gridRows.toDouble(),
                      roomHeight: 2.8,
                      gridCols: gridCols,
                      gridRows: gridRows,
                      yaw: _cameraYawRad,
                      pitch: _cameraPitchRad,
                      distance: _cameraDistance,
                      lookAtX: _lookAtX,
                      lookAtZ: _lookAtZ,
                      items: renderItems,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Text(
                        '1 finger orbit · 2 fingers pan + pinch · double-tap reset',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        'yaw ${_orbitYawDegrees()}°  pitch ${(_cameraPitchRad * 180 / math.pi).round()}°',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        state.selectedFurniture != null
                            ? 'Drag item · Facing buttons aim fans / coolers / heaters'
                            : 'Drag to orbit · select an item to move or aim it',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// A one-finger drag that starts on the already-selected item moves it;
  /// anywhere else keeps orbiting the camera, so a crowded room stays inspectable.
  void _armItemDrag3D(Offset localPos, Size size, AppState state) {
    _pendingDragId = null;
    _pendingGrabOffset = null;
    _dragItemId = null;
    _dragGrabOffset = null;

    final selected = state.selectedFurniture;
    FurnitureItem? item;
    if (selected != null &&
        !state.selectedIsScanObject &&
        !selected.hidden &&
        state.canMoveFurniture(selected) &&
        _pointerNearSelected(selected, localPos, size, state)) {
      item = selected;
    } else {
      final picked = _pickItemIn3D(localPos, size, state);
      if (picked == null || picked.isScanObject) return;
      if (state.selectedItemId != picked.id || state.selectedIsScanObject) return;
      final matches = state.furniture.where((f) => f.id == picked.id);
      if (matches.isEmpty) return;
      item = matches.first;
      if (!state.canMoveFurniture(item) || item.hidden) return;
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
    final render = _furnitureRenderItem(
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
  }

  CameraPose _cameraFor(AppState state) => CameraPose(
        roomWidth: state.currentRoomData.gridCols.toDouble(),
        roomDepth: state.currentRoomData.gridRows.toDouble(),
        roomHeight: 2.8,
        yaw: _cameraYawRad,
        pitch: _cameraPitchRad,
        distance: _cameraDistance,
        lookAtX: _lookAtX,
        lookAtZ: _lookAtZ,
      );

  _PickedEntity? _pickItemIn3D(Offset localPos, Size size, AppState state) {
    final cam = _cameraFor(state);

    _PickedEntity? best;
    double bestDepth = double.infinity;

    final roomLayout = state.activeRoomLayout;
    final roomLengthMeters = roomLayout?.dimensions.lengthMeters ?? state.currentRoomData.gridCols.toDouble();
    final roomWidthMeters = roomLayout?.dimensions.widthMeters ?? state.currentRoomData.gridRows.toDouble();
    final metersPerGridX = roomLengthMeters <= 0 ? 1.0 : roomLengthMeters / state.currentRoomData.gridCols;
    final metersPerGridZ = roomWidthMeters <= 0 ? 1.0 : roomWidthMeters / state.currentRoomData.gridRows;

    final furnitureIds = state.furniture.map((f) => f.id).toSet();
    final pickItems = <_RoomRenderItem>[
      ...state.furniture.map(
        (item) => _furnitureRenderItem(
          item: item,
          gridCols: state.currentRoomData.gridCols,
          gridRows: state.currentRoomData.gridRows,
          furniture: state.furniture,
          color: Colors.white,
          selected: false,
        ),
      ),
      ...state.detectedScanObjects.where((obj) => !furnitureIds.contains(obj.id)).map(
        (obj) => _RoomRenderItem(
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
          best = _PickedEntity(id: item.id, isScanObject: item.isScanObject);
        }
      }
    }

    if (best != null) return best;

    _PickedEntity? fallback;
    double fallbackDist = 24;
    for (final item in pickItems) {
      final point = RoomProjection.project(_pickAnchor(item), size, cam);
      if (point == null) continue;
      final distance = (point.offset - localPos).distance;
      if (distance < fallbackDist) {
        fallbackDist = distance;
        fallback = _PickedEntity(id: item.id, isScanObject: item.isScanObject);
      }
    }
    return fallback;
  }

  /// Tap targets follow the same geometry the painter uses, so a wall AC is
  /// tappable where it is drawn rather than where its floor cell would be.
  List<ProjectedFace> _pickFaces(_RoomRenderItem item, Size size, CameraPose cam) {
    final mount = item.mount;
    final span = mount.span;
    final faces = <RoomFace>[];

    if (mount.isWall && span != null) {
      final inner = _fittingFace(span, mount.bottomY, mount.topY, mount.protrusion);
      final outer = _fittingFace(span, mount.bottomY, mount.topY, 0);
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

  OrbitVec3 _pickAnchor(_RoomRenderItem item) {
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


  Widget _buildDetectedItemsDrawer(AppState state) {
    final scanObjects = state.detectedScanObjects;
    final q = _sidebarQuery.trim().toLowerCase();
    bool matchesQuery(String name, String category, String id) {
      if (q.isEmpty) return true;
      return name.toLowerCase().contains(q) ||
          category.toLowerCase().contains(q) ||
          id.toLowerCase().contains(q);
    }

    bool matchesCategory(String category) {
      final filter = _sidebarCategory;
      if (filter == null) return true;
      return category.toLowerCase() == filter;
    }

    final layoutItems = state.furniture.where((item) {
      if (!matchesQuery(item.name, item.category, item.id)) return false;
      if (!matchesCategory(item.category)) return false;
      final conf = state.confidenceForFurniture(item.id) ?? 0.95;
      return conf >= _sidebarMinConfidence;
    }).toList(growable: false);

    final filteredScan = scanObjects.where((obj) {
      if (!matchesQuery(obj.label, obj.category, obj.id)) return false;
      if (!matchesCategory(obj.category)) return false;
      return obj.confidence >= _sidebarMinConfidence;
    }).toList(growable: false);

    return Drawer(
      backgroundColor: AppColors.surface,
      width: 320,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
              child: Row(
                children: [
                  Text(
                    'ROOM ITEMS',
                    style: TextStyle(color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2),
                  ),
                  const Spacer(),
                  Text(
                    '${layoutItems.length + filteredScan.length}/${state.furniture.length + scanObjects.length}',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: TextField(
                onChanged: (v) => setState(() => _sidebarQuery = v),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search name or category',
                  hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  prefixIcon: Icon(Icons.search_rounded, color: AppColors.textMuted, size: 18),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.cyan.withValues(alpha: 0.7)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final cat in const [null, 'airflow', 'lighting', 'ergonomics', 'neutral'])
                    _SidebarFilterChip(
                      label: cat ?? 'All',
                      active: _sidebarCategory == cat,
                      onTap: () => setState(() => _sidebarCategory = cat),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final entry in const [
                    (0.0, 'Any %'),
                    (0.5, '≥50%'),
                    (0.7, '≥70%'),
                    (0.85, '≥85%'),
                  ])
                    _SidebarFilterChip(
                      label: entry.$2,
                      active: (_sidebarMinConfidence - entry.$1).abs() < 0.001,
                      onTap: () => setState(() => _sidebarMinConfidence = entry.$1),
                    ),
                ],
              ),
            ),
            const Divider(color: AppColors.border, height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
                children: [
                  Text(
                    'LAYOUT ITEMS',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 8),
                  if (layoutItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text('No layout items match filters.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    )
                  else
                    ...layoutItems.map((item) {
                      final isSelected = state.selectedItemId == item.id && !state.selectedIsScanObject;
                      final catColor = _categoryColor(item.category);
                      final conf = state.confidenceForFurniture(item.id);
                      final confLabel = conf == null ? '—' : '${(conf * 100).round()}%';
                      final canDelete = item.iconName != 'door' &&
                          item.iconName != 'window' &&
                          (state.invasiveEdit || !SurfaceMounts.isStructuralMount(item));
                      final structuralFixed =
                          !state.invasiveEdit && SurfaceMounts.isStructuralMount(item);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isSelected ? catColor.withValues(alpha: 0.12) : AppColors.card,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? catColor : AppColors.border,
                              width: isSelected ? 1.4 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  state.selectFurniture(item.id, toggle: true);
                                  Navigator.of(context).pop();
                                },
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: catColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Center(
                                        child: Opacity(
                                          opacity: item.hidden ? 0.35 : 1,
                                          child: SvgIcon(
                                            furnitureSvgFor(item.iconName),
                                            size: 18,
                                            color: catColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(item.name, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                                          const SizedBox(height: 3),
                                          Text(
                                            '${item.category.toUpperCase()}  •  ${item.statusLabel}  •  $confLabel'
                                            '${structuralFixed ? '  •  FIXED' : ''}',
                                            style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (item.locked || structuralFixed)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: Icon(Icons.lock_rounded, size: 14, color: AppColors.amber),
                                      ),
                                    if (item.hidden)
                                      const Icon(Icons.visibility_off_rounded, size: 14, color: AppColors.textMuted),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _ScanActionButton(
                                    icon: item.hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                                    label: item.hidden ? 'Show' : 'Hide',
                                    color: AppColors.textSecondary,
                                    onTap: () => state.toggleFurnitureHidden(item.id),
                                  ),
                                  const SizedBox(width: 6),
                                  _ScanActionButton(
                                    icon: item.locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                                    label: item.locked ? 'Unlock' : 'Lock',
                                    color: item.locked ? AppColors.amber : AppColors.textSecondary,
                                    onTap: () => state.toggleFurnitureLock(item.id),
                                  ),
                                  const SizedBox(width: 6),
                                  _ScanActionButton(
                                    icon: Icons.copy_rounded,
                                    label: 'Dup',
                                    color: AppColors.cyan,
                                    onTap: () {
                                      state.duplicateFurniture(item.id);
                                      Navigator.of(context).pop();
                                    },
                                  ),
                                  if (canDelete) ...[
                                    const SizedBox(width: 6),
                                    _ScanActionButton(
                                      icon: Icons.delete_outline_rounded,
                                      label: 'Del',
                                      color: AppColors.red,
                                      onTap: () => state.deleteFurniture(item.id),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 6),
                  Text(
                    'SCAN OBJECTS',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 8),
                  if (filteredScan.isEmpty)
                    EmptyState(
                      iconSvg: RoomSvg.scan,
                      title: scanObjects.isEmpty ? 'No scan objects yet' : 'No matches',
                      message: scanObjects.isEmpty
                          ? 'Run a room scan to detect furniture with confidence scores. Layout items stay available above.'
                          : 'Try a different filter.',
                      actionLabel: scanObjects.isEmpty ? 'Go to Scan' : null,
                      onAction: scanObjects.isEmpty
                          ? () {
                              Navigator.of(context).pop();
                              state.setTab(1);
                            }
                          : null,
                    )
                  else
                    ...filteredScan.map((obj) {
                      final isSelected = state.selectedItemId == obj.id && state.selectedIsScanObject;
                      final catColor = _categoryColor(obj.category);
                      final status = [
                        if (obj.hidden) 'Hidden',
                        if (obj.locked) 'Locked',
                        if (!obj.hidden && !obj.locked) 'Active',
                      ].join(' · ');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isSelected ? catColor.withValues(alpha: 0.12) : AppColors.card,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? catColor : catColor.withValues(alpha: 0.55),
                              width: isSelected ? 1.4 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  state.selectScanObject(obj.id, toggle: true);
                                  Navigator.of(context).pop();
                                },
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: catColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Center(
                                        child: Opacity(
                                          opacity: obj.hidden ? 0.35 : 1,
                                          child: Icon(Icons.view_in_ar_rounded, size: 18, color: catColor),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(obj.label, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                                          const SizedBox(height: 3),
                                          Text(
                                            '${obj.category.toUpperCase()}  •  $status',
                                            style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.green.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${(obj.confidence * 100).round()}%',
                                        style: TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _ScanActionButton(
                                    icon: obj.hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                                    label: obj.hidden ? 'Show' : 'Hide',
                                    color: AppColors.textSecondary,
                                    onTap: () => state.toggleDetectedScanObjectHidden(obj.id),
                                  ),
                                  const SizedBox(width: 6),
                                  _ScanActionButton(
                                    icon: obj.locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                                    label: obj.locked ? 'Unlock' : 'Lock',
                                    color: obj.locked ? AppColors.amber : AppColors.textSecondary,
                                    onTap: () => state.toggleDetectedScanObjectLock(obj.id),
                                  ),
                                  const SizedBox(width: 6),
                                  _ScanActionButton(
                                    icon: Icons.copy_rounded,
                                    label: 'Dup',
                                    color: AppColors.cyan,
                                    onTap: () {
                                      state.duplicateDetectedScanObject(obj.id);
                                      Navigator.of(context).pop();
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  _ScanActionButton(
                                    icon: Icons.swap_horiz_rounded,
                                    label: 'Replace',
                                    color: AppColors.cyan,
                                    onTap: () => _showScanReplacePicker(state, obj),
                                  ),
                                  const SizedBox(width: 6),
                                  _ScanActionButton(
                                    icon: Icons.delete_outline_rounded,
                                    label: 'Del',
                                    color: AppColors.red,
                                    onTap: () => _deleteScanObjectWithUndo(state, obj),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showScanReplacePicker(AppState state, ScanObject obj) async {
    final templates = <String, List<String>>{
      'ergonomics': ['Office Chair', 'Standing Desk', 'Monitor Stand', 'Keyboard Tray'],
      'lighting': ['Floor Lamp', 'Task Light', 'Window', 'Ceiling Light'],
      'airflow': ['Tower Fan', 'Air Purifier', 'Vent Unit', 'AC Outlet'],
      'neutral': ['Storage Cabinet', 'Side Table', 'Shelf Unit', 'Decor Piece'],
    };

    final category = obj.category;
    final options = templates[category] ?? ['Generic Item', 'Storage Unit', 'Desk Accessory'];

    final selected = await showModalBottomSheet<String>(
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
                ...options.map(
                  (option) => ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: Icon(Icons.swap_horiz_rounded, color: AppColors.cyan),
                    title: Text(option, style: const TextStyle(color: AppColors.textPrimary)),
                    onTap: () => Navigator.of(context).pop(option),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || !mounted) return;
    final previousLabel = obj.label;
    final previousCategory = obj.category;

    state.replaceDetectedScanObject(
      obj.id,
      newLabel: selected,
      newCategory: category,
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Replaced "$previousLabel" with "$selected"'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              state.replaceDetectedScanObject(
                obj.id,
                newLabel: previousLabel,
                newCategory: previousCategory,
              );
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
                  tooltip: _detailsExpanded ? 'Hide details' : 'Show details',
                  onPressed: () => setState(() => _detailsExpanded = !_detailsExpanded),
                  icon: Icon(
                    _detailsExpanded ? Icons.expand_more_rounded : Icons.info_outline_rounded,
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
            if (_detailsExpanded) ...[
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
                  tooltip: _detailsExpanded ? 'Hide details' : 'Show details',
                  onPressed: () => setState(() => _detailsExpanded = !_detailsExpanded),
                  icon: Icon(
                    _detailsExpanded ? Icons.expand_more_rounded : Icons.info_outline_rounded,
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
            if (_detailsExpanded) ...[
              const SizedBox(height: 8),
              Text(
                '${obj.sizeMeters.x.toStringAsFixed(2)}m × ${obj.sizeMeters.z.toStringAsFixed(2)}m × ${obj.sizeMeters.y.toStringAsFixed(2)}m'
                '  •  ${(obj.confidence * 100).round()}% confidence',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FurnitureCell extends StatelessWidget {
  final FurnitureItem item;
  final bool isSelected;
  final bool hasConflict;
  const _FurnitureCell({
    required this.item,
    required this.isSelected,
    this.hasConflict = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = hasConflict
        ? AppColors.red
        : switch (item.category) {
            'airflow' => AppColors.airflowColor,
            'lighting' => AppColors.lightingColor,
            'ergonomics' => AppColors.ergonomicsColor,
            _ => AppColors.textMuted,
          };
    final kind = FurnitureShapes.kindOf(item);
    return CustomPaint(
      painter: _FurniturePlanPainter(
        kind: kind,
        color: color,
        selected: isSelected,
        hasConflict: hasConflict,
        yawDegrees: item.yawDegrees,
        showFacing: FurnitureShapes.showsFacing(kind),
      ),
    );
  }
}

class _FurniturePlanPainter extends CustomPainter {
  final FurnitureKind kind;
  final Color color;
  final bool selected;
  final bool hasConflict;
  final double yawDegrees;
  final bool showFacing;

  _FurniturePlanPainter({
    required this.kind,
    required this.color,
    required this.selected,
    required this.hasConflict,
    required this.yawDegrees,
    required this.showFacing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    FurnitureShapes.paintPlan(
      canvas,
      size,
      kind,
      color,
      selected: selected,
      hasConflict: hasConflict,
      yawDegrees: yawDegrees,
    );
    if (showFacing) {
      _FacingChevronPainter(
        color: selected ? AppColors.cyan : color,
        yawDegrees: yawDegrees,
      ).paint(canvas, size);
    }
  }

  @override
  bool shouldRepaint(covariant _FurniturePlanPainter old) =>
      old.kind != kind ||
      old.color != color ||
      old.selected != selected ||
      old.hasConflict != hasConflict ||
      old.yawDegrees != yawDegrees ||
      old.showFacing != showFacing;
}

class _FacingChevronPainter extends CustomPainter {
  final Color color;
  final double yawDegrees;
  _FacingChevronPainter({required this.color, required this.yawDegrees});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final rad = yawDegrees * math.pi / 180.0;
    // Plan: yaw 0° → +Z → down the screen.
    final dirX = math.sin(rad);
    final dirY = math.cos(rad);
    final reach = math.min(size.width, size.height) * 0.48;
    final tip = Offset(cx + dirX * reach, cy + dirY * reach);
    final back = Offset(cx + dirX * reach * 0.15, cy + dirY * reach * 0.15);
    final px = -dirY;
    final py = dirX;
    final left = Offset(back.dx + px * reach * 0.28, back.dy + py * reach * 0.28);
    final right = Offset(back.dx - px * reach * 0.28, back.dy - py * reach * 0.28);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.95));
  }

  @override
  bool shouldRepaint(covariant _FacingChevronPainter old) =>
      old.color != color || old.yawDegrees != yawDegrees;
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

typedef _Fitting2D = ({SurfaceMount mount, bool selected});

class _RoomGridPainter extends CustomPainter {
  final int gridCols;
  final int gridRows;
  final Rect? roomRect;
  final CoverageGrid? coverage;
  final List<_Fitting2D> fittings;
  final double lengthMeters;
  final double widthMeters;

  _RoomGridPainter({
    required this.gridCols,
    required this.gridRows,
    this.roomRect,
    this.coverage,
    this.fittings = const [],
    this.lengthMeters = 0,
    this.widthMeters = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final room = roomRect ?? Rect.fromLTWH(0, 0, size.width, size.height);
    final cellW = room.width / gridCols;
    final cellH = room.height / gridRows;

    final cov = coverage;
    if (cov != null && cov.cols == gridCols && cov.rows == gridRows) {
      for (int row = 0; row < gridRows; row++) {
        for (int col = 0; col < gridCols; col++) {
          final v = cov.coverage[row * cov.cols + col].clamp(0.0, 1.0);
          if (v < 0.05) continue;
          final paint = Paint()
            ..color = AppColors.cyan.withValues(alpha: 0.08 + v * 0.18);
          canvas.drawRect(
            Rect.fromLTWH(
              room.left + col * cellW,
              room.top + row * cellH,
              cellW,
              cellH,
            ),
            paint,
          );
        }
      }
    }

    final gridPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.45)
      ..strokeWidth = 0.5;

    for (int col = 0; col <= gridCols; col++) {
      final x = room.left + col * cellW;
      canvas.drawLine(Offset(x, room.top), Offset(x, room.bottom), gridPaint);
    }
    for (int row = 0; row <= gridRows; row++) {
      final y = room.top + row * cellH;
      canvas.drawLine(Offset(room.left, y), Offset(room.right, y), gridPaint);
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(room.deflate(1.5), const Radius.circular(4)),
      Paint()
        ..color = AppColors.cyan.withValues(alpha: 0.38)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );

    _paintDimensionLabels(canvas, room);
    _paintFittingContext(canvas, room, cellW, cellH);
    _paintCeilingFixture(canvas, room);
  }

  void _paintDimensionLabels(Canvas canvas, Rect room) {
    final length = lengthMeters > 0 ? lengthMeters : RoomScale.metersFromCells(gridCols);
    final width = widthMeters > 0 ? widthMeters : RoomScale.metersFromCells(gridRows);
    final style = const TextStyle(color: Color(0xFF8B93B8), fontSize: 10, fontWeight: FontWeight.w700);
    final top = TextPainter(
      text: TextSpan(text: RoomScale.formatMeters(length), style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    top.paint(canvas, Offset(room.left + (room.width - top.width) / 2, room.top + 4));
    final side = TextPainter(
      text: TextSpan(text: RoomScale.formatMeters(width), style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(room.left + 4, room.top + (room.height + side.width) / 2);
    canvas.rotate(-1.5708);
    side.paint(canvas, Offset.zero);
    canvas.restore();
  }

  /// What each wall fitting does to the room: daylight from windows, the swing
  /// path of a door, the throw of a wall vent.
  void _paintFittingContext(Canvas canvas, Rect room, double cellW, double cellH) {
    Offset toPx(double gx, double gz) => Offset(room.left + gx * cellW, room.top + gz * cellH);

    for (final f in fittings) {
      final span = f.mount.span;
      if (span == null) continue;
      final a = toPx(span.x0, span.z0);
      final b = toPx(span.x1, span.z1);
      final inward = Offset(span.inwardX * cellW, span.inwardZ * cellH);
      final alpha = f.selected ? 1.6 : 1.0;

      switch (f.mount.style) {
        case MountStyle.window:
          // Daylight falls off with depth into the room.
          for (int i = 1; i <= 4; i++) {
            final t = i / 4;
            final shade = (0.13 * (1 - t) * alpha).clamp(0.0, 0.5);
            final near = a + inward * (t - 0.25) * 2.2;
            final far = b + inward * t * 2.2;
            canvas.drawRect(
              Rect.fromPoints(near, far),
              Paint()..color = AppColors.lightingColor.withValues(alpha: shade),
            );
          }
        case MountStyle.door:
          final radius = (b - a).distance;
          final path = Path()..moveTo(a.dx, a.dy);
          for (int i = 0; i <= 12; i++) {
            final angle = (i / 12) * math.pi / 2;
            final along = (b - a) / (radius == 0 ? 1 : radius);
            final dir = Offset(
              along.dx * math.cos(angle) + span.inwardX * math.sin(angle),
              along.dy * math.cos(angle) + span.inwardZ * math.sin(angle),
            );
            final p = a + dir * radius;
            path.lineTo(p.dx, p.dy);
          }
          path.close();
          canvas.drawPath(
            path,
            Paint()..color = AppColors.textMuted.withValues(alpha: 0.10 * alpha),
          );
        case MountStyle.vent:
          // Throw cone: roughly the sweep the airflow sim gives a wall unit.
          final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
          final reach = inward * 3.2;
          final sideways = Offset(-inward.dy, inward.dx) * 1.6;
          final cone = Path()
            ..moveTo(mid.dx, mid.dy)
            ..lineTo(mid.dx + reach.dx - sideways.dx, mid.dy + reach.dy - sideways.dy)
            ..lineTo(mid.dx + reach.dx + sideways.dx, mid.dy + reach.dy + sideways.dy)
            ..close();
          canvas.drawPath(
            cone,
            Paint()..color = AppColors.airflowColor.withValues(alpha: 0.09 * alpha),
          );
        case MountStyle.intake:
          final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
          final reach = inward * 2.8;
          canvas.drawLine(
            mid,
            mid + reach,
            Paint()
              ..color = AppColors.green.withValues(alpha: 0.35 * alpha)
              ..strokeWidth = 2,
          );
        case MountStyle.exhaust:
          final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
          final reach = inward * 2.8;
          canvas.drawLine(
            mid + reach,
            mid,
            Paint()
              ..color = AppColors.orange.withValues(alpha: 0.35 * alpha)
              ..strokeWidth = 2,
          );
        case MountStyle.floorItem:
        case MountStyle.deskItem:
        case MountStyle.ceilingFixture:
          break;
      }
    }
  }

  /// The overhead fixture the lighting model always assumes is present.
  void _paintCeilingFixture(Canvas canvas, Rect room) {
    final center = Offset(
      room.left + room.width * LightingSimulator.ceilingLightU,
      room.top + room.height * LightingSimulator.ceilingLightV,
    );
    canvas.drawCircle(
      center,
      26,
      Paint()..color = AppColors.lightingColor.withValues(alpha: 0.05),
    );
    canvas.drawCircle(
      center,
      9,
      Paint()
        ..color = AppColors.lightingColor.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    // Cross-hairs mark it as a ceiling item rather than something on the floor.
    final tick = Paint()
      ..color = AppColors.lightingColor.withValues(alpha: 0.45)
      ..strokeWidth = 1.2;
    canvas.drawLine(center + const Offset(-14, 0), center + const Offset(-11, 0), tick);
    canvas.drawLine(center + const Offset(11, 0), center + const Offset(14, 0), tick);
    canvas.drawLine(center + const Offset(0, -14), center + const Offset(0, -11), tick);
    canvas.drawLine(center + const Offset(0, 11), center + const Offset(0, 14), tick);
  }

  @override
  bool shouldRepaint(_RoomGridPainter old) =>
      old.gridCols != gridCols ||
      old.gridRows != gridRows ||
      old.roomRect != roomRect ||
      old.coverage != coverage ||
      old.fittings != fittings ||
      old.lengthMeters != lengthMeters ||
      old.widthMeters != widthMeters;
}

/// A painted element paired with the depth it should sort at.
class _Drawable {
  final double depth;
  final void Function(Canvas canvas) paint;

  const _Drawable(this.depth, this.paint);
}

class _RoomRenderItem {
  final String id;
  final double x;
  final double z;
  final double width;
  final double depth;
  final double heightY;
  final FurnitureKind kind;
  final double yawDegrees;
  final Color color;
  final bool selected;
  final bool isScanObject;
  final bool ghost;
  final String label;

  /// Whether this sits on the floor, a wall, or the ceiling.
  final SurfaceMount mount;

  const _RoomRenderItem({
    required this.id,
    required this.x,
    required this.z,
    required this.width,
    required this.depth,
    required this.heightY,
    this.kind = FurnitureKind.generic,
    this.yawDegrees = 0,
    this.mount = const SurfaceMount(
      surface: MountSurface.floor,
      style: MountStyle.floorItem,
      bottomY: 0,
      topY: 0.95,
    ),
    required this.color,
    required this.selected,
    required this.isScanObject,
    required this.label,
    this.ghost = false,
  });
}

class _RoomOrbit3DPainter extends CustomPainter {
  final double roomWidth;
  final double roomDepth;
  final double roomHeight;
  final int gridCols;
  final int gridRows;
  final double yaw;
  final double pitch;
  final double distance;
  final double? lookAtX;
  final double? lookAtZ;
  final List<_RoomRenderItem> items;

  _RoomOrbit3DPainter({
    required this.roomWidth,
    required this.roomDepth,
    required this.roomHeight,
    required this.gridCols,
    required this.gridRows,
    required this.yaw,
    required this.pitch,
    required this.distance,
    this.lookAtX,
    this.lookAtZ,
    required this.items,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cam = CameraPose(
      roomWidth: roomWidth,
      roomDepth: roomDepth,
      roomHeight: roomHeight,
      yaw: yaw,
      pitch: pitch,
      distance: distance,
      lookAtX: lookAtX,
      lookAtZ: lookAtZ,
    );

    _paintShell(canvas, size, cam);
    _paintFloorGrid(canvas, size, cam);
    _paintCeilingFixture(canvas, size, cam);

    final drawables = <_Drawable>[];
    for (final item in items) {
      final start = drawables.length;
      final mount = item.mount;
      if (mount.isWall && mount.span != null) {
        _collectWallFitting(drawables, item, mount, size, cam);
      } else if (mount.isCeiling) {
        _collectCeilingFixture(drawables, item, mount, size, cam);
      } else {
        _collectBox(drawables, item, size, cam);
      }
      if (item.ghost) {
        for (var i = start; i < drawables.length; i++) {
          final inner = drawables[i];
          drawables[i] = _Drawable(inner.depth, (canvas) {
            canvas.saveLayer(null, Paint()..color = const Color(0x62FFFFFF));
            inner.paint(canvas);
            canvas.restore();
          });
        }
      }
    }

    drawables.sort((a, b) => b.depth.compareTo(a.depth));
    for (final d in drawables) {
      d.paint(canvas);
    }
  }

  void _paintShell(Canvas canvas, Size size, CameraPose cam) {
    final floor = RoomProjection.projectFace(
      RoomFace(
        [
          OrbitVec3(0, 0, 0),
          OrbitVec3(roomWidth, 0, 0),
          OrbitVec3(roomWidth, 0, roomDepth),
          OrbitVec3(0, 0, roomDepth),
        ],
        AppColors.surfaceAlt.withValues(alpha: 0.72),
      ),
      size,
      cam,
    );
    if (floor != null) {
      canvas.drawPath(Path()..addPolygon(floor.points, true), Paint()..color = floor.color);
    }

    // Open wireframe shell — no solid wall faces, so the interior stays visible
    // when orbiting behind walls (matches Benchmark 3D).
    final corners = [
      OrbitVec3(0, 0, 0),
      OrbitVec3(roomWidth, 0, 0),
      OrbitVec3(roomWidth, 0, roomDepth),
      OrbitVec3(0, 0, roomDepth),
      OrbitVec3(0, roomHeight, 0),
      OrbitVec3(roomWidth, roomHeight, 0),
      OrbitVec3(roomWidth, roomHeight, roomDepth),
      OrbitVec3(0, roomHeight, roomDepth),
    ];
    final projected = corners.map((v) => RoomProjection.project(v, size, cam)).toList();
    final edge = Paint()
      ..color = AppColors.border.withValues(alpha: 0.85)
      ..strokeWidth = 1.2;
    void line(int a, int b) {
      final pa = projected[a];
      final pb = projected[b];
      if (pa == null || pb == null) return;
      canvas.drawLine(pa.offset, pb.offset, edge);
    }

    line(0, 1);
    line(1, 2);
    line(2, 3);
    line(3, 0);
    line(4, 5);
    line(5, 6);
    line(6, 7);
    line(7, 4);
    line(0, 4);
    line(1, 5);
    line(2, 6);
    line(3, 7);
  }

  /// The overhead fixture the lighting model always assumes is on. Drawn from
  /// the simulator's own position so the two never disagree.
  void _paintCeilingFixture(Canvas canvas, Size size, CameraPose cam) {
    final cx = roomWidth * LightingSimulator.ceilingLightU;
    final cz = roomDepth * LightingSimulator.ceilingLightV;
    final mount = RoomProjection.project(OrbitVec3(cx, roomHeight, cz), size, cam);
    final lens = RoomProjection.project(OrbitVec3(cx, roomHeight - 0.14, cz), size, cam);
    if (mount == null || lens == null) return;

    canvas.drawLine(
      mount.offset,
      lens.offset,
      Paint()
        ..color = AppColors.lightingColor.withValues(alpha: 0.55)
        ..strokeWidth = 1.6,
    );
    canvas.drawCircle(lens.offset, 10, Paint()..color = AppColors.lightingColor.withValues(alpha: 0.22));
    canvas.drawCircle(lens.offset, 4.5, Paint()..color = AppColors.lightingColor.withValues(alpha: 0.9));

    final pool = RoomProjection.project(OrbitVec3(cx, 0.02, cz), size, cam);
    if (pool != null) {
      canvas.drawCircle(
        pool.offset,
        26,
        Paint()..color = AppColors.lightingColor.withValues(alpha: 0.06),
      );
    }
  }

  void _paintFloorGrid(Canvas canvas, Size size, CameraPose cam) {
    final gridPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.55)
      ..strokeWidth = 0.8;
    for (int c = 0; c <= gridCols; c++) {
      final a = RoomProjection.project(OrbitVec3(c.toDouble(), 0.001, 0), size, cam);
      final b = RoomProjection.project(OrbitVec3(c.toDouble(), 0.001, roomDepth), size, cam);
      if (a != null && b != null) canvas.drawLine(a.offset, b.offset, gridPaint);
    }
    for (int r = 0; r <= gridRows; r++) {
      final a = RoomProjection.project(OrbitVec3(0, 0.001, r.toDouble()), size, cam);
      final b = RoomProjection.project(OrbitVec3(roomWidth, 0.001, r.toDouble()), size, cam);
      if (a != null && b != null) canvas.drawLine(a.offset, b.offset, gridPaint);
    }
  }

  void _collectBox(List<_Drawable> out, _RoomRenderItem item, Size size, CameraPose cam) {
    final List<RoomFace> faces;
    if (item.isScanObject) {
      final yTop = item.heightY;
      final a = OrbitVec3(item.x, 0, item.z);
      final b = OrbitVec3(item.x + item.width, 0, item.z);
      final c = OrbitVec3(item.x + item.width, 0, item.z + item.depth);
      final d = OrbitVec3(item.x, 0, item.z + item.depth);
      final a2 = OrbitVec3(item.x, yTop, item.z);
      final b2 = OrbitVec3(item.x + item.width, yTop, item.z);
      final c2 = OrbitVec3(item.x + item.width, yTop, item.z + item.depth);
      final d2 = OrbitVec3(item.x, yTop, item.z + item.depth);
      const sideBase = 0.28;
      faces = [
        RoomFace([a2, b2, c2, d2], item.color.withValues(alpha: item.selected ? 0.8 : 0.46)),
        RoomFace([a, b, b2, a2], item.color.withValues(alpha: sideBase)),
        RoomFace([b, c, c2, b2], item.color.withValues(alpha: sideBase + 0.06)),
        RoomFace([c, d, d2, c2], item.color.withValues(alpha: sideBase + 0.02)),
        RoomFace([d, a, a2, d2], item.color.withValues(alpha: sideBase - 0.02)),
      ];
    } else {
      final yBase = item.mount.isDesk ? item.mount.bottomY : 0.0;
      faces = FurnitureShapes.facesFor(
        FurnitureShapes.boxes(
          kind: item.kind,
          x: item.x,
          z: item.z,
          width: item.width,
          depth: item.depth,
          color: item.color,
          yBase: yBase,
          yawDegrees: item.yawDegrees,
        ),
      );
    }

    for (final face in faces) {
      final p = RoomProjection.projectFace(face, size, cam);
      if (p == null) continue;
      out.add(_Drawable(p.depth, (canvas) {
        final path = Path()..addPolygon(p.points, true);
        canvas.drawPath(path, Paint()..color = p.color);
        canvas.drawPath(
          path,
          Paint()
            ..color = (item.selected ? item.color : Colors.black).withValues(alpha: item.selected ? 0.85 : 0.25)
            ..style = PaintingStyle.stroke
            ..strokeWidth = item.selected ? 1.4 : 0.8,
        );
      }));
    }

    if (!FurnitureShapes.showsFacing(item.kind)) return;

    final yChev = item.mount.isDesk ? item.mount.bottomY + 0.02 : 0.02;
    final cx = item.x + item.width * 0.5;
    final cz = item.z + item.depth * 0.5;
    final rad = item.yawDegrees * math.pi / 180.0;
    final dirX = math.sin(rad);
    final dirZ = math.cos(rad);
    final reach = math.max(item.width, item.depth) * 0.55 + 0.2;
    final tip = OrbitVec3(cx + dirX * reach, yChev, cz + dirZ * reach);
    final back = OrbitVec3(cx + dirX * reach * 0.35, yChev, cz + dirZ * reach * 0.35);
    final px = -dirZ;
    final pz = dirX;
    final left = OrbitVec3(back.x + px * 0.18, yChev, back.z + pz * 0.18);
    final right = OrbitVec3(back.x - px * 0.18, yChev, back.z - pz * 0.18);
    final tipP = RoomProjection.project(tip, size, cam);
    final leftP = RoomProjection.project(left, size, cam);
    final rightP = RoomProjection.project(right, size, cam);
    if (tipP != null && leftP != null && rightP != null) {
      final depth = (tipP.depth + leftP.depth + rightP.depth) / 3;
      out.add(_Drawable(depth - 0.01, (canvas) {
        final path = Path()
          ..moveTo(tipP.offset.dx, tipP.offset.dy)
          ..lineTo(leftP.offset.dx, leftP.offset.dy)
          ..lineTo(rightP.offset.dx, rightP.offset.dy)
          ..close();
        canvas.drawPath(
          path,
          Paint()..color = (item.selected ? AppColors.cyan : item.color).withValues(alpha: 0.9),
        );
      }));
    }
  }

  void _collectWallFitting(
    List<_Drawable> out,
    _RoomRenderItem item,
    SurfaceMount mount,
    Size size,
    CameraPose cam,
  ) {
    final span = mount.span!;
    switch (mount.style) {
      case MountStyle.window:
        _collectWindow(out, item, mount, span, size, cam);
      case MountStyle.door:
        _collectDoor(out, item, mount, span, size, cam);
      case MountStyle.vent:
        _collectVent(out, item, mount, span, size, cam);
      case MountStyle.intake:
      case MountStyle.exhaust:
        _collectVent(out, item, mount, span, size, cam);
      case MountStyle.floorItem:
      case MountStyle.deskItem:
      case MountStyle.ceilingFixture:
        _collectBox(out, item, size, cam);
    }
  }

  void _collectWindow(
    List<_Drawable> out,
    _RoomRenderItem item,
    SurfaceMount mount,
    WallSpan span,
    Size size,
    CameraPose cam,
  ) {
    final glass = _fittingFace(span, mount.bottomY, mount.topY, 0.02);
    final face = RoomProjection.projectFace(
      RoomFace(glass, AppColors.lightingColor.withValues(alpha: item.selected ? 0.42 : 0.28)),
      size,
      cam,
    );
    if (face == null) return;

    // Mullion endpoints, projected up front so the closure just draws.
    final midY = (mount.bottomY + mount.topY) / 2;
    final midT = 0.5;
    final vTop = _projectAlongWall(span, midT, mount.topY, 0.02, size, cam);
    final vBottom = _projectAlongWall(span, midT, mount.bottomY, 0.02, size, cam);
    final hStart = _projectAlongWall(span, 0, midY, 0.02, size, cam);
    final hEnd = _projectAlongWall(span, 1, midY, 0.02, size, cam);
    final sillA = _projectAlongWall(span, 0, mount.bottomY, 0.14, size, cam);
    final sillB = _projectAlongWall(span, 1, mount.bottomY, 0.14, size, cam);

    out.add(_Drawable(face.depth, (canvas) {
      final path = Path()..addPolygon(face.points, true);
      canvas.drawPath(path, Paint()..color = face.color);
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.lightingColor.withValues(alpha: item.selected ? 0.95 : 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = item.selected ? 2.4 : 1.8,
      );

      final mullion = Paint()
        ..color = AppColors.lightingColor.withValues(alpha: 0.55)
        ..strokeWidth = 1.2;
      if (vTop != null && vBottom != null) canvas.drawLine(vTop, vBottom, mullion);
      if (hStart != null && hEnd != null) canvas.drawLine(hStart, hEnd, mullion);

      // Sill: a small ledge that reads as the window sitting in the wall.
      if (sillA != null && sillB != null) {
        canvas.drawLine(
          sillA,
          sillB,
          Paint()
            ..color = AppColors.lightingColor.withValues(alpha: 0.85)
            ..strokeWidth = 3,
        );
      }
    }));
  }

  void _collectDoor(
    List<_Drawable> out,
    _RoomRenderItem item,
    SurfaceMount mount,
    WallSpan span,
    Size size,
    CameraPose cam,
  ) {
    final leaf = _fittingFace(span, mount.bottomY, mount.topY, 0.02);
    final face = RoomProjection.projectFace(
      RoomFace(leaf, AppColors.textMuted.withValues(alpha: item.selected ? 0.42 : 0.26)),
      size,
      cam,
    );
    if (face == null) return;

    // Swing arc on the floor, hinged at the span start.
    final radius = span.length;
    final arc = <Offset>[];
    const steps = 12;
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final angle = t * math.pi / 2;
      // Sweep from along-wall toward the inward normal.
      final alongX = (span.x1 - span.x0) / (radius == 0 ? 1 : radius);
      final alongZ = (span.z1 - span.z0) / (radius == 0 ? 1 : radius);
      final px = span.x0 + (alongX * math.cos(angle) + span.inwardX * math.sin(angle)) * radius;
      final pz = span.z0 + (alongZ * math.cos(angle) + span.inwardZ * math.sin(angle)) * radius;
      final p = RoomProjection.project(OrbitVec3(px, 0.02, pz), size, cam);
      if (p == null) {
        arc.clear();
        break;
      }
      arc.add(p.offset);
    }

    final handle = _projectAlongWall(span, 0.82, mount.topY * 0.45, 0.05, size, cam);

    out.add(_Drawable(face.depth, (canvas) {
      final path = Path()..addPolygon(face.points, true);
      canvas.drawPath(path, Paint()..color = face.color);
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.textSecondary.withValues(alpha: item.selected ? 0.95 : 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = item.selected ? 2.4 : 1.8,
      );

      if (arc.length > 2) {
        final arcPath = Path()..moveTo(arc.first.dx, arc.first.dy);
        for (final p in arc.skip(1)) {
          arcPath.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(
          arcPath,
          Paint()
            ..color = AppColors.textSecondary.withValues(alpha: 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        canvas.drawLine(
          arc.first,
          arc.last,
          Paint()
            ..color = AppColors.textSecondary.withValues(alpha: 0.28)
            ..strokeWidth = 1,
        );
      }

      if (handle != null) {
        canvas.drawCircle(handle, 2.4, Paint()..color = AppColors.textSecondary.withValues(alpha: 0.8));
      }
    }));
  }

  void _collectVent(
    List<_Drawable> out,
    _RoomRenderItem item,
    SurfaceMount mount,
    WallSpan span,
    Size size,
    CameraPose cam,
  ) {
    // An AC head visibly stands off the wall, so it gets a body with depth
    // rather than a flat decal.
    final inner = _fittingFace(span, mount.bottomY, mount.topY, mount.protrusion);
    final outer = _fittingFace(span, mount.bottomY, mount.topY, 0.01);

    final bodyFaces = <RoomFace>[
      RoomFace(inner, AppColors.airflowColor.withValues(alpha: item.selected ? 0.55 : 0.38)),
      // Underside, where the air actually leaves the unit.
      RoomFace(
        [outer[0], inner[0], inner[1], outer[1]],
        AppColors.airflowColor.withValues(alpha: 0.5),
      ),
      RoomFace(
        [outer[3], inner[3], inner[2], outer[2]],
        AppColors.airflowColor.withValues(alpha: 0.26),
      ),
    ];

    final louvers = <(Offset, Offset)>[];
    for (int i = 1; i <= 3; i++) {
      final y = mount.bottomY + (mount.topY - mount.bottomY) * (i / 5);
      final a = _projectAlongWall(span, 0.08, y, mount.protrusion + 0.01, size, cam);
      final b = _projectAlongWall(span, 0.92, y, mount.protrusion + 0.01, size, cam);
      if (a != null && b != null) louvers.add((a, b));
    }

    // Short arrows showing the throw direction into the room and downward.
    final throwLines = <(Offset, Offset)>[];
    for (final t in const [0.25, 0.5, 0.75]) {
      final from = _projectAlongWall(span, t, mount.bottomY, mount.protrusion, size, cam);
      final toX = span.x0 + (span.x1 - span.x0) * t + span.inwardX * 0.95;
      final toZ = span.z0 + (span.z1 - span.z0) * t + span.inwardZ * 0.95;
      final to = RoomProjection.project(OrbitVec3(toX, mount.bottomY - 0.55, toZ), size, cam);
      if (from != null && to != null) throwLines.add((from, to.offset));
    }

    for (final face in bodyFaces) {
      final p = RoomProjection.projectFace(face, size, cam);
      if (p == null) continue;
      final isInner = identical(face, bodyFaces.first);
      out.add(_Drawable(p.depth, (canvas) {
        final path = Path()..addPolygon(p.points, true);
        canvas.drawPath(path, Paint()..color = p.color);
        canvas.drawPath(
          path,
          Paint()
            ..color = AppColors.airflowColor.withValues(alpha: item.selected ? 0.95 : 0.62)
            ..style = PaintingStyle.stroke
            ..strokeWidth = item.selected ? 2.2 : 1.4,
        );
        if (!isInner) return;

        final louverPaint = Paint()
          ..color = AppColors.airflowColor.withValues(alpha: 0.75)
          ..strokeWidth = 1.2;
        for (final (a, b) in louvers) {
          canvas.drawLine(a, b, louverPaint);
        }

        final throwPaint = Paint()
          ..color = AppColors.airflowColor.withValues(alpha: 0.35)
          ..strokeWidth = 1.4;
        for (final (a, b) in throwLines) {
          canvas.drawLine(a, b, throwPaint);
        }
      }));
    }
  }

  void _collectCeilingFixture(
    List<_Drawable> out,
    _RoomRenderItem item,
    SurfaceMount mount,
    Size size,
    CameraPose cam,
  ) {
    final cx = item.x + item.width / 2;
    final cz = item.z + item.depth / 2;
    final anchor = RoomProjection.project(OrbitVec3(cx, mount.topY, cz), size, cam);
    if (anchor == null) return;
    final lens = RoomProjection.project(OrbitVec3(cx, mount.bottomY, cz), size, cam);
    final floorSpot = RoomProjection.project(OrbitVec3(cx, 0.02, cz), size, cam);

    out.add(_Drawable(anchor.depth, (canvas) {
      if (lens != null) {
        canvas.drawLine(
          anchor.offset,
          lens.offset,
          Paint()
            ..color = AppColors.lightingColor.withValues(alpha: 0.6)
            ..strokeWidth = 1.6,
        );
        canvas.drawCircle(
          lens.offset,
          item.selected ? 11 : 9,
          Paint()..color = AppColors.lightingColor.withValues(alpha: 0.30),
        );
        canvas.drawCircle(
          lens.offset,
          item.selected ? 5.5 : 4.5,
          Paint()..color = AppColors.lightingColor.withValues(alpha: 0.95),
        );
      }
      // Faint pool on the floor so the fixture reads as lighting the room.
      if (floorSpot != null) {
        canvas.drawCircle(
          floorSpot.offset,
          22,
          Paint()..color = AppColors.lightingColor.withValues(alpha: 0.07),
        );
      }
    }));
  }

  /// Projects a point [t] of the way along a wall span, [y] metres up, inset
  /// from the wall by [inset].
  Offset? _projectAlongWall(
    WallSpan span,
    double t,
    double y,
    double inset,
    Size size,
    CameraPose cam,
  ) {
    final x = span.x0 + (span.x1 - span.x0) * t + span.inwardX * inset;
    final z = span.z0 + (span.z1 - span.z0) * t + span.inwardZ * inset;
    return RoomProjection.project(OrbitVec3(x, y, z), size, cam)?.offset;
  }

  @override
  bool shouldRepaint(covariant _RoomOrbit3DPainter oldDelegate) {
    return oldDelegate.yaw != yaw ||
        oldDelegate.pitch != pitch ||
        oldDelegate.distance != distance ||
        oldDelegate.lookAtX != lookAtX ||
        oldDelegate.lookAtZ != lookAtZ ||
        oldDelegate.items != items;
  }
}

class _PickedEntity {
  final String id;
  final bool isScanObject;

  const _PickedEntity({required this.id, required this.isScanObject});
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
  final bool installed;
  final VoidCallback? onTap;

  const _AddCatalogTile({
    required this.icon,
    required this.name,
    required this.detail,
    required this.category,
    this.trailing,
    this.installed = false,
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
                  if (installed)
                    Text(
                      'ADDED',
                      style: TextStyle(
                        color: AppColors.green,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  else ...[
                    if (trailing != null)
                      Text(
                        trailing!,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    const SizedBox(width: 8),
                    const Icon(Icons.add_circle_outline_rounded, size: 20, color: AppColors.cyan),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarFilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SidebarFilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppColors.cyan.withValues(alpha: 0.18) : AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppColors.cyan.withValues(alpha: 0.6) : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? AppColors.cyan : AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ScanActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ScanActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ],
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

