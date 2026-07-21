// lib/models/airflow_prototype.dart
// Demo layouts for the airflow benchmark prototype (not live scan data).
import 'room_model.dart';

/// Average gaming room with clear airflow problems, plus an improved rearrange.
///
/// Arrangement logic (airflow goal):
/// 1. Place the AC on a long wall, mid-room, so its throw covers max floor area.
/// 2. Keep tall/large furniture out of that primary throw cone.
/// 3. Put heat sources (PC) inside the cooled zone so exhaust mixes with supply.
/// 4. Use the window as a return/exhaust — ideally opposite or offset from the AC,
///    not blocking the throw.
/// 5. Bed / storage along perimeter walls, not in the center circulation volume.
class AirflowPrototypeLayouts {
  AirflowPrototypeLayouts._();

  /// Cluttered but believable: AC jammed in a far corner (tiny coverage),
  /// bed + shelf sit in what little throw exists, PC heat trapped mid-room.
  static List<FurnitureItem> baseline(List<FurnitureItem> source) {
    final positions = <String, ({double x, double y})>{
      'desk': (x: 1.8, y: 2.8),
      'chair': (x: 1.8, y: 4.0),
      'bed': (x: 2.8, y: 5.0),
      'pc': (x: 2.2, y: 3.5),
      'ac': (x: 5.0, y: 6.8), // corner — covers almost nothing
      'window': (x: 0.0, y: 0.0),
      'lamp': (x: 4.4, y: 5.8),
      'shelf': (x: 4.6, y: 3.6), // blocks residual throw
      'fan': (x: 5.0, y: 5.5), // corner — barely helps circulation
    };
    return _applyPositions(source, positions);
  }

  /// Coverage-first rearrange:
  /// - AC mid-depth on the long right wall → throw sweeps most of the 6×8 room
  /// - Desk/PC on the left sit inside that cooled sweep
  /// - Bed along the far wall, shelf in a dead corner — out of the cone
  /// - Window on the front wall acts as return exhaust (offset, not fighting AC)
  /// - Stand fan against the wall by the desk (not mid-floor) oscillating into the room
  static List<FurnitureItem> optimized(List<FurnitureItem> source) {
    final positions = <String, ({double x, double y})>{
      'ac': (x: 5.0, y: 3.2), // mid long-wall — max coverage throw
      'window': (x: 0.5, y: 0.0), // return path, offset from throw axis
      'desk': (x: 0.3, y: 2.4),
      'chair': (x: 0.4, y: 3.6),
      'pc': (x: 0.2, y: 2.0), // inside AC coverage so heat is scrubbed
      'bed': (x: 2.5, y: 5.8), // perimeter, below throw cone
      'shelf': (x: 0.2, y: 6.5), // far corner, out of primary sweep
      'lamp': (x: 2.2, y: 1.2),
      'fan': (x: 0.15, y: 4.7), // wall by desk — keeps floor clear, aims into room
    };
    return _applyPositions(source, positions);
  }

  static List<FurnitureItem> _applyPositions(
    List<FurnitureItem> source,
    Map<String, ({double x, double y})> positions,
  ) {
    const cols = 6.0;
    const rows = 8.0;
    return source.map((item) {
      final pos = positions[item.id];
      if (pos == null) return item.copyWith();
      final maxX = (cols - item.width).clamp(0.0, cols);
      final maxY = (rows - item.height).clamp(0.0, rows);
      return item.copyWith(
        gridX: pos.x.clamp(0.0, maxX),
        gridY: pos.y.clamp(0.0, maxY),
      );
    }).toList(growable: false);
  }

  static const baselineNotes = [
    'AC buried in a corner — throw covers only a sliver of the room',
    'Bed and shelf sit in the weak leftover airflow path',
    'Stand fan stuck in a corner; PC heat sits outside useful cold coverage',
  ];

  static const optimizedNotes = [
    'AC mid-wall on the long side so cold throw covers most of the floor',
    'Stand fan on the desk wall (not mid-room) — oscillates into the open floor',
    'Desk / PC inside coverage; bed on the perimeter; window as return',
  ];
}
