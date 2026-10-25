// lib/models/sim_room_bounds.dart
// Sim world size in grid cells (XY) + ceiling height in metres.
import 'room_model.dart';
import 'room_scale.dart';
import 'scan_layout_model.dart';

/// Footprint for Air / Light / Ergo solvers. Width/depth match furniture grid
/// cells; height is physical metres ([RoomScale.defaultHeightMeters] fallback).
class SimRoomBounds {
  final double width;
  final double depth;
  final double height;

  const SimRoomBounds({
    required this.width,
    required this.depth,
    required this.height,
  });

  /// Classic preset when room data is missing.
  static const fallback = SimRoomBounds(
    width: 6,
    depth: 8,
    height: RoomScale.defaultHeightMeters,
  );

  factory SimRoomBounds.fromRoomData(RoomData room) {
    final h = room.heightMeters > 0.5
        ? room.heightMeters
        : RoomScale.defaultHeightMeters;
    return SimRoomBounds(
      width: room.gridCols.toDouble().clamp(RoomScale.minCells.toDouble(), RoomScale.maxCells.toDouble()),
      depth: room.gridRows.toDouble().clamp(RoomScale.minCells.toDouble(), RoomScale.maxCells.toDouble()),
      height: h.clamp(2.2, 4.5),
    );
  }

  factory SimRoomBounds.fromGrid({
    required int gridCols,
    required int gridRows,
    double? heightMeters,
  }) {
    return SimRoomBounds(
      width: gridCols.toDouble().clamp(RoomScale.minCells.toDouble(), RoomScale.maxCells.toDouble()),
      depth: gridRows.toDouble().clamp(RoomScale.minCells.toDouble(), RoomScale.maxCells.toDouble()),
      height: (heightMeters != null && heightMeters > 0.5)
          ? heightMeters.clamp(2.2, 4.5)
          : RoomScale.defaultHeightMeters,
    );
  }

  factory SimRoomBounds.fromLayout(RoomLayoutModel? layout, {RoomData? room}) {
    if (room != null) return SimRoomBounds.fromRoomData(room);
    if (layout == null) return fallback;
    final cols = RoomScale.colsFrom(layout);
    final rows = RoomScale.rowsFrom(layout);
    final h = layout.dimensions.heightMeters > 0.5
        ? layout.dimensions.heightMeters
        : RoomScale.defaultHeightMeters;
    return SimRoomBounds.fromGrid(gridCols: cols, gridRows: rows, heightMeters: h);
  }

  int get gridCols => width.round().clamp(RoomScale.minCells, RoomScale.maxCells);
  int get gridRows => depth.round().clamp(RoomScale.minCells, RoomScale.maxCells);

  /// ~3 samples per cell (classic 6→18, 8→24), clamped for perf.
  int get airflowNx => (width * 3).round().clamp(12, 48);
  int get airflowNz => (depth * 3).round().clamp(12, 48);
  int get airflowNy => (10 + ((height - 2.7) * 2).round()).clamp(8, 14);

  /// ~4 samples per cell (classic 6→24, 8→32).
  int get lightingNx => (width * 4).round().clamp(16, 64);
  int get lightingNz => (depth * 4).round().clamp(16, 64);

  int get ergoPathCols => (width * 4).round().clamp(16, 64);
  int get ergoPathRows => (depth * 4).round().clamp(16, 64);

  @override
  bool operator ==(Object other) =>
      other is SimRoomBounds &&
      other.width == width &&
      other.depth == depth &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, depth, height);
}
