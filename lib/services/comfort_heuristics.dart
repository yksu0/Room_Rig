// Fact-checked comfort / behavioral heuristics for Auto-Rig + Bench.
//
// Source tiers (honest labeling in UI reasons):
// - agency: OSHA eTools / similar public guidance
// - research: peer-reviewed or classic environmental-psychology theory
// - practice: widely taught interior / HVAC clearances (not a statute)
// - code-adjacent: inspired by egress practice; not claiming IBC compliance
//
// Do NOT cite ISO/ASHRAE/CPTED/WELL as if this app certifies against them.
import 'dart:math';

import '../models/room_model.dart';
import '../models/surface_mount.dart';
import 'layout_collision.dart';

/// Shared scoring + placement cues that Bench and Auto-Rig both use.
class ComfortHeuristics {
  ComfortHeuristics._();

  /// Chair pull-back behind the desk front (~0.9–1.0 m).
  /// Practice clearance for sit/stand and rolling (Panero-style interior
  /// clearances). Not a literal ISO 9241-5 numeric requirement.
  static const chairPullbackMeters = 0.95;

  /// Clear strip inward from the door for entry circulation.
  /// Code-adjacent residential planning habit; IBC/IRC regulate door clear
  /// opening width, not bedroom furniture setbacks.
  static const doorApproachDepth = 1.2;

  /// Keep floor furniture off supply / return / wall AC faces (~6–18 in practice).
  static const hvacClearanceCells = 0.55;

  /// Approximate person radius for circulation (~18 in; Panero; Merrell 2011).
  static const personRadiusCells = 0.45;

  // ── Scores (0–1, higher is more comfortable) ───────────────────────────

  /// Seat can see the entry rather than turn its back to it.
  /// Research preference (Appleton prospect–refuge, 1975; workplace design
  /// practice). Preference, not a safety code.
  static double doorProspectScore({
    required FurnitureItem? chair,
    required FurnitureItem? desk,
    required FurnitureItem? door,
  }) {
    if (chair == null || desk == null || door == null) return 0.55;
    final chairC = _center(chair);
    final deskC = _center(desk);
    final doorC = _center(door);

    var fx = deskC.x - chairC.x;
    var fz = deskC.z - chairC.z;
    final fMag = sqrt(fx * fx + fz * fz);
    if (fMag < 1e-4) return 0.4;
    fx /= fMag;
    fz /= fMag;

    var dx = doorC.x - chairC.x;
    var dz = doorC.z - chairC.z;
    final dMag = sqrt(dx * dx + dz * dz);
    if (dMag < 1e-4) return 0.5;
    dx /= dMag;
    dz /= dMag;

    final facingDot = fx * dx + fz * dz;
    if (facingDot >= 0) {
      return (0.72 + facingDot * 0.28).clamp(0.0, 1.0);
    }
    return (0.55 + facingDot * 0.55).clamp(0.0, 1.0);
  }

  /// Sleep zone not sitting in the door's straight inbound view.
  /// Residential layout research / practice (bedroom privacy from entry;
  /// CAADRIA-style bedroom solvers encode the same heuristic).
  static double bedPrivacyFromDoor({
    required FurnitureItem? bed,
    required FurnitureItem? door,
    required int gridCols,
    required int gridRows,
  }) {
    if (bed == null || door == null) return 0.6;
    final bedC = _center(bed);
    final doorC = _center(door);
    final dx = bedC.x - doorC.x;
    final dz = bedC.z - doorC.z;
    final dist = sqrt(dx * dx + dz * dz);
    final roomDiag = sqrt(gridCols * gridCols + gridRows * gridRows.toDouble());

    // Lateral offset from the door's inbound axis (door faces into room).
    final inward = _doorInward(door, gridCols, gridRows);
    final along = (dx * inward.x + dz * inward.z);
    final cross = (dx * -inward.z + dz * inward.x).abs();

    // Bad: bed directly ahead of the door and close.
    final axialPenalty = along > 0.4
        ? (1.0 - (cross / 2.2).clamp(0.0, 1.0)) * (1.0 - (dist / (roomDiag * 0.55)).clamp(0.0, 1.0))
        : 0.0;
    return (1.0 - axialPenalty * 0.85).clamp(0.0, 1.0);
  }

  /// Desk / seated facing not square-on to the window (side light preferred).
  /// Agency guidance: OSHA Computer Workstations eTools — place the display
  /// at right angles to windows to cut reflected glare.
  static double windowSideLightScore({
    required FurnitureItem? desk,
    required FurnitureItem? chair,
    required FurnitureItem? window,
  }) {
    if (desk == null || window == null) return 0.55;
    final deskC = _center(desk);
    final winC = _center(window);
    final toWinX = winC.x - deskC.x;
    final toWinZ = winC.z - deskC.z;
    final toWinMag = sqrt(toWinX * toWinX + toWinZ * toWinZ);
    if (toWinMag < 1e-4) return 0.4;

    // Facing: chair→desk if present, else assume desk faces +Z (south seat).
    double fx;
    double fz;
    if (chair != null) {
      final chairC = _center(chair);
      fx = deskC.x - chairC.x;
      fz = deskC.z - chairC.z;
    } else {
      fx = 0;
      fz = 1;
    }
    final fMag = sqrt(fx * fx + fz * fz);
    if (fMag < 1e-4) {
      fx = 0;
      fz = 1;
    } else {
      fx /= fMag;
      fz /= fMag;
    }
    final wx = toWinX / toWinMag;
    final wz = toWinZ / toWinMag;
    // |dot| near 0 => window beside seated view (good). |dot| near 1 => front/back (bad).
    final align = (fx * wx + fz * wz).abs();
    return (1.0 - align).clamp(0.0, 1.0);
  }

