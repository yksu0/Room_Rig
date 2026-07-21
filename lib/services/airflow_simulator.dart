// lib/services/airflow_simulator.dart
// Coarse voxel airflow + interactive particle advection for Bench prototype.
import 'dart:math';
import '../models/room_model.dart';

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
  final String kind; // furniture | ac | heat | sink | fan

  const AirflowBox({
    required this.min,
    required this.max,
    required this.id,
    required this.label,
    required this.kind,
  });

  AirflowVec3 get center => AirflowVec3(
        (min.x + max.x) * 0.5,
        (min.y + max.y) * 0.5,
        (min.z + max.z) * 0.5,
      );

  bool get isSolidObstacle => kind == 'furniture' || kind == 'heat';

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

  static AirflowSimSnapshot build({
    required List<FurnitureItem> furniture,
    required bool optimized,
    int particleCount = 120,
    int ambientCount = 220,
  }) {
    final boxes = _buildBoxes(furniture);
    final field = _solveField(boxes, optimized: optimized);
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
    final sinks = boxes.where((b) => b.kind == 'sink').toList(growable: false);
    final fans = boxes.where((b) => b.kind == 'fan').toList(growable: false);

    final ambientDecay = snapshot.optimized ? 0.22 : 0.16;
    final buoyancyScale = snapshot.optimized ? 1.15 : 1.0;
    final seconds = time * 0.001;

    for (final p in snapshot.particles) {
      p.age += dt;
      if (p.age >= p.life || (!p.isAmbient && p.intensity < 0.06)) {
        if (p.isAmbient) {
          _respawnAmbient(p, field, time);
        } else {
          _respawnParticle(p, acs, heats, sinks, time, snapshot.optimized);
        }
        continue;
      }

      final ageFrac = (p.age / p.life).clamp(0.0, 1.0);

      // --- Forces ---
      var force = field.sampleVelocity(p.position) * (p.isAmbient ? 1.15 : 0.75);

      // Buoyancy: cold sinks, hot rises (tracers follow local temp lightly).
      if (!p.isAmbient) {
        final buoyancy = p.temperature * 0.95 * buoyancyScale;
        force = force + AirflowVec3(0, buoyancy, 0);
      } else {
        // Ambient smoke gently follows stratified temperature.
        force = force + AirflowVec3(0, field.sampleTemperature(p.position) * 0.25, 0);
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

      // Source influence: AC push weakens with age so parcels can diffuse.
      if (!p.isAmbient) {
        for (final ac in acs) {
          final d = (p.position - ac.center).length;
          if (d < 3.2) {
            final w = (1.0 - d / 3.2) * (1.0 - ageFrac * 0.65);
            final out = _acEmitDir(ac, sinks).normalized();
            // Wide cone jitter so cold isn't a laser beam.
            final cone = AirflowVec3(n1 * 0.55, -0.25, n2 * 0.55);
            force = force + (out + cone).normalized() * (w * (p.isCold ? 0.85 : 0.12));
            if (p.isCold && d < 1.4 && ageFrac < 0.25) {
              // Only re-chill near the vent early in life.
              p.temperature -= 0.03 * w * dt * 6;
            }
          }
        }
        for (final hot in heats) {
          final d = (p.position - hot.center).length;
          if (d < 2.2) {
            final w = (1.0 - d / 2.2);
            force = force + AirflowVec3(0, 0.9 * w, 0);
            if (!p.isCold && ageFrac < 0.3) p.temperature += 0.05 * w * dt * 8;
            if (snapshot.optimized && sinks.isNotEmpty) {
              force = force + (sinks.first.center - p.position).normalized() * (0.25 * w);
            }
          }
        }
      } else {
        // Ambient tracers pick up heat/cold tint when they pass through plumes.
        for (final ac in acs) {
          final d = (p.position - ac.center).length;
          if (d < 2.0) {
            final w = 1.0 - d / 2.0;
            p.temperature -= 0.35 * w * dt;
            force = force + _acEmitDir(ac, sinks).normalized() * (0.45 * w);
          }
        }
        for (final hot in heats) {
          final d = (p.position - hot.center).length;
          if (d < 1.8) {
            final w = 1.0 - d / 1.8;
            p.temperature += 0.4 * w * dt;
            force = force + AirflowVec3(0, 0.55 * w, 0);
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
            final strength = falloff * coneW * (snapshot.optimized ? 2.4 : 1.5);
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

      // Soft attraction of spent cold air toward window exhaust.
      if (!p.isAmbient && sinks.isNotEmpty && p.isCold && p.intensity < 0.45) {
        force = force + (sinks.first.center - p.position).normalized() * 0.18;
      }

      // Obstacle proximity: deflect around furniture before hard collision.
      force = force + _softObstacleAvoidance(p.position, solids) * 1.4;

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
        p.temperature += (localTemp - p.temperature) * 0.12;
        p.temperature *= (1.0 - 0.15 * dt);
      } else {
        p.temperature += (localTemp - p.temperature) * 0.05;
        // Cold neutralizes faster once it has left the vent (mirrors hot fading at ceiling).
        var decay = ambientDecay;
        if (p.isCold) {
          decay += 0.12 + ageFrac * 0.28;
          if (p.position.y < 0.9) decay += 0.18; // floor mixing
        } else {
          decay += ageFrac * 0.15;
          if (p.position.y > roomHeight - 0.7) decay += 0.2; // ceiling mixing
        }
        p.temperature *= (1.0 - decay * dt);
      }
      p.temperature = p.temperature.clamp(-1.15, 1.15);

      // Trail for collision / flow visualization.
      p.trail.add(p.position);
      final trailMax = p.isAmbient ? 10 : _trailLength;
      while (p.trail.length > trailMax) {
        p.trail.removeAt(0);
      }
    }
  }

  /// Public aim vector for viz — stand fan sweeps ±45° around room-center aim.
  static AirflowVec3 fanAimDirection(AirflowBox fan, double timeMs) {
    return _fanOscillateDir(fan, timeMs * 0.001);
  }

  /// Stand fan sweeps ±45° around a base aim toward room center.
  static AirflowVec3 _fanOscillateDir(AirflowBox fan, double seconds) {
    final base = AirflowVec3(
      roomWidth * 0.5 - fan.center.x,
      0.05,
      roomDepth * 0.5 - fan.center.z,
    );
    final baseAngle = base.lengthSquared < 1e-4 ? 0.0 : atan2(base.z, base.x);
    // Full left-right cycle ~3.5s — common pedestal oscillation feel.
    final sweep = sin(seconds * (2 * pi / 3.5)) * (pi / 4);
    final angle = baseAngle + sweep;
    return AirflowVec3(cos(angle), 0.08, sin(angle));
  }

  static AirflowVec3 _acEmitDir(AirflowBox ac, List<AirflowBox> sinks) {
    // Primary: blow toward room center so throw covers max floor area.
    final toCenter = AirflowVec3(
      roomWidth * 0.5 - ac.center.x,
      -0.25,
      roomDepth * 0.5 - ac.center.z,
    );
    if (toCenter.lengthSquared > 0.01) return toCenter;
    if (sinks.isNotEmpty) return sinks.first.center - ac.center;
    return const AirflowVec3(-1, -0.3, 0);
  }

  static AirflowVec3 _softObstacleAvoidance(AirflowVec3 p, List<AirflowBox> solids) {
    var push = const AirflowVec3(0, 0, 0);
    for (final b in solids) {
      final nearest = b.closestPoint(p);
      final away = p - nearest;
      final d = away.length;
      if (d < 0.001) {
        // Inside: strong outward from center.
        push = push + (p - b.center).normalized() * 1.8;
      } else if (d < 0.55) {
        push = push + away.normalized() * ((0.55 - d) / 0.55) * 1.2;
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
      final height = _itemHeight(f, kind);
      // AC / window are thin wall devices, not full solid blocks.
      if (kind == 'ac') {
        boxes.add(
          AirflowBox(
            min: AirflowVec3(f.gridX, 1.4, f.gridY),
            max: AirflowVec3(f.gridX + f.width, 2.3, f.gridY + max(f.height, 0.4)),
            id: f.id,
            label: f.name,
            kind: kind,
          ),
        );
      } else if (kind == 'sink') {
        boxes.add(
          AirflowBox(
            min: AirflowVec3(f.gridX, 0.9, f.gridY),
            max: AirflowVec3(f.gridX + f.width, 2.1, f.gridY + 0.15),
            id: f.id,
            label: f.name,
            kind: kind,
          ),
        );
      } else if (kind == 'fan') {
        // Slim pedestal footprint; head ~1.1m.
        boxes.add(
          AirflowBox(
            min: AirflowVec3(f.gridX + 0.2, 0, f.gridY + 0.2),
            max: AirflowVec3(f.gridX + 0.55, 1.15, f.gridY + 0.55),
            id: f.id,
            label: f.name,
            kind: kind,
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
          ),
        );
      }
    }
    return boxes;
  }

  static String _classify(FurnitureItem f) {
    final hay = '${f.id} ${f.name} ${f.iconName}'.toLowerCase();
    if (hay.contains('ac') || hay.contains('air conditioner') || hay.contains('vent')) {
      return 'ac';
    }
    if (hay.contains('window')) return 'sink';
    if (hay.contains('pc') || hay.contains('computer') || hay.contains('tower')) {
      return 'heat';
    }
    if (hay.contains('fan') || hay.contains('circulator')) return 'fan';
    return 'furniture';
  }

  static double _itemHeight(FurnitureItem f, String kind) {
    switch (kind) {
      case 'heat':
        return 1.35;
      case 'fan':
        return 1.1;
      default:
        // Beds / desks / shelves need real collision volume.
        if (f.id == 'bed') return 0.85;
        if (f.id == 'desk') return 0.75;
        if (f.id == 'shelf' || f.id == 'bookshelf') return 1.7;
        if (f.id == 'chair') return 1.05;
        return (0.55 + f.ergonomicsImpact.abs() * 0.55 + f.height * 0.15).clamp(0.45, 1.9);
    }
  }

  static AirflowVoxelField _solveField(List<AirflowBox> boxes, {required bool optimized}) {
    final count = nx * ny * nz;
    final solid = List<bool>.filled(count, false);
    final vx = List<double>.filled(count, 0);
    final vy = List<double>.filled(count, 0);
    final vz = List<double>.filled(count, 0);
    final temperature = List<double>.filled(count, 0);
    final speed = List<double>.filled(count, 0);

    for (final b in boxes) {
      if (b.kind == 'ac' || b.kind == 'sink' || b.kind == 'fan') continue;
      _rasterizeSolid(solid, b);
    }

    final acs = boxes.where((b) => b.kind == 'ac').toList();
    final heats = boxes.where((b) => b.kind == 'heat').toList();
    final sinks = boxes.where((b) => b.kind == 'sink').toList();
    final fans = boxes.where((b) => b.kind == 'fan').toList();

    final sinkCenter = sinks.isNotEmpty
        ? sinks.first.center
        : const AirflowVec3(0.3, 1.6, 0.4);
    final acCenter = acs.isNotEmpty ? acs.first.center : const AirflowVec3(5.4, 2.0, 0.8);

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

          final toSink = (sinkCenter - c).normalized();
          final acDist = (c - acCenter).length;
          final acInfluence = exp(-acDist * (optimized ? 0.26 : 0.40));

          var force = toSink * (optimized ? 0.45 : 0.22) * (0.3 + acInfluence);

          for (final ac in acs) {
            final d = (c - ac.center).length;
            if (d < (optimized ? 3.4 : 2.4)) {
              final push = _acEmitDir(ac, sinks).normalized();
              final w = 1 - d / 3.4;
              force = force + push * ((optimized ? 1.2 : 0.6) * w);
              force = force + AirflowVec3(0, -0.45 * w, 0); // cold sinks in field too
              temperature[i] -= (optimized ? 0.9 : 0.6) * w;
            }
          }

          for (final hot in heats) {
            final d = (c - hot.center).length;
            if (d < (optimized ? 2.5 : 2.9)) {
              final w = 1 - d / 2.9;
              force = force + AirflowVec3(0, (optimized ? 0.7 : 1.0) * w, 0);
              temperature[i] += (optimized ? 0.5 : 1.0) * w;
              if (optimized) {
                force = force + toSink * 0.4 * w;
              } else {
                force = force + AirflowVec3(-(c.z - 4) * 0.05, 0, (c.x - 3) * 0.05);
              }
            }
          }

          for (final fan in fans) {
            final d = (c - fan.center).length;
            if (d < 2.8) {
              // Static field uses average push toward room center (live sim oscillates).
              final push = AirflowVec3(
                roomWidth * 0.5 - fan.center.x,
                0.05,
                roomDepth * 0.5 - fan.center.z,
              ).normalized();
              force = force + push * ((optimized ? 0.85 : 0.45) * (1 - d / 2.8));
            }
          }

          // Obstacle-aware: weaken flow that would punch through nearby solids.
          force = force + _fieldObstacleSteer(c, solid, x, y, z) * 0.9;

          if (!optimized) {
            final dead = const AirflowVec3(4.6, 0.7, 6.2);
            final dd = (c - dead).length;
            if (dd < 1.8) {
              force = force * 0.12;
              temperature[i] += 0.4 * (1 - dd / 1.8);
            }
          }

          // Stratification bias: lower voxels prefer cold drift, upper prefer hot.
          final heightFrac = c.y / roomHeight;
          force = force + AirflowVec3(0, (heightFrac - 0.45) * temperature[i] * 0.15, 0);

          vx[i] = force.x;
          vy[i] = force.y;
          vz[i] = force.z;
        }
      }
    }

    final iterations = optimized ? 12 : 8;
    for (int iter = 0; iter < iterations; iter++) {
      _diffuse(vx, vy, vz, temperature, solid, strength: optimized ? 0.45 : 0.32);
      // Extra temperature diffusion so cold/hot spreads gradually through free air.
      _diffuseTemperatureOnly(temperature, solid, strength: 0.5);
    }

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
    final sinks = boxes.where((b) => b.kind == 'sink').toList();
    final rng = Random(optimized ? 42 : 7);
    final coldCount = (count * 0.58).round();
    final particles = <AirflowParticle>[];

    for (int i = 0; i < count; i++) {
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
        sinks,
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
    List<AirflowBox> sinks,
    double time,
    bool optimized, {
    double? stagger,
  }) {
    final emit = p.isCold
        ? (acs.isNotEmpty ? acs[p.seed % acs.length].center : const AirflowVec3(5.4, 2.0, 0.8))
        : (heats.isNotEmpty
            ? heats[p.seed % heats.length].center
            : const AirflowVec3(2.2, 1.0, 3.5));

    final jx = _noise(p.seed, time) * 0.22;
    final jz = _noise(p.seed + 3, time) * 0.22;
    p.position = AirflowVec3(
      emit.x + jx,
      emit.y + (p.isCold ? -0.15 : 0.2),
      emit.z + jz,
    );
    p.temperature = p.isCold ? -1.0 : 1.0;
    p.age = (stagger ?? 0) * 0.01;
    // Longer life so you see gradual decay + wrapping around furniture.
    p.life = (p.isCold ? 3.8 : 3.2) + (p.seed % 7) * 0.15;
    if (!optimized && p.isCold) p.life *= 0.85;
    p.trail.clear();
    p.trail.add(p.position);

    if (p.isCold && acs.isNotEmpty) {
      p.velocity = _acEmitDir(acs[p.seed % acs.length], sinks).normalized() * 1.15 +
          AirflowVec3(_noise(p.seed, time + 1) * 0.2, -0.55, _noise(p.seed, time + 2) * 0.2);
    } else {
      p.velocity = AirflowVec3(
        _noise(p.seed, time) * 0.15,
        0.95,
        _noise(p.seed + 9, time) * 0.15,
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
