// lib/services/airflow_simulator.dart
// Coarse voxel airflow + interactive particle advection for Bench prototype.
import 'dart:math';
import '../models/room_model.dart';
import '../models/surface_mount.dart';

class AirflowVec3 {
  final double x;
  final double y;
  final double z;

  const AirflowVec3(this.x, this.y, this.z);

  AirflowVec3 operator +(AirflowVec3 o) => AirflowVec3(x + o.x, y + o.y, z + o.z);
  AirflowVec3 operator -(AirflowVec3 o) => AirflowVec3(x - o.x, y - o.y, z - o.z);
  AirflowVec3 operator *(double s) => AirflowVec3(x * s, y * s, z * s);

  double get length => sqrt(x * x + y * y + z * z);
  double get lengthSquared => x * x + y * y + z * z;

  AirflowVec3 normalized() {
    final l = length;
    if (l < 1e-6) return const AirflowVec3(0, 0, 0);
    return AirflowVec3(x / l, y / l, z / l);
  }
}

class AirflowBox {
  final AirflowVec3 min;
  final AirflowVec3 max;
  final String id;
  final String label;
  final String kind; // furniture | ac | heat | fan | door | opening | intake | exhaust

  /// Facing yaw in degrees. 0° blows toward +Z (down the floor plan).
  final double yawDegrees;

  /// Relative emitter strength (1.0 = default AC / PC).
  final double strength;

  /// When true, jets aim along [yawDegrees] instead of room-center heuristics.
  final bool directional;

  /// Unit wall-normal pointing into the room. Used by wall devices and openings.
  final double inwardX;
  final double inwardZ;

  /// Openings only: +1 air leaves the room, -1 air enters, 0 idle.
  final double leakSign;

  const AirflowBox({
    required this.min,
    required this.max,
    required this.id,
    required this.label,
    required this.kind,
    this.yawDegrees = 0,
    this.strength = 1.0,
    this.directional = false,
    this.inwardX = 0,
    this.inwardZ = 1,
    this.leakSign = 0,
  });

  AirflowVec3 get center => AirflowVec3(
        (min.x + max.x) * 0.5,
        (min.y + max.y) * 0.5,
        (min.z + max.z) * 0.5,
      );

  bool get isSolidObstacle => kind == 'furniture' || kind == 'heat';

  /// Unit aim on the floor plane from yaw (0° = +Z, 90° = +X).
  AirflowVec3 get yawAim {
    final rad = yawDegrees * pi / 180.0;
    return AirflowVec3(sin(rad), 0, cos(rad));
  }

  AirflowVec3 get inwardAim => AirflowVec3(inwardX, 0, inwardZ);

  /// Room-side flow next to an opening. Outflow pulls toward the wall;
  /// inflow pushes into the room.
  AirflowVec3 get leakFlow => AirflowVec3(inwardX * -leakSign, 0, inwardZ * -leakSign);

  bool contains(AirflowVec3 p, {double pad = 0}) {
    return p.x >= min.x - pad &&
        p.x <= max.x + pad &&
        p.y >= min.y - pad &&
        p.y <= max.y + pad &&
        p.z >= min.z - pad &&
        p.z <= max.z + pad;
  }

  /// Closest point on AABB surface (or inside point if contained).
  AirflowVec3 closestPoint(AirflowVec3 p) {
    return AirflowVec3(
      p.x.clamp(min.x, max.x),
      p.y.clamp(min.y, max.y),
      p.z.clamp(min.z, max.z),
    );
  }
}

class AirflowParticle {
  AirflowVec3 position;
  AirflowVec3 velocity;
  double temperature; // -1 cold .. +1 hot (decays toward ambient 0)
  double age;
  double life;
  final bool isCold;
  final bool isAmbient; // room-volume tracer smoke (PC-case style)
  final int seed;
  final List<AirflowVec3> trail;

  AirflowParticle({
    required this.position,
    required this.velocity,
    required this.temperature,
    required this.age,
    required this.life,
    required this.isCold,
    required this.seed,
    this.isAmbient = false,
    List<AirflowVec3>? trail,
  }) : trail = trail ?? <AirflowVec3>[];

  /// Visual strength — ambient tracers stay faintly visible; others fade with |temp|.
  double get intensity =>
      isAmbient ? 0.42 : temperature.abs().clamp(0.0, 1.0);
}

class AirflowMetrics {
  final double circulationScore;
  final double deadZoneRatio;
  final double heatPocketRatio;
  final double mixingScore;
  final int deadVoxelCount;
  final int heatVoxelCount;
  final int fluidVoxelCount;

  const AirflowMetrics({
    required this.circulationScore,
    required this.deadZoneRatio,
    required this.heatPocketRatio,
    required this.mixingScore,
    required this.deadVoxelCount,
    required this.heatVoxelCount,
    required this.fluidVoxelCount,
  });
}

/// Mass-balance readout for Bench UI — supply vs extract and passive window leak.
class AirflowPressureSummary {
  final double supplyStrength;
  final double extractStrength;
  final double delta;
  final int openingCount;
  final double leakStrengthPerOpening;
  final double leakSign; // +1 out, -1 in, 0 balanced

  const AirflowPressureSummary({
    required this.supplyStrength,
    required this.extractStrength,
    required this.delta,
    required this.openingCount,
    required this.leakStrengthPerOpening,
    required this.leakSign,
  });

  bool get isBalanced => delta.abs() < 0.25 || openingCount == 0;

  String get balanceLabel {
    if (isBalanced) return 'Balanced';
    if (delta > 0) return 'Pressurized';
    return 'Under-pressured';
  }

  String get leakHint {
    if (openingCount == 0) return 'No passive openings in this layout';
    if (isBalanced) return 'Windows idle — intake and extract are matched';
    if (leakSign > 0) {
      return 'Windows/doors leak out (~22% of mismatch)';
    }
    return 'Windows/doors leak in (~22% of mismatch)';
  }
}

class AirflowVoxelField {
  final int nx;
  final int ny;
  final int nz;
  final double roomWidth;
  final double roomHeight;
  final double roomDepth;
  final List<double> vx;
  final List<double> vy;
  final List<double> vz;
  final List<double> temperature;
  final List<bool> solid;
  final List<double> speed;

  AirflowVoxelField({
    required this.nx,
    required this.ny,
    required this.nz,
    required this.roomWidth,
    required this.roomHeight,
    required this.roomDepth,
    required this.vx,
    required this.vy,
    required this.vz,
    required this.temperature,
    required this.solid,
    required this.speed,
  });

  int index(int x, int y, int z) => x + nx * (y + ny * z);

  bool inBounds(int x, int y, int z) =>
      x >= 0 && x < nx && y >= 0 && y < ny && z >= 0 && z < nz;

  AirflowVec3 voxelCenter(int x, int y, int z) {
    return AirflowVec3(
      (x + 0.5) * roomWidth / nx,
      (y + 0.5) * roomHeight / ny,
      (z + 0.5) * roomDepth / nz,
    );
  }

  (int, int, int) worldToVoxel(AirflowVec3 p) {
    final ix = (p.x / roomWidth * nx).floor().clamp(0, nx - 1);
    final iy = (p.y / roomHeight * ny).floor().clamp(0, ny - 1);
    final iz = (p.z / roomDepth * nz).floor().clamp(0, nz - 1);
    return (ix, iy, iz);
  }

  bool isSolidAt(AirflowVec3 p) {
    final (ix, iy, iz) = worldToVoxel(p);
    return solid[index(ix, iy, iz)];
  }

  AirflowVec3 sampleVelocity(AirflowVec3 p) {
    final (ix, iy, iz) = worldToVoxel(p);
    final i = index(ix, iy, iz);
    if (solid[i]) return const AirflowVec3(0, 0, 0);
    return AirflowVec3(vx[i], vy[i], vz[i]);
  }

  double sampleTemperature(AirflowVec3 p) {
    final (ix, iy, iz) = worldToVoxel(p);
    return temperature[index(ix, iy, iz)];
  }
}

