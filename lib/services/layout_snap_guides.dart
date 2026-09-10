import '../models/room_model.dart';

/// Axis-aligned guide used while dragging furniture.
enum SnapGuideAxis { vertical, horizontal }

class SnapGuideLine {
  final SnapGuideAxis axis;

  /// Grid coordinate of the guide (x for vertical, y for horizontal).
  final double position;

  const SnapGuideLine({required this.axis, required this.position});

  @override
  bool operator ==(Object other) =>
      other is SnapGuideLine && other.axis == axis && other.position == position;

  @override
  int get hashCode => Object.hash(axis, position);
}

class SnapGuideResult {
  final double gridX;
  final double gridY;
  final List<SnapGuideLine> guides;

  const SnapGuideResult({
    required this.gridX,
    required this.gridY,
    required this.guides,
  });
}

/// Soft alignment snap against other furniture and room centerlines.
class LayoutSnapGuides {
  static const double threshold = 0.28;

  static SnapGuideResult apply({
    required FurnitureItem moving,
    required double proposedX,
    required double proposedY,
    required List<FurnitureItem> others,
    required int gridCols,
    required int gridRows,
  }) {
    final w = moving.width;
    final h = moving.height;
    final movingLeft = proposedX;
    final movingRight = proposedX + w;
    final movingCx = proposedX + w * 0.5;
    final movingTop = proposedY;
    final movingBottom = proposedY + h;
    final movingCy = proposedY + h * 0.5;

    final xTargets = <double>[
      0,
      gridCols * 0.5,
      gridCols.toDouble(),
    ];
    final yTargets = <double>[
      0,
      gridRows * 0.5,
      gridRows.toDouble(),
    ];

    for (final other in others) {
      if (other.id == moving.id || other.hidden) continue;
      xTargets.addAll([
        other.gridX,
        other.gridX + other.width * 0.5,
        other.gridX + other.width,
      ]);
      yTargets.addAll([
        other.gridY,
        other.gridY + other.height * 0.5,
        other.gridY + other.height,
      ]);
    }

    double? bestDx;
    double? bestGuideX;
    for (final t in xTargets) {
      for (final candidate in [movingLeft, movingCx, movingRight]) {
        final d = t - candidate;
        if (d.abs() > threshold) continue;
        if (bestDx == null || d.abs() < bestDx.abs()) {
          bestDx = d;
          bestGuideX = t;
        }
      }
    }

    double? bestDy;
    double? bestGuideY;
    for (final t in yTargets) {
      for (final candidate in [movingTop, movingCy, movingBottom]) {
        final d = t - candidate;
        if (d.abs() > threshold) continue;
        if (bestDy == null || d.abs() < bestDy.abs()) {
          bestDy = d;
          bestGuideY = t;
        }
      }
    }

    final guides = <SnapGuideLine>[];
    var nextX = proposedX;
    var nextY = proposedY;
    if (bestDx != null && bestGuideX != null) {
      nextX = proposedX + bestDx;
      guides.add(SnapGuideLine(axis: SnapGuideAxis.vertical, position: bestGuideX));
    }
    if (bestDy != null && bestGuideY != null) {
      nextY = proposedY + bestDy;
      guides.add(SnapGuideLine(axis: SnapGuideAxis.horizontal, position: bestGuideY));
    }
    return SnapGuideResult(gridX: nextX, gridY: nextY, guides: guides);
  }
}
