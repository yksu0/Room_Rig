import 'dart:math';

import '../models/room_model.dart';
import '../models/scan_layout_model.dart';
import 'scan_pipeline.dart';

/// Converts fused scan geometry into editable [FurnitureItem]s for Rig / Bench.
class ScanLayoutConverter {
  static const double defaultCellMeters = 0.6;
  static const double minKeepConfidence = 0.28;

  /// Finalize a fused layout: prune weak objects, ensure door/window openings,
  /// attach confidence metrics.
  static RoomLayoutModel finalizeLayout(
    RoomLayoutModel layout, {
    required int gridCols,
    required int gridRows,
    double cellMeters = defaultCellMeters,
    String inputProviderId = 'unknown',
    bool usedFallback = false,
    ScanPipelineDiagnostics? diagnostics,
  }) {
    final fallback = usedFallback || (diagnostics?.hasFallback ?? false);
    var objects = layout.objects
        .where((o) => o.locked || o.confidence >= minKeepConfidence || _isOpening(o))
        .toList(growable: true);

    objects = _ensureOpenings(
      objects,
      dimensions: layout.dimensions,
      gridCols: gridCols,
      gridRows: gridRows,
      cellMeters: cellMeters,
    );

    final drafted = RoomLayoutModel(
      roomName: layout.roomName.isEmpty ? 'Scanned Room' : layout.roomName,
      dimensions: layout.dimensions,
      coverageGrid: layout.coverageGrid,
      objects: objects,
      detections: layout.detections,
      updatedAt: DateTime.now().toUtc(),
      scanSource: inputProviderId,
    );

    return drafted.withConfidence(
      ScanConfidenceMetrics.fromLayout(
        drafted,
        inputProviderId: inputProviderId,
        usedFallback: fallback,
      ),
      nextScanSource: inputProviderId,
    );
  }

  static List<FurnitureItem> toFurniture(
    RoomLayoutModel layout, {
    required int gridCols,
    required int gridRows,
    double cellMeters = defaultCellMeters,
  }) {
    final items = <FurnitureItem>[];
    final usedIds = <String>{};

    for (final obj in layout.objects) {
      final item = _toFurnitureItem(
        obj,
        gridCols: gridCols,
        gridRows: gridRows,
        cellMeters: cellMeters,
        usedIds: usedIds,
      );
      items.add(item);
      usedIds.add(item.id);
    }

    if (!items.any((f) => f.id.contains('door') || f.iconName == 'door')) {
      items.add(
        FurnitureItem(
          id: 'door',
          name: 'Entry Door',
          iconName: 'door',
          category: 'neutral',
          gridX: 0,
          gridY: (gridRows - 2).clamp(1, gridRows - 1).toDouble(),
          width: 1,
          height: 1,
          airflowImpact: 0.3,
          ergonomicsImpact: 0.2,
          cost: 200,
          description: 'Entry opening inferred from scan finalize.',
        ),
      );
    }
    if (!items.any((f) => f.id.contains('window') || f.iconName == 'window')) {
      items.add(
        FurnitureItem(
          id: 'window',
          name: 'Window',
          iconName: 'window',
          category: 'lighting',
          gridX: (gridCols / 2 - 0.5).clamp(0, gridCols - 1.0),
          gridY: 0,
          width: 1,
          height: 1,
          lightingImpact: 0.7,
          airflowImpact: 0.25,
          cost: 150,
          description: 'Daylight opening inferred from scan finalize.',
        ),
      );
    }

    return items;
  }

  static FurnitureItem _toFurnitureItem(
    ScanObject obj, {
    required int gridCols,
    required int gridRows,
    required double cellMeters,
    required Set<String> usedIds,
  }) {
    final icon = _iconFor(obj.label, obj.id);
    final baseId = _slug(obj.label.isNotEmpty ? obj.label : icon);
    var id = baseId;
    var n = 2;
    while (usedIds.contains(id)) {
      id = '${baseId}_$n';
      n++;
    }

    final isOpening = icon == 'door' || icon == 'window';
    final wCells = isOpening ? 1.0 : (obj.sizeMeters.x / cellMeters).clamp(1.0, 3.0);
    final hCells = isOpening ? 1.0 : (obj.sizeMeters.z / cellMeters).clamp(1.0, 3.0);

    var gridX = (obj.center.x / cellMeters) - wCells / 2;
    var gridY = (obj.center.z / cellMeters) - hCells / 2;
    gridX = gridX.clamp(0.0, max(0.0, gridCols - wCells));
    gridY = gridY.clamp(0.0, max(0.0, gridRows - hCells));

    if (icon == 'door') {
      gridX = 0;
      gridY = gridY.clamp(1.0, max(1.0, gridRows - 1.0));
    } else if (icon == 'window') {
      gridY = 0;
      gridX = gridX.clamp(0.0, max(0.0, gridCols - 1.0));
    }

    return FurnitureItem(
      id: id,
      name: obj.label.isNotEmpty ? obj.label : _titleCase(icon),
      iconName: icon,
      category: obj.category.isNotEmpty ? obj.category : _categoryFor(icon),
      gridX: gridX,
      gridY: gridY,
      width: wCells,
      height: hCells,
      yawDegrees: obj.yawDegrees,
      locked: obj.locked,
      hidden: obj.hidden,
      airflowImpact: _airflowImpact(icon),
      lightingImpact: _lightingImpact(icon),
      ergonomicsImpact: _ergonomicsImpact(icon),
      cost: 120 + (obj.confidence * 180),
      description: 'Detected from scan (${(obj.confidence * 100).round()}% confidence).',
    );
  }