class AirflowSimSnapshot {
  final AirflowVoxelField field;
  final List<AirflowBox> boxes;
  final List<AirflowParticle> particles;
  final AirflowMetrics metrics;
  final bool optimized;

  const AirflowSimSnapshot({
    required this.field,
    required this.boxes,
    required this.particles,
    required this.metrics,
    required this.optimized,
  });
}

/// Builds a coarse voxel velocity/temperature field and seeds particles.
class AirflowSimulator {
  static const roomWidth = 6.0;
  static const roomDepth = 8.0;
  static const roomHeight = 2.8;

  static const nx = 18;
  static const ny = 10;
  static const nz = 24;

  static const _trailLength = 14;
  static const _collisionPad = 0.06;

  /// How much of a supply/extract mismatch leaks through a window or door.
  /// Same idea as a PC case: extra intake pressurizes the box so USB/PCI gaps
  /// seep out, extra exhaust starves it so they seep in — never at fan CFM.
  static const openingLeakFraction = 0.22;
  static const openingLeakMax = 0.32;

  /// [optimized] only styles the tracer particles and painter ramps; the solved
  /// field and every metric come from [furniture] alone.
  static AirflowSimSnapshot build({
    required List<FurnitureItem> furniture,
    required bool optimized,
    int particleCount = 120,
    int ambientCount = 220,
  }) {
    final boxes = _buildBoxes(furniture);
    final field = _solveField(boxes);
    final metrics = _computeMetrics(field);
    final particles = _seedParticles(
      field,
      boxes,
      optimized: optimized,
      count: particleCount,
      ambientCount: ambientCount,
    );
    return AirflowSimSnapshot(
      field: field,
      boxes: boxes,
      particles: particles,
      metrics: metrics,
      optimized: optimized,
    );
  }

  /// Supply / extract / passive leak without running the full voxel solve.
  static AirflowPressureSummary summarizePressure(List<FurnitureItem> furniture) {
    final boxes = _buildBoxes(furniture);
    var supply = 0.0;
    var extract = 0.0;
    for (final b in boxes) {
      if (b.kind == 'intake') supply += b.strength;
      if (b.kind == 'exhaust') extract += b.strength;
    }
    final delta = supply - extract;
    final openings = boxes.where((b) => b.kind == 'opening' || b.kind == 'door').toList();
    final leakSign = openings.isNotEmpty ? openings.first.leakSign : 0.0;
    final leakStrength = openings.isNotEmpty ? openings.first.strength : 0.0;
    return AirflowPressureSummary(
      supplyStrength: supply,
      extractStrength: extract,
      delta: delta,
      openingCount: openings.length,
      leakStrengthPerOpening: leakStrength,
      leakSign: leakSign,
    );
  }

