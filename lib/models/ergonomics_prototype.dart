// lib/models/ergonomics_prototype.dart
// Demo layouts for the ergonomics benchmark prototype.
import 'room_model.dart';

/// Desk / chair / reach stories for Bench / Auto-Rig.
class ErgonomicsPrototypeLayouts {
  ErgonomicsPrototypeLayouts._();

  /// Chair jammed against bed, desk crowded, PC out of reach,
  /// no knee-clearance for sit/stand transitions.
  static List<FurnitureItem> baseline(List<FurnitureItem> source) {
    final positions = <String, ({double x, double y})>{
      'window': (x: 2.0, y: 0.0),
      'door': (x: 0.0, y: 6.0),
      'desk': (x: 2.0, y: 3.5),
      'chair': (x: 2.4, y: 4.2), // too tight to desk + blocked behind
      'pc': (x: 5.0, y: 6.5), // stranded, long reach
      'lamp': (x: 0.2, y: 6.5),
      'bed': (x: 1.5, y: 5.2), // blocks chair pull-back
      'shelf': (x: 4.0, y: 3.2), // crowds desk side
      'ac': (x: 5.0, y: 0.2),
      'fan': (x: 0.2, y: 1.5),
      'monitor': (x: 5.0, y: 5.5),
    };
    return _applyPositions(source, positions);
  }

  /// Chair centered with pull-back clearance, PC/monitor at desk,
  /// bed/shelf parked off the work aisle.
  static List<FurnitureItem> optimized(List<FurnitureItem> source) {
    final positions = <String, ({double x, double y})>{
      'window': (x: 2.0, y: 0.0),
      'door': (x: 0.0, y: 6.2),
      'desk': (x: 1.5, y: 2.0),
      'chair': (x: 1.9, y: 3.15),
      'pc': (x: 0.4, y: 2.0),
      'lamp': (x: 3.2, y: 2.0),
      'bed': (x: 3.5, y: 5.5),
      'shelf': (x: 5.0, y: 5.5),
      'ac': (x: 5.0, y: 2.5),
      'fan': (x: 0.15, y: 4.5),
      'monitor': (x: 2.0, y: 2.0),
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
    'Chair sits too tight to the desk — no knee or pull-back clearance',
    'Bed blocks frequent walk paths (bed → PC / desk)',
    'PC / gear is out of easy reach from the seated position',
  ];

  static const optimizedNotes = [
    'Chair centered on the desk with a clear pull-back aisle',
    'High-traffic routes (bed → PC, entry → desk) stay short and clear',
    'Bed and tall storage moved off the work circulation path',
  ];
}
