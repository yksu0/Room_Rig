// lib/models/surface_mount.dart
// Where a piece of the layout physically lives: on the floor, on a wall, or on
// the ceiling.
//
// The mount heights here deliberately mirror the volumes the simulators build
// (see AirflowSimulator._buildBoxes and LightingSimulator._buildLights) so the
// Rig can never draw a wall AC in a spot the physics treats as floor.
import 'dart:math' as math;
import 'room_model.dart';

enum MountSurface { floor, wall, ceiling, desk }

/// North is z = 0, the top edge of the 2D floor plan.
enum RoomWall { north, east, south, west }

/// Drives which symbol the Rig draws for the item.
enum MountStyle { floorItem, window, door, vent, intake, exhaust, ceilingFixture, deskItem }

/// A wall-mounted item's footprint, expressed on the floor in grid units.
class WallSpan {
  final RoomWall wall;
  final double x0;
  final double z0;
  final double x1;
  final double z1;

  /// Unit vector pointing from the wall into the room.
  final double inwardX;
  final double inwardZ;

  const WallSpan({
    required this.wall,
    required this.x0,
    required this.z0,
    required this.x1,
    required this.z1,
    required this.inwardX,
    required this.inwardZ,
  });

  double get length {
    final dx = x1 - x0;
    final dz = z1 - z0;
    return dx.abs() + dz.abs();
  }
}

class SurfaceMount {
  final MountSurface surface;
  final MountStyle style;

  /// Null unless [surface] is [MountSurface.wall].
  final WallSpan? span;

  /// Metres above the floor.
  final double bottomY;
  final double topY;

  /// How far the fitting protrudes into the room, in grid units.
  final double protrusion;

  const SurfaceMount({
    required this.surface,
    required this.style,
    required this.bottomY,
    required this.topY,
    this.span,
    this.protrusion = 0.18,
  });

  bool get isWall => surface == MountSurface.wall;
  bool get isCeiling => surface == MountSurface.ceiling;
  bool get isDesk => surface == MountSurface.desk;

  /// Floor-standing items are the only ones that contest floor space. A wall AC
  /// at 1.4–2.3 m has to be free to sit above a desk, and a monitor on that desk
  /// lives on the work surface rather than as a second floor block.
  bool get occupiesFloor => surface == MountSurface.floor;

  double get height => topY - bottomY;
}

class SurfaceMounts {
  SurfaceMounts._();

  // Matched to AirflowSimulator._buildBoxes.
  static const windowBottom = 0.9;
  static const windowTop = 2.1;
  static const doorTop = 2.1;
  static const ventBottom = 1.4;
  static const ventTop = 2.3;
  static const deskTop = 0.74;

  static bool isWindow(FurnitureItem f) =>
      _hay(f).contains('window') || f.iconName == 'window';

  static bool isDoor(FurnitureItem f) => _hay(f).contains('door') || f.iconName == 'door';

  /// Outdoor-air supply grille. Always pushes into the room.
  static bool isIntake(FurnitureItem f) {
    final hay = _hay(f);
    if (isVent(f) || isExhaust(f)) return false;
    return hay.contains('intake') ||
        hay.contains('fresh air') ||
        (hay.contains('supply') && hay.contains('vent')) ||
        f.iconName == 'intake';
  }

  /// Extract / exhaust fan. Always pulls room air out.
  static bool isExhaust(FurnitureItem f) {
    final hay = _hay(f);
    if (isVent(f)) return false;
    return hay.contains('exhaust') ||
        hay.contains('extractor') ||
        (hay.contains('extract') && hay.contains('fan')) ||
        f.iconName == 'exhaust';
  }