  /// Advances particles with buoyancy, decay, furniture collision, and trails.
  static void stepParticles(
    AirflowSimSnapshot snapshot, {
    required double dt,
    required double time,
  }) {
    final field = snapshot.field;
    final boxes = snapshot.boxes;
    final solids = boxes.where((b) => b.isSolidObstacle).toList(growable: false);
    final acs = boxes.where((b) => b.kind == 'ac').toList(growable: false);
    final heats = boxes.where((b) => b.kind == 'heat').toList(growable: false);
    final fans = boxes.where((b) => b.kind == 'fan').toList(growable: false);
    final intakes = boxes.where((b) => b.kind == 'intake').toList(growable: false);
    final exhausts = boxes.where((b) => b.kind == 'exhaust').toList(growable: false);
    final openings = boxes.where((b) => b.kind == 'opening' || b.kind == 'door').toList(growable: false);

    final ambientDecay = snapshot.optimized ? 0.22 : 0.16;
    final buoyancyScale = snapshot.optimized ? 1.15 : 1.0;
    final seconds = time * 0.001;

    for (final p in snapshot.particles) {
      p.age += dt;
      if (p.age >= p.life || (!p.isAmbient && p.intensity < 0.06)) {
        if (p.isAmbient) {
          _respawnAmbient(p, field, time);
        } else {
          _respawnParticle(p, acs, heats, time, snapshot.optimized);
        }
        continue;
      }

      final ageFrac = (p.age / p.life).clamp(0.0, 1.0);

      // --- Forces ---
      var force = field.sampleVelocity(p.position) * (p.isAmbient ? 1.15 : 0.75);

      // Buoyancy: cold sinks, hot rises — stronger near floor/ceiling (stratification).
      if (!p.isAmbient) {
        final yFrac = (p.position.y / roomHeight).clamp(0.0, 1.0);
        final layerBoost = p.isCold ? (1.0 + (1.0 - yFrac) * 0.55) : (1.0 + yFrac * 0.55);
        final buoyancy = p.temperature * 1.38 * buoyancyScale * layerBoost;
        force = force + AirflowVec3(0, buoyancy, 0);
      } else {
        // Ambient smoke gently follows stratified temperature.
        final strat = field.sampleTemperature(p.position);
        force = force + AirflowVec3(0, strat * 0.38, 0);
      }

      // Spreading bloom — cold needs a wider, growing lateral spread (was too tight).
      final n1 = _noise(p.seed, time * 0.001);
      final n2 = _noise(p.seed + 17, time * 0.0013);
      final n3 = _noise(p.seed + 31, time * 0.0009);
      if (p.isAmbient) {
        force = force + AirflowVec3(n1 * 0.08, n3 * 0.04, n2 * 0.08);
      } else if (p.isCold) {
        // Starts as a plume, then opens into a wide floor-level bloom as it ages.
        final bloom = 0.35 + ageFrac * 1.15 + (1.0 - p.intensity) * 0.7;
        force = force + AirflowVec3(n1 * bloom, n3 * 0.12, n2 * bloom);
        // Once low in the room, cold pools and rushes sideways (like heat spreading at ceiling).
        if (p.position.y < 1.15) {
          final radial = AirflowVec3(
            p.position.x - roomWidth * 0.5,
            0,
            p.position.z - roomDepth * 0.5,
          );
          final out = radial.lengthSquared > 0.05
              ? radial.normalized()
              : AirflowVec3(n1, 0, n2).normalized();
          final floorW = (1.15 - p.position.y) / 1.15;
          force = force + out * (0.55 * floorW * (0.4 + ageFrac));
        }
      } else {
        final spread = 0.2 + ageFrac * 0.55 + (1.0 - p.intensity) * 0.35;
        force = force + AirflowVec3(n1 * spread, 0, n2 * spread);
        // Hot spreads under the ceiling.
        if (p.position.y > roomHeight - 1.0) {
          final ceilingW = (p.position.y - (roomHeight - 1.0)) / 1.0;
          force = force + AirflowVec3(n1, 0, n2).normalized() * (0.5 * ceilingW);
        }
      }

      // Source influence: AC cone jet + heat plume entrainment.
      if (!p.isAmbient) {
        for (final ac in acs) {
          final w = _acParticleWeight(ac, p.position, ageFrac);
          if (w <= 0) continue;
          final out = _acEmitDir(ac).normalized();
          final n1c = _noise(p.seed, time * 0.001);
          final n2c = _noise(p.seed + 17, time * 0.0013);
          final cone = AirflowVec3(n1c * 0.42, -0.18 - ageFrac * 0.12, n2c * 0.42);
          force = force + (out + cone).normalized() * (w * (p.isCold ? 1.05 : 0.15));
          if (p.isCold && w > 0.25 && ageFrac < 0.35) {
            p.temperature -= 0.04 * w * dt * 5;
          }
        }
        for (final hot in heats) {
          final inf = _heatFieldInfluence(hot, p.position);
          if (inf.weight <= 0) continue;
          force = force + inf.push * (1.05 * inf.weight);
          if (!p.isCold && ageFrac < 0.45) {
            p.temperature += 0.06 * inf.weight * dt * 7;
          }
        }
      } else {
        // Ambient tracers pick up heat/cold tint when they pass through plumes.
        for (final ac in acs) {
          final d = (p.position - ac.center).length;
          if (d < 2.0) {
            final w = (1.0 - d / 2.0) * ac.strength;
            p.temperature -= 0.35 * w * dt;
            force = force + _acEmitDir(ac).normalized() * (0.45 * w);
          }
        }
        for (final hot in heats) {
          final d = (p.position - hot.center).length;
          if (d < 1.8) {
            final w = (1.0 - d / 1.8) * hot.strength;
            p.temperature += 0.4 * w * dt;
            force = force + _heatEmitDir(hot).normalized() * (0.55 * w);
          }
        }
      }

      // Oscillating stand fan — strong cone push on EVERYTHING in its path
      // (cold, hot, and ambient tracers), like a PC case fan stream.
      for (final fan in fans) {
        final push = _fanOscillateDir(fan, seconds);
        final rel = p.position - fan.center;
        final flat = AirflowVec3(rel.x, 0, rel.z);
        final dist = flat.length;
        if (dist < 3.6 && dist > 0.05) {
          final dir = flat.normalized();
          final align = dir.x * push.x + dir.z * push.z; // cos(theta)
          // ~50° half-angle cone in front of the oscillating aim.
          if (align > 0.55) {
            final along = dist;
            final falloff = (1.0 - along / 3.6).clamp(0.0, 1.0);
            final coneW = ((align - 0.55) / 0.45).clamp(0.0, 1.0);
            final strength =
                falloff * coneW * fan.strength * (snapshot.optimized ? 2.4 : 1.5);
            // Extra punch for thermal parcels so the fan visibly redirects them.
            final thermalBoost = p.isAmbient ? 1.0 : 1.45;
            force = force + push * (strength * thermalBoost);
            // Slight lift/mix in the stream.
            force = force + AirflowVec3(0, 0.12 * strength, 0);
            // Fan mixes temperature toward ambient for anything it hits.
            p.temperature *= (1.0 - 0.28 * strength * dt);
            // Inject streamwise velocity so redirect is immediate.
            p.velocity = p.velocity + push * (strength * 0.35);
          }
        }
      }

      // Dedicated intake: outdoor air pushed into the room along the wall normal.
      for (final vent in intakes) {
        final rel = p.position - vent.center;
        final d = rel.length;
        if (d < 2.6) {
          final w = (1.0 - d / 2.6) * vent.strength;
          force = force + vent.inwardAim.normalized() * (0.85 * w);
        }
      }

      // Dedicated exhaust: pull toward the grille, then leave the room.
      var leftThroughVent = false;
      for (final vent in exhausts) {
        final d = (p.position - vent.center).length;
        if (d < 2.8) {
          final w = (1.0 - d / 2.8) * vent.strength;
          force = force + vent.inwardAim.normalized() * (-0.95 * w);
        }
        if (d < 0.28) leftThroughVent = true;
      }

      // Passive openings seep with room pressure, close to the glass only.
      // Strength is already a fraction of the mismatch — keep the reach short
      // so a window never reads as a second intake/exhaust fan.
      for (final opening in openings) {
        if (opening.leakSign.abs() < 0.01) continue;
        final d = (p.position - opening.center).length;
        if (d < 1.15) {
          final w = exp(-d * 2.1) * opening.strength;
          final flow = opening.leakFlow;
          if (flow.lengthSquared > 1e-6) {
            force = force + flow.normalized() * (0.38 * w);
          }
        }
      }

      if (leftThroughVent) {
        if (p.isAmbient) {
          _respawnAmbient(p, field, time);
        } else {
          _respawnParticle(p, acs, heats, time, snapshot.optimized);
        }
        continue;
      }

      // Obstacle proximity: deflect and wrap around furniture before hard collision.
      force = force + _softObstacleAvoidance(p.position, p.velocity, solids) * 1.4;

      // Integrate velocity with light damping so motion feels continuous.
      p.velocity = (p.velocity * (p.isAmbient ? 0.78 : 0.70)) + (force * (p.isAmbient ? 0.22 : 0.30));
      final speedCap = p.isAmbient
          ? (snapshot.optimized ? 2.2 : 1.7)
          : (snapshot.optimized ? 2.5 : 2.0);
      if (p.velocity.length > speedCap) {
        p.velocity = p.velocity.normalized() * speedCap;
      }

      var next = p.position + p.velocity * dt;

      // Room walls.
      next = _resolveWalls(next, p);

      // Hard furniture collisions — slide along faces.
      next = _resolveFurnitureCollisions(next, p, solids);

      // Voxel solid fallback (in case rasterized solids differ slightly).
      if (field.isSolidAt(next)) {
        next = _slideOutOfSolid(field, p.position, next);
      }

      p.position = next;

      // Temperature: mix toward ambient + local field, with gradual decay.
      final localTemp = field.sampleTemperature(p.position);
      if (p.isAmbient) {
        p.temperature += (localTemp - p.temperature) * 0.14;
        p.temperature *= (1.0 - 0.14 * dt);
      } else {
        // Faster exchange at hot/cold fronts (thermal mixing).
        final frontMix = (localTemp * p.temperature < 0) ? 0.22 : 0.06;
        p.temperature += (localTemp - p.temperature) * frontMix;
        var decay = ambientDecay;
        if (p.isCold) {
          decay += 0.1 + ageFrac * 0.22;
          if (p.position.y < 0.95) decay += 0.14; // floor pool neutralizes
        } else {
          decay += ageFrac * 0.12;
          if (p.position.y > roomHeight - 0.75) decay += 0.22; // ceiling layer mixes out
        }
        p.temperature *= (1.0 - decay * dt);
      }
      p.temperature = p.temperature.clamp(-1.2, 1.2);

      // Trail for collision / flow visualization.
      p.trail.add(p.position);
      final trailMax = p.isAmbient ? 10 : _trailLength;
      while (p.trail.length > trailMax) {
        p.trail.removeAt(0);
      }
    }
  }

  /// Public aim vector for viz — stand fan / directional cooler sweeps ±45°
  /// around the item's yaw (or room-center if undirected).
  static AirflowVec3 fanAimDirection(AirflowBox fan, double timeMs) {
    return _fanOscillateDir(fan, timeMs * 0.001);
  }

  /// Oscillates ±45° around the fan's facing yaw (0° = +Z, matching [AirflowBox.yawAim]).
  static AirflowVec3 _fanOscillateDir(AirflowBox fan, double seconds) {
    double baseAngle;
    if (fan.directional || fan.yawDegrees.abs() > 0.5) {
      baseAngle = fan.yawDegrees * pi / 180.0;
    } else {
      final base = AirflowVec3(
        roomWidth * 0.5 - fan.center.x,
        0.05,
        roomDepth * 0.5 - fan.center.z,
      );
      // atan2(x, z): angle from +Z toward +X, same basis as yawAim.
      baseAngle = base.lengthSquared < 1e-4 ? 0.0 : atan2(base.x, base.z);
    }
    // Full left-right cycle ~3.5s — common pedestal oscillation feel.
    final sweep = sin(seconds * (2 * pi / 3.5)) * (pi / 4);
    final angle = baseAngle + sweep;
    return AirflowVec3(sin(angle), 0.08, cos(angle));
  }

  static AirflowVec3 _acEmitDir(AirflowBox ac) {
    // Portable / aimed coolers blow along yaw.
    if (ac.directional) {
      final aim = ac.yawAim;
      return AirflowVec3(aim.x, -0.28, aim.z);
    }
    // Wall units blow into the room along the wall normal, not toward a window.
    if (ac.inwardX.abs() + ac.inwardZ.abs() > 0.05) {
      return AirflowVec3(ac.inwardX, -0.28, ac.inwardZ);
    }
    return AirflowVec3(
      roomWidth * 0.5 - ac.center.x,
      -0.25,
      roomDepth * 0.5 - ac.center.z,
    );
  }

  static AirflowVec3 _heatEmitDir(AirflowBox hot) {
    if (hot.directional) {
      final aim = hot.yawAim;
      return AirflowVec3(aim.x * 0.35, 0.75, aim.z * 0.35);
    }
    return const AirflowVec3(0, 1.0, 0);
  }

