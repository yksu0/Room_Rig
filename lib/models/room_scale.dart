// lib/models/room_scale.dart
// One cell on the Rig/Bench grid is 0.6 m — same as scan sizing.
import 'scan_layout_model.dart';

class RoomScale {
  RoomScale._();

  static const double cellMeters = 0.6;
  static const int minCells = 5;
  static const int maxCells = 16;
  static const double defaultHeightMeters = 2.7;
  static const double minMeters = 2.6;
  static const double maxMeters = 9.6;

  static int cellsFromMeters(double meters) {
    final clamped = meters.clamp(minMeters, maxMeters);
    return (clamped / cellMeters).round().clamp(minCells, maxCells);
  }

  static double metersFromCells(num cells) => cells * cellMeters;

  static String formatMeters(num meters) {
    final v = meters.toDouble();
    if ((v * 10).round() % 10 == 0) return '${v.round()} m';
    return '${v.toStringAsFixed(1)} m';
  }

  static String formatCellsAsMeters(num cells) => formatMeters(metersFromCells(cells));

  static int colsFrom(RoomLayoutModel? layout, {int fallback = 6}) {
    if (layout == null) return fallback;
    final cov = layout.coverageGrid.cols;
    if (cov >= minCells) return cov.clamp(minCells, maxCells);
    final fromDim = layout.dimensions.lengthMeters;
    if (fromDim >= minMeters * 0.5) return cellsFromMeters(fromDim);
    return fallback;
  }

  static int rowsFrom(RoomLayoutModel? layout, {int fallback = 8}) {
    if (layout == null) return fallback;
    final cov = layout.coverageGrid.rows;
    if (cov >= minCells) return cov.clamp(minCells, maxCells);
    final fromDim = layout.dimensions.widthMeters;
    if (fromDim >= minMeters * 0.5) return cellsFromMeters(fromDim);
    return fallback;
  }

  static RoomDimensions dimensionsForGrid({
    required int cols,
    required int rows,
    double heightMeters = defaultHeightMeters,
  }) {
    return RoomDimensions(
      lengthMeters: metersFromCells(cols),
      widthMeters: metersFromCells(rows),
      heightMeters: heightMeters,
    );
  }

  /// Rebuild coverage if it does not match the measured room.
  static RoomLayoutModel alignCoverage(RoomLayoutModel layout) {
    final cols = colsFrom(layout);
    final rows = rowsFrom(layout);
    final cov = layout.coverageGrid;
    if (cov.cols == cols && cov.rows == rows) return layout;
    return RoomLayoutModel(
      roomName: layout.roomName,
      dimensions: RoomDimensions(
        lengthMeters: layout.dimensions.lengthMeters > 0
            ? layout.dimensions.lengthMeters
            : metersFromCells(cols),
        widthMeters: layout.dimensions.widthMeters > 0
            ? layout.dimensions.widthMeters
            : metersFromCells(rows),
        heightMeters: layout.dimensions.heightMeters > 0
            ? layout.dimensions.heightMeters
            : defaultHeightMeters,
      ),
      coverageGrid: CoverageGrid.empty(cols: cols, rows: rows),
      objects: layout.objects,
      detections: layout.detections,
      updatedAt: layout.updatedAt,
      scanSource: layout.scanSource,
      confidence: layout.confidence,
    );
  }
}
