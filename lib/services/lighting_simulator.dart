// lib/services/lighting_simulator.dart
// Coarse illuminance grid for lighting Bench / Auto-Rig scoring.
import 'dart:math';
import '../models/room_model.dart';

class LightingMetrics {
  final double exposureScore; // 0-100 overall
  final double taskIllumination; // 0-1 at desk/chair
  final double shadowRatio; // 0-1 of free cells under-lit
  final double daylightReach; // 0-1 how far window light travels
  final double glareRisk; // 0-1 higher = worse (desk too square-on to window)

  const LightingMetrics({
    required this.exposureScore,
    required this.taskIllumination,
    required this.shadowRatio,
    required this.daylightReach,
    required this.glareRisk,
  });
}

class LightingSample {
  final double x;
  final double z;
  final double lux; // 0-1 proxy
  final bool shadowed;

  const LightingSample({
    required this.x,
    required this.z,
    required this.lux,
    required this.shadowed,
  });
}

class LightingLight {
  final double x;
  final double z;
  final double y;
  final double intensity;
  final String kind; // window | lamp | ceiling
  final String label;

  const LightingLight({
    required this.x,
    required this.z,
    required this.y,
    required this.intensity,
    required this.kind,
    required this.label,
  });
}

class LightingOccluder {
  final double minX, minZ, maxX, maxZ;
  final double height;
  final String id;

  const LightingOccluder({
    required this.minX,
    required this.minZ,
    required this.maxX,
    required this.maxZ,
    required this.height,
    required this.id,
  });
}

class LightingSimSnapshot {
  final int nx;
  final int nz;
  final double roomWidth;
  final double roomDepth;
  final List<double> lux; // row-major nx * nz
  final List<LightingSample> samples;
  final List<LightingLight> lights;
  final List<LightingOccluder> occluders;
  final LightingMetrics metrics;
  final bool optimized;

  const LightingSimSnapshot({
    required this.nx,
    required this.nz,
    required this.roomWidth,
    required this.roomDepth,
    required this.lux,
    required this.samples,
    required this.lights,
    required this.occluders,
    required this.metrics,
    required this.optimized,
  });

  int index(int x, int z) => x + nx * z;
}

class LightingSimulator {
  static const roomWidth = 6.0;
  static const roomDepth = 8.0;
  static const roomHeight = 2.8;
  static const nx = 24;
  static const nz = 32;

  static LightingSimSnapshot build({
    required List<FurnitureItem> furniture,
    required bool optimized,
  }) {
    final lights = _buildLights(furniture, optimized: optimized);
    final occluders = _buildOccluders(furniture);
    final lux = List<double>.filled(nx * nz, 0);
    final samples = <LightingSample>[];

    for (int z = 0; z < nz; z++) {
      for (int x = 0; x < nx; x++) {
        final wx = (x + 0.5) * roomWidth / nx;
        final wz = (z + 0.5) * roomDepth / nz;
        if (_solidFloorBlocker(occluders, wx, wz)) {
          lux[x + nx * z] = 0;
          continue;
        }

        var value = 0.0;
        for (final light in lights) {
          value += _contribution(light, wx, wz, occluders);
        }
        value = value.clamp(0.0, 1.35);
        lux[x + nx * z] = value;
        samples.add(
          LightingSample(
            x: wx,
            z: wz,
            lux: value.clamp(0.0, 1.0),
            shadowed: value < 0.18,
          ),
        );
      }
    }

    final metrics = _computeMetrics(furniture, lux, lights, occluders);
    return LightingSimSnapshot(
      nx: nx,
      nz: nz,
      roomWidth: roomWidth,
      roomDepth: roomDepth,
      lux: lux,
      samples: samples,
      lights: lights,
      occluders: occluders,
      metrics: metrics,
      optimized: optimized,
    );
  }

