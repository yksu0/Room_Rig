import 'item_detection.dart';
import 'room_model.dart';

/// Aggregate confidence / coverage for a scan layout (Milestone 2).
class ScanConfidenceMetrics {
  final double coverageRatio;
  final double meanObjectConfidence;
  final int objectCount;
  final int detectionCount;
  final double overallScore;
  final String inputProviderId;
  final bool usedFallback;
  final List<String> notes;

  const ScanConfidenceMetrics({
    required this.coverageRatio,
    required this.meanObjectConfidence,
    required this.objectCount,
    required this.detectionCount,
    required this.overallScore,
    this.inputProviderId = 'unknown',
    this.usedFallback = false,
    this.notes = const [],
  });

  Map<String, dynamic> toJson() => {
        'coverageRatio': coverageRatio,
        'meanObjectConfidence': meanObjectConfidence,
        'objectCount': objectCount,
        'detectionCount': detectionCount,
        'overallScore': overallScore,
        'inputProviderId': inputProviderId,
        'usedFallback': usedFallback,
        'notes': notes,
      };

  factory ScanConfidenceMetrics.fromJson(Map<String, dynamic> json) {
    return ScanConfidenceMetrics(
      coverageRatio: (json['coverageRatio'] as num?)?.toDouble() ?? 0,
      meanObjectConfidence: (json['meanObjectConfidence'] as num?)?.toDouble() ?? 0,
      objectCount: (json['objectCount'] as num?)?.toInt() ?? 0,
      detectionCount: (json['detectionCount'] as num?)?.toInt() ?? 0,
      overallScore: (json['overallScore'] as num?)?.toDouble() ?? 0,
      inputProviderId: (json['inputProviderId'] as String?) ?? 'unknown',
      usedFallback: (json['usedFallback'] as bool?) ?? false,
      notes: (json['notes'] as List?)?.map((e) => '$e').toList(growable: false) ?? const [],
    );
  }

  static ScanConfidenceMetrics fromLayout(
    RoomLayoutModel layout, {
    String inputProviderId = 'unknown',
    bool usedFallback = false,
    List<String> extraNotes = const [],
  }) {
    final objects = layout.objects;
    final meanConf = objects.isEmpty
        ? 0.0
        : objects.map((o) => o.confidence).fold<double>(0, (a, b) => a + b) / objects.length;
    final coverage = layout.coverageGrid.ratio();
    final overall = (coverage * 0.55 + meanConf * 0.45).clamp(0.0, 1.0);
    final notes = <String>[
      if (coverage < 0.55) 'Low floor coverage — walk the room again for a stronger scan.',
      if (meanConf < 0.45 && objects.isNotEmpty)
        'Object confidence is low — lighting or framing may be weak.',
      if (objects.isEmpty) 'No furniture detections yet — keep scanning or use a preset.',
      if (usedFallback) 'One or more pipeline stages used fallback paths.',
      ...extraNotes,
    ];

    return ScanConfidenceMetrics(
      coverageRatio: coverage,
      meanObjectConfidence: meanConf,
      objectCount: objects.length,
      detectionCount: layout.detections.length,
      overallScore: overall,
      inputProviderId: inputProviderId,
      usedFallback: usedFallback,
      notes: notes,
    );
  }
}

class Vec3 {
  final double x;
  final double y;
  final double z;

  const Vec3({required this.x, required this.y, required this.z});

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'z': z,
      };

  factory Vec3.fromJson(Map<String, dynamic> json) {
    return Vec3(
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      z: (json['z'] as num?)?.toDouble() ?? 0,
    );
  }

  static Vec3 lerp(Vec3 a, Vec3 b, double t) {
    final w = t.clamp(0, 1).toDouble();
    return Vec3(
      x: a.x + (b.x - a.x) * w,
      y: a.y + (b.y - a.y) * w,
      z: a.z + (b.z - a.z) * w,
    );
  }
}

class RoomDimensions {
  final double lengthMeters;
  final double widthMeters;
  final double heightMeters;

