// lib/models/app_state.dart
import 'dart:convert';
import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'airflow_prototype.dart';
import 'ergonomics_prototype.dart';
import 'item_detection.dart';
import 'lighting_prototype.dart';
import 'room_model.dart';
import 'scan_layout_model.dart';
import '../services/airflow_optimizer.dart';
import '../services/airflow_simulator.dart';
import '../services/benchmark_validator.dart';
import '../services/ergonomics_optimizer.dart';
import '../services/ergonomics_simulator.dart';
import '../services/layout_collision.dart';
import '../services/lighting_optimizer.dart';
import '../services/lighting_simulator.dart';
import '../services/multi_objective_optimizer.dart';
import '../services/scan_layout_converter.dart';
import '../services/scan_pipeline.dart';

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

  void setScanProgress(double p) {
    _scanProgress = p;
    if (p >= 1.0) _scanComplete = true;
    notifyListeners();
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

  AppState() {
    _loadPreset(RoomPreset.gamingSetup);
    unawaited(_restorePersistedLayout());
    unawaited(_restoreOnboardingFlag());
  }

  void _loadPreset(RoomPreset preset) {
    final data = RoomPresets.getPreset(preset);
    _furniture = List.from(data.furniture.map((f) => f.copyWith()));
    _selectedPreset = preset;
    _activeRoomLayout = RoomLayoutModel.fromPreset(data, _furniture);
  }

  List<FurnitureItem> get furniture => _furniture;
  RoomData get currentRoomData => RoomPresets.getPreset(_selectedPreset);
  RoomLayoutModel? get activeRoomLayout => _activeRoomLayout;

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

  bool deleteFurniture(String id) {
    final idx = _furniture.indexWhere((f) => f.id == id);
    if (idx < 0) return false;
    final item = _furniture[idx];
    // Keep openings — sims depend on door/window.
    if (item.iconName == 'door' || item.iconName == 'window') return false;

    _pushUndoCheckpoint();
    _furniture = _furniture.where((f) => f.id != id).toList(growable: false);
    _activeRoomLayout = _activeRoomLayout?.withFurniture(_furniture);
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
    clearLayoutHistory();
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
  }

  void moveFurniture(String id, double newX, double newY, {bool respectCollision = true}) {
    final idx = _furniture.indexWhere((f) => f.id == id);
    if (idx < 0) return;
    if (_furniture[idx].locked) return;

    final room = currentRoomData;
    final resolved = respectCollision
        ? LayoutCollision.resolveMove(
            id: id,
            proposedX: newX,
            proposedY: newY,
            furniture: _furniture,
            gridCols: room.gridCols,
            gridRows: room.gridRows,
          )
        : LayoutMoveResult(
            gridX: newX.clamp(0.0, (room.gridCols - _furniture[idx].width).toDouble()),
            gridY: newY.clamp(0.0, (room.gridRows - _furniture[idx].height).toDouble()),
          );

    final current = _furniture[idx];
    if ((current.gridX - resolved.gridX).abs() < 0.001 &&
        (current.gridY - resolved.gridY).abs() < 0.001) {
      return;
    }

    _furniture[idx] = current.copyWith(gridX: resolved.gridX, gridY: resolved.gridY);
    _activeRoomLayout = _activeRoomLayout?.withFurniture(_furniture);
    _airflowMetricsDirty = true;
    _lightingMetricsDirty = true;
    _ergonomicsMetricsDirty = true;
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
  }

  /// Snap-rotate selected (or named) furniture by ±90°. Returns false if blocked.
  bool rotateFurniture(String id, {double deltaDegrees = 90}) {
    final idxCheck = _furniture.indexWhere((f) => f.id == id);
    if (idxCheck < 0) return false;
    if (_furniture[idxCheck].locked) return false;

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

  bool get canUndoLayout => _undoStack.isNotEmpty;
  bool get canRedoLayout => _redoStack.isNotEmpty;

  List<LayoutConflict> get layoutConflicts => LayoutCollision.findConflicts(
        furniture: _furniture,
        gridCols: currentRoomData.gridCols,
        gridRows: currentRoomData.gridRows,
      );

  List<FurnitureItem> _cloneFurniture(List<FurnitureItem> source) =>
      source.map((f) => f.copyWith()).toList(growable: false);

  void beginFurnitureGesture() {
    if (_gestureCheckpointOpen) return;
    _pushUndoCheckpoint();
    _gestureCheckpointOpen = true;
  }

  void endFurnitureGesture() {
    _gestureCheckpointOpen = false;
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
    _activeRoomLayout = RoomLayoutModel.fromPreset(currentRoomData, _furniture);
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
    _activeRoomLayout = RoomLayoutModel.fromPreset(currentRoomData, _furniture);
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
  void applyScannedRoomLayout(RoomLayoutModel layout) {
    _activeRoomLayout = layout;
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
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
    final room = currentRoomData;
    final finalized = ScanLayoutConverter.finalizeLayout(
      layout,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
      inputProviderId: inputProviderId,
      usedFallback: usedFallback,
      diagnostics: diagnostics,
    );

    _furniture = ScanLayoutConverter.toFurniture(
      finalized,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
    );
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
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode({
        'version': 2,
        'scanComplete': _scanComplete,
        'scanProgress': _scanProgress,
        'preset': _selectedPreset.name,
        'layout': layout.toJson(),
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
    final layoutRaw = decoded['layout'];
    final RoomLayoutModel restored;
    if (layoutRaw is Map) {
      restored = RoomLayoutModel.fromJson(layoutRaw.cast<String, dynamic>());
    } else {
      // Legacy: entire blob was the layout itself.
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

    if (complete && restored.objects.isNotEmpty) {
      final room = RoomPresets.getPreset(_selectedPreset);
      _furniture = ScanLayoutConverter.toFurniture(
        restored,
        gridCols: room.gridCols,
        gridRows: room.gridRows,
      );
      _activeRoomLayout = restored.withFurniture(_furniture);
    }

    notifyListeners();
    return true;
  }

  // Optimization sliders
  double _airflowSlider = 0.7;
  double _lightingSlider = 0.5;
  double _ergonomicsSlider = 0.6;

  double get airflowSlider => _airflowSlider;
  double get lightingSlider => _lightingSlider;
  double get ergonomicsSlider => _ergonomicsSlider;

  MultiObjectiveWeights get optimizeWeights => MultiObjectiveWeights(
        airflow: _airflowSlider,
        lighting: _lightingSlider,
        ergonomics: _ergonomicsSlider,
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

  void setOptimizeWeights({
    required double airflow,
    required double lighting,
    required double ergonomics,
  }) {
    _airflowSlider = airflow.clamp(0.0, 1.0);
    _lightingSlider = lighting.clamp(0.0, 1.0);
    _ergonomicsSlider = ergonomics.clamp(0.0, 1.0);
    notifyListeners();
  }

  void applyOptimizeGoalPreset(String goal) {
    switch (goal) {
      case 'airflow':
        setOptimizeWeights(airflow: 0.95, lighting: 0.35, ergonomics: 0.35);
        _benchmarkMode = 'airflow';
        break;
      case 'lighting':
        setOptimizeWeights(airflow: 0.35, lighting: 0.95, ergonomics: 0.35);
        _benchmarkMode = 'lighting';
        break;
      case 'ergonomics':
        setOptimizeWeights(airflow: 0.35, lighting: 0.35, ergonomics: 0.95);
        _benchmarkMode = 'ergonomics';
        break;
      default:
        setOptimizeWeights(airflow: 0.75, lighting: 0.75, ergonomics: 0.75);
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

  AirflowMetrics? get airflowMetrics => _airflowMetrics;
  LightingMetrics? get lightingMetrics => _lightingMetrics;
  ErgonomicsMetrics? get ergonomicsMetrics => _ergonomicsMetrics;
  List<String> get lastOptimizeReasons => _lastOptimizeReasons;

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

  double get overallScore {
    final total = _airflowSlider + _lightingSlider + _ergonomicsSlider;
    if (total == 0) return (airflowScore + lightingScore + ergonomicsScore) / 3;
    return (airflowScore * _airflowSlider +
            lightingScore * _lightingSlider +
            ergonomicsScore * _ergonomicsSlider) /
        total;
  }

  double get previousOverallScore {
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

  /// Auto-Rig: rearranges furniture using weighted multi-objective blending.
  /// [goal] optionally applies a weight preset before solving.
  void runOptimization({String? goal}) {
    if (goal != null) {
      applyOptimizeGoalPreset(goal);
    }

    _pushUndoCheckpoint();
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
    _activeRoomLayout = RoomLayoutModel.fromPreset(currentRoomData, _furniture);
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
  void applyFurnitureLayout(List<FurnitureItem> items, {bool markOptimized = false}) {
    _pushUndoCheckpoint();
    _loadPreset(RoomPreset.gamingSetup);
    _furniture = items.map((f) => f.copyWith()).toList(growable: false);
    _activeRoomLayout = RoomLayoutModel.fromPreset(currentRoomData, _furniture);
    _scanComplete = false;
    _scanProgress = 0.0;
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
    unawaited(_persistActiveRoomLayout());
    notifyListeners();
  }

  void loadSimulatedPrototypeBaseline({String? mode}) {
    final m = mode ?? _benchmarkMode;
    _loadPreset(RoomPreset.gamingSetup);
    if (m == 'lighting') {
      _furniture = LightingPrototypeLayouts.baseline(_furniture);
    } else if (m == 'ergonomics') {
      _furniture = ErgonomicsPrototypeLayouts.baseline(_furniture);
    } else {
      _furniture = AirflowPrototypeLayouts.baseline(_furniture);
    }
    _activeRoomLayout = RoomLayoutModel.fromPreset(currentRoomData, _furniture);
    _scanComplete = false;
    _scanProgress = 0.0;
    _isOptimized = false;
    _airflowSlider = 0.25;
    _lightingSlider = 0.25;
    _ergonomicsSlider = 0.25;
    _benchmarkMode = switch (m) {
      'lighting' => 'lighting',
      'ergonomics' => 'ergonomics',
      _ => 'airflow',
    };
    final air = AirflowOptimizer.evaluate(_furniture);
    final light = LightingOptimizer.evaluate(_furniture);
    final ergo = ErgonomicsOptimizer.evaluate(_furniture);
    _preOptimizeAirflowMetrics = air;
    _preOptimizeLightingMetrics = light;
    _preOptimizeErgonomicsMetrics = ergo;
    _setAirflowMetrics(air);
    _setLightingMetrics(light);
    _setErgonomicsMetrics(ergo);
    _lastOptimizeReasons = const [];
    clearLayoutHistory();
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

  // Upgrade catalog — icon names reference upgradeSvgFor() with price tags
  final List<Map<String, dynamic>> upgrades = [
    {'name': 'Air Circulator Fan', 'iconName': 'fan', 'type': 'airflow', 'desc': 'Reduces stagnant zones by 40%', 'airflowBoost': 15.0, 'lightingBoost': 0.0, 'ergonomicsBoost': 0.0, 'price': 89.0, 'added': false},
    {'name': 'Smart Air Purifier', 'iconName': 'purifier', 'type': 'airflow', 'desc': 'Cleans and circulates air continuously', 'airflowBoost': 10.0, 'lightingBoost': 0.0, 'ergonomicsBoost': 5.0, 'price': 189.0, 'added': false},
    {'name': 'Smart Light Bar', 'iconName': 'lightBar', 'type': 'lighting', 'desc': 'Bias lighting reduces eye strain 60%', 'airflowBoost': 0.0, 'lightingBoost': 18.0, 'ergonomicsBoost': 5.0, 'price': 99.0, 'added': false},
    {'name': 'Diffused Floor Lamp', 'iconName': 'floorLamp', 'type': 'lighting', 'desc': 'Soft ambient glow, no harsh shadows', 'airflowBoost': 0.0, 'lightingBoost': 12.0, 'ergonomicsBoost': 2.0, 'price': 79.0, 'added': false},
    {'name': 'Monitor Arm', 'iconName': 'monitorArm', 'type': 'ergonomics', 'desc': 'Frees desk space, optimizes eye level', 'airflowBoost': 5.0, 'lightingBoost': 0.0, 'ergonomicsBoost': 20.0, 'price': 129.0, 'added': false},
    {'name': 'Cable Tray', 'iconName': 'cableTray', 'type': 'ergonomics', 'desc': 'Eliminates cable clutter, improves airflow', 'airflowBoost': 8.0, 'lightingBoost': 0.0, 'ergonomicsBoost': 10.0, 'price': 39.0, 'added': false},
    {'name': 'Anti-Fatigue Mat', 'iconName': 'mat', 'type': 'ergonomics', 'desc': 'Reduces standing fatigue by 55%', 'airflowBoost': 0.0, 'lightingBoost': 0.0, 'ergonomicsBoost': 15.0, 'price': 49.0, 'added': false},
    {'name': 'Smart Blinds', 'iconName': 'smartBlinds', 'type': 'lighting', 'desc': 'Auto-adjusts glare throughout the day', 'airflowBoost': 2.0, 'lightingBoost': 14.0, 'ergonomicsBoost': 0.0, 'price': 249.0, 'added': false},
  ];

  double _upgradeAirflowBonus = 0;
  double _upgradeLightingBonus = 0;
  double _upgradeErgonomicsBonus = 0;

  double get upgradeAirflowBonus => _upgradeAirflowBonus;
  double get upgradeLightingBonus => _upgradeLightingBonus;
  double get upgradeErgonomicsBonus => _upgradeErgonomicsBonus;

  void toggleUpgrade(int index) {
    final u = upgrades[index];
    u['added'] = !(u['added'] as bool);
    _recalcUpgrades();
    notifyListeners();
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
}