  /// Cone-weight for a wall AC jet — cold air throws forward then drops (displacement cooling).
  static ({double weight, AirflowVec3 push}) _acFieldInfluence(AirflowBox ac, AirflowVec3 c) {
    final rel = c - ac.center;
    final emit = _acEmitDir(ac);
    final emitLen = emit.length;
    if (emitLen < 1e-5) return (weight: 0, push: const AirflowVec3(0, 0, 0));
    final dir = AirflowVec3(emit.x / emitLen, emit.y / emitLen, emit.z / emitLen);
    final along = rel.x * dir.x + rel.y * dir.y + rel.z * dir.z;
    if (along < 0) return (weight: 0, push: const AirflowVec3(0, 0, 0));

    final reach = 3.5 * (0.85 + 0.15 * ac.strength);
    if (along > reach) return (weight: 0, push: const AirflowVec3(0, 0, 0));

    final axial = dir * along;
    final latX = rel.x - axial.x;
    final latY = rel.y - axial.y;
    final latZ = rel.z - axial.z;
    final latDist = sqrt(latX * latX + latY * latY * 0.35 + latZ * latZ);
    final coneRadius = 0.22 + along * 0.42;
    if (latDist > coneRadius) return (weight: 0, push: const AirflowVec3(0, 0, 0));

    final cone = (1 - latDist / coneRadius).clamp(0.0, 1.0);
    final axialFall = (1 - along / reach).clamp(0.0, 1.0);
    // Dense cold supply sinks as it travels — classic high-wall supply behavior.
    final drop = AirflowVec3(dir.x, dir.y - 0.22 - along * 0.14, dir.z);
    final w = cone * axialFall * ac.strength;
    return (weight: w, push: drop.normalized());
  }

  /// Buoyant plume for PC / radiator / passive heat — narrow at source, spreads aloft.
  static ({double weight, AirflowVec3 push}) _heatFieldInfluence(AirflowBox hot, AirflowVec3 c) {
    if (hot.directional) {
      final d = (c - hot.center).length;
      final reach = 2.5 * (0.85 + 0.15 * hot.strength);
      if (d > reach) return (weight: 0, push: const AirflowVec3(0, 0, 0));
      final w = (1 - d / reach) * hot.strength;
      return (weight: w, push: _heatEmitDir(hot).normalized());
    }

    final dx = c.x - hot.center.x;
    final dz = c.z - hot.center.z;
    final horiz = sqrt(dx * dx + dz * dz);
    final above = c.y - hot.center.y;
    if (above < -0.2) return (weight: 0, push: const AirflowVec3(0, 0, 0));

    final reach = 2.9 * (0.85 + 0.15 * hot.strength);
    if (above > reach) return (weight: 0, push: const AirflowVec3(0, 0, 0));

    // Plume widens with height (entrainment); cap radius for small sources.
    final plumeRadius = (0.24 + above * 0.48).clamp(0.22, 1.55);
    if (horiz > plumeRadius) return (weight: 0, push: const AirflowVec3(0, 0, 0));

    final radial = (1 - horiz / plumeRadius).clamp(0.0, 1.0);
    final vertical = (1 - above / reach).clamp(0.0, 1.0);
    final w = radial * vertical * hot.strength;

    // Mushroom cap: upper plume spreads outward; lower plume rises fast.
    final spread = above > reach * 0.5 ? 0.42 : 0.08;
    final horizNorm = horiz > 0.02 ? horiz : 0.02;
    final push = AirflowVec3(
      (dx / horizNorm) * spread,
      0.72 + above * 0.12,
      (dz / horizNorm) * spread,
    ).normalized();
    return (weight: w, push: push);
  }

  /// Particle-side AC cone (matches field jet, wider near grille).
  static double _acParticleWeight(AirflowBox ac, AirflowVec3 p, double ageFrac) {
    final rel = p - ac.center;
    final emit = _acEmitDir(ac).normalized();
    final along = rel.x * emit.x + rel.y * emit.y + rel.z * emit.z;
    if (along < 0 || along > 3.4) return 0;
    final axial = emit * along;
    final lat = rel - axial;
    final latDist = sqrt(lat.x * lat.x + lat.z * lat.z + lat.y * lat.y * 0.4);
    final coneR = 0.3 + along * 0.45 + ageFrac * 0.25;
    if (latDist > coneR) return 0;
    return (1 - latDist / coneR) * (1 - along / 3.6) * (1 - ageFrac * 0.55) * ac.strength;
  }

  /// Boussinesq-style coupling after diffusion — hot rises, cold sinks.
  static void _applyBuoyancyCoupling(
    List<double> vx,
    List<double> vy,
    List<double> vz,
    List<double> temperature,
    List<bool> solid,
  ) {
    for (int z = 0; z < nz; z++) {
      for (int y = 0; y < ny; y++) {
        for (int x = 0; x < nx; x++) {
          final i = x + nx * (y + ny * z);
          if (solid[i]) continue;
          final t = temperature[i];
          if (t.abs() < 0.04) continue;
          final yFrac = (y + 0.5) / ny;
          final layer = t > 0 ? (0.4 + yFrac * 0.6) : (0.45 + (1 - yFrac) * 0.55);
          vy[i] += t.sign * 0.16 * layer * t.abs().clamp(0.0, 1.0);
          // Weak horizontal drift from thermal expansion at ceiling / floor pooling.
          if (t.abs() > 0.35) {
            final cx = (x + 0.5) / nx - 0.5;
            final cz = (z + 0.5) / nz - 0.5;
            vx[i] += cx * t * 0.06;
            vz[i] += cz * t * 0.06;
          }
        }
      }
    }
  }

  static AirflowVec3 _fanBasePush(AirflowBox fan) {
    if (fan.directional || fan.yawDegrees.abs() > 0.5) return fan.yawAim;
    return AirflowVec3(
      roomWidth * 0.5 - fan.center.x,
      0.05,
      roomDepth * 0.5 - fan.center.z,
    );
  }

  static AirflowVec3 _softObstacleAvoidance(
    AirflowVec3 p,
    AirflowVec3 vel,
    List<AirflowBox> solids,
  ) {
    var push = const AirflowVec3(0, 0, 0);
    for (final b in solids) {
      final nearest = b.closestPoint(p);
      final away = p - nearest;
      final d = away.length;
      if (d < 0.001) {
        // Inside: strong outward from center.
        push = push + (p - b.center).normalized() * 1.8;
      } else if (d < 0.55) {
        final n = away.normalized();
        final w = (0.55 - d) / 0.55;
        push = push + n * (1.2 * w);
        // Keep the component that slides around the face so air wraps instead of stalling.
        final into = vel.x * n.x + vel.z * n.z;
        var tangent = AirflowVec3(vel.x - n.x * into, 0, vel.z - n.z * into);
        if (tangent.lengthSquared < 1e-5) {
          tangent = AirflowVec3(-n.z, 0, n.x);
        }
        push = push + tangent.normalized() * (0.65 * w);
      }
    }
    return push;
  }

  static AirflowVec3 _resolveWalls(AirflowVec3 next, AirflowParticle p) {
    var x = next.x;
    var y = next.y;
    var z = next.z;
    var vx = p.velocity.x;
    var vy = p.velocity.y;
    var vz = p.velocity.z;

    if (x < 0.08) {
      x = 0.08;
      vx = vx.abs() * 0.4;
    } else if (x > roomWidth - 0.08) {
      x = roomWidth - 0.08;
      vx = -vx.abs() * 0.4;
    }
    if (y < 0.08) {
      y = 0.08;
      vy = vy.abs() * 0.25; // cold pools then slides along floor
    } else if (y > roomHeight - 0.08) {
      y = roomHeight - 0.08;
      vy = -vy.abs() * 0.35; // hot hits ceiling and spreads
    }
    if (z < 0.08) {
      z = 0.08;
      vz = vz.abs() * 0.4;
    } else if (z > roomDepth - 0.08) {
      z = roomDepth - 0.08;
      vz = -vz.abs() * 0.4;
    }

    p.velocity = AirflowVec3(vx, vy, vz);
    return AirflowVec3(x, y, z);
  }

