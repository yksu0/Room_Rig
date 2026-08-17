// lib/models/app_state.dart
import 'dart:convert';
import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'item_detection.dart';
import 'rig_catalog.dart';
import 'room_model.dart';
import 'room_scale.dart';
import 'saved_room.dart';
import 'surface_mount.dart';
import 'scan_layout_model.dart';
import '../services/airflow_optimizer.dart';
import '../services/airflow_simulator.dart';
import '../services/bench_layouts.dart';
import '../services/benchmark_validator.dart';
import '../services/ergonomics_optimizer.dart';
import '../services/ergonomics_simulator.dart';
import '../services/layout_collision.dart';
import '../services/lighting_optimizer.dart';
import '../services/lighting_simulator.dart';
import '../services/multi_objective_optimizer.dart';
import '../services/scan_layout_converter.dart';
import '../services/scan_pipeline.dart';
import '../services/spatial_analyzer.dart';

class AppState extends ChangeNotifier {
  static const _persistedLayoutKey = 'room_rig.persisted_layout';
  static const _persistedScanSessionKey = 'room_rig.last_successful_scan';
  static const _onboardingSeenKey = 'room_rig.onboarding_seen';

  // Navigation
  int _currentTab = 0;
  int get currentTab => _currentTab;

  void setTab(int tab) {
    _currentTab = tab;
    notifyListeners();
  }

  // Scan state
  bool _scanComplete = false;
  bool get scanComplete => _scanComplete;
  double _scanProgress = 0.0;
  double get scanProgress => _scanProgress;

  void setScanProgress(double p, {bool notify = true}) {
    _scanProgress = p;
    if (p >= 1.0) _scanComplete = true;
    if (notify) notifyListeners();
  }

  void resetScan() {
    _scanProgress = 0.0;
    _scanComplete = false;
    notifyListeners();
  }

  // Selected Room
  RoomPreset _selectedPreset = RoomPreset.gamingSetup;
  RoomPreset get selectedPreset => _selectedPreset;
  late List<FurnitureItem> _furniture;
  RoomLayoutModel? _activeRoomLayout;
  String _activeRoomId = 'room_default';
  final List<SavedRoom> _rooms = [];

  AppState() {
    _loadPreset(RoomPreset.gamingSetup);
    unawaited(_restorePersistedLayout());
    unawaited(_restoreOnboardingFlag());
  }

  void _loadPreset(RoomPreset preset) {
    final data = RoomPresets.getPreset(preset);
    _furniture = RigCatalog.retainV1(List.from(data.furniture.map((f) => f.copyWith())));
    _selectedPreset = preset;
    _activeRoomLayout = RoomLayoutModel.fromPreset(data, _furniture);
    _activeRoomId = 'room_${DateTime.now().millisecondsSinceEpoch}';
    _originalFurniture = null;
    _originalScores = null;
    _pendingPlacementId = null;
    _pendingUpgradeIndex = null;
  }

  List<FurnitureItem> get furniture => _furniture;
  List<SavedRoom> get savedRooms => List.unmodifiable(_rooms);
  String get activeRoomId => _activeRoomId;

  RoomData get currentRoomData {
    final preset = RoomPresets.getPreset(_selectedPreset);
    final layout = _activeRoomLayout;
    final cols = RoomScale.colsFrom(layout, fallback: preset.gridCols);
    final rows = RoomScale.rowsFrom(layout, fallback: preset.gridRows);
    final name = (layout != null && layout.roomName.trim().isNotEmpty)
        ? layout.roomName
        : preset.name;
    final subtitle = layout?.scanSource == 'manual'
        ? 'Created without a scan'
        : preset.subtitle;
    return RoomData(
      name: name,
      subtitle: subtitle,
      iconName: preset.iconName,
      gridCols: cols,
      gridRows: rows,
      furniture: _furniture,
      heightMeters: layout?.dimensions.heightMeters ?? RoomScale.defaultHeightMeters,
    );
  }

  RoomLayoutModel? get activeRoomLayout => _activeRoomLayout;

  void _rememberFurniture() {
    final layout = _activeRoomLayout;
    if (layout == null) {
      _activeRoomLayout = RoomLayoutModel.fromPreset(currentRoomData, _furniture);
    } else {
      _activeRoomLayout = layout.withFurniture(_furniture);
    }
  }

  /// When false (default), doors / windows / wall ACs / ceiling lights stay put.
  /// Flip on to rearrange the room's built-in mounts.
  bool _invasiveEdit = false;
  bool get invasiveEdit => _invasiveEdit;

  void setInvasiveEdit(bool value) {
    if (_invasiveEdit == value) return;
    _invasiveEdit = value;
    notifyListeners();
  }

  void toggleInvasiveEdit() => setInvasiveEdit(!_invasiveEdit);

  /// Whether the user may drag / rotate this piece right now.
  bool canMoveFurniture(FurnitureItem item) {
    if (item.id == _pendingPlacementId) return true;
    if (item.locked) return false;
    if (!_invasiveEdit && SurfaceMounts.isStructuralMount(item)) return false;
    return true;
  }

  bool canMoveFurnitureId(String id) {
    final idx = _furniture.indexWhere((f) => f.id == id);
    if (idx < 0) return false;
    return canMoveFurniture(_furniture[idx]);
  }

  // --- Shared selection (2D / 3D / sidebar) ---
  String? _selectedItemId;
  bool _selectedIsScanObject = false;

  String? get selectedItemId => _selectedItemId;
  bool get selectedIsScanObject => _selectedIsScanObject;

  FurnitureItem? get selectedFurniture {
    final id = _selectedItemId;
    if (id == null || _selectedIsScanObject) return null;
    for (final f in _furniture) {
      if (f.id == id) return f;
    }
    return null;
  }

  ScanObject? get selectedScanObject {
    final id = _selectedItemId;
    if (id == null || !_selectedIsScanObject) return null;
    for (final o in detectedScanObjects) {
      if (o.id == id) return o;
    }
    return null;
  }

  void clearSelection() {
    if (_selectedItemId == null) return;
    _selectedItemId = null;
    _selectedIsScanObject = false;
    notifyListeners();
  }

  void selectFurniture(String id, {bool toggle = false}) {
    if (toggle && _selectedItemId == id && !_selectedIsScanObject) {
      clearSelection();
      return;
    }
    _selectedItemId = id;
    _selectedIsScanObject = false;
    notifyListeners();
  }

  void selectScanObject(String id, {bool toggle = false}) {
    if (toggle && _selectedItemId == id && _selectedIsScanObject) {
      clearSelection();
      return;
    }
    _selectedItemId = id;
    _selectedIsScanObject = true;
    notifyListeners();
  }

  /// Confidence for a layout furniture id from the live room model, if present.
  double? confidenceForFurniture(String id) {
    final layout = _activeRoomLayout;
    if (layout == null) return null;
    for (final o in layout.objects) {
      if (o.id == id) return o.confidence;
    }
    return null;
  }

  List<ScanObject> get detectedScanObjects {
    return _activeRoomLayout?.objects
            .where((o) => o.source == 'scan-fusion')
            .toList(growable: false) ??
        const <ScanObject>[];
  }

  List<ItemDetection> get latestItemDetections =>
      _activeRoomLayout?.detections ?? const <ItemDetection>[];

  void deleteDetectedScanObject(String id) {
    final layout = _activeRoomLayout;
    if (layout == null) return;
    final next = layout.objects.where((o) => o.id != id).toList(growable: false);
    _activeRoomLayout = layout.withObjects(next);
    if (_selectedItemId == id && _selectedIsScanObject) {
      _selectedItemId = null;
      _selectedIsScanObject = false;
    }
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
  }

  void toggleDetectedScanObjectLock(String id) {
    final layout = _activeRoomLayout;
    if (layout == null) return;

    final next = layout.objects
        .map((o) => o.id == id ? o.copyWith(locked: !o.locked) : o)
        .toList(growable: false);
    _activeRoomLayout = layout.withObjects(next);
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
  }

  void toggleDetectedScanObjectHidden(String id) {
    final layout = _activeRoomLayout;
    if (layout == null) return;
    final next = layout.objects
        .map((o) => o.id == id ? o.copyWith(hidden: !o.hidden) : o)
        .toList(growable: false);
    _activeRoomLayout = layout.withObjects(next);
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
  }