  /// Large floor pieces not smothering AC / intake / exhaust faces.
  /// HVAC practice: leave ~6–18 in clear at supply and return.
  static double hvacClearanceScore(List<FurnitureItem> furniture) {
    final vents = furniture.where((f) {
      return SurfaceMounts.isVent(f) ||
          SurfaceMounts.isIntake(f) ||
          SurfaceMounts.isExhaust(f);
    }).toList();
    if (vents.isEmpty) return 0.55;

    var clear = 0.0;
    for (final vent in vents) {
      final pad = hvacClearanceCells;
      final zone = (
        minX: vent.gridX - pad,
        minZ: vent.gridY - pad,
        maxX: vent.gridX + vent.width + pad,
        maxZ: vent.gridY + vent.height + pad,
      );
      var blocked = false;
      for (final f in furniture) {
        if (f.id == vent.id) continue;
        if (f.locked && SurfaceMounts.isStructuralMount(f)) continue;
        if (LayoutCollision.skipsFloorOccupancy(f)) continue;
        if (SurfaceMounts.isDeskTopItem(f)) continue;
        if (SurfaceMounts.isVent(f) ||
            SurfaceMounts.isIntake(f) ||
            SurfaceMounts.isExhaust(f) ||
            SurfaceMounts.isDoor(f) ||
            SurfaceMounts.isWindow(f)) {
          continue;
        }
        if (_rectsOverlap(
          zone.minX,
          zone.minZ,
          zone.maxX,
          zone.maxZ,
          f.gridX,
          f.gridY,
          f.gridX + f.width,
          f.gridY + f.height,
        )) {
          blocked = true;
          break;
        }
      }
      clear += blocked ? 0.15 : 1.0;
    }
    return (clear / vents.length).clamp(0.0, 1.0);
  }

  /// Human-readable reason lines (honest source phrasing).
  static List<String> explainLayout(List<FurnitureItem> furniture, {required int gridCols, required int gridRows}) {
    final desk = _first(furniture, SurfaceMounts.isDeskHost);
    final chair = _first(furniture, (f) {
      final hay = '${f.id} ${f.name} ${f.iconName}'.toLowerCase();
      return f.iconName == 'chair' || hay.contains('chair');
    });
    final door = _first(furniture, SurfaceMounts.isDoor);
    final window = _first(furniture, SurfaceMounts.isWindow);
    final bed = _first(furniture, (f) {
      final hay = '${f.id} ${f.name} ${f.iconName}'.toLowerCase();
      return f.iconName == 'bed' || hay.contains('bed');
    });

    final out = <String>[];
    final prospect = doorProspectScore(chair: chair, desk: desk, door: door);
    if (door != null && chair != null && prospect >= 0.65) {
      out.add('Seat keeps the entry in view (prospect–refuge preference)');
    } else if (door != null && chair != null && prospect < 0.45) {
      out.add('Seat turns its back to the door — many people find that uneasy');
    }

    final privacy = bedPrivacyFromDoor(
      bed: bed,
      door: door,
      gridCols: gridCols,
      gridRows: gridRows,
    );
    if (bed != null && door != null && privacy >= 0.7) {
      out.add('Bed sits off the door sightline (sleep-zone privacy)');
    } else if (bed != null && door != null && privacy < 0.45) {
      out.add('Bed is in the door’s inbound view — weak sleep privacy');
    }

    final side = windowSideLightScore(desk: desk, chair: chair, window: window);
    if (window != null && desk != null && side >= 0.55) {
      out.add('Desk/window nearly at right angles (OSHA glare guidance)');
    } else if (window != null && desk != null && side < 0.35) {
      out.add('Desk faces the window axis — higher screen glare risk');
    }

    final hvac = hvacClearanceScore(furniture);
    if (hvac >= 0.75) {
      out.add('HVAC faces stay clear of large furniture (~hand-width gap)');
    } else if (hvac < 0.45) {
      out.add('Furniture crowds AC / vents — supply or return can stall');
    }
    return out;
  }

  static ({double x, double z}) _center(FurnitureItem f) => (
        x: f.gridX + f.width * 0.5,
        z: f.gridY + f.height * 0.5,
      );

  static ({double x, double z}) _doorInward(
    FurnitureItem door,
    int gridCols,
    int gridRows,
  ) {
    final c = _center(door);
    final dN = c.z;
    final dS = gridRows - c.z;
    final dW = c.x;
    final dE = gridCols - c.x;
    final minD = [dN, dS, dW, dE].reduce(min);
    if (minD == dN) return (x: 0, z: 1);
    if (minD == dS) return (x: 0, z: -1);
    if (minD == dW) return (x: 1, z: 0);
    return (x: -1, z: 0);
  }

  static bool _rectsOverlap(
    double ax0,
    double az0,
    double ax1,
    double az1,
    double bx0,
    double bz0,
    double bx1,
    double bz1,
  ) {
    return ax0 < bx1 && ax1 > bx0 && az0 < bz1 && az1 > bz0;
  }

  static FurnitureItem? _first(
    List<FurnitureItem> items,
    bool Function(FurnitureItem) test,
  ) {
    for (final f in items) {
      if (test(f)) return f;
    }
    return null;
  }
}