  static AirflowVec3 _resolveFurnitureCollisions(
    AirflowVec3 next,
    AirflowParticle p,
    List<AirflowBox> solids,
  ) {
    var pos = next;
    for (final b in solids) {
      if (!b.contains(pos, pad: _collisionPad)) continue;

      // Push out along the shallowest penetration axis.
      final cx = ((b.min.x + b.max.x) * 0.5);
      final cz = ((b.min.z + b.max.z) * 0.5);

      final penLeft = pos.x - (b.min.x - _collisionPad);
      final penRight = (b.max.x + _collisionPad) - pos.x;
      final penBottom = pos.y - (b.min.y - _collisionPad);
      final penTop = (b.max.y + _collisionPad) - pos.y;
      final penFront = pos.z - (b.min.z - _collisionPad);
      final penBack = (b.max.z + _collisionPad) - pos.z;

      final minPen = [
        (penLeft, AirflowVec3(-1, 0, 0)),
        (penRight, AirflowVec3(1, 0, 0)),
        (penBottom, AirflowVec3(0, -1, 0)),
        (penTop, AirflowVec3(0, 1, 0)),
        (penFront, AirflowVec3(0, 0, -1)),
        (penBack, AirflowVec3(0, 0, 1)),
      ].reduce((a, b) => a.$1 < b.$1 ? a : b);

      final normal = minPen.$2;
      pos = pos + normal * (minPen.$1 + 0.02);

      // Kill velocity into the surface; keep tangential slide + slight lift/drop.
      final into = p.velocity.x * -normal.x + p.velocity.y * -normal.y + p.velocity.z * -normal.z;
      if (into > 0) {
        p.velocity = p.velocity + normal * into; // remove inward component
      }
      // Tangential boost so air visibly wraps around furniture.
      final tangent = AirflowVec3(
        (pos.x - cx) * 0.15,
        p.isCold ? -0.08 : 0.12,
        (pos.z - cz) * 0.15,
      );
      p.velocity = p.velocity + tangent;

      // Contact with furniture slightly mixes temperature toward ambient.
      p.temperature *= 0.92;
    }
    return pos;
  }