  bool duplicateDetectedScanObject(String id) {
    final layout = _activeRoomLayout;
    if (layout == null) return false;
    ScanObject? source;
    for (final o in layout.objects) {
      if (o.id == id) {
        source = o;
        break;
      }
    }
    if (source == null) return false;

    final cloneId = _uniqueScanId('${source.id}_copy', layout.objects.map((o) => o.id).toSet());
    final clone = ScanObject(
      id: cloneId,
      label: '${source.label} Copy',
      category: source.category,
      confidence: source.confidence,
      center: Vec3(x: source.center.x + 0.4, y: source.center.y, z: source.center.z + 0.4),
      sizeMeters: source.sizeMeters,
      yawDegrees: source.yawDegrees,
      source: source.source,
      locked: false,
      hidden: false,
    );
    _activeRoomLayout = layout.withObjects([...layout.objects, clone]);
    _selectedItemId = cloneId;
    _selectedIsScanObject = true;
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
    return true;
  }

  void replaceDetectedScanObject(
    String id, {
    required String newLabel,
    required String newCategory,
  }) {
    final layout = _activeRoomLayout;
    if (layout == null) return;

    final next = layout.objects
        .map((o) => o.id == id
            ? o.copyWith(label: newLabel, category: newCategory)
            : o)
        .toList(growable: false);

    _activeRoomLayout = layout.withObjects(next);
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
  }

  void toggleFurnitureHidden(String id) {
    final idx = _furniture.indexWhere((f) => f.id == id);
    if (idx < 0) return;
    _pushUndoCheckpoint();
    _furniture[idx] = _furniture[idx].copyWith(hidden: !_furniture[idx].hidden);
    _activeRoomLayout = _activeRoomLayout?.withFurniture(_furniture);
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
  }

  void toggleFurnitureLock(String id) {
    final idx = _furniture.indexWhere((f) => f.id == id);
    if (idx < 0) return;
    _pushUndoCheckpoint();
    _furniture[idx] = _furniture[idx].copyWith(locked: !_furniture[idx].locked);
    _activeRoomLayout = _activeRoomLayout?.withFurniture(_furniture);
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
  }

  bool duplicateFurniture(String id) {
    final idx = _furniture.indexWhere((f) => f.id == id);
    if (idx < 0) return false;
    final source = _furniture[idx];
    if (!_invasiveEdit && SurfaceMounts.isStructuralMount(source)) return false;
    final room = currentRoomData;
    final used = _furniture.map((f) => f.id).toSet();
    final cloneId = _uniqueScanId('${source.id}_copy', used);

    final proposedX = (source.gridX + 1).clamp(0.0, (room.gridCols - source.width).toDouble());
    final proposedY = (source.gridY + 1).clamp(0.0, (room.gridRows - source.height).toDouble());
    final draft = source.copyWith(
      id: cloneId,
      name: '${source.name} Copy',
      gridX: proposedX,
      gridY: proposedY,
      locked: false,
      hidden: false,
    );
    final withDraft = [..._furniture, draft];
    final resolved = LayoutCollision.resolveMove(
      id: cloneId,
      proposedX: proposedX,
      proposedY: proposedY,
      furniture: withDraft,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
    );

    _pushUndoCheckpoint();
    _furniture = [
      ..._furniture,
      draft.copyWith(gridX: resolved.gridX, gridY: resolved.gridY),
    ];
    _activeRoomLayout = _activeRoomLayout?.withFurniture(_furniture);
    _selectedItemId = cloneId;
    _selectedIsScanObject = false;
    _airflowMetricsDirty = true;
    _lightingMetricsDirty = true;
    _ergonomicsMetricsDirty = true;
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
    return true;
  }

  String? _pendingPlacementId;
  int? _pendingUpgradeIndex;
  String? get pendingPlacementId => _pendingPlacementId;
  bool get hasPendingPlacement => _pendingPlacementId != null;
  bool isPendingPlacement(String id) => _pendingPlacementId == id;

  /// Places a catalog blueprint. [pending] drops a ghost in the room centre
  /// until [confirmPendingPlacement]; otherwise it occupies the first free cell.
  String? addCatalogFurniture(RigCatalogEntry entry, {bool pending = false}) {
    final room = currentRoomData;
    final id = _uniqueScanId(entry.baseId, _furniture.map((f) => f.id).toSet());
    if (pending) {
      cancelPendingPlacement(notify: false);
      final maxX = (room.gridCols - entry.width).clamp(0.0, room.gridCols.toDouble());
      final maxY = (room.gridRows - entry.height).clamp(0.0, room.gridRows.toDouble());
      final x = LayoutCollision.snap(((room.gridCols - entry.width) / 2).clamp(0.0, maxX));
      final y = LayoutCollision.snap(((room.gridRows - entry.height) / 2).clamp(0.0, maxY));
      _furniture = [
        ..._furniture,
        SurfaceMounts.snapToWall(
          entry.toFurniture(id: id, gridX: x, gridY: y),
          gridCols: room.gridCols,
          gridRows: room.gridRows,
        ),
      ];
      _pendingPlacementId = id;
      _selectedItemId = id;
      _selectedIsScanObject = false;
      notifyListeners();
      return id;
    }

    final spot = LayoutCollision.findEmptyCell(
      furniture: _furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      width: entry.width,
      height: entry.height,
    );
    if (spot == null) return null;

    _pushUndoCheckpoint();
    _furniture = [
      ..._furniture,
      // A window or AC dropped into the first free floor cell would be drawn on
      // a wall it does not actually touch, so seat it before it lands.
      SurfaceMounts.snapToWall(
        entry.toFurniture(id: id, gridX: spot.gridX, gridY: spot.gridY),
        gridCols: room.gridCols,
        gridRows: room.gridRows,
      ),
    ];
    _rememberFurniture();
    _selectedItemId = id;
    _selectedIsScanObject = false;
    _airflowMetricsDirty = true;
    _lightingMetricsDirty = true;
    _ergonomicsMetricsDirty = true;
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
    return id;
  }

  bool confirmPendingPlacement() {
    final id = _pendingPlacementId;
    if (id == null) return true;
    final idx = _furniture.indexWhere((f) => f.id == id);
    if (idx < 0) {
      _pendingPlacementId = null;
      _pendingUpgradeIndex = null;
      return true;
    }
    final hosted = SurfaceMounts.snapOntoHost(_furniture[idx], _furniture);
    _furniture = [
      for (final f in _furniture) if (f.id == id) hosted else f,
    ];
    if (LayoutCollision.itemCollides(hosted, _furniture)) return false;

    final without = _furniture.where((f) => f.id != id).map((f) => f.copyWith()).toList(growable: false);
    _undoStack.add(without);
    if (_undoStack.length > _maxUndo) _undoStack.removeAt(0);
    _redoStack.clear();
    _pendingPlacementId = null;
    _pendingUpgradeIndex = null;
    _rememberFurniture();
    _airflowMetricsDirty = true;
    _lightingMetricsDirty = true;
    _ergonomicsMetricsDirty = true;
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
    return true;
  }

  void cancelPendingPlacement({bool notify = true}) {
    final id = _pendingPlacementId;
    if (id == null) return;
    _furniture = _furniture.where((f) => f.id != id).toList(growable: false);
    final upgradeIdx = _pendingUpgradeIndex;
    if (upgradeIdx != null && upgradeIdx >= 0 && upgradeIdx < upgrades.length) {
      upgrades[upgradeIdx]['added'] = false;
      _recalcUpgrades();
    }
    if (_selectedItemId == id) _selectedItemId = null;
    _pendingPlacementId = null;
    _pendingUpgradeIndex = null;
    if (notify) notifyListeners();
  }

  /// User-defined box: name + footprint in grid cells.
  String? addCustomFurniture({
    required String name,
    required double width,
    required double height,
    bool pending = false,
  }) {
    final w = width.clamp(0.5, 4.0);
    final h = height.clamp(0.5, 4.0);
    final entry = RigCatalogEntry(
      baseId: 'custom',
      name: name.trim().isEmpty ? 'Custom' : name.trim(),
      iconName: 'shelf',
      category: 'neutral',
      width: w,
      height: h,
      cost: 0,
      description: 'Custom object',
    );
    return addCatalogFurniture(entry, pending: pending);
  }

