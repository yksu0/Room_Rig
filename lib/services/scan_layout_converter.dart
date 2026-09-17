import 'dart:math';

import '../models/room_model.dart';
import '../models/scan_layout_model.dart';
import 'scan_pipeline.dart';

/// Converts fused scan geometry into editable [FurnitureItem]s for Rig / Bench.
class ScanLayoutConverter {
  static const double defaultCellMeters = 0.6;
  static const double minKeepConfidence = 0.28;

  /// Finalize a fused layout: prune weak objects, ensure door/window openings,
  /// optionally nudge room meters from known-object priors, attach confidence.
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

    final refined = refineDimensionsFromObjects(
      layout.dimensions,
      objects,
    );

    final drafted = RoomLayoutModel(
      roomName: layout.roomName.isEmpty ? 'Scanned Room' : layout.roomName,
      dimensions: refined.dimensions,
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
        extraNotes: [
          if (refined.usedObjectScale)
            'Room size nudged from known-object priors (bed/sofa/chair) — still approximate.',
        ],
      ),
      nextScanSource: inputProviderId,
    );
  }

  /// Known real-world widths used to sanity-check scan room meters (no SLAM).
  static const Map<String, double> knownObjectWidthMeters = {
    'bed': 1.9,
    'sofa': 2.0,
    'couch': 2.0,
    'chair': 0.55,
    'desk': 1.4,
    'dining table': 1.5,
  };

  /// Nudge length/width when a confident detection spans an implausible fraction
  /// of the preset room (object-scale heuristic — not measured architecture).
  static ({RoomDimensions dimensions, bool usedObjectScale}) refineDimensionsFromObjects(
    RoomDimensions current,
    List<ScanObject> objects, {
    double minMeters = 2.6,
    double maxMeters = 8.5,
  }) {
    var length = current.lengthMeters;
    var width = current.widthMeters;
    var used = false;

    for (final obj in objects) {
      if (obj.confidence < 0.55) continue;
      final label = obj.label.toLowerCase();
      double? prior;
      for (final e in knownObjectWidthMeters.entries) {
        if (label.contains(e.key)) {
          prior = e.value;
          break;
        }
      }
      if (prior == null) continue;
      final observed = max(obj.sizeMeters.x, obj.sizeMeters.z);
      if (observed < 0.15 || observed > 6.0) continue;
      // If a known piece claims most of a room axis, expand that axis so the
      // prior physical size fits with ~40% occupancy (still a coarse hint).
      final fracL = observed / length.clamp(0.5, 20.0);
      final fracW = observed / width.clamp(0.5, 20.0);
      if (fracL > 0.55) {
        length = max(length, (prior / 0.42).clamp(minMeters, maxMeters));
        used = true;
      }
      if (fracW > 0.55) {
        width = max(width, (prior / 0.42).clamp(minMeters, maxMeters));
        used = true;
      }
    }

    return (
      dimensions: RoomDimensions(
        lengthMeters: length,
        widthMeters: width,
        heightMeters: current.heightMeters,
      ),
      usedObjectScale: used,
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

  static FurnitureItem furnitureFromScanObject(
    ScanObject obj, {
    required int gridCols,
    required int gridRows,
    required Set<String> usedIds,
    double cellMeters = defaultCellMeters,
  }) =>
      _toFurnitureItem(
        obj,
        gridCols: gridCols,
        gridRows: gridRows,
        cellMeters: cellMeters,
        usedIds: usedIds,
      );

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
    // COCO smoke → Rig catalog icons (honest remap, not a custom detector).
    if (hay.contains('potted plant') || hay.contains('plant')) return 'plant';
    if (hay.contains('couch')) return 'sofa';
    if (hay.contains('dining table') || hay.contains('desk')) return 'desk';
    if (hay.contains('tv') || hay.contains('television')) return 'tv';
    if (hay.contains('laptop') || hay.contains('keyboard') || hay.contains('mouse')) {
      return 'pc';
    }
    if (hay.contains('monitor') || hay.contains('display')) return 'monitor';
    if (hay.contains('book') || hay.contains('bookshelf') || hay.contains('cabinet')) {
      return 'shelf';
    }
    if (hay.contains('refrigerator') || hay.contains('oven') || hay.contains('microwave')) {
      return 'shelf';
    }
    if (hay.contains('bed')) return 'bed';
    if (hay.contains('chair')) return 'chair';
    if (hay.contains('sofa')) return 'sofa';
    if (hay.contains('lamp') || hay.contains('light_bar') || hay.contains('light bar')) {
      return 'lamp';
    }
    if (hay.contains('fan')) return 'fan';
    if (hay.contains('door')) return 'door';
    if (hay.contains('window')) return 'window';
    if (hay.contains('wardrobe') || hay.contains('closet')) return 'wardrobe';
    if (hay.contains('ac') || hay.contains('air conditioner')) return 'ac';
    if (hay.contains('table')) return 'desk';
    if (hay.contains('furniture')) return 'shelf';
    return 'desk';
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
      case 'tv':
      case 'sofa':
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