  static AirflowVec3 _slideOutOfSolid(AirflowVoxelField field, AirflowVec3 from, AirflowVec3 to) {
    // Binary search back toward free space.
    var a = from;
    var b = to;
    for (int i = 0; i < 6; i++) {
      final m = AirflowVec3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, (a.z + b.z) * 0.5);
      if (field.isSolidAt(m)) {
        b = m;
      } else {
        a = m;
      }
    }
    final (ix, iy, iz) = field.worldToVoxel(a);
    return _findFreeNeighbor(field, ix, iy, iz) ?? a;
  }

  static double _noise(int seed, double t) {
    final v = sin(seed * 12.9898 + t * 78.233) * 43758.5453;
    return (v - v.floorToDouble()) * 2.0 - 1.0;
  }

  static List<AirflowBox> _buildBoxes(List<FurnitureItem> furniture) {
    final boxes = <AirflowBox>[];
    for (final f in furniture) {
      final kind = _classify(f);
      final meta = _emitMeta(f, kind);
      final height = _itemHeight(f, kind);
      final yaw = f.yawDegrees;
      final span = _wallSpan(f);

      if (kind == 'ac') {
        if (meta.floorStanding) {
          boxes.add(
            AirflowBox(
              min: AirflowVec3(f.gridX, 0, f.gridY),
              max: AirflowVec3(f.gridX + f.width, height, f.gridY + f.height),
              id: f.id,
              label: f.name,
              kind: kind,
              yawDegrees: yaw,
              strength: meta.strength,
              directional: true,
            ),
          );
        } else {
          boxes.add(_wallBandBox(
            f: f,
            span: span,
            kind: kind,
            bottomY: 1.4,
            topY: 2.3,
            strength: meta.strength,
          ));
        }
      } else if (kind == 'opening' || kind == 'door') {
        boxes.add(_wallBandBox(
          f: f,
          span: span,
          kind: kind,
          bottomY: kind == 'door' ? 0.0 : 0.9,
          topY: 2.1,
          strength: 0,
        ));
      } else if (kind == 'intake' || kind == 'exhaust') {
        boxes.add(_wallBandBox(
          f: f,
          span: span,
          kind: kind,
          bottomY: 1.4,
          topY: 2.3,
          strength: meta.strength,
        ));
      } else if (kind == 'fan') {
        boxes.add(
          AirflowBox(
            min: AirflowVec3(f.gridX + 0.2, 0, f.gridY + 0.2),
            max: AirflowVec3(f.gridX + 0.55, height, f.gridY + 0.55),
            id: f.id,
            label: f.name,
            kind: kind,
            yawDegrees: yaw,
            strength: meta.strength,
            directional: true,
          ),
        );
      } else {
        boxes.add(
          AirflowBox(
            min: AirflowVec3(f.gridX, 0, f.gridY),
            max: AirflowVec3(f.gridX + f.width, height, f.gridY + f.height),
            id: f.id,
            label: f.name,
            kind: kind,
            yawDegrees: yaw,
            strength: meta.strength,
            directional: meta.directional,
          ),
        );
      }
    }

    return _applyOpeningPressure(boxes);
  }

  static WallSpan _wallSpan(FurnitureItem f) {
    return SurfaceMounts.spanFor(
      f,
      gridCols: roomWidth.round().clamp(1, 64),
      gridRows: roomDepth.round().clamp(1, 64),
    );
  }

  static AirflowBox _wallBandBox({
    required FurnitureItem f,
    required WallSpan span,
    required String kind,
    required double bottomY,
    required double topY,
    required double strength,
  }) {
    const thick = 0.22;
    final x0 = min(span.x0, span.x1);
    final x1 = max(span.x0, span.x1);
    final z0 = min(span.z0, span.z1);
    final z1 = max(span.z0, span.z1);
    return AirflowBox(
      min: AirflowVec3(
        min(x0, x0 + span.inwardX * thick),
        bottomY,
        min(z0, z0 + span.inwardZ * thick),
      ),
      max: AirflowVec3(
        max(x1, x1 + span.inwardX * thick),
        topY,
        max(z1, z1 + span.inwardZ * thick),
      ),
      id: f.id,
      label: f.name,
      kind: kind,
      yawDegrees: f.yawDegrees,
      strength: strength,
      inwardX: span.inwardX,
      inwardZ: span.inwardZ,
    );
  }

  /// Windows and doors leak with the room's mass balance. Recirculating AC
  /// does not pressurize the room; only dedicated intake / exhaust does.
  /// The leak is a fraction of the mismatch, split across every opening.
  static List<AirflowBox> _applyOpeningPressure(List<AirflowBox> boxes) {
    var supply = 0.0;
    var extract = 0.0;
    for (final b in boxes) {
      if (b.kind == 'intake') supply += b.strength;
      if (b.kind == 'exhaust') extract += b.strength;
    }
    final delta = supply - extract;
    final openings = boxes.where((b) => b.kind == 'opening' || b.kind == 'door').toList();
    var leakSign = 0.0;
    var leakStrength = 0.0;
    if (delta.abs() >= 0.25 && openings.isNotEmpty) {
      leakSign = delta > 0 ? 1.0 : -1.0;
      leakStrength =
          (delta.abs() * openingLeakFraction / openings.length).clamp(0.0, openingLeakMax);
    }
    return [
      for (final b in boxes)
        if (b.kind == 'opening' || b.kind == 'door')
          AirflowBox(
            min: b.min,
            max: b.max,
            id: b.id,
            label: b.label,
            kind: b.kind,
            yawDegrees: b.yawDegrees,
            strength: leakStrength,
            inwardX: b.inwardX,
            inwardZ: b.inwardZ,
            leakSign: leakSign,
          )
        else
          b,
    ];
  }

  /// Strength / aim profile for thermal and fan emitters.
  static ({double strength, bool directional, bool floorStanding}) _emitMeta(
    FurnitureItem f,
    String kind,
  ) {
    final id = f.id.toLowerCase();
    final name = f.name.toLowerCase();

    if (kind == 'ac') {
      if (id.contains('portable') ||
          name.contains('portable') ||
          id.contains('evaporative') ||
          name.contains('evaporative') ||
          id.contains('cooler') ||
          (name.contains('cooler') && !name.contains('wall'))) {
        final evaporative = id.contains('evaporative') || name.contains('evaporative');
        return (
          strength: evaporative ? 0.55 : 0.75,
          directional: true,
          floorStanding: true,
        );
      }
      return (strength: 1.0, directional: false, floorStanding: false);
    }

    if (kind == 'heat') {
      if (id.contains('radiator') || name.contains('radiator')) {
        return (strength: 1.15, directional: false, floorStanding: true);
      }
      if (id.contains('heater') || name.contains('heater')) {
        return (strength: 0.9, directional: true, floorStanding: true);
      }
      if (id.contains('nas') ||
          id.contains('server') ||
          name.contains('nas') ||
          name.contains('server')) {
        return (strength: 1.25, directional: false, floorStanding: true);
      }
      if (id.contains('console') || name.contains('console')) {
        return (strength: 0.45, directional: false, floorStanding: true);
      }
      if (id.contains('fridge') || name.contains('fridge')) {
        // Compressor waste heat — mild plume, not a jet.
        return (strength: 0.35, directional: false, floorStanding: true);
      }
      // Default PC / tower.
      return (strength: 1.0, directional: false, floorStanding: true);
    }

    if (kind == 'fan') {
      if (id.contains('desk') || name.contains('desk fan')) {
        return (strength: 0.7, directional: true, floorStanding: true);
      }
      return (strength: 1.0, directional: true, floorStanding: true);
    }

    if (kind == 'intake') {
      return (strength: 1.0, directional: false, floorStanding: false);
    }
    if (kind == 'exhaust') {
      return (strength: 1.0, directional: false, floorStanding: false);
    }

    return (strength: 1.0, directional: false, floorStanding: false);
  }

  static String _classify(FurnitureItem f) {
    final id = f.id.toLowerCase();
    final name = f.name.toLowerCase();
    final icon = f.iconName.toLowerCase();

    if (_isColdEmitter(id: id, name: name, icon: icon)) return 'ac';
    if (SurfaceMounts.isExhaust(f)) return 'exhaust';
    if (SurfaceMounts.isIntake(f)) return 'intake';
    if (name.contains('window') || id.contains('window') || icon == 'window') {
      return 'opening';
    }
    if (name.contains('door') || id.contains('door') || icon == 'door') {
      return 'door';
    }
    if (_isHeatEmitter(id: id, name: name, icon: icon)) return 'heat';
    if (icon == 'fan' ||
        id.contains('fan') ||
        name.contains('fan') ||
        name.contains('circulator')) {
      return 'fan';
    }
    return 'furniture';
  }

  /// Stricter than bare `contains('ac')` so words like "rack" do not match.
  static bool _isColdEmitter({
    required String id,
    required String name,
    required String icon,
  }) {
    if (icon == 'ac' || icon == 'acunit') return true;
    if (id == 'ac' || id.startsWith('ac_') || id.contains('portable_ac')) {
      return true;
    }
    if (id.contains('evaporative') || id.contains('cooler')) return true;
    if (name.contains('air condition') ||
        name.contains('aircon') ||
        name.contains('a/c') ||
        name.contains('portable ac') ||
        name.contains('evaporative') ||
        name == 'ac' ||
        name.endsWith(' ac')) {
      return true;
    }
    if (name.contains('cooler') && !name.contains('beverage')) return true;
    return false;
  }

  static bool _isHeatEmitter({
    required String id,
    required String name,
    required String icon,
  }) {
    if (icon == 'pc') return true;
    if (id == 'pc' ||
        id.startsWith('pc_') ||
        id.contains('nas') ||
        id.contains('server') ||
        id.contains('console') ||
        id.contains('heater') ||
        id.contains('radiator') ||
        id.contains('mini_fridge') ||
        id.contains('fridge')) {
      return true;
    }
    if (name.contains('pc tower') ||
        name.contains('computer') ||
        name.contains('gaming console') ||
        name.contains('nas') ||
        name.contains('server') ||
        name.contains('space heater') ||
        name.contains('radiator') ||
        name.contains('mini fridge') ||
        name.contains('fridge')) {
      return true;
    }
    // Bare "tower" only with PC-ish context.
    if ((name.contains('tower') || id.contains('tower')) &&
        (name.contains('pc') || id.contains('pc') || icon == 'pc')) {
      return true;
    }
    return false;
  }

  static double _itemHeight(FurnitureItem f, String kind) {
    final id = f.id.toLowerCase();
    final name = f.name.toLowerCase();
    switch (kind) {
      case 'heat':
        if (id.contains('console') || name.contains('console')) return 0.55;
        if (id.contains('fridge') || name.contains('fridge')) return 0.95;
        if (id.contains('heater') || name.contains('heater')) return 0.75;
        if (id.contains('radiator') || name.contains('radiator')) return 0.7;
        if (id.contains('nas') || name.contains('nas')) return 0.45;
        return 1.35;
      case 'fan':
        if (id.contains('desk') || name.contains('desk fan')) return 0.45;
        return 1.1;
      case 'ac':
        if (id.contains('portable') ||
            name.contains('portable') ||
            id.contains('evaporative') ||
            name.contains('evaporative') ||
            id.contains('cooler') ||
            name.contains('cooler')) {
          return 0.85;
        }
        return 2.3;
      default:
        // Beds / desks / shelves need real collision volume.
        if (f.id == 'bed') return 0.85;
        if (f.id == 'desk') return 0.75;
        if (f.id == 'shelf' || f.id == 'bookshelf') return 1.7;
        if (f.id == 'chair') return 1.05;
        return (0.55 + f.ergonomicsImpact.abs() * 0.55 + f.height * 0.15).clamp(0.45, 1.9);
    }
  }

  /// Physics here depends on furniture placement alone — no "this is the good
  /// layout" tuning — so circulation scores are comparable between variants.
  static AirflowVoxelField _solveField(List<AirflowBox> boxes) {
    final count = nx * ny * nz;
    final solid = List<bool>.filled(count, false);
    final vx = List<double>.filled(count, 0);
    final vy = List<double>.filled(count, 0);
    final vz = List<double>.filled(count, 0);
    final temperature = List<double>.filled(count, 0);
    final speed = List<double>.filled(count, 0);

    for (final b in boxes) {
      if (b.kind == 'ac' ||
          b.kind == 'opening' ||
          b.kind == 'door' ||
          b.kind == 'fan' ||
          b.kind == 'intake' ||
          b.kind == 'exhaust') {
        continue;
      }
      _rasterizeSolid(solid, b);
    }

    final acs = boxes.where((b) => b.kind == 'ac').toList();
    final heats = boxes.where((b) => b.kind == 'heat').toList();
    final fans = boxes.where((b) => b.kind == 'fan').toList();
    final intakes = boxes.where((b) => b.kind == 'intake').toList();
    final exhausts = boxes.where((b) => b.kind == 'exhaust').toList();
    final openings = boxes.where((b) => b.kind == 'opening' || b.kind == 'door').toList();

    // Room-scale circulation only from furniture that is actually present.
    // Recirculating AC does not drag the whole field toward a window.

    for (int z = 0; z < nz; z++) {
      for (int y = 0; y < ny; y++) {
        for (int x = 0; x < nx; x++) {
          final i = x + nx * (y + ny * z);
          if (solid[i]) continue;
          final c = AirflowVec3(
            (x + 0.5) * roomWidth / nx,
            (y + 0.5) * roomHeight / ny,
            (z + 0.5) * roomDepth / nz,
          );

          var force = const AirflowVec3(0, 0, 0);

          for (final ac in acs) {
            final inf = _acFieldInfluence(ac, c);
            if (inf.weight <= 0) continue;
            force = force + inf.push * (0.72 * inf.weight);
            // Cold supply cools and sinks along the jet path.
            temperature[i] -= 0.75 * inf.weight;
            force = force + AirflowVec3(0, -0.35 * inf.weight, 0);
          }

          for (final hot in heats) {
            final inf = _heatFieldInfluence(hot, c);
            if (inf.weight <= 0) continue;
            force = force + inf.push * (0.95 * inf.weight);
            temperature[i] += 1.05 * inf.weight;
          }

          for (final fan in fans) {
            final d = (c - fan.center).length;
            if (d < 2.8) {
              // Static field uses yaw when set; otherwise toward room center.
              final push = _fanBasePush(fan).normalized();
              force = force + push * (0.45 * (1 - d / 2.8) * fan.strength);
            }
          }

          for (final vent in intakes) {
            final d = (c - vent.center).length;
            if (d < 2.6) {
              force = force +
                  vent.inwardAim.normalized() * (0.7 * (1 - d / 2.6) * vent.strength);
            }
          }

          for (final vent in exhausts) {
            final d = (c - vent.center).length;
            if (d < 2.8) {
              force = force +
                  vent.inwardAim.normalized() * (-0.75 * (1 - d / 2.8) * vent.strength);
            }
          }

          for (final opening in openings) {
            if (opening.leakSign.abs() < 0.01) continue;
            final d = (c - opening.center).length;
            if (d > 1.2) continue;
            final flow = opening.leakFlow;
            if (flow.lengthSquared < 1e-6) continue;
            force = force + flow.normalized() * (0.28 * exp(-d * 2.0) * opening.strength);
          }

          // Obstacle-aware: weaken flow that would punch through nearby solids,
          // and add a wrap component so air goes around furniture.
          final steer = _fieldObstacleSteer(c, solid, x, y, z);
          force = force + steer * 0.9;
          if (steer.lengthSquared > 1e-6 && force.lengthSquared > 1e-6) {
            var around = AirflowVec3(-steer.z, 0, steer.x);
            if (around.x * force.x + around.z * force.z < 0) {
              around = around * -1;
            }
            force = force + around.normalized() * 0.22;
          }

          // Stratification: warm air gains upward bias, cold air sinks.
          force = force + AirflowVec3(0, temperature[i] * 0.18, 0);

          vx[i] = force.x;
          vy[i] = force.y;
          vz[i] = force.z;
        }
      }
    }

    const iterations = 9;
    for (int iter = 0; iter < iterations; iter++) {
      _diffuse(vx, vy, vz, temperature, solid, strength: 0.3);
      _diffuseTemperatureOnly(temperature, solid, strength: 0.48);
    }
    _applyBuoyancyCoupling(vx, vy, vz, temperature, solid);
    // One more gentle temperature pass after buoyancy redistributes flow.
    _diffuseTemperatureOnly(temperature, solid, strength: 0.22);

    for (int i = 0; i < count; i++) {
      if (solid[i]) {
        vx[i] = 0;
        vy[i] = 0;
        vz[i] = 0;
        temperature[i] = 0;
        speed[i] = 0;
      } else {
        speed[i] = sqrt(vx[i] * vx[i] + vy[i] * vy[i] + vz[i] * vz[i]);
        temperature[i] = temperature[i].clamp(-1.2, 1.2);
      }
    }

    return AirflowVoxelField(
      nx: nx,
      ny: ny,
      nz: nz,
      roomWidth: roomWidth,
      roomHeight: roomHeight,
      roomDepth: roomDepth,
      vx: vx,
      vy: vy,
      vz: vz,
      temperature: temperature,
      solid: solid,
      speed: speed,
    );
  }

  static AirflowVec3 _fieldObstacleSteer(AirflowVec3 c, List<bool> solid, int x, int y, int z) {
    var steer = const AirflowVec3(0, 0, 0);
    const dirs = [
      (1, 0, 0),
      (-1, 0, 0),
      (0, 1, 0),
      (0, -1, 0),
      (0, 0, 1),
      (0, 0, -1),
    ];
    for (final d in dirs) {
      final xi = x + d.$1;
      final yi = y + d.$2;
      final zi = z + d.$3;
      if (xi < 0 || xi >= nx || yi < 0 || yi >= ny || zi < 0 || zi >= nz) continue;
      if (solid[xi + nx * (yi + ny * zi)]) {
        steer = steer + AirflowVec3(-d.$1.toDouble(), -d.$2.toDouble(), -d.$3.toDouble());
      }
    }
    return steer.normalized() * 0.55;
  }

  static void _rasterizeSolid(List<bool> solid, AirflowBox box) {
    final x0 = (box.min.x / roomWidth * nx).floor().clamp(0, nx - 1);
    final x1 = (box.max.x / roomWidth * nx).ceil().clamp(0, nx);
    final y0 = (box.min.y / roomHeight * ny).floor().clamp(0, ny - 1);
    final y1 = (box.max.y / roomHeight * ny).ceil().clamp(0, ny);
    final z0 = (box.min.z / roomDepth * nz).floor().clamp(0, nz - 1);
    final z1 = (box.max.z / roomDepth * nz).ceil().clamp(0, nz);

    for (int z = z0; z < z1; z++) {
      for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
          solid[x + nx * (y + ny * z)] = true;
        }
      }
    }
  }

  static void _diffuse(
    List<double> vx,
    List<double> vy,
    List<double> vz,
    List<double> temperature,
    List<bool> solid, {
    required double strength,
  }) {
    final nvx = List<double>.from(vx);
    final nvy = List<double>.from(vy);
    final nvz = List<double>.from(vz);
    final nt = List<double>.from(temperature);

    for (int z = 1; z < nz - 1; z++) {
      for (int y = 1; y < ny - 1; y++) {
        for (int x = 1; x < nx - 1; x++) {
          final i = x + nx * (y + ny * z);
          if (solid[i]) continue;

          double sx = 0, sy = 0, sz = 0, st = 0;
          int n = 0;
          void accum(int xi, int yi, int zi) {
            final j = xi + nx * (yi + ny * zi);
            if (solid[j]) return;
            sx += vx[j];
            sy += vy[j];
            sz += vz[j];
            st += temperature[j];
            n++;
          }

          accum(x - 1, y, z);
          accum(x + 1, y, z);
          accum(x, y - 1, z);
          accum(x, y + 1, z);
          accum(x, y, z - 1);
          accum(x, y, z + 1);

          if (n == 0) continue;
          nvx[i] = vx[i] * (1 - strength) + (sx / n) * strength;
          nvy[i] = vy[i] * (1 - strength) + (sy / n) * strength;
          nvz[i] = vz[i] * (1 - strength) + (sz / n) * strength;
          nt[i] = temperature[i] * (1 - strength) + (st / n) * strength;
        }
      }
    }

    for (int i = 0; i < vx.length; i++) {
      vx[i] = nvx[i];
      vy[i] = nvy[i];
      vz[i] = nvz[i];
      temperature[i] = nt[i];
    }
  }

  static void _diffuseTemperatureOnly(List<double> temperature, List<bool> solid, {required double strength}) {
    final nt = List<double>.from(temperature);
    for (int z = 1; z < nz - 1; z++) {
      for (int y = 1; y < ny - 1; y++) {
        for (int x = 1; x < nx - 1; x++) {
          final i = x + nx * (y + ny * z);
          if (solid[i]) continue;
          double st = 0;
          int n = 0;
          void accum(int xi, int yi, int zi) {
            final j = xi + nx * (yi + ny * zi);
            if (solid[j]) return;
            st += temperature[j];
            n++;
          }

          accum(x - 1, y, z);
          accum(x + 1, y, z);
          accum(x, y - 1, z);
          accum(x, y + 1, z);
          accum(x, y, z - 1);
          accum(x, y, z + 1);
          if (n == 0) continue;
          nt[i] = temperature[i] * (1 - strength) + (st / n) * strength;
        }
      }
    }
    for (int i = 0; i < temperature.length; i++) {
      temperature[i] = nt[i];
    }
  }

  static AirflowMetrics _computeMetrics(AirflowVoxelField field) {
    var fluid = 0;
    var dead = 0;
    var heat = 0;
    var speedSum = 0.0;
    var tempVar = 0.0;

    final yMid = field.ny ~/ 2;
    for (int z = 0; z < field.nz; z++) {
      for (int x = 0; x < field.nx; x++) {
        final i = field.index(x, yMid, z);
        if (field.solid[i]) continue;
        fluid++;
        final s = field.speed[i];
        final t = field.temperature[i];
        speedSum += s;
        if (s < 0.12) dead++;
        if (t > 0.45 && s < 0.28) heat++;
        tempVar += t * t;
      }
    }

    if (fluid == 0) {
      return const AirflowMetrics(
        circulationScore: 0,
        deadZoneRatio: 1,
        heatPocketRatio: 1,
        mixingScore: 0,
        deadVoxelCount: 0,
        heatVoxelCount: 0,
        fluidVoxelCount: 0,
      );
    }

    final deadRatio = dead / fluid;
    final heatRatio = heat / fluid;
    final avgSpeed = speedSum / fluid;
    final mixing = (1 - (tempVar / fluid).clamp(0.0, 1.0)).clamp(0.0, 1.0);
    final circulation = ((avgSpeed * 55) + (1 - deadRatio) * 30 + (1 - heatRatio) * 25 + mixing * 15)
        .clamp(0.0, 100.0);

    return AirflowMetrics(
      circulationScore: circulation,
      deadZoneRatio: deadRatio,
      heatPocketRatio: heatRatio,
      mixingScore: mixing * 100,
      deadVoxelCount: dead,
      heatVoxelCount: heat,
      fluidVoxelCount: fluid,
    );
  }

  static List<AirflowParticle> _seedParticles(
    AirflowVoxelField field,
    List<AirflowBox> boxes, {
    required bool optimized,
    required int count,
    int ambientCount = 220,
  }) {
    final acs = boxes.where((b) => b.kind == 'ac').toList();
    final heats = boxes.where((b) => b.kind == 'heat').toList();
    final rng = Random(optimized ? 42 : 7);
    final particles = <AirflowParticle>[];

    // Thermal plumes only exist when their source furniture exists.
    // No AC → no cold jets. No PC/heat → no hot plumes.
    final coldCount = acs.isEmpty ? 0 : (heats.isEmpty ? count : (count * 0.58).round());
    final hotCount = heats.isEmpty ? 0 : (acs.isEmpty ? count : count - coldCount);
    final thermalCount = coldCount + hotCount;

    for (int i = 0; i < thermalCount; i++) {
      final isCold = i < coldCount;
      final p = AirflowParticle(
        position: const AirflowVec3(0, 0, 0),
        velocity: const AirflowVec3(0, 0, 0),
        temperature: isCold ? -1.0 : 1.0,
        age: 0,
        life: 1,
        isCold: isCold,
        isAmbient: false,
        seed: i,
      );
      _respawnParticle(
        p,
        acs,
        heats,
        rng.nextDouble() * 100,
        optimized,
        stagger: rng.nextDouble(),
      );
      particles.add(p);
    }

    // PC-case style volume tracers — fill free air so whole-room flow is visible.
    for (int i = 0; i < ambientCount; i++) {
      final p = AirflowParticle(
        position: const AirflowVec3(0, 0, 0),
        velocity: const AirflowVec3(0, 0, 0),
        temperature: 0,
        age: 0,
        life: 8,
        isCold: false,
        isAmbient: true,
        seed: 10000 + i,
      );
      _respawnAmbient(p, field, rng.nextDouble() * 1000, stagger: rng.nextDouble());
      particles.add(p);
    }
    return particles;
  }

  static void _respawnAmbient(
    AirflowParticle p,
    AirflowVoxelField field,
    double time, {
    double? stagger,
  }) {
    final rng = Random(p.seed ^ (time * 1000).toInt());
    // Rejection sample free voxels so tracers fill the whole volume.
    for (int attempt = 0; attempt < 40; attempt++) {
      final ix = rng.nextInt(field.nx);
      final iy = rng.nextInt(field.ny);
      final iz = rng.nextInt(field.nz);
      if (field.solid[field.index(ix, iy, iz)]) continue;
      final c = field.voxelCenter(ix, iy, iz);
      p.position = AirflowVec3(
        c.x + (rng.nextDouble() - 0.5) * 0.12,
        c.y + (rng.nextDouble() - 0.5) * 0.1,
        c.z + (rng.nextDouble() - 0.5) * 0.12,
      );
      break;
    }
    p.temperature = 0;
    p.age = (stagger ?? rng.nextDouble()) * 0.8;
    p.life = 7.0 + rng.nextDouble() * 4.0;
    p.velocity = field.sampleVelocity(p.position) * 0.45;
    p.trail.clear();
    p.trail.add(p.position);
  }

  static void _respawnParticle(
    AirflowParticle p,
    List<AirflowBox> acs,
    List<AirflowBox> heats,
    double time,
    bool optimized, {
    double? stagger,
  }) {
    // If the matching source disappeared, kill this thermal tracer instead of
    // inventing a corner emitter.
    if (p.isCold && acs.isEmpty) {
      p.life = 0.01;
      p.age = p.life;
      p.temperature = 0;
      p.velocity = const AirflowVec3(0, 0, 0);
      p.trail.clear();
      return;
    }
    if (!p.isCold && heats.isEmpty) {
      p.life = 0.01;
      p.age = p.life;
      p.temperature = 0;
      p.velocity = const AirflowVec3(0, 0, 0);
      p.trail.clear();
      return;
    }

    final emitBox = p.isCold ? acs[p.seed % acs.length] : heats[p.seed % heats.length];
    final emit = emitBox.center;

    final jx = _noise(p.seed, time) * 0.22;
    final jz = _noise(p.seed + 3, time) * 0.22;
    final spawnY = p.isCold
        ? emit.y - 0.12
        : (emitBox.max.y - 0.08).clamp(0.35, roomHeight * 0.55);
    p.position = AirflowVec3(
      emit.x + jx,
      spawnY,
      emit.z + jz,
    );
    p.temperature = p.isCold ? -1.0 : 1.0;
    p.age = (stagger ?? 0) * 0.01;
    // Longer life so you see gradual decay + wrapping around furniture.
    p.life = (p.isCold ? 3.8 : 3.2) + (p.seed % 7) * 0.15;
    if (!optimized && p.isCold) p.life *= 0.85;
    p.trail.clear();
    p.trail.add(p.position);

    final s = emitBox.strength;
    if (p.isCold) {
      p.velocity = _acEmitDir(emitBox).normalized() * (1.25 * s) +
          AirflowVec3(_noise(p.seed, time + 1) * 0.18, -0.62, _noise(p.seed, time + 2) * 0.18);
    } else {
      final jet = _heatEmitDir(emitBox).normalized() * (1.05 * s);
      p.velocity = jet +
          AirflowVec3(
            _noise(p.seed, time) * 0.12,
            emitBox.directional ? 0.35 : 0.72,
            _noise(p.seed + 9, time) * 0.12,
          );
    }
  }

  static AirflowVec3? _findFreeNeighbor(AirflowVoxelField field, int x, int y, int z) {
    const offsets = [
      (1, 0, 0),
      (-1, 0, 0),
      (0, 1, 0),
      (0, -1, 0),
      (0, 0, 1),
      (0, 0, -1),
      (1, 0, 1),
      (-1, 0, -1),
      (1, 1, 0),
      (-1, -1, 0),
    ];
    for (final o in offsets) {
      final nx = x + o.$1;
      final ny = y + o.$2;
      final nz = z + o.$3;
      if (!field.inBounds(nx, ny, nz)) continue;
      if (!field.solid[field.index(nx, ny, nz)]) {
        return field.voxelCenter(nx, ny, nz);
      }
    }
    return null;
  }
}