  bool deleteFurniture(String id) {
    final idx = _furniture.indexWhere((f) => f.id == id);
    if (idx < 0) return false;
    final item = _furniture[idx];
    // Keep openings — sims depend on door/window.
    if (item.iconName == 'door' || item.iconName == 'window') return false;
    // Wall ACs / ceiling fixtures also need invasive mode to remove.
    if (!_invasiveEdit && SurfaceMounts.isStructuralMount(item)) return false;

    _pushUndoCheckpoint();
    _furniture = _furniture.where((f) => f.id != id).toList(growable: false);
    _activeRoomLayout = _activeRoomLayout?.withFurniture(_furniture);
    _syncUpgradesFromFurniture();
    if (_selectedItemId == id && !_selectedIsScanObject) {
      _selectedItemId = null;
    }
    _airflowMetricsDirty = true;
    _lightingMetricsDirty = true;
    _ergonomicsMetricsDirty = true;
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
    return true;
  }

  String _uniqueScanId(String base, Set<String> used) {
    if (!used.contains(base)) return base;
    var n = 2;
    while (used.contains('${base}_$n')) {
      n++;
    }
    return '${base}_$n';
  }

  void selectPreset(RoomPreset preset) {
    _stashActiveRoom();
    _loadPreset(preset);
    _scanComplete = false;
    _scanProgress = 0.0;
    _isOptimized = false;
    _airflowMetrics = null;
    _preOptimizeAirflowMetrics = null;
    _lightingMetrics = null;
    _preOptimizeLightingMetrics = null;
    _ergonomicsMetrics = null;
    _preOptimizeErgonomicsMetrics = null;
    _airflowMetricsDirty = true;
    _lightingMetricsDirty = true;
    _ergonomicsMetricsDirty = true;
    _lastOptimizeReasons = const [];
    _selectedItemId = null;
    _selectedIsScanObject = false;
    _pendingPlacementId = null;
    _pendingUpgradeIndex = null;
    clearLayoutHistory();
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
  }

  /// Empty rectangle with a door + window so Bench still has sources.
  void createManualRoom({
    required String name,
    required double lengthMeters,
    required double widthMeters,
    double heightMeters = RoomScale.defaultHeightMeters,
  }) {
    _stashActiveRoom();
    final cols = RoomScale.cellsFromMeters(lengthMeters);
    final rows = RoomScale.cellsFromMeters(widthMeters);
    final height = heightMeters.clamp(2.2, 4.0);
    final label = name.trim().isEmpty ? 'My Room' : name.trim();
    _selectedPreset = RoomPreset.gamingSetup;
    _furniture = [
      FurnitureItem(
        id: 'door',
        name: 'Entry Door',
        iconName: 'door',
        category: 'neutral',
        gridX: 0,
        gridY: (rows - 2).clamp(1, rows - 1).toDouble(),
        height: 1,
        airflowImpact: 0.3,
        ergonomicsImpact: 0.2,
        cost: 180,
        description: 'Primary room entrance; keep approach path clear.',
      ),
      FurnitureItem(
        id: 'window',
        name: 'Window',
        iconName: 'window',
        category: 'lighting',
        gridX: (cols / 2 - 1).clamp(0, cols - 2.0),
        gridY: 0,
        width: 2,
        lightingImpact: 0.85,
        airflowImpact: 0.5,
        cost: 280,
        description: 'Provides natural light and ambient ventilation.',
      ),
    ];
    _furniture = _furniture
        .map(
          (f) => SurfaceMounts.snapToWall(
            f,
            gridCols: cols,
            gridRows: rows,
          ),
        )
        .toList();
    _activeRoomLayout = RoomLayoutModel(
      roomName: label,
      dimensions: RoomDimensions(
        lengthMeters: lengthMeters.clamp(RoomScale.minMeters, RoomScale.maxMeters),
        widthMeters: widthMeters.clamp(RoomScale.minMeters, RoomScale.maxMeters),
        heightMeters: height,
      ),
      coverageGrid: CoverageGrid.empty(cols: cols, rows: rows),
      objects: const [],
      detections: const [],
      updatedAt: DateTime.now().toUtc(),
      scanSource: 'manual',
    ).withFurniture(_furniture);
    _activeRoomId = 'room_${DateTime.now().millisecondsSinceEpoch}';
    _scanComplete = false;
    _scanProgress = 0;
    _isOptimized = false;
    _airflowMetrics = null;
    _preOptimizeAirflowMetrics = null;
    _lightingMetrics = null;
    _preOptimizeLightingMetrics = null;
    _ergonomicsMetrics = null;
    _preOptimizeErgonomicsMetrics = null;
    _airflowMetricsDirty = true;
    _lightingMetricsDirty = true;
    _ergonomicsMetricsDirty = true;
    _lastOptimizeReasons = const [];
    _originalFurniture = null;
    _originalScores = null;
    _selectedItemId = null;
    _selectedIsScanObject = false;
    _pendingPlacementId = null;
    _pendingUpgradeIndex = null;
    _roomShape = 'Rectangular';
    clearLayoutHistory();
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
  }

  void renameActiveRoom(String name) {
    final next = name.trim();
    if (next.isEmpty) return;
    final layout = _activeRoomLayout;
    if (layout == null) return;
    _activeRoomLayout = layout.copyMeta(roomName: next);
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
  }

  void loadSavedRoom(String id) {
    if (id == _activeRoomId) return;
    SavedRoom? found;
    for (final r in _rooms) {
      if (r.id == id) {
        found = r;
        break;
      }
    }
    if (found == null) return;
    _stashActiveRoom();
    _applySavedRoom(found);
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
  }

  bool duplicateActiveRoom() {
    _stashActiveRoom();
    final copyId = 'room_${DateTime.now().millisecondsSinceEpoch}';
    final layout = _activeRoomLayout;
    if (layout == null) return false;
    final copy = SavedRoom(
      id: copyId,
      name: '${currentRoomData.name} Copy',
      presetName: _selectedPreset.name,
      scanComplete: _scanComplete,
      scanProgress: _scanProgress,
      layout: layout.copyMeta(roomName: '${currentRoomData.name} Copy'),
      furniture: _cloneFurniture(_furniture),
      installedUpgrades: upgrades
          .where((u) => u['added'] == true)
          .map((u) => u['furnitureId'])
          .whereType<String>()
          .toList(growable: false),
    );
    _rooms.add(copy);
    _applySavedRoom(copy);
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
    return true;
  }

  bool deleteSavedRoom(String id) {
    if (_rooms.length <= 1 && id == _activeRoomId) return false;
    _stashActiveRoom();
    _rooms.removeWhere((r) => r.id == id);
    if (id == _activeRoomId) {
      if (_rooms.isEmpty) {
        _loadPreset(RoomPreset.gamingSetup);
      } else {
        _applySavedRoom(_rooms.last);
      }
    }
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
    return true;
  }

  void _applySavedRoom(SavedRoom room) {
    _activeRoomId = room.id;
    _furniture = RigCatalog.retainV1(_cloneFurniture(room.furniture));
    _activeRoomLayout = room.layout.withFurniture(_furniture);
    _scanComplete = room.scanComplete;
    _scanProgress = room.scanProgress;
    _originalFurniture = room.originalFurniture == null
        ? null
        : _cloneFurniture(room.originalFurniture!);
    _originalScores = room.originalScores == null
        ? null
        : Map<String, double>.from(room.originalScores!);
    final match = RoomPreset.values.where((p) => p.name == room.presetName);
    if (match.isNotEmpty) _selectedPreset = match.first;
    _selectedItemId = null;
    _selectedIsScanObject = false;
    _isOptimized = _originalFurniture != null;
    _airflowMetricsDirty = true;
    _lightingMetricsDirty = true;
    _ergonomicsMetricsDirty = true;
    _syncUpgradesFromFurniture();
    clearLayoutHistory();
  }

  void _stashActiveRoom() {
    final layout = _activeRoomLayout;
    if (layout == null) return;
    final snap = SavedRoom(
      id: _activeRoomId,
      name: currentRoomData.name,
      presetName: _selectedPreset.name,
      scanComplete: _scanComplete,
      scanProgress: _scanProgress,
      layout: layout.withFurniture(_furniture),
      furniture: _cloneFurniture(_furniture),
      installedUpgrades: upgrades
          .where((u) => u['added'] == true)
          .map((u) => u['furnitureId'])
          .whereType<String>()
          .toList(growable: false),
      originalFurniture: _originalFurniture,
      originalScores: _originalScores,
    );
    final idx = _rooms.indexWhere((r) => r.id == _activeRoomId);
    if (idx >= 0) {
      _rooms[idx] = snap;
    } else {
      _rooms.add(snap);
    }
  }

