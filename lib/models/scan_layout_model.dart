import 'room_model.dart';

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
  });

  ScanObject copyWith({
    Vec3? center,
    Vec3? sizeMeters,
    double? yawDegrees,
    double? confidence,
    bool? locked,
  }) {
    return ScanObject(
      id: id,
      label: label,
      category: category,
      confidence: confidence ?? this.confidence,
      center: center ?? this.center,
      sizeMeters: sizeMeters ?? this.sizeMeters,
      yawDegrees: yawDegrees ?? this.yawDegrees,
      source: source,
      locked: locked ?? this.locked,
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
      yawDegrees: 0,
      source: 'preset',
      locked: false,
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
    next[idx] = value.clamp(0, 1).toDouble();
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
  final DateTime updatedAt;

  const RoomLayoutModel({
    required this.roomName,
    required this.dimensions,
    required this.coverageGrid,
    required this.objects,
    required this.updatedAt,
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
      updatedAt: DateTime.now().toUtc(),
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
      updatedAt: DateTime.now().toUtc(),
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
      updatedAt: DateTime.now().toUtc(),
    );
  }

  RoomLayoutModel withCoverage(CoverageGrid nextCoverage) {
    return RoomLayoutModel(
      roomName: roomName,
      dimensions: dimensions,
      coverageGrid: nextCoverage,
      objects: objects,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  RoomLayoutModel withObjects(List<ScanObject> nextObjects) {
    return RoomLayoutModel(
      roomName: roomName,
      dimensions: dimensions,
      coverageGrid: coverageGrid,
      objects: List<ScanObject>.from(nextObjects),
      updatedAt: DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'roomName': roomName,
        'dimensions': dimensions.toJson(),
        'coverageGrid': coverageGrid.toJson(),
        'objects': objects.map((o) => o.toJson()).toList(growable: false),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory RoomLayoutModel.fromJson(Map<String, dynamic> json) {
    return RoomLayoutModel(
      roomName: (json['roomName'] as String?) ?? 'Unknown Room',
      dimensions: RoomDimensions.fromJson((json['dimensions'] as Map?)?.cast<String, dynamic>() ?? const {}),
      coverageGrid: CoverageGrid.fromJson((json['coverageGrid'] as Map?)?.cast<String, dynamic>() ?? const {}),
      objects: (json['objects'] as List?)
              ?.map((e) => ScanObject.fromJson((e as Map).cast<String, dynamic>()))
              .toList(growable: false) ??
          const <ScanObject>[],
      updatedAt: DateTime.tryParse((json['updatedAt'] as String?) ?? '')?.toUtc() ?? DateTime.now().toUtc(),
    );
  }
}