  static List<LightingLight> _buildLights(
    List<FurnitureItem> furniture, {
    required bool optimized,
  }) {
    final lights = <LightingLight>[];

    // Soft ceiling fill — represents overhead fixtures (stronger when optimized).
    lights.add(
      LightingLight(
        x: roomWidth * 0.5,
        z: roomDepth * 0.45,
        y: roomHeight - 0.05,
        intensity: optimized ? 0.42 : 0.22,
        kind: 'ceiling',
        label: 'Ceiling',
      ),
    );

    for (final f in furniture) {
      final hay = '${f.id} ${f.name} ${f.iconName}'.toLowerCase();
      final cx = f.gridX + f.width * 0.5;
      final cz = f.gridY + f.height * 0.5;

      if (hay.contains('window')) {
        lights.add(
          LightingLight(
            x: cx,
            z: max(0.05, f.gridY + 0.05),
            y: 1.6,
            intensity: optimized ? 1.15 : 1.0,
            kind: 'window',
            label: 'Window',
          ),
        );
      } else if (hay.contains('lamp') || hay.contains('light') || hay.contains('bulb')) {
        lights.add(
          LightingLight(
            x: cx,
            z: cz,
            y: 1.2,
            intensity: optimized ? 0.85 : 0.7,
            kind: 'lamp',
            label: f.name,
          ),
        );
      }
    }

    // Guarantee a window light so scoring stays stable on odd presets.
    if (!lights.any((l) => l.kind == 'window')) {
      lights.add(
        const LightingLight(
          x: 3.0,
          z: 0.08,
          y: 1.6,
          intensity: 0.9,
          kind: 'window',
          label: 'Window',
        ),
      );
    }
    return lights;
  }

  static List<LightingOccluder> _buildOccluders(List<FurnitureItem> furniture) {
    final list = <LightingOccluder>[];
    for (final f in furniture) {
      final hay = '${f.id} ${f.name}'.toLowerCase();
      if (hay.contains('window') || hay.contains('door') || hay.contains('lamp') || hay.contains('ac')) {
        continue;
      }
      final height = hay.contains('shelf') || hay.contains('bookshelf') || hay.contains('wardrobe')
          ? 1.8
          : hay.contains('bed')
              ? 0.9
              : (0.6 + f.height * 0.25).clamp(0.5, 1.6);
      list.add(
        LightingOccluder(
          minX: f.gridX,
          minZ: f.gridY,
          maxX: f.gridX + f.width,
          maxZ: f.gridY + f.height,
          height: height,
          id: f.id,
        ),
      );
    }
    return list;
  }

  /// Tall storage occupies floor cells; desks/chairs still receive surface light.
  static bool _solidFloorBlocker(List<LightingOccluder> occluders, double x, double z) {
    for (final o in occluders) {
      if (o.height < 1.35) continue;
      if (x >= o.minX && x <= o.maxX && z >= o.minZ && z <= o.maxZ) return true;
    }
    return false;
  }

  static double _contribution(
    LightingLight light,
    double x,
    double z,
    List<LightingOccluder> occluders,
  ) {
    final dx = x - light.x;
    final dz = z - light.z;
    final dist = sqrt(dx * dx + dz * dz) + 0.15;

    double base;
    if (light.kind == 'window') {
      // Directional daylight: strongest near the window wall, falls with depth.
      final depthFade = exp(-max(0.0, z - light.z) * 0.42);
      final lateral = exp(-(dx * dx) * 0.18);
      base = light.intensity * depthFade * lateral / (1.0 + dist * 0.15);
    } else if (light.kind == 'ceiling') {
      base = light.intensity / (1.0 + dist * 0.55);
    } else {
      base = light.intensity / (1.0 + dist * dist * 0.55);
    }

    // Occlusion: sample toward the light; tall blockers cast shadows.
    if (_occluded(light.x, light.z, x, z, light.y, occluders)) {
      base *= light.kind == 'ceiling' ? 0.55 : 0.18;
    }
    return base;
  }