  /// Deliberately stricter than a bare `contains('ac')`, which would also match
  /// words like "rack" or "backrest". Portable / floor coolers are NOT wall vents.
  static bool isVent(FurnitureItem f) {
    final id = f.id.toLowerCase();
    final name = f.name.toLowerCase();
    if (id.contains('portable') ||
        name.contains('portable') ||
        id.contains('evaporative') ||
        name.contains('evaporative') ||
        id.contains('cooler') ||
        (name.contains('cooler') && !name.contains('wall'))) {
      return false;
    }
    if (f.iconName == 'ac' || f.iconName == 'acUnit') return true;
    if (id == 'ac' || id.startsWith('ac_')) return true;
    return name.contains('air condition') ||
        name.contains('aircon') ||
        name.contains('a/c') ||
        name == 'ac' ||
        name.endsWith(' ac');
  }

  static bool isCeilingFixture(FurnitureItem f) {
    final hay = _hay(f);
    return hay.contains('ceiling') || f.iconName == 'ceilingLight';
  }

  /// Desks and tables that can hold a monitor, PC or task lamp.
  static bool isDeskHost(FurnitureItem f) {
    final hay = _hay(f);
    if (hay.contains('fan') || hay.contains('lamp')) return false;
    return f.iconName == 'desk' || hay.contains('desk') || hay.contains('table');
  }

  /// Small items that may sit on a desk instead of the floor.
  static bool isDeskTopItem(FurnitureItem f) {
    final hay = _hay(f);
    if (hay.contains('floor') && hay.contains('lamp')) return false;
    if (f.iconName == 'monitor' || hay.contains('monitor') || hay.contains('display')) {
      return true;
    }
    if (f.iconName == 'pc' ||
        f.id == 'pc' ||
        f.id.startsWith('pc_') ||
        hay.contains('pc tower') ||
        hay.contains(' pc') ||
        hay.contains('computer') ||
        (hay.contains('tower') && !hay.contains('fan'))) {
      return true;
    }
    if (hay.contains('task lamp') || (f.iconName == 'lamp' && !hay.contains('floor'))) {
      return true;
    }
    return false;
  }

  static bool _containsPoint(FurnitureItem host, double x, double y) {
    return x >= host.gridX &&
        x <= host.gridX + host.width &&
        y >= host.gridY &&
        y <= host.gridY + host.height;
  }

  static bool _overlaps(FurnitureItem a, FurnitureItem b) {
    return a.gridX < b.gridX + b.width &&
        a.gridX + a.width > b.gridX &&
        a.gridY < b.gridY + b.height &&
        a.gridY + a.height > b.gridY;
  }

  /// The desk/table [item] is sitting on, if it overlaps one or its centre is over one.
  static FurnitureItem? hostUnder(FurnitureItem item, List<FurnitureItem> furniture) {
    if (!isDeskTopItem(item)) return null;
    final cx = item.gridX + item.width / 2;
    final cy = item.gridY + item.height / 2;
    FurnitureItem? best;
    for (final host in furniture) {
      if (host.id == item.id) continue;
      if (!isDeskHost(host)) continue;
      if (_containsPoint(host, cx, cy) || _overlaps(item, host)) {
        best = host;
        break;
      }
    }
    return best;
  }