  const RoomDimensions({
    required this.lengthMeters,
    required this.widthMeters,
    required this.heightMeters,
  });

  Map<String, dynamic> toJson() => {
        'lengthMeters': lengthMeters,
        'widthMeters': widthMeters,
        'heightMeters': heightMeters,
      };

  factory RoomDimensions.fromJson(Map<String, dynamic> json) {
    return RoomDimensions(
      lengthMeters: (json['lengthMeters'] as num?)?.toDouble() ?? 0,
      widthMeters: (json['widthMeters'] as num?)?.toDouble() ?? 0,
      heightMeters: (json['heightMeters'] as num?)?.toDouble() ?? 2.7,
    );
  }
}

class ScanObject {
  final String id;
  final String label;
  final String category;
  final double confidence;
  final Vec3 center;
  final Vec3 sizeMeters;
  final double yawDegrees;
  final String source;
  final bool locked;
  final bool hidden;

  const ScanObject({
    required this.id,
    required this.label,
    required this.category,
    required this.confidence,
    required this.center,
    required this.sizeMeters,
    required this.yawDegrees,
    required this.source,
    this.locked = false,
    this.hidden = false,
  });

  ScanObject copyWith({
    Vec3? center,
    Vec3? sizeMeters,
    double? yawDegrees,
    double? confidence,
    bool? locked,
    bool? hidden,
    String? label,
    String? category,
  }) {
    return ScanObject(
      id: id,
      label: label ?? this.label,
      category: category ?? this.category,
      confidence: confidence ?? this.confidence,
      center: center ?? this.center,
      sizeMeters: sizeMeters ?? this.sizeMeters,
      yawDegrees: yawDegrees ?? this.yawDegrees,
      source: source,
      locked: locked ?? this.locked,
      hidden: hidden ?? this.hidden,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'category': category,
        'confidence': confidence,
        'center': center.toJson(),
        'sizeMeters': sizeMeters.toJson(),
        'yawDegrees': yawDegrees,
        'source': source,
        'locked': locked,
        'hidden': hidden,
      };

  factory ScanObject.fromJson(Map<String, dynamic> json) {
    return ScanObject(
      id: (json['id'] as String?) ?? 'unknown',
      label: (json['label'] as String?) ?? 'Unknown',
      category: (json['category'] as String?) ?? 'neutral',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      center: Vec3.fromJson((json['center'] as Map?)?.cast<String, dynamic>() ?? const {}),
      sizeMeters: Vec3.fromJson((json['sizeMeters'] as Map?)?.cast<String, dynamic>() ?? const {}),
      yawDegrees: (json['yawDegrees'] as num?)?.toDouble() ?? 0,
      source: (json['source'] as String?) ?? 'unknown',
      locked: (json['locked'] as bool?) ?? false,
      hidden: (json['hidden'] as bool?) ?? false,
    );
  }

  static ScanObject fromFurniture(FurnitureItem item, {double cellMeters = 0.6}) {
    final center = Vec3(
      x: (item.gridX + item.width / 2) * cellMeters,
      y: 0.45,
      z: (item.gridY + item.height / 2) * cellMeters,
    );
    final size = Vec3(
      x: item.width * cellMeters,
      y: 0.9,
      z: item.height * cellMeters,
    );

    return ScanObject(
      id: item.id,
      label: item.name,
      category: item.category,
      confidence: 0.95,
      center: center,
      sizeMeters: size,
      yawDegrees: item.yawDegrees,
      source: 'preset',
      locked: item.locked,
      hidden: item.hidden,
    );
  }
}

class CoverageGrid {
  final int cols;
  final int rows;
  final List<double> coverage; // 0.0 - 1.0 per cell

  CoverageGrid({required this.cols, required this.rows, required List<double> coverage})
      : coverage = List<double>.from(coverage);

