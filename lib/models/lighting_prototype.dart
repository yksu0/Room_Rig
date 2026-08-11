// lib/models/lighting_prototype.dart
// Demo layouts for the lighting benchmark prototype.
import 'room_model.dart';

/// Daylight + task-light arrangement stories for Bench / Auto-Rig.
class LightingPrototypeLayouts {
  LightingPrototypeLayouts._();

  /// Desk buried away from the window; tall shelf blocks daylight;
  /// lamp abandoned in a dark corner — harsh shadows on the task zone.
  static List<FurnitureItem> baseline(List<FurnitureItem> source) {
    final positions = <String, ({double x, double y})>{
      'window': (x: 2.0, y: 0.0),
      'door': (x: 0.0, y: 6.0),
      'desk': (x: 3.5, y: 5.5),
      'chair': (x: 3.5, y: 6.6),
      'pc': (x: 4.5, y: 5.5),
      'lamp': (x: 0.2, y: 6.5), // useless corner
      'shelf': (x: 2.0, y: 1.5), // blocks window throw
      'bed': (x: 0.2, y: 3.0),
      'ac': (x: 5.0, y: 0.2),
      'fan': (x: 5.0, y: 4.0),
    };
    return _applyPositions(source, positions);
  }

  /// Desk in the daylight band (offset to reduce glare), lamp on-task,
  /// shelf cleared from the window path, bed on the dark perimeter.
  static List<FurnitureItem> optimized(List<FurnitureItem> source) {
    final positions = <String, ({double x, double y})>{
      'window': (x: 2.0, y: 0.0),
      'door': (x: 0.0, y: 6.2),
      'desk': (x: 1.0, y: 1.8), // in daylight, slightly offset
      'chair': (x: 1.2, y: 2.9),
      'pc': (x: 0.3, y: 1.8),
      'lamp': (x: 2.6, y: 1.8), // task light at desk
      'shelf': (x: 5.0, y: 5.5), // out of daylight corridor
      'bed': (x: 3.0, y: 5.5),
      'ac': (x: 5.0, y: 2.5),
      'fan': (x: 0.15, y: 4.2),
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
    'Desk sits deep in the room — daylight barely reaches the task zone',
    'Shelf blocks the window throw and casts a hard shadow band',
    'Lamp is stranded in a corner instead of lighting the desk',
  ];

  static const optimizedNotes = [
    'Desk sits in the daylight band, offset to limit screen glare',
    'Task lamp anchors the desk; shelf cleared from the window path',
    'Bed / storage kept on the darker perimeter wall',
  ];
}