  void moveFurniture(String id, double newX, double newY, {bool respectCollision = true}) {
    final idx = _furniture.indexWhere((f) => f.id == id);
    if (idx < 0) return;
    if (!canMoveFurniture(_furniture[idx])) return;
    final current = _furniture[idx];
    if (_gestureCheckpointOpen) {
      _dragItemId = id;
      _dragLastValidX ??= current.gridX;
      _dragLastValidY ??= current.gridY;
    }

    final room = currentRoomData;
    final allowOverlap =
        _gestureCheckpointOpen || !respectCollision || id == _pendingPlacementId;
    var resolved = LayoutCollision.resolveMove(
      id: id,
      proposedX: newX,
      proposedY: newY,
      furniture: _furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      allowOverlap: allowOverlap,
    );

    // Windows, doors and wall vents stay flush with a wall, so a drag slides
    // them along it instead of floating them into the middle of the room. The
    // wall they are already on wins ties, so a nudge inward does not fling the
    // fitting onto whichever wall happens to be marginally closer.
    final seated = SurfaceMounts.snapToWall(
      _furniture[idx].copyWith(gridX: resolved.gridX, gridY: resolved.gridY),
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      preferred: SurfaceMounts.nearestWall(
        _furniture[idx],
        gridCols: room.gridCols,
        gridRows: room.gridRows,
      ),
    );
    resolved = LayoutMoveResult(gridX: seated.gridX, gridY: seated.gridY);
    final hosted = SurfaceMounts.snapOntoHost(
      _furniture[idx].copyWith(gridX: resolved.gridX, gridY: resolved.gridY),
      _furniture,
    );
    resolved = LayoutMoveResult(gridX: hosted.gridX, gridY: hosted.gridY);

    if ((current.gridX - resolved.gridX).abs() < 0.001 &&
        (current.gridY - resolved.gridY).abs() < 0.001) {
      if (_gestureCheckpointOpen) {
        _dragPoseBlocked = LayoutCollision.itemCollides(
          current.copyWith(gridX: resolved.gridX, gridY: resolved.gridY),
          _furniture,
        );
      }
      return;
    }

    _furniture[idx] = current.copyWith(gridX: resolved.gridX, gridY: resolved.gridY);
    _airflowMetricsDirty = true;
    _lightingMetricsDirty = true;
    _ergonomicsMetricsDirty = true;

    if (_gestureCheckpointOpen) {
      final posed = _furniture[idx];
      _dragPoseBlocked = LayoutCollision.itemCollides(posed, _furniture);
      if (!_dragPoseBlocked) {
        _dragLastValidX = posed.gridX;
        _dragLastValidY = posed.gridY;
      }
      notifyListeners();
      return;
    }

    _rememberFurniture();
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
  }

  /// Grow/shrink the selected footprint by 0.25 cells. Returns false if blocked.
  bool resizeFurniture(String id, {double dWidth = 0, double dHeight = 0}) {
    final idx = _furniture.indexWhere((f) => f.id == id);
    if (idx < 0) return false;
    final current = _furniture[idx];
    if (!canMoveFurniture(current)) return false;
    if (id != _pendingPlacementId &&
        SurfaceMounts.isStructuralMount(current) &&
        !_invasiveEdit) {
      return false;
    }

    final room = currentRoomData;
    final nextW = (current.width + dWidth).clamp(0.5, room.gridCols.toDouble());
    final nextH = (current.height + dHeight).clamp(0.5, room.gridRows.toDouble());
    final snappedW = LayoutCollision.snap(nextW).clamp(0.5, room.gridCols.toDouble());
    final snappedH = LayoutCollision.snap(nextH).clamp(0.5, room.gridRows.toDouble());
    final maxX = (room.gridCols - snappedW).clamp(0.0, room.gridCols.toDouble());
    final maxY = (room.gridRows - snappedH).clamp(0.0, room.gridRows.toDouble());
    final x = current.gridX.clamp(0.0, maxX);
    final y = current.gridY.clamp(0.0, maxY);
    final candidate = current.copyWith(
      gridX: x,
      gridY: y,
      width: snappedW,
      height: snappedH,
    );
    if (id != _pendingPlacementId && LayoutCollision.itemCollides(candidate, _furniture)) {
      return false;
    }

    if (id != _pendingPlacementId) {
      _pushUndoCheckpoint();
    }
    _furniture[idx] = candidate;
    if (id == _pendingPlacementId) {
      notifyListeners();
      return true;
    }
    _rememberFurniture();
    _airflowMetricsDirty = true;
    _lightingMetricsDirty = true;
    _ergonomicsMetricsDirty = true;
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
    return true;
  }

  /// Snap-rotate selected (or named) furniture by ±90°. Returns false if blocked.
  bool rotateFurniture(String id, {double deltaDegrees = 90}) {
    final idxCheck = _furniture.indexWhere((f) => f.id == id);
    if (idxCheck < 0) return false;
    if (!canMoveFurniture(_furniture[idxCheck])) return false;

    final room = currentRoomData;
    final next = LayoutCollision.rotatedItem(
      id: id,
      deltaDegrees: deltaDegrees,
      furniture: _furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
    );
    if (next == null) return false;

    final idx = _furniture.indexWhere((f) => f.id == id);
    if (idx < 0) return false;

    final current = _furniture[idx];
    if ((current.yawDegrees - next.yawDegrees).abs() < 0.01 &&
        (current.width - next.width).abs() < 0.01 &&
        (current.height - next.height).abs() < 0.01 &&
        (current.gridX - next.gridX).abs() < 0.01 &&
        (current.gridY - next.gridY).abs() < 0.01) {
      return false;
    }

    _pushUndoCheckpoint();
    _furniture[idx] = next;
    _activeRoomLayout = _activeRoomLayout?.withFurniture(_furniture);
    _airflowMetricsDirty = true;
    _lightingMetricsDirty = true;
    _ergonomicsMetricsDirty = true;
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
    return true;
  }

  // --- Undo / redo for furniture layout edits ---
  static const _maxUndo = 40;
  final List<List<FurnitureItem>> _undoStack = [];
  final List<List<FurnitureItem>> _redoStack = [];
  bool _gestureCheckpointOpen = false;
  bool _dragPoseBlocked = false;
  String? _dragItemId;
  double? _dragLastValidX;
  double? _dragLastValidY;

  bool get canUndoLayout => _undoStack.isNotEmpty;
  bool get canRedoLayout => _redoStack.isNotEmpty;
  bool get dragPoseBlocked => _dragPoseBlocked;

  List<LayoutConflict> get layoutConflicts => LayoutCollision.findConflicts(
        furniture: _furniture,
        gridCols: currentRoomData.gridCols,
        gridRows: currentRoomData.gridRows,
      );

  List<FurnitureItem> _cloneFurniture(List<FurnitureItem> source) =>
      source.map((f) => f.copyWith()).toList(growable: false);

  void beginFurnitureGesture() {
    if (_gestureCheckpointOpen) return;
    if (_pendingPlacementId == null || _selectedItemId != _pendingPlacementId) {
      _pushUndoCheckpoint();
    }
    _gestureCheckpointOpen = true;
    _dragPoseBlocked = false;
    _dragItemId = _selectedItemId;
    _dragLastValidX = null;
    _dragLastValidY = null;
  }

  /// Flushes the work [moveFurniture] skipped while the drag was in flight.
  void endFurnitureGesture() {
    if (!_gestureCheckpointOpen) return;
    final keepOverlap = _pendingPlacementId != null && _dragItemId == _pendingPlacementId;
    _gestureCheckpointOpen = false;
    if (!keepOverlap &&
        _dragPoseBlocked &&
        _dragItemId != null &&
        _dragLastValidX != null &&
        _dragLastValidY != null) {
      final idx = _furniture.indexWhere((f) => f.id == _dragItemId);
      if (idx >= 0) {
        _furniture[idx] = _furniture[idx].copyWith(
          gridX: _dragLastValidX,
          gridY: _dragLastValidY,
        );
      }
    }
    _dragPoseBlocked = false;
    _dragItemId = null;
    _dragLastValidX = null;
    _dragLastValidY = null;
    if (keepOverlap) {
      notifyListeners();
      return;
    }
    _rememberFurniture();
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
  }