  factory CoverageGrid.empty({required int cols, required int rows}) {
    return CoverageGrid(
      cols: cols,
      rows: rows,
      coverage: List<double>.filled(cols * rows, 0),
    );
  }

  double ratio() {
    if (coverage.isEmpty) return 0;
    final sum = coverage.fold<double>(0, (total, v) => total + v.clamp(0, 1));
    return sum / coverage.length;
  }

  CoverageGrid markCell(int col, int row, double value) {
    if (col < 0 || row < 0 || col >= cols || row >= rows) return this;
    final next = List<double>.from(coverage);
    final idx = row * cols + col;
    final incoming = value.clamp(0, 1).toDouble();
    next[idx] = next[idx] > incoming ? next[idx] : incoming;
    return CoverageGrid(cols: cols, rows: rows, coverage: next);
  }

  Map<String, dynamic> toJson() => {
        'cols': cols,
        'rows': rows,
        'coverage': coverage,
      };

  factory CoverageGrid.fromJson(Map<String, dynamic> json) {
    final cols = (json['cols'] as num?)?.toInt() ?? 0;
    final rows = (json['rows'] as num?)?.toInt() ?? 0;
    final values = (json['coverage'] as List?)
            ?.map((v) => (v as num).toDouble())
            .toList(growable: false) ??
        const <double>[];

    if (values.length == cols * rows) {
      return CoverageGrid(cols: cols, rows: rows, coverage: values);
    }

    return CoverageGrid.empty(cols: cols, rows: rows);
  }
}

class RoomLayoutModel {
  final String roomName;
  final RoomDimensions dimensions;
  final CoverageGrid coverageGrid;
  final List<ScanObject> objects;
  final List<ItemDetection> detections;
  final DateTime updatedAt;
  final String? scanSource;
  final ScanConfidenceMetrics? confidence;

  const RoomLayoutModel({
    required this.roomName,
    required this.dimensions,
    required this.coverageGrid,
    required this.objects,
    this.detections = const <ItemDetection>[],
    required this.updatedAt,
    this.scanSource,
    this.confidence,
  });

  factory RoomLayoutModel.fromPreset(RoomData roomData, List<FurnitureItem> furniture, {double cellMeters = 0.6}) {
    final objects = furniture
        .map((item) => ScanObject.fromFurniture(item, cellMeters: cellMeters))
        .toList(growable: false);

    return RoomLayoutModel(
      roomName: roomData.name,
      dimensions: RoomDimensions(
        lengthMeters: roomData.gridCols * cellMeters,
        widthMeters: roomData.gridRows * cellMeters,
        heightMeters: 2.7,
      ),
      coverageGrid: CoverageGrid.empty(cols: roomData.gridCols, rows: roomData.gridRows),
      objects: objects,
      detections: const <ItemDetection>[],
      updatedAt: DateTime.now().toUtc(),
      scanSource: 'preset',
    );
  }

  factory RoomLayoutModel.emptyFromRoom(RoomData roomData, {double cellMeters = 0.6}) {
    return RoomLayoutModel(
      roomName: roomData.name,
      dimensions: RoomDimensions(
        lengthMeters: roomData.gridCols * cellMeters,
        widthMeters: roomData.gridRows * cellMeters,
        heightMeters: 2.7,
      ),
      coverageGrid: CoverageGrid.empty(cols: roomData.gridCols, rows: roomData.gridRows),
      objects: const <ScanObject>[],
      detections: const <ItemDetection>[],
      updatedAt: DateTime.now().toUtc(),
      scanSource: 'scan-seed',
    );
  }

  RoomLayoutModel copyMeta({
    String? roomName,
    RoomDimensions? dimensions,
    String? scanSource,
  }) {
    return RoomLayoutModel(
      roomName: roomName ?? this.roomName,
      dimensions: dimensions ?? this.dimensions,
      coverageGrid: coverageGrid,
      objects: objects,
      detections: detections,
      updatedAt: DateTime.now().toUtc(),
      scanSource: scanSource ?? this.scanSource,
      confidence: confidence,
    );
  }