  /// If a desktop item is over (or just beside) a desk, keep it on that top.
  static FurnitureItem snapOntoHost(FurnitureItem f, List<FurnitureItem> furniture) {
    if (!isDeskTopItem(f)) return f;
    var host = hostUnder(f, furniture);
    if (host == null) {
      for (final h in furniture) {
        if (h.id == f.id || !isDeskHost(h)) continue;
        if (_overlaps(f, h)) {
          host = h;
          break;
        }
      }
    }
    if (host == null) {
      final cx = f.gridX + f.width / 2;
      final cy = f.gridY + f.height / 2;
      var best = 0.4;
      for (final h in furniture) {
        if (h.id == f.id || !isDeskHost(h)) continue;
        final dx = math.max(h.gridX - cx, math.max(0.0, cx - (h.gridX + h.width)));
        final dy = math.max(h.gridY - cy, math.max(0.0, cy - (h.gridY + h.height)));
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist < best) {
          best = dist;
          host = h;
        }
      }
    }
    if (host == null) return f;
    final maxX = host.gridX + host.width - f.width;
    final maxY = host.gridY + host.height - f.height;
    final x = maxX >= host.gridX
        ? f.gridX.clamp(host.gridX, maxX)
        : host.gridX + (host.width - f.width) / 2;
    final y = maxY >= host.gridY
        ? f.gridY.clamp(host.gridY, maxY)
        : host.gridY + (host.height - f.height) / 2;
    if ((x - f.gridX).abs() < 0.001 && (y - f.gridY).abs() < 0.001) return f;
    return f.copyWith(gridX: x, gridY: y);
  }

  /// Doors, windows, wall ACs, ceiling lights — fixed architecture of the room.
  /// These stay put in non-invasive edit mode so casual rearranging cannot
  /// yank openings and wall fittings off their walls.
  static bool isStructuralMount(FurnitureItem f) {
    return isWindow(f) ||
        isDoor(f) ||
        isVent(f) ||
        isIntake(f) ||
        isExhaust(f) ||
        isCeilingFixture(f);
  }

  static String _hay(FurnitureItem f) =>
      '${f.id} ${f.name} ${f.iconName}'.toLowerCase();

  static SurfaceMount of(
    FurnitureItem f, {
    required int gridCols,
    required int gridRows,
    double roomHeight = 2.8,
    List<FurnitureItem>? furniture,
  }) {
    if (isCeilingFixture(f)) {
      return SurfaceMount(
        surface: MountSurface.ceiling,
        style: MountStyle.ceilingFixture,
        bottomY: roomHeight - 0.14,
        topY: roomHeight,
      );
    }

    if (isDeskTopItem(f) && furniture != null && hostUnder(f, furniture) != null) {
      const rise = 0.42;
      return const SurfaceMount(
        surface: MountSurface.desk,
        style: MountStyle.deskItem,
        bottomY: deskTop,
        topY: deskTop + rise,
      );
    }

    MountStyle? style;
    double bottom = 0;
    double top = 0;
    if (isWindow(f)) {
      style = MountStyle.window;
      bottom = windowBottom;
      top = windowTop;
    } else if (isDoor(f)) {
      style = MountStyle.door;
      bottom = 0;
      top = doorTop;
    } else if (isVent(f)) {
      style = MountStyle.vent;
      bottom = ventBottom;
      top = ventTop;
    } else if (isIntake(f)) {
      style = MountStyle.intake;
      bottom = ventBottom;
      top = ventTop;
    } else if (isExhaust(f)) {
      style = MountStyle.exhaust;
      bottom = ventBottom;
      top = ventTop;
    }

    if (style == null) {
      return const SurfaceMount(
        surface: MountSurface.floor,
        style: MountStyle.floorItem,
        bottomY: 0,
        topY: 0.95,
      );
    }

    return SurfaceMount(
      surface: MountSurface.wall,
      style: style,
      bottomY: bottom,
      topY: top,
      span: spanFor(f, gridCols: gridCols, gridRows: gridRows),
      protrusion: (style == MountStyle.vent ||
              style == MountStyle.intake ||
              style == MountStyle.exhaust)
          ? 0.32
          : 0.14,
    );
  }

  /// True when [wall] is on the far side of the room from a camera at
  /// (eyeX, eyeZ). Near walls are skipped when drawing so the 3D view cuts away
  /// instead of hiding the interior behind the wall closest to the viewer.
  static bool wallIsFarSide(
    RoomWall wall,
    double eyeX,
    double eyeZ, {
    required double roomWidth,
    required double roomDepth,
  }) {
    switch (wall) {
      case RoomWall.north:
        return eyeZ > 0;
      case RoomWall.south:
        return eyeZ < roomDepth;
      case RoomWall.west:
        return eyeX > 0;
      case RoomWall.east:
        return eyeX < roomWidth;
    }
  }

  /// Distance from the item to each wall, in grid units.
  static Map<RoomWall, double> wallDistances(
    FurnitureItem f, {
    required int gridCols,
    required int gridRows,
  }) {
    return {
      RoomWall.north: f.gridY,
      RoomWall.south: gridRows - (f.gridY + f.height),
      RoomWall.west: f.gridX,
      RoomWall.east: gridCols - (f.gridX + f.width),
    };
  }

  /// How much closer another wall has to be before a fitting jumps to it.
  /// Without this a window nudged off its wall would snap to whichever wall
  /// happened to be marginally nearer, which reads as the item teleporting.
  static const wallStickiness = 1.0;

  /// The wall an item belongs to, chosen by whichever it sits closest to.
  ///
  /// When [preferred] is supplied it wins unless another wall is nearer by more
  /// than [wallStickiness].
  static RoomWall nearestWall(
    FurnitureItem f, {
    required int gridCols,
    required int gridRows,
    RoomWall? preferred,
  }) {
    final dist = wallDistances(f, gridCols: gridCols, gridRows: gridRows);

    // Ties resolve in this order, which keeps corner fittings deterministic.
    var best = RoomWall.north;
    var bestDist = dist[RoomWall.north]!;
    for (final wall in const [RoomWall.south, RoomWall.west, RoomWall.east]) {
      if (dist[wall]! < bestDist) {
        best = wall;
        bestDist = dist[wall]!;
      }
    }

    if (preferred != null && dist[preferred]! <= bestDist + wallStickiness) {
      return preferred;
    }
    return best;
  }

  static WallSpan spanFor(
    FurnitureItem f, {
    required int gridCols,
    required int gridRows,
  }) {
    final wall = nearestWall(f, gridCols: gridCols, gridRows: gridRows);
    switch (wall) {
      case RoomWall.north:
        return WallSpan(
          wall: wall,
          x0: f.gridX,
          z0: 0,
          x1: f.gridX + f.width,
          z1: 0,
          inwardX: 0,
          inwardZ: 1,
        );
      case RoomWall.south:
        return WallSpan(
          wall: wall,
          x0: f.gridX,
          z0: gridRows.toDouble(),
          x1: f.gridX + f.width,
          z1: gridRows.toDouble(),
          inwardX: 0,
          inwardZ: -1,
        );
      case RoomWall.west:
        return WallSpan(
          wall: wall,
          x0: 0,
          z0: f.gridY,
          x1: 0,
          z1: f.gridY + f.height,
          inwardX: 1,
          inwardZ: 0,
        );
      case RoomWall.east:
        return WallSpan(
          wall: wall,
          x0: gridCols.toDouble(),
          z0: f.gridY,
          x1: gridCols.toDouble(),
          z1: f.gridY + f.height,
          inwardX: -1,
          inwardZ: 0,
        );
    }
  }

  /// Pulls a wall fitting flush against its nearest wall. Returns the item
  /// unchanged when it is already seated or is not wall-mounted.
  static FurnitureItem snapToWall(
    FurnitureItem f, {
    required int gridCols,
    required int gridRows,
    RoomWall? preferred,
  }) {
    if (!isWindow(f) && !isDoor(f) && !isVent(f) && !isIntake(f) && !isExhaust(f)) {
      return f;
    }

    final wall = nearestWall(f, gridCols: gridCols, gridRows: gridRows, preferred: preferred);
    switch (wall) {
      case RoomWall.north:
        return f.gridY == 0 ? f : f.copyWith(gridY: 0);
      case RoomWall.south:
        final y = gridRows - f.height;
        return f.gridY == y ? f : f.copyWith(gridY: y);
      case RoomWall.west:
        return f.gridX == 0 ? f : f.copyWith(gridX: 0);
      case RoomWall.east:
        final x = gridCols - f.width;
        return f.gridX == x ? f : f.copyWith(gridX: x);
    }
  }
}