  void _pushUndoCheckpoint() {
    _undoStack.add(_cloneFurniture(_furniture));
    if (_undoStack.length > _maxUndo) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void undoLayout() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_cloneFurniture(_furniture));
    _furniture = _undoStack.removeLast().map((f) => f.copyWith()).toList();
    _rememberFurniture();
    _syncUpgradesFromFurniture();
    _airflowMetricsDirty = true;
    _lightingMetricsDirty = true;
    _ergonomicsMetricsDirty = true;
    _gestureCheckpointOpen = false;
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
  }

  void redoLayout() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_cloneFurniture(_furniture));
    _furniture = _redoStack.removeLast().map((f) => f.copyWith()).toList();
    _rememberFurniture();
    _syncUpgradesFromFurniture();
    _airflowMetricsDirty = true;
    _lightingMetricsDirty = true;
    _ergonomicsMetricsDirty = true;
    _gestureCheckpointOpen = false;
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
  }

  void clearLayoutHistory() {
    _undoStack.clear();
    _redoStack.clear();
    _gestureCheckpointOpen = false;
  }

  void markCoverageCell(int col, int row, double coverageValue) {
    final current = _activeRoomLayout;
    if (current == null) return;
    final nextCoverage = current.coverageGrid.markCell(col, row, coverageValue);
    _activeRoomLayout = current.withCoverage(nextCoverage);
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
  }

  /// Live scan tick — updates layout only (does not replace editable furniture yet).
  void applyScannedRoomLayout(
    RoomLayoutModel layout, {
    bool persist = true,
    bool notify = true,
  }) {
    _activeRoomLayout = layout;
    if (persist) unawaited(_persistActiveRoomLayout());
    if (notify) notifyListeners();
  }

  ScanConfidenceMetrics? get lastScanConfidence => _activeRoomLayout?.confidence;

  bool get hasSuccessfulScan =>
      _scanComplete &&
      (_activeRoomLayout?.scanSource != null &&
          _activeRoomLayout!.scanSource != 'preset' &&
          _activeRoomLayout!.scanSource != 'scan-seed');

  /// Commit a finished scan into the editable furniture model + persist session.
  void commitScannedRoomLayout(
    RoomLayoutModel layout, {
    String inputProviderId = 'unknown',
    bool usedFallback = false,
    ScanPipelineDiagnostics? diagnostics,
  }) {
    final aligned = RoomScale.alignCoverage(layout);
    final cols = RoomScale.colsFrom(aligned);
    final rows = RoomScale.rowsFrom(aligned);
    final finalized = ScanLayoutConverter.finalizeLayout(
      aligned,
      gridCols: cols,
      gridRows: rows,
      inputProviderId: inputProviderId,
      usedFallback: usedFallback,
      diagnostics: diagnostics,
    );

    _furniture = ScanLayoutConverter.toFurniture(
      finalized,
      gridCols: cols,
      gridRows: rows,
    );
    _furniture = RigCatalog.retainV1(_furniture);
    _activeRoomLayout = finalized.withFurniture(_furniture);
    _scanComplete = true;
    final coverage = finalized.coverageGrid.ratio();
    _scanProgress = max(coverage, 0.92).clamp(0.0, 1.0);
    _selectedItemId = null;
    _selectedIsScanObject = false;
    _isOptimized = false;
    _airflowMetrics = null;
    _preOptimizeAirflowMetrics = null;
    _lightingMetrics = null;
    _preOptimizeLightingMetrics = null;
    _ergonomicsMetrics = null;
    _preOptimizeErgonomicsMetrics = null;
    _airflowMetricsDirty = true;
    _lightingMetricsDirty = true;
    _ergonomicsMetricsDirty = true;
    _lastOptimizeReasons = const [];
    clearLayoutHistory();
    unawaited(_persistActiveRoomLayout());
    unawaited(_persistSuccessfulScanSession());
    notifyListeners();
  }

  String? exportRoomLayoutJson() {
    final layout = _activeRoomLayout;
    if (layout == null) return null;
    return const JsonEncoder.withIndent('  ').convert(layout.toJson());
  }

  bool tryImportRoomLayoutJson(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
      final layout = RoomLayoutModel.fromJson(decoded);
      final looksLikeScan = layout.scanSource != null &&
          layout.scanSource != 'preset' &&
          layout.objects.any((o) => o.source.contains('scan'));
      if (looksLikeScan || layout.confidence != null) {
        commitScannedRoomLayout(
          layout,
          inputProviderId: layout.scanSource ?? 'import',
          usedFallback: layout.confidence?.usedFallback ?? false,
        );
      } else {
        _activeRoomLayout = layout;
        _furniture = RigCatalog.retainV1(
          ScanLayoutConverter.toFurniture(
            layout,
            gridCols: RoomScale.colsFrom(layout),
            gridRows: RoomScale.rowsFrom(layout),
          ),
        );
        _rememberFurniture();
        unawaited(_persistActiveRoomLayout());
        notifyListeners();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _persistActiveRoomLayout() async {
    final layout = _activeRoomLayout;
    if (layout == null) return;
    try {
      _stashActiveRoom();
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode({
        'version': 4,
        'activeRoomId': _activeRoomId,
        'rooms': _rooms.map((r) => r.toJson()).toList(growable: false),
        'scanComplete': _scanComplete,
        'scanProgress': _scanProgress,
        'preset': _selectedPreset.name,
        'layout': layout.toJson(),
        'furniture': _furniture.map((f) => f.toJson()).toList(growable: false),
        'installedUpgrades': upgrades
            .where((u) => u['added'] == true)
            .map((u) => u['furnitureId'])
            .whereType<String>()
            .toList(growable: false),
      });
      await prefs.setString(_persistedLayoutKey, raw);
    } catch (_) {
      // Prefs unavailable in some test/runtime contexts.
    }
  }

  Future<void> _persistSuccessfulScanSession() async {
    final layout = _activeRoomLayout;
    if (layout == null || !_scanComplete) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _persistedScanSessionKey,
        jsonEncode({
          'savedAt': DateTime.now().toUtc().toIso8601String(),
          'scanComplete': true,
          'scanProgress': _scanProgress,
          'preset': _selectedPreset.name,
          'layout': layout.toJson(),
          'furniture': _furniture.map((f) => f.toJson()).toList(growable: false),
          'confidence': layout.confidence?.toJson(),
        }),
      );
    } catch (_) {
      // Prefs unavailable in some test/runtime contexts.
    }
  }

  Future<void> _restorePersistedLayout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionRaw = prefs.getString(_persistedScanSessionKey);
      if (sessionRaw != null && sessionRaw.isNotEmpty) {
        if (_tryRestoreSessionJson(sessionRaw)) return;
      }

      final raw = prefs.getString(_persistedLayoutKey);
      if (raw == null || raw.isEmpty) return;
      _tryRestoreSessionJson(raw);
    } catch (_) {
      // Ignore invalid cached layouts and continue with preset state.
    }
  }

  bool _tryRestoreSessionJson(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final version = (decoded['version'] as num?)?.toInt() ?? 0;
    if (version >= 4 && decoded['rooms'] is List) {
      return _tryRestoreRoomsBlob(decoded);
    }

    final layoutRaw = decoded['layout'];
    final RoomLayoutModel restored;
    if (layoutRaw is Map) {
      restored = RoomLayoutModel.fromJson(layoutRaw.cast<String, dynamic>());
    } else {
      restored = RoomLayoutModel.fromJson(decoded);
    }

    final presetName = decoded['preset'] as String?;
    if (presetName != null) {
      final match = RoomPreset.values.where((p) => p.name == presetName);
      if (match.isNotEmpty) {
        _selectedPreset = match.first;
      }
    }

    _activeRoomLayout = restored;
    final complete = (decoded['scanComplete'] as bool?) ??
        (restored.scanSource != null &&
            restored.scanSource != 'preset' &&
            restored.scanSource != 'scan-seed');
    _scanComplete = complete;
    _scanProgress = (decoded['scanProgress'] as num?)?.toDouble() ??
        (complete ? 1.0 : restored.coverageGrid.ratio());

    final furnitureRaw = decoded['furniture'];
    if (furnitureRaw is List && furnitureRaw.isNotEmpty) {
      _furniture = RigCatalog.retainV1(
        furnitureRaw
            .whereType<Map>()
            .map((e) => FurnitureItem.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
      _activeRoomLayout = restored.withFurniture(_furniture);
    } else if (restored.objects.isNotEmpty) {
      _furniture = RigCatalog.retainV1(
        ScanLayoutConverter.toFurniture(
          restored,
          gridCols: RoomScale.colsFrom(restored),
          gridRows: RoomScale.rowsFrom(restored),
        ),
      );
      _activeRoomLayout = restored.withFurniture(_furniture);
    }

    _activeRoomId = 'room_restored';
    _rooms
      ..clear()
      ..add(
        SavedRoom(
          id: _activeRoomId,
          name: restored.roomName,
          presetName: _selectedPreset.name,
          scanComplete: _scanComplete,
          scanProgress: _scanProgress,
          layout: _activeRoomLayout!,
          furniture: _cloneFurniture(_furniture),
        ),
      );
    _syncUpgradesFromFurniture();
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
    return true;
  }

  bool _tryRestoreRoomsBlob(Map<String, dynamic> decoded) {
    final roomsRaw = decoded['rooms'] as List;
    _rooms
      ..clear()
      ..addAll(
        roomsRaw.whereType<Map>().map(
              (e) => SavedRoom.fromJson(e.cast<String, dynamic>()),
            ),
      );
    if (_rooms.isEmpty) return false;
    final activeId = decoded['activeRoomId'] as String?;
    SavedRoom pick = _rooms.last;
    if (activeId != null) {
      for (final r in _rooms) {
        if (r.id == activeId) {
          pick = r;
          break;
        }
      }
    }
    _applySavedRoom(pick);
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
    return true;
  }

  // Optimization sliders
  double _airflowSlider = 0.7;
  double _lightingSlider = 0.5;
  double _ergonomicsSlider = 0.6;
  double _spatialSlider = 0.55;

  double get airflowSlider => _airflowSlider;
  double get lightingSlider => _lightingSlider;
  double get ergonomicsSlider => _ergonomicsSlider;
  double get spatialSlider => _spatialSlider;

  MultiObjectiveWeights get optimizeWeights => MultiObjectiveWeights(
        airflow: _airflowSlider,
        lighting: _lightingSlider,
        ergonomics: _ergonomicsSlider,
        spatial: _spatialSlider,
      );

  void setAirflowSlider(double v) {
    _airflowSlider = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  void setLightingSlider(double v) {
    _lightingSlider = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  void setErgonomicsSlider(double v) {
    _ergonomicsSlider = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  void setSpatialSlider(double v) {
    _spatialSlider = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  void setOptimizeWeights({
    required double airflow,
    required double lighting,
    required double ergonomics,
    double? spatial,
  }) {
    _airflowSlider = airflow.clamp(0.0, 1.0);
    _lightingSlider = lighting.clamp(0.0, 1.0);
    _ergonomicsSlider = ergonomics.clamp(0.0, 1.0);
    if (spatial != null) _spatialSlider = spatial.clamp(0.0, 1.0);
    notifyListeners();
  }

  void applyOptimizeGoalPreset(String goal) {
    switch (goal) {
      case 'airflow':
        setOptimizeWeights(airflow: 0.95, lighting: 0.35, ergonomics: 0.35, spatial: 0.4);
        _benchmarkMode = 'airflow';
        break;
      case 'lighting':
        setOptimizeWeights(airflow: 0.35, lighting: 0.95, ergonomics: 0.35, spatial: 0.4);
        _benchmarkMode = 'lighting';
        break;
      case 'ergonomics':
        setOptimizeWeights(airflow: 0.35, lighting: 0.35, ergonomics: 0.95, spatial: 0.4);
        _benchmarkMode = 'ergonomics';
        break;
      case 'spatial':
        setOptimizeWeights(airflow: 0.35, lighting: 0.35, ergonomics: 0.45, spatial: 0.95);
        _benchmarkMode = 'spatial';
        break;
      default:
        setOptimizeWeights(airflow: 0.75, lighting: 0.75, ergonomics: 0.75, spatial: 0.7);
        _benchmarkMode = 'airflow';
    }
  }

  // Scores
  bool _isOptimized = false;
  bool get isOptimized => _isOptimized;

  AirflowMetrics? _airflowMetrics;
  AirflowMetrics? _preOptimizeAirflowMetrics;
  LightingMetrics? _lightingMetrics;
  LightingMetrics? _preOptimizeLightingMetrics;
  ErgonomicsMetrics? _ergonomicsMetrics;
  ErgonomicsMetrics? _preOptimizeErgonomicsMetrics;
  List<String> _lastOptimizeReasons = const [];
  bool _airflowMetricsDirty = true;
  bool _lightingMetricsDirty = true;
  bool _ergonomicsMetricsDirty = true;
  List<FurnitureItem>? _originalFurniture;
  Map<String, double>? _originalScores;

  AirflowMetrics? get airflowMetrics => _airflowMetrics;
  LightingMetrics? get lightingMetrics => _lightingMetrics;
  ErgonomicsMetrics? get ergonomicsMetrics => _ergonomicsMetrics;
  SpatialMetrics get spatialMetrics => SpatialAnalyzer.evaluate(
        furniture: _furniture,
        gridCols: currentRoomData.gridCols,
        gridRows: currentRoomData.gridRows,
      );

  List<String> get lastOptimizeReasons => _lastOptimizeReasons;
  List<FurnitureItem>? get originalFurniture => _originalFurniture;
  Map<String, double>? get originalScores => _originalScores;
  bool get hasCompareSnapshot => _originalFurniture != null;

  double get _baseAirflowScore {
    double score = 50;
    for (final f in _furniture) { score += f.airflowImpact * 15; }
    return score.clamp(0, 100);
  }

  double get _baseLightingScore {
    double score = 40;
    for (final f in _furniture) { score += f.lightingImpact * 12; }
    return score.clamp(0, 100);
  }

  double get _baseErgonomicsScore {
    double score = 45;
    for (final f in _furniture) { score += f.ergonomicsImpact * 13; }
    return score.clamp(0, 100);
  }

  /// Sim circulation score when fresh; otherwise furniture-impact estimate.
  double get airflowScore {
    final sim = _airflowMetrics;
    if (sim != null && !_airflowMetricsDirty) {
      return sim.circulationScore.clamp(0, 100);
    }
    return _baseAirflowScore;
  }

  double get baselineAirflowScore {
    final pre = _preOptimizeAirflowMetrics;
    if (pre != null) return pre.circulationScore.clamp(0, 100);
    return _baseAirflowScore;
  }

  double get lightingScore {
    final sim = _lightingMetrics;
    if (sim != null && !_lightingMetricsDirty) {
      return sim.exposureScore.clamp(0, 100);
    }
    return _baseLightingScore;
  }

  double get baselineLightingScore {
    final pre = _preOptimizeLightingMetrics;
    if (pre != null) return pre.exposureScore.clamp(0, 100);
    return _baseLightingScore;
  }

  double get baselineErgonomicsScore {
    final pre = _preOptimizeErgonomicsMetrics;
    if (pre != null) return pre.comfortScore.clamp(0, 100);
    return _baseErgonomicsScore;
  }

  double get ergonomicsScore {
    final sim = _ergonomicsMetrics;
    if (sim != null && !_ergonomicsMetricsDirty) {
      return sim.comfortScore.clamp(0, 100);
    }
    return _baseErgonomicsScore;
  }

  double get spatialScore => spatialMetrics.overallScore;

  double get overallScore {
    final total = _airflowSlider + _lightingSlider + _ergonomicsSlider + _spatialSlider;
    if (total == 0) {
      return (airflowScore + lightingScore + ergonomicsScore + spatialScore) / 4;
    }
    return (airflowScore * _airflowSlider +
            lightingScore * _lightingSlider +
            ergonomicsScore * _ergonomicsSlider +
            spatialScore * _spatialSlider) /
        total;
  }

  double get previousOverallScore {
    final original = _originalScores;
    if (original != null && original['overall'] != null) {
      return original['overall']!;
    }
    return (baselineAirflowScore + baselineLightingScore + baselineErgonomicsScore) / 3;
  }

  String get scoreGrade {
    final s = overallScore;
    if (s >= 90) return 'S';
    if (s >= 80) return 'A';
    if (s >= 70) return 'B';
    if (s >= 55) return 'C';
    return 'D';
  }

  void _captureAirflowBaselineIfNeeded() {
    _preOptimizeAirflowMetrics ??= AirflowOptimizer.evaluate(_furniture);
  }

  void _captureLightingBaselineIfNeeded() {
    _preOptimizeLightingMetrics ??= LightingOptimizer.evaluate(_furniture);
  }

  void _captureErgonomicsBaselineIfNeeded() {
    _preOptimizeErgonomicsMetrics ??= ErgonomicsOptimizer.evaluate(_furniture);
  }

  void _setAirflowMetrics(AirflowMetrics metrics, {bool markClean = true}) {
    _airflowMetrics = metrics;
    if (markClean) _airflowMetricsDirty = false;
  }

  void _setLightingMetrics(LightingMetrics metrics, {bool markClean = true}) {
    _lightingMetrics = metrics;
    if (markClean) _lightingMetricsDirty = false;
  }

  void _setErgonomicsMetrics(ErgonomicsMetrics metrics, {bool markClean = true}) {
    _ergonomicsMetrics = metrics;
    if (markClean) _ergonomicsMetricsDirty = false;
  }

  void _captureOriginalIfNeeded() {
    if (_originalFurniture != null) return;
    _originalFurniture = _cloneFurniture(_furniture);
    _originalScores = {
      'airflow': airflowScore,
      'lighting': lightingScore,
      'ergonomics': ergonomicsScore,
      'spatial': spatialScore,
      'overall': overallScore,
    };
  }

  void restoreOriginalLayout() {
    final original = _originalFurniture;
    if (original == null) return;
    _pushUndoCheckpoint();
    _furniture = _cloneFurniture(original);
    _rememberFurniture();
    _isOptimized = false;
    _airflowMetricsDirty = true;
    _lightingMetricsDirty = true;
    _ergonomicsMetricsDirty = true;
    _syncUpgradesFromFurniture();
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
  }

  /// Auto-Rig: rearranges furniture using weighted multi-objective blending.
  /// [goal] optionally applies a weight preset before solving.
  void runOptimization({String? goal}) {
    if (goal != null) {
      applyOptimizeGoalPreset(goal);
    }

    _pushUndoCheckpoint();
    _captureOriginalIfNeeded();
    _captureAirflowBaselineIfNeeded();
    _captureLightingBaselineIfNeeded();
    _captureErgonomicsBaselineIfNeeded();

    final result = MultiObjectiveOptimizer.optimize(
      furniture: _furniture,
      gridCols: currentRoomData.gridCols,
      gridRows: currentRoomData.gridRows,
      weights: optimizeWeights,
    );

    _furniture = result.furniture;
    _setAirflowMetrics(result.airflowMetrics);
    _setLightingMetrics(result.lightingMetrics);
    _setErgonomicsMetrics(result.ergonomicsMetrics);
    _lastOptimizeReasons = result.reasons;
    _rememberFurniture();
    unawaited(_persistActiveRoomLayout());

    _isOptimized = true;
    notifyListeners();
  }

  void applyAirflowOptimizedLayout() {
    runOptimization(goal: 'airflow');
  }

  void applyLightingOptimizedLayout() {
    runOptimization(goal: 'lighting');
  }

  void applyErgonomicsOptimizedLayout() {
    runOptimization(goal: 'ergonomics');
  }

  /// Bench → Rig: copy a benchmark furniture list into the Rig editor.
  /// Replaces the layout with [items], keeping the room the user is actually
  /// in. The Bench now derives its layouts from this furniture, so applying one
  /// is a rearrange of their own room — it must not swap their preset back to
  /// the gaming setup or throw away a completed scan.
  void applyFurnitureLayout(List<FurnitureItem> items, {bool markOptimized = false}) {
    _pushUndoCheckpoint();
    if (markOptimized) _captureOriginalIfNeeded();
    final room = currentRoomData;
    _furniture = RigCatalog.retainV1(
      items
          .map(
            (f) => SurfaceMounts.snapToWall(
              f.copyWith(),
              gridCols: room.gridCols,
              gridRows: room.gridRows,
            ),
          )
          .toList(growable: false),
    );
    _rememberFurniture();
    _isOptimized = markOptimized;
    final air = AirflowOptimizer.evaluate(_furniture);
    final light = LightingOptimizer.evaluate(_furniture);
    final ergo = ErgonomicsOptimizer.evaluate(_furniture);
    if (markOptimized) {
      _preOptimizeAirflowMetrics ??= air;
      _preOptimizeLightingMetrics ??= light;
      _preOptimizeErgonomicsMetrics ??= ergo;
    }
    _setAirflowMetrics(air);
    _setLightingMetrics(light);
    _setErgonomicsMetrics(ergo);
    _lastOptimizeReasons = const [];
    _syncUpgradesFromFurniture();
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
  }

  // Room Shape Layout support
  String _roomShape = 'Rectangular';
  String get roomShape => _roomShape;
  
  void setRoomShape(String shape) {
    _roomShape = shape;
    notifyListeners();
  }

  // Budget tracking properties
  double get totalBudget => 4000.0;
  
  double get baseRoomCost {
    double total = 0;
    for (final f in _furniture) {
      total += f.cost;
    }
    return total;
  }

  double get upgradesCost {
    double total = 0;
    for (final u in upgrades) {
      if (u['added'] as bool) {
        total += u['price'] as double;
      }
    }
    return total;
  }

  double get totalSpent => baseRoomCost + upgradesCost;
  double get budgetRemaining => totalBudget - totalSpent;

  // Benchmark simulation mode
  String _benchmarkMode = 'airflow';
  String get benchmarkMode => _benchmarkMode;

  void setBenchmarkMode(String mode) {
    _benchmarkMode = mode;
    notifyListeners();
  }

  /// Which layout the Bench should switch to next time it builds. The Rig's
  /// "Sim Prototype" button uses this to show the reference room instead of
  /// overwriting the user's furniture with it. The token makes it a one-shot
  /// request, so the panels can honour it once and then let the user pick
  /// freely again.
  BenchLayoutKind _benchLayoutFocus = BenchLayoutKind.myRoom;
  int _benchLayoutFocusToken = 0;

  BenchLayoutKind get benchLayoutFocus => _benchLayoutFocus;
  int get benchLayoutFocusToken => _benchLayoutFocusToken;

  void focusBenchLayout(BenchLayoutKind kind) {
    _benchLayoutFocus = kind;
    _benchLayoutFocusToken++;
    notifyListeners();
  }

  // Onboarding
  bool _onboardingReady = false;
  bool _hasSeenOnboarding = true; // default true until prefs load to avoid flash
  bool get onboardingReady => _onboardingReady;
  bool get hasSeenOnboarding => _hasSeenOnboarding;
  bool get shouldShowOnboarding => _onboardingReady && !_hasSeenOnboarding;

  Future<void> _restoreOnboardingFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _hasSeenOnboarding = prefs.getBool(_onboardingSeenKey) ?? false;
    } catch (_) {
      _hasSeenOnboarding = false;
    }
    _onboardingReady = true;
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    _hasSeenOnboarding = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_onboardingSeenKey, true);
    } catch (_) {}
  }

  BenchmarkValidation validateActiveLayout({String? mode}) {
    return BenchmarkValidator.validateLayout(
      furniture: _furniture,
      gridCols: currentRoomData.gridCols,
      gridRows: currentRoomData.gridRows,
      mode: mode ?? _benchmarkMode,
    );
  }

  // Upgrade catalog — installing places a real item on the Rig layout.
  final List<Map<String, dynamic>> upgrades = [
    {'name': 'Air Circulator Fan', 'iconName': 'fan', 'furnitureId': 'upg_fan', 'type': 'airflow', 'desc': 'Places a stand fan on your Rig — oscilates into open floor', 'airflowBoost': 15.0, 'lightingBoost': 0.0, 'ergonomicsBoost': 0.0, 'price': 89.0, 'added': false},
    {'name': 'Smart Air Purifier', 'iconName': 'purifier', 'furnitureId': 'upg_purifier', 'type': 'airflow', 'desc': 'Adds a floor purifier that also stirs room air', 'airflowBoost': 10.0, 'lightingBoost': 0.0, 'ergonomicsBoost': 5.0, 'price': 189.0, 'added': false},
    {'name': 'Smart Light Bar', 'iconName': 'lightBar', 'furnitureId': 'upg_light_bar', 'type': 'lighting', 'desc': 'Bias light near the desk for task illumination', 'airflowBoost': 0.0, 'lightingBoost': 18.0, 'ergonomicsBoost': 5.0, 'price': 99.0, 'added': false},
    {'name': 'Diffused Floor Lamp', 'iconName': 'floorLamp', 'furnitureId': 'upg_floor_lamp', 'type': 'lighting', 'desc': 'Soft ambient lamp on the Rig floor plan', 'airflowBoost': 0.0, 'lightingBoost': 12.0, 'ergonomicsBoost': 2.0, 'price': 79.0, 'added': false},
    {'name': 'Monitor Arm', 'iconName': 'monitorArm', 'furnitureId': 'upg_monitor_arm', 'type': 'ergonomics', 'desc': 'Monitor arm at the desk — frees surface, better eye line', 'airflowBoost': 5.0, 'lightingBoost': 0.0, 'ergonomicsBoost': 20.0, 'price': 129.0, 'added': false},
    {'name': 'Cable Tray', 'iconName': 'cableTray', 'furnitureId': 'upg_cable_tray', 'type': 'ergonomics', 'desc': 'Under-desk tray that clears walk/air paths', 'airflowBoost': 8.0, 'lightingBoost': 0.0, 'ergonomicsBoost': 10.0, 'price': 39.0, 'added': false},
    {'name': 'Anti-Fatigue Mat', 'iconName': 'mat', 'furnitureId': 'upg_mat', 'type': 'ergonomics', 'desc': 'Standing mat at the work zone', 'airflowBoost': 0.0, 'lightingBoost': 0.0, 'ergonomicsBoost': 15.0, 'price': 49.0, 'added': false},
    {'name': 'Smart Blinds', 'iconName': 'smartBlinds', 'furnitureId': 'upg_blinds', 'type': 'lighting', 'desc': 'Blinds on the window wall to cut glare', 'airflowBoost': 2.0, 'lightingBoost': 14.0, 'ergonomicsBoost': 0.0, 'price': 249.0, 'added': false},
  ];

  double _upgradeAirflowBonus = 0;
  double _upgradeLightingBonus = 0;
  double _upgradeErgonomicsBonus = 0;

  double get upgradeAirflowBonus => _upgradeAirflowBonus;
  double get upgradeLightingBonus => _upgradeLightingBonus;
  double get upgradeErgonomicsBonus => _upgradeErgonomicsBonus;

  /// Installs or removes the upgrade as a real Rig furniture item.
  /// Returns false if there is no free cell to place it.
  bool toggleUpgrade(int index, {bool pending = false}) {
    if (index < 0 || index >= upgrades.length) return false;
    final u = upgrades[index];
    final furnitureId = (u['furnitureId'] as String?) ?? 'upg_$index';
    final adding = !(u['added'] as bool);

    if (adding) {
      if (_furniture.any((f) => f.id == furnitureId)) {
        u['added'] = true;
        _recalcUpgrades();
        notifyListeners();
        return true;
      }
      final room = currentRoomData;
      if (pending) {
        cancelPendingPlacement(notify: false);
        final x = LayoutCollision.snap(((room.gridCols - 1) / 2).clamp(0.0, room.gridCols - 1.0));
        final y = LayoutCollision.snap(((room.gridRows - 1) / 2).clamp(0.0, room.gridRows - 1.0));
        _furniture = [..._furniture, _furnitureForUpgrade(u, furnitureId, x, y)];
        u['added'] = true;
        _pendingPlacementId = furnitureId;
        _pendingUpgradeIndex = index;
        _selectedItemId = furnitureId;
        _selectedIsScanObject = false;
        _recalcUpgrades();
        notifyListeners();
        return true;
      }
      final spot = LayoutCollision.findEmptyCell(
        furniture: _furniture,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
      );
      if (spot == null) return false;
      _pushUndoCheckpoint();
      _furniture = [..._furniture, _furnitureForUpgrade(u, furnitureId, spot.gridX, spot.gridY)];
      u['added'] = true;
      _selectedItemId = furnitureId;
      _selectedIsScanObject = false;
    } else {
      _pushUndoCheckpoint();
      _furniture = _furniture.where((f) => f.id != furnitureId).toList(growable: false);
      u['added'] = false;
      if (_selectedItemId == furnitureId) _selectedItemId = null;
      if (_pendingPlacementId == furnitureId) {
        _pendingPlacementId = null;
        _pendingUpgradeIndex = null;
      }
    }

    _rememberFurniture();
    _recalcUpgrades();
    _refreshLayoutScores();
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
    return true;
  }

  FurnitureItem _furnitureForUpgrade(
    Map<String, dynamic> u,
    String id,
    double gridX,
    double gridY,
  ) {
    final type = (u['type'] as String?) ?? 'neutral';
    return FurnitureItem(
      id: id,
      name: (u['name'] as String?) ?? 'Upgrade',
      iconName: (u['iconName'] as String?) ?? 'fan',
      category: type,
      gridX: gridX,
      gridY: gridY,
      width: 1,
      height: 1,
      airflowImpact: ((u['airflowBoost'] as num?)?.toDouble() ?? 0) / 20,
      lightingImpact: ((u['lightingBoost'] as num?)?.toDouble() ?? 0) / 20,
      ergonomicsImpact: ((u['ergonomicsBoost'] as num?)?.toDouble() ?? 0) / 20,
      cost: (u['price'] as num?)?.toDouble() ?? 0,
      description: (u['desc'] as String?) ?? 'Installed upgrade',
    );
  }

  void _syncUpgradesFromFurniture() {
    final ids = _furniture.map((f) => f.id).toSet();
    for (final u in upgrades) {
      final id = u['furnitureId'];
      if (id is String) {
        u['added'] = ids.contains(id);
      }
    }
    _recalcUpgrades();
  }

  void _refreshLayoutScores() {
    _setAirflowMetrics(AirflowOptimizer.evaluate(_furniture));
    _setLightingMetrics(LightingOptimizer.evaluate(_furniture));
    _setErgonomicsMetrics(ErgonomicsOptimizer.evaluate(_furniture));
  }

  void _recalcUpgrades() {
    _upgradeAirflowBonus = 0;
    _upgradeLightingBonus = 0;
    _upgradeErgonomicsBonus = 0;
    for (final u in upgrades) {
      if (u['added'] as bool) {
        _upgradeAirflowBonus += u['airflowBoost'] as double;
        _upgradeLightingBonus += u['lightingBoost'] as double;
        _upgradeErgonomicsBonus += u['ergonomicsBoost'] as double;
      }
    }
  }

  String buildShareReport() {
    final room = currentRoomData;
    final dims = _activeRoomLayout?.dimensions;
    final length = dims?.lengthMeters ?? RoomScale.metersFromCells(room.gridCols);
    final width = dims?.widthMeters ?? RoomScale.metersFromCells(room.gridRows);
    final height = dims?.heightMeters ?? room.heightMeters;
    final buf = StringBuffer()
      ..writeln('Room Rig report')
      ..writeln('Room: ${room.name}')
      ..writeln(
        'Size: ${RoomScale.formatMeters(length)} × ${RoomScale.formatMeters(width)} × ${RoomScale.formatMeters(height)}',
      )
      ..writeln('Grid: ${room.gridCols} × ${room.gridRows} cells')
      ..writeln('')
      ..writeln('Scores')
      ..writeln('  Overall: ${overallScore.toStringAsFixed(0)}  (grade $scoreGrade)')
      ..writeln('  Airflow: ${airflowScore.toStringAsFixed(0)}')
      ..writeln('  Lighting: ${lightingScore.toStringAsFixed(0)}')
      ..writeln('  Ergonomics: ${ergonomicsScore.toStringAsFixed(0)}')
      ..writeln('  Space: ${spatialScore.toStringAsFixed(0)}');
    final original = _originalScores;
    if (original != null) {
      buf
        ..writeln('')
        ..writeln('Before Auto-Rig')
        ..writeln('  Overall: ${original['overall']?.toStringAsFixed(0) ?? '—'}')
        ..writeln('  Airflow: ${original['airflow']?.toStringAsFixed(0) ?? '—'}')
        ..writeln('  Lighting: ${original['lighting']?.toStringAsFixed(0) ?? '—'}')
        ..writeln('  Ergonomics: ${original['ergonomics']?.toStringAsFixed(0) ?? '—'}')
        ..writeln('  Space: ${original['spatial']?.toStringAsFixed(0) ?? '—'}');
    }
    buf
      ..writeln('')
      ..writeln('Furniture');
    for (final f in _furniture) {
      buf.writeln(
        '  - ${f.name}  ${RoomScale.formatCellsAsMeters(f.width)} × ${RoomScale.formatCellsAsMeters(f.height)}  @ (${f.gridX.toStringAsFixed(1)}, ${f.gridY.toStringAsFixed(1)})',
      );
    }
    if (_lastOptimizeReasons.isNotEmpty) {
      buf
        ..writeln('')
        ..writeln('Auto-Rig notes');
      for (final r in _lastOptimizeReasons) {
        buf.writeln('  - $r');
      }
    }
    for (final n in spatialMetrics.notes) {
      buf.writeln('  - $n');
    }
    return buf.toString();
  }
}