  static List<ScanObject> _ensureOpenings(
    List<ScanObject> objects, {
    required RoomDimensions dimensions,
    required int gridCols,
    required int gridRows,
    required double cellMeters,
  }) {
    final next = List<ScanObject>.from(objects);
    final hasDoor = next.any(_isDoor);
    final hasWindow = next.any(_isWindow);

    if (!hasDoor) {
      final y = ((gridRows - 1.8).clamp(4.0, gridRows - 1)) * cellMeters;
      next.add(
        ScanObject(
          id: 'door',
          label: 'Door',
          category: 'neutral',
          confidence: 0.72,
          center: Vec3(x: cellMeters * 0.5, y: 1.0, z: y),
          sizeMeters: const Vec3(x: 0.9, y: 2.1, z: 0.15),
          yawDegrees: 0,
          source: 'scan-inferred',
        ),
      );
    }
    if (!hasWindow) {
      final x = (gridCols * 0.45) * cellMeters;
      next.add(
        ScanObject(
          id: 'window',
          label: 'Window',
          category: 'lighting',
          confidence: 0.70,
          center: Vec3(x: x, y: 1.4, z: cellMeters * 0.35),
          sizeMeters: Vec3(x: min(1.6, dimensions.lengthMeters * 0.3), y: 1.2, z: 0.12),
          yawDegrees: 0,
          source: 'scan-inferred',
        ),
      );
    }
    return next;
  }

  static bool _isOpening(ScanObject o) => _isDoor(o) || _isWindow(o);

  static bool _isDoor(ScanObject o) {
    final hay = '${o.id} ${o.label}'.toLowerCase();
    return hay.contains('door');
  }

  static bool _isWindow(ScanObject o) {
    final hay = '${o.id} ${o.label}'.toLowerCase();
    return hay.contains('window');
  }

  static String _iconFor(String label, String id) {
    final hay = '${label}_$id'.toLowerCase();
    const keys = [
      'door',
      'window',
      'desk',
      'chair',
      'bed',
      'sofa',
      'lamp',
      'fan',
      'ac',
      'monitor',
      'pc',
      'shelf',
      'bookshelf',
      'wardrobe',
      'plant',
      'cabinet',
      'table',
    ];
    for (final k in keys) {
      if (hay.contains(k)) {
        if (k == 'table') return 'desk';
        if (k == 'bookshelf' || k == 'cabinet') return 'shelf';
        return k;
      }
    }
    return hay.contains('furniture') ? 'shelf' : 'desk';
  }

  static String _slug(String raw) {
    final cleaned = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final trimmed = cleaned.replaceAll(RegExp(r'^_+|_+$'), '');
    return trimmed.isEmpty ? 'item' : trimmed;
  }

  static String _titleCase(String raw) {
    if (raw.isEmpty) return raw;
    return raw[0].toUpperCase() + raw.substring(1);
  }

  static String _categoryFor(String icon) {
    switch (icon) {
      case 'window':
      case 'lamp':
        return 'lighting';
      case 'ac':
      case 'fan':
        return 'airflow';
      case 'desk':
      case 'chair':
      case 'bed':
      case 'monitor':
        return 'ergonomics';
      default:
        return 'neutral';
    }
  }

  static double _airflowImpact(String icon) {
    switch (icon) {
      case 'ac':
        return 0.9;
      case 'fan':
        return 0.7;
      case 'window':
      case 'door':
        return 0.3;
      case 'pc':
        return -0.35;
      default:
        return 0.0;
    }
  }

  static double _lightingImpact(String icon) {
    switch (icon) {
      case 'window':
        return 0.75;
      case 'lamp':
        return 0.55;
      case 'monitor':
        return 0.15;
      default:
        return 0.0;
    }
  }

  static double _ergonomicsImpact(String icon) {
    switch (icon) {
      case 'chair':
        return 0.8;
      case 'desk':
        return 0.6;
      case 'bed':
        return 0.4;
      case 'monitor':
        return 0.35;
      default:
        return 0.1;
    }
  }
}