  static bool _occluded(
    double x0,
    double z0,
    double x1,
    double z1,
    double lightY,
    List<LightingOccluder> occluders,
  ) {
    const steps = 14;
    for (int i = 1; i < steps; i++) {
      final t = i / steps;
      final x = x0 + (x1 - x0) * t;
      final z = z0 + (z1 - z0) * t;
      for (final o in occluders) {
        if (x >= o.minX && x <= o.maxX && z >= o.minZ && z <= o.maxZ) {
          // Light rays from ceiling clear short furniture more easily.
          if (o.height > lightY * 0.55) return true;
        }
      }
    }
    return false;
  }

  static LightingMetrics _computeMetrics(
    List<FurnitureItem> furniture,
    List<double> lux,
    List<LightingLight> lights,
    List<LightingOccluder> occluders,
  ) {
    var free = 0;
    var shadow = 0;
    var sum = 0.0;
    for (final v in lux) {
      if (v <= 0.001) continue;
      free++;
      sum += v;
      if (v < 0.18) shadow++;
    }
    final mean = free == 0 ? 0.0 : sum / free;
    final shadowRatio = free == 0 ? 1.0 : shadow / free;

    // Task zone = desk / chair centers (sample contributions even on furniture tops).
    double task = 0;
    var taskN = 0;
    for (final f in furniture) {
      final id = f.id.toLowerCase();
      if (id.contains('desk') || id.contains('chair')) {
        final cx = f.gridX + f.width * 0.5;
        final cz = f.gridY + f.height * 0.5;
        var value = 0.0;
        for (final light in lights) {
          value += _contribution(light, cx, cz, occluders);
        }
        task += value.clamp(0.0, 1.35);
        taskN++;
      }
    }
    final taskIllum = taskN == 0 ? mean : (task / taskN).clamp(0.0, 1.2) / 1.2;

    // Daylight reach: average lux in the front third of the room.
    var daySum = 0.0;
    var dayN = 0;
    final zCut = (nz * 0.34).floor();
    for (int z = 0; z < zCut; z++) {
      for (int x = 0; x < nx; x++) {
        final v = lux[x + nx * z];
        if (v <= 0.001) continue;
        daySum += v;
        dayN++;
      }
    }
    final daylightReach = dayN == 0 ? 0.0 : (daySum / dayN).clamp(0.0, 1.0);

    // Glare: desk very close and centered on window axis.
    var glare = 0.0;
    LightingLight? windowLight;
    for (final l in lights) {
      if (l.kind == 'window') {
        windowLight = l;
        break;
      }
    }
    FurnitureItem? desk;
    for (final f in furniture) {
      if (f.id == 'desk') {
        desk = f;
        break;
      }
    }
    if (windowLight != null && desk != null) {
      final dx = (desk.gridX + desk.width * 0.5) - windowLight.x;
      final dz = (desk.gridY + desk.height * 0.5) - windowLight.z;
      final aligned = 1.0 - (dx.abs() / 2.5).clamp(0.0, 1.0);
      final tooClose = dz < 1.4 ? (1.0 - dz / 1.4) : 0.0;
      // Lateral offset reduces glare risk (desk beside window path, not square-on).
      final offsetRelief = (dx.abs() / 1.8).clamp(0.0, 0.55);
      glare = (aligned * 0.45 + tooClose * 0.55 - offsetRelief).clamp(0.0, 1.0);
    }

    final exposure = (
            taskIllum * 50 +
            (1 - shadowRatio) * 22 +
            daylightReach * 18 +
            mean * 18 -
            glare * 12)
        .clamp(0.0, 100.0);

    return LightingMetrics(
      exposureScore: exposure,
      taskIllumination: taskIllum,
      shadowRatio: shadowRatio,
      daylightReach: daylightReach,
      glareRisk: glare,
    );
  }
}
