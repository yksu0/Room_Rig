// lib/screens/rig_customizer_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/room_model.dart';
import '../models/scan_layout_model.dart';
import '../services/layout_collision.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/glass_card.dart';
import '../widgets/room_icons.dart';

enum _RigViewMode { twoD, threeD }
enum _OptimizeGoal { balanced, airflow, lighting, ergonomics }

class RigCustomizerScreen extends StatefulWidget {
  const RigCustomizerScreen({super.key});

  @override
  State<RigCustomizerScreen> createState() => _RigCustomizerScreenState();
}

class _RigCustomizerScreenState extends State<RigCustomizerScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  _RigViewMode _viewMode = _RigViewMode.twoD;
  _OptimizeGoal _optimizeGoal = _OptimizeGoal.balanced;
  double _roomRotationRad = 0;
  double _cameraPitchRad = 0.34;
  double _cameraDistance = 15;
  double _scaleStartDistance = 15;
  final Map<int, Offset> _active3DPoints = {};
  String _sidebarQuery = '';
  String? _sidebarCategory; // null = all
  double _sidebarMinConfidence = 0; // 0, 0.5, 0.7, 0.85

  double get _roomRotationRadians => _roomRotationRad;

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
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(child: _buildCanvas(state)),
                      _buildOptimizationPanel(state),
                    ],
                  ),
                  if (selectedFurniture != null) _buildFurnitureInfoCard(state, selectedFurniture),
                  if (selectedScanObject != null) _buildScanInfoCard(state, selectedScanObject),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RIG CUSTOMIZER',
                    style: TextStyle(color: AppColors.cyan, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 3),
                  ),
                  Text(
                    state.currentRoomData.name,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const Spacer(),
              _HistoryButton(
                icon: Icons.undo_rounded,
                enabled: state.canUndoLayout,
                tooltip: 'Undo layout',
                onTap: state.canUndoLayout ? state.undoLayout : null,
              ),
              const SizedBox(width: 6),
              _HistoryButton(
                icon: Icons.redo_rounded,
                enabled: state.canRedoLayout,
                tooltip: 'Redo layout',
                onTap: state.canRedoLayout ? state.redoLayout : null,
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      SvgIcon(RoomSvg.tune, size: 15, color: AppColors.cyan),
                      const SizedBox(width: 6),
                      const Text('Items', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (state.layoutConflicts.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ConflictBanner(conflicts: state.layoutConflicts),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(width: 170, child: _buildViewToggle()),
              SizedBox(width: 170, child: _buildRotationControl()),
              GestureDetector(
                onTap: () {
                  final goal = switch (_optimizeGoal) {
                    _OptimizeGoal.airflow => 'airflow',
                    _OptimizeGoal.lighting => 'lighting',
                    _OptimizeGoal.ergonomics => 'ergonomics',
                    _OptimizeGoal.balanced => null,
                  };
                  // Balanced uses live slider mix; other chips apply their preset via goal.
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
                          Expanded(
                            child: Text('Auto-Rig applied · $mix'),
                          ),
                        ],
                      ),
                      backgroundColor: AppColors.cyan.withValues(alpha: 0.9),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: AppColors.accentGradient,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.3), blurRadius: 12)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgIcon(RoomSvg.star, size: 16, color: Colors.white),
                      const SizedBox(width: 6),
                      const Text('Auto-Rig', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  state.loadSimulatedPrototypeBaseline();
                  state.setTab(3);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Loaded inefficient demo baseline. Airflow simulation is first, then Lighting and Ergonomics.'),
                      backgroundColor: AppColors.card,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.science_rounded, size: 16, color: AppColors.cyan),
                      const SizedBox(width: 6),
                      const Text(
                        'Sim Prototype',
                        style: TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildViewToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ViewModeChip(
              label: '2D Grid',
              active: _viewMode == _RigViewMode.twoD,
              onTap: () => setState(() => _viewMode = _RigViewMode.twoD),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _ViewModeChip(
              label: '3D View',
              active: _viewMode == _RigViewMode.threeD,
              onTap: () => setState(() => _viewMode = _RigViewMode.threeD),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRotationControl() {
    final state = context.watch<AppState>();
    final selected = state.selectedFurniture;
    final rotatingItem = selected != null;
    final labelDeg = rotatingItem
        ? selected.yawDegrees.round()
        : (_roomRotationRad * 180 / math.pi).round();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 160;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (compact)
                Row(
                  children: [
                    Icon(
                      rotatingItem ? Icons.crop_rotate_rounded : Icons.threesixty_rounded,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$labelDeg°',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(
                      rotatingItem ? Icons.crop_rotate_rounded : Icons.threesixty_rounded,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        rotatingItem ? 'Item yaw' : 'Room orbit',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1),
                      ),
                    ),
                    Text(
                      '$labelDeg deg',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _RotationButton(
                    icon: Icons.rotate_left_rounded,
                    tooltip: rotatingItem ? 'Rotate item left 90°' : 'Orbit left',
                    onTap: () {
                      if (rotatingItem) {
                        state.rotateFurniture(selected.id, deltaDegrees: -90);
                      } else {
                        setState(() => _roomRotationRad = (_roomRotationRad - math.pi / 8).clamp(-math.pi, math.pi));
                      }
                    },
                  ),
                  _RotationButton(
                    icon: Icons.center_focus_strong_rounded,
                    tooltip: rotatingItem ? 'Reset item yaw' : 'Reset orbit',
                    onTap: () {
                      if (rotatingItem) {
                        final current = selected.yawDegrees;
                        if (current.abs() > 0.01) {
                          state.rotateFurniture(selected.id, deltaDegrees: -current);
                        }
                      } else {
                        setState(() => _roomRotationRad = 0);
                      }
                    },
                  ),
                  _RotationButton(
                    icon: Icons.rotate_right_rounded,
                    tooltip: rotatingItem ? 'Rotate item right 90°' : 'Orbit right',
                    onTap: () {
                      if (rotatingItem) {
                        state.rotateFurniture(selected.id, deltaDegrees: 90);
                      } else {
                        setState(() => _roomRotationRad = (_roomRotationRad + math.pi / 8).clamp(-math.pi, math.pi));
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCanvas(AppState state) {
    if (_viewMode == _RigViewMode.threeD) {
      return _buildPseudo3DCanvas(state);
    }

    return GestureDetector(
      onTap: () => state.clearSelection(),
      onHorizontalDragUpdate: (details) {
        setState(() {
          _roomRotationRad = (_roomRotationRad + details.delta.dx * 0.01).clamp(-math.pi, math.pi);
        });
      },
      child: Container(
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
              final cellW = constraints.maxWidth / state.currentRoomData.gridCols;
              final cellH = constraints.maxHeight / state.currentRoomData.gridRows;
              final coverage = state.activeRoomLayout?.coverageGrid;
              return Stack(
                children: [
                  Transform.rotate(
                    angle: _roomRotationRadians,
                    alignment: Alignment.center,
                    child: Stack(
                      children: [
                        CustomPaint(
                          size: Size(constraints.maxWidth, constraints.maxHeight),
                          painter: _RoomGridPainter(
                            gridCols: state.currentRoomData.gridCols,
                            gridRows: state.currentRoomData.gridRows,
                            coverage: coverage,
                          ),
                        ),
                        ..._buildSurfaceDetections2D(constraints.maxWidth, constraints.maxHeight),
                        ...state.furniture.where((item) => !item.hidden).map((item) {
                          final isSelected = state.selectedItemId == item.id && !state.selectedIsScanObject;
                          return Positioned(
                            left: item.gridX * cellW + cellW * 0.05,
                            top: item.gridY * cellH + cellH * 0.05,
                            width: item.width * cellW * 0.9,
                            height: item.height * cellH * 0.9,
                            child: GestureDetector(
                              onTap: () => state.selectFurniture(item.id, toggle: true),
                              onPanStart: item.locked
                                  ? null
                                  : (_) {
                                      state.selectFurniture(item.id);
                                      state.beginFurnitureGesture();
                                    },
                              onPanUpdate: item.locked
                                  ? null
                                  : (details) {
                                      final rotatedDelta = _rotateOffset(details.delta, -_roomRotationRadians);
                                      final newX = item.gridX + rotatedDelta.dx / cellW;
                                      final newY = item.gridY + rotatedDelta.dy / cellH;
                                      state.moveFurniture(item.id, newX, newY);
                                    },
                              onPanEnd: item.locked ? null : (_) => state.endFurnitureGesture(),
                              onPanCancel: item.locked ? null : () => state.endFurnitureGesture(),
                              child: Opacity(
                                opacity: item.locked ? 0.85 : 1,
                                child: _FurnitureCell(
                                  item: item,
                                  isSelected: isSelected,
                                  hasConflict: state.layoutConflicts.any((c) => c.itemIds.contains(item.id)),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
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
                  (item) => _RoomRenderItem(
                    id: item.id,
                    x: item.gridX,
                    z: item.gridY,
                    width: item.width,
                    depth: item.height,
                    color: _categoryColor(item.category),
                    selected: state.selectedItemId == item.id && !state.selectedIsScanObject,
                    isScanObject: false,
                    label: item.name,
                    heightY: 0.95,
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
              onPointerDown: (event) {
                _active3DPoints[event.pointer] = event.localPosition;
                if (_active3DPoints.length == 2) {
                  _scaleStartDistance = _cameraDistance;
                }
              },
              onPointerMove: (event) {
                final start = _active3DPoints[event.pointer];
                if (start == null) return;

                _active3DPoints[event.pointer] = event.localPosition;

                setState(() {
                  if (_active3DPoints.length >= 2) {
                    final points = _active3DPoints.values.toList(growable: false);
                    final first = points[0];
                    final second = points[1];
                    final currentDistance = (first - second).distance;
                    final baseDistance = currentDistance < 0.001 ? 0.001 : currentDistance;
                    _cameraDistance = (_scaleStartDistance * (baseDistance / 220)).clamp(8.0, 28.0);
                    final center = Offset((first.dx + second.dx) / 2, (first.dy + second.dy) / 2);
                    final delta = center - start;
                    _roomRotationRad = (_roomRotationRad + delta.dx * 0.008).clamp(-math.pi, math.pi);
                    _cameraPitchRad = (_cameraPitchRad - delta.dy * 0.006).clamp(-0.1, 1.0);
                  } else {
                    final delta = event.delta;
                    _roomRotationRad = (_roomRotationRad + delta.dx * 0.008).clamp(-math.pi, math.pi);
                    _cameraPitchRad = (_cameraPitchRad - delta.dy * 0.006).clamp(-0.1, 1.0);
                  }
                });
              },
              onPointerUp: (event) {
                final start = _active3DPoints[event.pointer];
                _active3DPoints.remove(event.pointer);
                if (_active3DPoints.isEmpty) {
                  _scaleStartDistance = _cameraDistance;
                }
                if (start != null && (start - event.localPosition).distance < 8) {
                  final picked = _pickItemIn3D(event.localPosition, canvasSize, state);
                  if (picked != null) {
                    if (picked.isScanObject) {
                      state.selectScanObject(picked.id, toggle: true);
                    } else {
                      state.selectFurniture(picked.id, toggle: true);
                    }
                  } else {
                    state.clearSelection();
                  }
                }
              },
              onPointerCancel: (event) {
                _active3DPoints.remove(event.pointer);
              },
              onPointerSignal: (signal) {
                if (signal is PointerScrollEvent) {
                  setState(() {
                    _cameraDistance = (_cameraDistance + signal.scrollDelta.dy * 0.02).clamp(8.0, 28.0);
                  });
                }
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
                      yaw: _roomRotationRadians,
                      pitch: _cameraPitchRad,
                      distance: _cameraDistance,
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
                        '3D orbit: drag to look, tap objects to select, pinch/scroll to zoom, hold and drag to orbit around the room',
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
                        'yaw ${(_roomRotationRad * 180 / math.pi).round()} deg  pitch ${(_cameraPitchRad * 180 / math.pi).round()} deg',
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
                      child: const Text(
                        'Tip: rotate to inspect airflow from all sides',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  _PickedEntity? _pickItemIn3D(Offset localPos, Size size, AppState state) {
    final roomWidth = state.currentRoomData.gridCols.toDouble();
    final roomDepth = state.currentRoomData.gridRows.toDouble();
    final cam = _CameraPose(
      roomWidth: roomWidth,
      roomDepth: roomDepth,
      roomHeight: 2.8,
      yaw: _roomRotationRadians,
      pitch: _cameraPitchRad,
      distance: _cameraDistance,
    );

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
        (item) => _RoomRenderItem(
          id: item.id,
          x: item.gridX,
          z: item.gridY,
          width: item.width,
          depth: item.height,
          heightY: 0.95,
          color: Colors.white,
          selected: false,
          isScanObject: false,
          label: item.name,
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
      final yTop = 0.95;
      final a = _Vec3(item.x, 0, item.z);
      final b = _Vec3(item.x + item.width, 0, item.z);
      final c = _Vec3(item.x + item.width, 0, item.z + item.depth);
      final d = _Vec3(item.x, 0, item.z + item.depth);
      final a2 = _Vec3(item.x, yTop, item.z);
      final b2 = _Vec3(item.x + item.width, yTop, item.z);
      final c2 = _Vec3(item.x + item.width, yTop, item.z + item.depth);
      final d2 = _Vec3(item.x, yTop, item.z + item.depth);

      final faces = [
        _RoomProjection.projectFace(_Face([a2, b2, c2, d2], Colors.white), size, cam),
        _RoomProjection.projectFace(_Face([a, b, b2, a2], Colors.white), size, cam),
        _RoomProjection.projectFace(_Face([b, c, c2, b2], Colors.white), size, cam),
        _RoomProjection.projectFace(_Face([c, d, d2, c2], Colors.white), size, cam),
        _RoomProjection.projectFace(_Face([d, a, a2, d2], Colors.white), size, cam),
      ];

      for (final face in faces) {
        if (face == null) continue;
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
      final point = _RoomProjection.project(
        _Vec3(item.x + item.width * 0.5, 0.6, item.z + item.depth * 0.5),
        size,
        cam,
      );
      if (point == null) continue;
      final distance = (point.offset - localPos).distance;
      if (distance < fallbackDist) {
        fallbackDist = distance;
        fallback = _PickedEntity(id: item.id, isScanObject: item.isScanObject);
      }
    }
    return fallback;
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
                      final canDelete = item.iconName != 'door' && item.iconName != 'window';

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
                                            '${item.category.toUpperCase()}  •  ${item.statusLabel}  •  $confLabel',
                                            style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (item.locked)
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

  Offset _rotateOffset(Offset p, double rad) {
    final c = math.cos(rad);
    final s = math.sin(rad);
    return Offset(p.dx * c - p.dy * s, p.dx * s + p.dy * c);
  }

  List<Widget> _buildSurfaceDetections2D(double w, double h) {
    return [
      Positioned(
        left: w * 0.12,
        top: 8,
        child: _SurfaceBadge(icon: RoomSvg.window, label: 'Window'),
      ),
      Positioned(
        left: 8,
        top: h * 0.72,
        child: _SurfaceBadge(icon: RoomSvg.door, label: 'Door'),
      ),
      Positioned(
        right: 10,
        top: h * 0.18,
        child: _SurfaceBadge(icon: RoomSvg.fan, label: 'AC'),
      ),
      Positioned(
        left: w * 0.45,
        top: h * 0.02,
        child: _SurfaceBadge(icon: RoomSvg.lightbulb, label: 'Ceiling Light'),
      ),
    ];
  }

  Widget _buildOptimizationPanel(AppState state) {
    final weights = state.optimizeWeights;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AUTO-RIG GOAL',
            style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
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
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'WEIGHT MIX  ·  ${weights.summaryLabel}',
            style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2),
          ),
          const SizedBox(height: 4),
          _WeightSlider(
            label: 'Airflow',
            color: AppColors.airflowColor,
            value: state.airflowSlider,
            percent: (weights.airflowNorm * 100).round(),
            onChanged: (v) {
              setState(() => _optimizeGoal = _OptimizeGoal.balanced);
              state.setAirflowSlider(v);
            },
          ),
          _WeightSlider(
            label: 'Lighting',
            color: AppColors.lightingColor,
            value: state.lightingSlider,
            percent: (weights.lightingNorm * 100).round(),
            onChanged: (v) {
              setState(() => _optimizeGoal = _OptimizeGoal.balanced);
              state.setLightingSlider(v);
            },
          ),
          _WeightSlider(
            label: 'Ergonomics',
            color: AppColors.ergonomicsColor,
            value: state.ergonomicsSlider,
            percent: (weights.ergonomicsNorm * 100).round(),
            onChanged: (v) {
              setState(() => _optimizeGoal = _OptimizeGoal.balanced);
              state.setErgonomicsSlider(v);
            },
          ),
          const SizedBox(height: 4),
          Text(
            weights.dominantGoal == null
                ? 'Blends independent proposals by weight (no sequential overwrite).'
                : 'Dominant ${weights.dominantGoal} — runs that Auto-Rig path directly.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
          if (state.lastOptimizeReasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...state.lastOptimizeReasons.take(5).map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline, size: 12, color: AppColors.green),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        r,
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFurnitureInfoCard(AppState state, FurnitureItem item) {
    return Positioned(
      bottom: 210,
      left: 16,
      right: 16,
      child: GestureDetector(
        onTap: () => state.clearSelection(),
        child: NeonBorderCard(
          glowColor: AppColors.cyan,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.cyan.withValues(alpha: 0.3)),
                    ),
                    child: Center(child: SvgIcon(furnitureSvgFor(item.iconName), size: 22, color: AppColors.cyan)),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(
                        '${item.category.toUpperCase()}  •  yaw ${item.yawDegrees.round()}°',
                        style: TextStyle(color: AppColors.cyan, fontSize: 10, letterSpacing: 1.2),
                      ),
                    ],
                  ),
                  const Spacer(),
                  SvgIcon(RoomSvg.info, size: 18, color: AppColors.textMuted),
                ],
              ),
              const SizedBox(height: 12),
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
                'Drag to move  •  Rotation buttons yaw ±90°  •  Tap to deselect'
                '${item.locked ? '  •  Locked' : ''}'
                '${item.hidden ? '  •  Hidden' : ''}',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScanInfoCard(AppState state, ScanObject obj) {
    final color = _categoryColor(obj.category);
    return Positioned(
      bottom: 210,
      left: 16,
      right: 16,
      child: GestureDetector(
        onTap: () => state.clearSelection(),
        child: NeonBorderCard(
          glowColor: color,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color.withValues(alpha: 0.3)),
                    ),
                    child: Center(child: Icon(Icons.view_in_ar_rounded, size: 22, color: color)),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(obj.label, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(obj.category.toUpperCase(), style: TextStyle(color: color, fontSize: 10, letterSpacing: 2)),
                    ],
                  ),
                  const Spacer(),
                  if (obj.locked) const Icon(Icons.lock_rounded, color: AppColors.amber, size: 18),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${obj.sizeMeters.x.toStringAsFixed(2)}m × ${obj.sizeMeters.z.toStringAsFixed(2)}m × ${obj.sizeMeters.y.toStringAsFixed(2)}m',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Text(
                'Detected confidence: ${(obj.confidence * 100).round()}%  •  Tap to deselect',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ),
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isSelected ? 0.2 : 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSelected || hasConflict ? color : color.withValues(alpha: 0.35),
          width: isSelected || hasConflict ? 1.8 : 1,
        ),
        boxShadow: isSelected
            ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 12)]
            : [],
      ),
      child: Center(
        child: SvgIcon(
          furnitureSvgFor(item.iconName),
          size: isSelected ? 24 : 20,
          color: isSelected || hasConflict ? color : AppColors.textSecondary,
        ),
      ),
    );
  }
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

class _RoomGridPainter extends CustomPainter {
  final int gridCols;
  final int gridRows;
  final CoverageGrid? coverage;

  _RoomGridPainter({
    required this.gridCols,
    required this.gridRows,
    this.coverage,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / gridCols;
    final cellH = size.height / gridRows;

    final cov = coverage;
    if (cov != null && cov.cols == gridCols && cov.rows == gridRows) {
      for (int row = 0; row < gridRows; row++) {
        for (int col = 0; col < gridCols; col++) {
          final v = cov.coverage[row * cov.cols + col].clamp(0.0, 1.0);
          if (v < 0.05) continue;
          final paint = Paint()
            ..color = AppColors.cyan.withValues(alpha: 0.08 + v * 0.18);
          canvas.drawRect(
            Rect.fromLTWH(col * cellW, row * cellH, cellW, cellH),
            paint,
          );
        }
      }
    }

    final gridPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.45)
      ..strokeWidth = 0.5;

    for (int col = 0; col <= gridCols; col++) {
      canvas.drawLine(Offset(col * cellW, 0), Offset(col * cellW, size.height), gridPaint);
    }
    for (int row = 0; row <= gridRows; row++) {
      canvas.drawLine(Offset(0, row * cellH), Offset(size.width, row * cellH), gridPaint);
    }

    final wallPaint = Paint()
      ..color = AppColors.cyan.withValues(alpha: 0.25)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTWH(1, 1, size.width - 2, size.height - 2), wallPaint);
  }

  @override
  bool shouldRepaint(_RoomGridPainter old) =>
      old.gridCols != gridCols ||
      old.gridRows != gridRows ||
      old.coverage != coverage;
}

class _RoomRenderItem {
  final String id;
  final double x;
  final double z;
  final double width;
  final double depth;
  final double heightY;
  final Color color;
  final bool selected;
  final bool isScanObject;
  final String label;

  const _RoomRenderItem({
    required this.id,
    required this.x,
    required this.z,
    required this.width,
    required this.depth,
    required this.heightY,
    required this.color,
    required this.selected,
    required this.isScanObject,
    required this.label,
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
    required this.items,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cam = _CameraPose(
      roomWidth: roomWidth,
      roomDepth: roomDepth,
      roomHeight: roomHeight,
      yaw: yaw,
      pitch: pitch,
      distance: distance,
    );

    final faces = <_Face>[];

    final v000 = _Vec3(0, 0, 0);
    final v100 = _Vec3(roomWidth, 0, 0);
    final v110 = _Vec3(roomWidth, 0, roomDepth);
    final v010 = _Vec3(0, 0, roomDepth);

    final v001 = _Vec3(0, roomHeight, 0);
    final v101 = _Vec3(roomWidth, roomHeight, 0);
    final v111 = _Vec3(roomWidth, roomHeight, roomDepth);
    final v011 = _Vec3(0, roomHeight, roomDepth);

    faces.add(_Face([v000, v100, v110, v010], AppColors.surfaceAlt.withValues(alpha: 0.72)));
    faces.add(_Face([v001, v011, v111, v101], AppColors.textMuted.withValues(alpha: 0.22)));
    faces.add(_Face([v000, v001, v101, v100], AppColors.surfaceAlt.withValues(alpha: 0.40)));
    faces.add(_Face([v100, v101, v111, v110], AppColors.surfaceAlt.withValues(alpha: 0.44)));
    faces.add(_Face([v110, v111, v011, v010], AppColors.surfaceAlt.withValues(alpha: 0.50)));
    faces.add(_Face([v010, v011, v001, v000], AppColors.surfaceAlt.withValues(alpha: 0.42)));

    final projected = <_ProjectedFace>[];
    for (final face in faces) {
      final p = _RoomProjection.projectFace(face, size, cam);
      if (p != null) projected.add(p);
    }
    projected.sort((a, b) => b.depth.compareTo(a.depth));

    for (final pFace in projected) {
      final path = Path()..addPolygon(pFace.points, true);
      canvas.drawPath(path, Paint()..color = pFace.color);
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.cyan.withValues(alpha: 0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    final gridPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.55)
      ..strokeWidth = 0.8;
    for (int c = 0; c <= gridCols; c++) {
      final a = _RoomProjection.project(_Vec3(c.toDouble(), 0.001, 0), size, cam);
      final b = _RoomProjection.project(_Vec3(c.toDouble(), 0.001, roomDepth), size, cam);
      if (a != null && b != null) canvas.drawLine(a.offset, b.offset, gridPaint);
    }
    for (int r = 0; r <= gridRows; r++) {
      final a = _RoomProjection.project(_Vec3(0, 0.001, r.toDouble()), size, cam);
      final b = _RoomProjection.project(_Vec3(roomWidth, 0.001, r.toDouble()), size, cam);
      if (a != null && b != null) canvas.drawLine(a.offset, b.offset, gridPaint);
    }

    final detections = [
      (_Vec3(roomWidth * 0.3, 1.3, 0.01), AppColors.lightingColor),
      (_Vec3(roomWidth - 0.01, 1.8, roomDepth * 0.62), AppColors.airflowColor),
      (_Vec3(roomWidth * 0.5, roomHeight - 0.02, roomDepth * 0.4), AppColors.cyan),
    ];
    for (final d in detections) {
      final p = _RoomProjection.project(d.$1, size, cam);
      if (p == null) continue;
      canvas.drawCircle(p.offset, 5, Paint()..color = d.$2.withValues(alpha: 0.35));
      canvas.drawCircle(
        p.offset,
        2.2,
        Paint()
          ..color = d.$2
          ..style = PaintingStyle.fill,
      );
    }

    final furnitureFaces = <_ProjectedFace>[];
    for (final item in items) {
      final yTop = item.heightY;
      final a = _Vec3(item.x, 0, item.z);
      final b = _Vec3(item.x + item.width, 0, item.z);
      final c = _Vec3(item.x + item.width, 0, item.z + item.depth);
      final d = _Vec3(item.x, 0, item.z + item.depth);
      final a2 = _Vec3(item.x, yTop, item.z);
      final b2 = _Vec3(item.x + item.width, yTop, item.z);
      final c2 = _Vec3(item.x + item.width, yTop, item.z + item.depth);
      final d2 = _Vec3(item.x, yTop, item.z + item.depth);

      final top = _RoomProjection.projectFace(
        _Face([a2, b2, c2, d2], item.color.withValues(alpha: item.selected ? 0.8 : (item.isScanObject ? 0.46 : 0.55))),
        size,
        cam,
      );
      final sideBase = item.isScanObject ? 0.28 : 0.4;
      final s1 = _RoomProjection.projectFace(_Face([a, b, b2, a2], item.color.withValues(alpha: sideBase)), size, cam);
      final s2 = _RoomProjection.projectFace(_Face([b, c, c2, b2], item.color.withValues(alpha: sideBase + 0.06)), size, cam);
      final s3 = _RoomProjection.projectFace(_Face([c, d, d2, c2], item.color.withValues(alpha: sideBase + 0.02)), size, cam);
      final s4 = _RoomProjection.projectFace(_Face([d, a, a2, d2], item.color.withValues(alpha: sideBase - 0.02)), size, cam);

      if (top != null) furnitureFaces.add(top);
      if (s1 != null) furnitureFaces.add(s1);
      if (s2 != null) furnitureFaces.add(s2);
      if (s3 != null) furnitureFaces.add(s3);
      if (s4 != null) furnitureFaces.add(s4);
    }

    furnitureFaces.sort((a, b) => b.depth.compareTo(a.depth));
    for (final f in furnitureFaces) {
      final path = Path()..addPolygon(f.points, true);
      canvas.drawPath(path, Paint()..color = f.color);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RoomOrbit3DPainter oldDelegate) {
    return oldDelegate.yaw != yaw ||
        oldDelegate.pitch != pitch ||
        oldDelegate.distance != distance ||
        oldDelegate.items != items;
  }
}

class _Face {
  final List<_Vec3> vertices;
  final Color color;
  _Face(this.vertices, this.color);
}

class _ProjectedFace {
  final List<Offset> points;
  final double depth;
  final Color color;
  _ProjectedFace({required this.points, required this.depth, required this.color});
}

class _ProjectedPoint {
  final Offset offset;
  final double depth;
  _ProjectedPoint(this.offset, this.depth);
}

class _Vec3 {
  final double x;
  final double y;
  final double z;
  const _Vec3(this.x, this.y, this.z);

  _Vec3 operator -(_Vec3 o) => _Vec3(x - o.x, y - o.y, z - o.z);
  _Vec3 operator +(_Vec3 o) => _Vec3(x + o.x, y + o.y, z + o.z);
  _Vec3 scale(double s) => _Vec3(x * s, y * s, z * s);
}

class _CameraPose {
  final double roomWidth;
  final double roomDepth;
  final double roomHeight;
  final double yaw;
  final double pitch;
  final double distance;

  _CameraPose({
    required this.roomWidth,
    required this.roomDepth,
    required this.roomHeight,
    required this.yaw,
    required this.pitch,
    required this.distance,
  });
}

class _RoomProjection {
  static _Vec3 _cross(_Vec3 a, _Vec3 b) =>
      _Vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);

  static double _dot(_Vec3 a, _Vec3 b) => a.x * b.x + a.y * b.y + a.z * b.z;

  static _Vec3 _normalize(_Vec3 v) {
    final m = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
    if (m <= 0.0001) return const _Vec3(0, 0, 1);
    return _Vec3(v.x / m, v.y / m, v.z / m);
  }

  static (_Vec3, _Vec3, _Vec3, _Vec3) _cameraBasis(_CameraPose cam) {
    final center = _Vec3(cam.roomWidth * 0.5, cam.roomHeight * 0.45, cam.roomDepth * 0.5);
    final horizontal = cam.distance * math.cos(cam.pitch);
    final eye = _Vec3(
      center.x + horizontal * math.sin(cam.yaw),
      center.y + cam.distance * math.sin(cam.pitch),
      center.z + horizontal * math.cos(cam.yaw),
    );
    final forward = _normalize(center - eye);
    final upWorld = const _Vec3(0, 1, 0);
    final right = _normalize(_cross(forward, upWorld));
    final up = _normalize(_cross(right, forward));
    return (eye, forward, right, up);
  }

  static _ProjectedPoint? project(_Vec3 p, Size size, _CameraPose cam) {
    final basis = _cameraBasis(cam);
    final eye = basis.$1;
    final forward = basis.$2;
    final right = basis.$3;
    final up = basis.$4;
    final rel = p - eye;
    final cx = _dot(rel, right);
    final cy = _dot(rel, up);
    final cz = _dot(rel, forward);
    if (cz <= 0.06) return null;

    const fov = 55 * math.pi / 180;
    final focal = (size.width * 0.5) / math.tan(fov * 0.5);
    final sx = size.width * 0.5 + (cx / cz) * focal;
    final sy = size.height * 0.58 - (cy / cz) * focal;
    return _ProjectedPoint(Offset(sx, sy), cz);
  }

  static _ProjectedFace? projectFace(_Face face, Size size, _CameraPose cam) {
    final points = <Offset>[];
    double depth = 0;
    for (final v in face.vertices) {
      final p = project(v, size, cam);
      if (p == null) return null;
      points.add(p.offset);
      depth += p.depth;
    }
    depth /= face.vertices.length;
    return _ProjectedFace(points: points, depth: depth, color: face.color);
  }
}

class _PickedEntity {
  final String id;
  final bool isScanObject;

  const _PickedEntity({required this.id, required this.isScanObject});
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

class _WeightSlider extends StatelessWidget {
  final String label;
  final Color color;
  final double value;
  final int percent;
  final ValueChanged<double> onChanged;

  const _WeightSlider({
    required this.label,
    required this.color,
    required this.value,
    required this.percent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: color,
                inactiveTrackColor: color.withValues(alpha: 0.18),
                thumbColor: color,
                overlayColor: color.withValues(alpha: 0.12),
              ),
              child: Slider(
                value: value.clamp(0.0, 1.0),
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$percent%',
              textAlign: TextAlign.right,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
        ],
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

class _SurfaceBadge extends StatelessWidget {
  final String icon;
  final String label;

  const _SurfaceBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgIcon(icon, size: 12, color: AppColors.cyan),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