  RoomLayoutModel withFurniture(List<FurnitureItem> furniture, {double cellMeters = 0.6}) {
    return RoomLayoutModel(
      roomName: roomName,
      dimensions: dimensions,
      coverageGrid: coverageGrid,
      objects: furniture
          .map((item) => ScanObject.fromFurniture(item, cellMeters: cellMeters))
          .toList(growable: false),
      detections: detections,
      updatedAt: DateTime.now().toUtc(),
      scanSource: scanSource,
      confidence: confidence,
    );
  }

  RoomLayoutModel withCoverage(CoverageGrid nextCoverage) {
    return RoomLayoutModel(
      roomName: roomName,
      dimensions: dimensions,
      coverageGrid: nextCoverage,
      objects: objects,
      detections: detections,
      updatedAt: DateTime.now().toUtc(),
      scanSource: scanSource,
      confidence: confidence,
    );
  }

  RoomLayoutModel withObjects(List<ScanObject> nextObjects) {
    return RoomLayoutModel(
      roomName: roomName,
      dimensions: dimensions,
      coverageGrid: coverageGrid,
      objects: List<ScanObject>.from(nextObjects),
      detections: detections,
      updatedAt: DateTime.now().toUtc(),
      scanSource: scanSource,
      confidence: confidence,
    );
  }

  RoomLayoutModel withDetections(List<ItemDetection> nextDetections) {
    return RoomLayoutModel(
      roomName: roomName,
      dimensions: dimensions,
      coverageGrid: coverageGrid,
      objects: objects,
      detections: List<ItemDetection>.from(nextDetections),
      updatedAt: DateTime.now().toUtc(),
      scanSource: scanSource,
      confidence: confidence,
    );
  }

  RoomLayoutModel withConfidence(ScanConfidenceMetrics? nextConfidence, {String? nextScanSource}) {
    return RoomLayoutModel(
      roomName: roomName,
      dimensions: dimensions,
      coverageGrid: coverageGrid,
      objects: objects,
      detections: detections,
      updatedAt: DateTime.now().toUtc(),
      scanSource: nextScanSource ?? scanSource,
      confidence: nextConfidence,
    );
  }

  Map<String, dynamic> toJson() => {
        'roomName': roomName,
        'dimensions': dimensions.toJson(),
        'coverageGrid': coverageGrid.toJson(),
        'objects': objects.map((o) => o.toJson()).toList(growable: false),
        'detections': detections.map((d) => d.toJson()).toList(growable: false),
        'updatedAt': updatedAt.toIso8601String(),
        if (scanSource != null) 'scanSource': scanSource,
        if (confidence != null) 'confidence': confidence!.toJson(),
      };

  factory RoomLayoutModel.fromJson(Map<String, dynamic> json) {
    final confRaw = json['confidence'];
    return RoomLayoutModel(
      roomName: (json['roomName'] as String?) ?? 'Unknown Room',
      dimensions: RoomDimensions.fromJson((json['dimensions'] as Map?)?.cast<String, dynamic>() ?? const {}),
      coverageGrid: CoverageGrid.fromJson((json['coverageGrid'] as Map?)?.cast<String, dynamic>() ?? const {}),
      objects: (json['objects'] as List?)
              ?.map((e) => ScanObject.fromJson((e as Map).cast<String, dynamic>()))
              .toList(growable: false) ??
          const <ScanObject>[],
      detections: (json['detections'] as List?)
              ?.map((e) => ItemDetection.fromJson((e as Map).cast<String, dynamic>()))
              .toList(growable: false) ??
          const <ItemDetection>[],
      updatedAt: DateTime.tryParse((json['updatedAt'] as String?) ?? '')?.toUtc() ?? DateTime.now().toUtc(),
      scanSource: json['scanSource'] as String?,
      confidence: confRaw is Map
          ? ScanConfidenceMetrics.fromJson(confRaw.cast<String, dynamic>())
          : null,
    );
  }
}
