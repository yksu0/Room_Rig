// Live Air / Light / Ergo overlay for Rig — same simulators + field ramps as
// Bench "My Room" (not the Bench "Improved" candidate).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/room_model.dart';
import '../services/airflow_simulator.dart';
import '../services/ergonomics_simulator.dart';
import '../services/lighting_simulator.dart';
import '../theme/app_theme.dart';

enum RigLiveDomain { none, airflow, lighting, ergonomics }

/// Cached sim snapshots so arrange refresh stays responsive.
class RigLiveFieldCache {
  RigLiveDomain domain = RigLiveDomain.none;
  String fingerprint = '';
  AirflowSimSnapshot? airflow;
  LightingSimSnapshot? lighting;
  ErgonomicsSimSnapshot? ergonomics;
  double score = 0;
  String detail = '';

  void refresh({
    required RigLiveDomain domain,
    required List<FurnitureItem> furniture,
    required String fingerprint,
  }) {
    if (domain == RigLiveDomain.none) {
      this.domain = domain;
      this.fingerprint = fingerprint;
      airflow = null;
      lighting = null;
      ergonomics = null;
      score = 0;
      detail = '';
      return;
    }
    if (this.domain == domain && this.fingerprint == fingerprint) return;
    this.domain = domain;
    this.fingerprint = fingerprint;
    switch (domain) {
      case RigLiveDomain.airflow:
        // Same build as Bench My Room / AirflowOptimizer.evaluate (no particles).
        airflow = AirflowSimulator.build(
          furniture: furniture,
          optimized: false,
          particleCount: 0,
          ambientCount: 0,
        );
        lighting = null;
        ergonomics = null;
        final m = airflow!.metrics;
        score = m.circulationScore.clamp(0, 100);
        detail =
            'Circ ${score.round()} · dead ${m.deadVoxelCount} · heat ${m.heatVoxelCount}';
      case RigLiveDomain.lighting:
        lighting = LightingSimulator.build(
          furniture: furniture,
          optimized: false,
        );
        airflow = null;
        ergonomics = null;
        score = lighting!.metrics.exposureScore.clamp(0, 100);
        detail = 'Exposure ${score.round()} (Bench My Room lux field)';
      case RigLiveDomain.ergonomics:
        ergonomics = ErgonomicsSimulator.build(
          furniture: furniture,
          optimized: false,
        );
        airflow = null;
        lighting = null;
        score = ergonomics!.metrics.comfortScore.clamp(0, 100);
        detail = 'Comfort ${score.round()} (Bench My Room reach)';
      case RigLiveDomain.none:
        break;
    }
  }
}

/// Same floor-temp blend Bench [AirflowVoxelPainter] uses for top-down heat maps.
double _compositeFloorTemp(AirflowVoxelField field, int x, int z) {
  final yFloor = 1.clamp(0, field.ny - 1);
  final yMid = field.ny ~/ 2;
  final yCeil = (field.ny - 2).clamp(0, field.ny - 1);
  final tFloor = field.temperature[field.index(x, yFloor, z)];
  final tMid = field.temperature[field.index(x, yMid, z)];
  final tCeil = field.temperature[field.index(x, yCeil, z)];
  return tFloor * 0.4 + tMid * 0.38 + tCeil * 0.22;
}

Color _airflowCellColor(AirflowVoxelField field, int x, int z) {
  final ySlice = field.ny ~/ 2;
  final i = field.index(x, ySlice, z);
  final temp = _compositeFloorTemp(field, x, z);
  final speed = field.speed[i];
  final color = Color.lerp(AppColors.cyan, AppColors.red, ((temp + 1) / 2).clamp(0.0, 1.0))!;
  final alpha = (0.08 + speed * 0.38 + temp.abs() * 0.14).clamp(0.05, 0.58);
  if (speed < 0.12) {
    return Color.alphaBlend(AppColors.red.withValues(alpha: 0.18), color.withValues(alpha: alpha));
  }
  return color.withValues(alpha: alpha);
}

class RigLiveFieldPainter extends CustomPainter {
  final Rect roomRect;
  final int gridCols;
  final int gridRows;
  final RigLiveDomain domain;
  final AirflowSimSnapshot? airflow;
  final LightingSimSnapshot? lighting;
  final ErgonomicsSimSnapshot? ergonomics;

  RigLiveFieldPainter({
    required this.roomRect,
    required this.gridCols,
    required this.gridRows,
    required this.domain,
    this.airflow,
    this.lighting,
    this.ergonomics,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (domain == RigLiveDomain.none) return;
    switch (domain) {
      case RigLiveDomain.airflow:
        _paintAirflow(canvas);
      case RigLiveDomain.lighting:
        _paintLighting(canvas);
      case RigLiveDomain.ergonomics:
        _paintErgonomics(canvas);
      case RigLiveDomain.none:
        break;
    }
  }

  /// Sims solve in a fixed world (e.g. 6×8). Map that world into this room's
  /// grid so furniture at gridX aligns with field world X (same as Bench data).
  Offset _worldToLocal(double wx, double wz) {
    final sx = roomRect.width / gridCols;
    final sz = roomRect.height / gridRows;
    return Offset(roomRect.left + wx * sx, roomRect.top + wz * sz);
  }

  bool _worldInRoom(double wx, double wz) =>
      wx < gridCols && wz < gridRows && wx >= 0 && wz >= 0;

  void _paintAirflow(Canvas canvas) {
    final snap = airflow;
    if (snap == null) return;
    final field = snap.field;
    final ySlice = field.ny ~/ 2;
    final voxW = field.roomWidth / field.nx;
    final voxD = field.roomDepth / field.nz;
    final sx = roomRect.width / gridCols;
    final sz = roomRect.height / gridRows;
    // Match Bench heatmap ramp; clip to this room's footprint.
    for (var z = 0; z < field.nz; z++) {
      for (var x = 0; x < field.nx; x++) {
        final wx = x * voxW;
        final wz = z * voxD;
        if (!_worldInRoom(wx, wz)) continue;
        final i = field.index(x, ySlice, z);
        if (field.solid[i]) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            roomRect.left + wx * sx,
            roomRect.top + wz * sz,
            voxW * sx - 0.4,
            voxD * sz - 0.4,
          ),
          Paint()..color = _airflowCellColor(field, x, z),
        );
      }
    }
    final arrowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    for (var z = 1; z < field.nz; z += 3) {
      for (var x = 1; x < field.nx; x += 3) {
        final wx = (x + 0.5) * voxW;
        final wz = (z + 0.5) * voxD;
        if (!_worldInRoom(wx, wz)) continue;
        final i = field.index(x, ySlice, z);
        if (field.solid[i] || field.speed[i] < 0.08) continue;
        final c = _worldToLocal(wx, wz);
        final len = (6.0 + field.speed[i] * 10).clamp(5.0, 16.0);
        final dx = field.vx[i];
        final dz = field.vz[i];
        final mag = math.sqrt(dx * dx + dz * dz);
        if (mag < 1e-4) continue;
        canvas.drawLine(
          c,
          Offset(c.dx + (dx / mag) * len, c.dy + (dz / mag) * len),
          arrowPaint,
        );
      }
    }
  }

  void _paintLighting(Canvas canvas) {
    final snap = lighting;
    if (snap == null) return;
    final voxW = snap.roomWidth / snap.nx;
    final voxD = snap.roomDepth / snap.nz;
    final sx = roomRect.width / gridCols;
    final sz = roomRect.height / gridRows;
    for (var z = 0; z < snap.nz; z++) {
      for (var x = 0; x < snap.nx; x++) {
        final wx = x * voxW;
        final wz = z * voxD;
        if (!_worldInRoom(wx, wz)) continue;
        final v = snap.lux[snap.index(x, z)];
        final rect = Rect.fromLTWH(
          roomRect.left + wx * sx,
          roomRect.top + wz * sz,
          voxW * sx - 0.3,
          voxD * sz - 0.3,
        );
        if (v <= 0.001) {
          canvas.drawRect(
            rect,
            Paint()..color = AppColors.textMuted.withValues(alpha: 0.28),
          );
          continue;
        }
        final color = Color.lerp(
          const Color(0xFF1A1D26),
          AppColors.lightingColor,
          v.clamp(0.0, 1.0),
        )!;
        canvas.drawRect(
          rect,
          Paint()..color = color.withValues(alpha: (0.2 + v * 0.65).clamp(0.15, 0.85)),
        );
        if (v < 0.18) {
          canvas.drawRect(
            rect,
            Paint()..color = AppColors.red.withValues(alpha: 0.16),
          );
        }
      }
    }
  }

  void _paintErgonomics(Canvas canvas) {
    final snap = ergonomics;
    if (snap == null) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(roomRect, const Radius.circular(8)),
      Paint()..color = AppColors.ergonomicsColor.withValues(alpha: 0.08),
    );
    // Reach / paths are already in sim-world metres (= grid cells).
    final sx = roomRect.width / gridCols;
    final sz = roomRect.height / gridRows;
    final circle = snap.reachCircle;
    if (circle != null) {
      final cx = roomRect.left + circle.x * sx;
      final cy = roomRect.top + circle.z * sz;
      final r = circle.radius * math.min(sx, sz);
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()..color = AppColors.ergonomicsColor.withValues(alpha: 0.18),
      );
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..color = AppColors.ergonomicsColor.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
    final paths = [...snap.paths]..sort((a, b) => b.frequency.compareTo(a.frequency));
    const pathColors = [
      AppColors.ergonomicsColor,
      AppColors.cyan,
      AppColors.amber,
    ];
    final topPaths = paths.take(3).toList();
    for (var i = 0; i < topPaths.length; i++) {
      final path = topPaths[i];
      if (path.points.length < 2) continue;
      final p = Path()
        ..moveTo(
          roomRect.left + path.points.first.x * sx,
          roomRect.top + path.points.first.z * sz,
        );
      for (var j = 1; j < path.points.length; j++) {
        p.lineTo(
          roomRect.left + path.points[j].x * sx,
          roomRect.top + path.points[j].z * sz,
        );
      }
      canvas.drawPath(
        p,
        Paint()
          ..color = pathColors[i % pathColors.length].withValues(alpha: 0.65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant RigLiveFieldPainter old) =>
      old.domain != domain ||
      old.roomRect != roomRect ||
      old.airflow != airflow ||
      old.lighting != lighting ||
      old.ergonomics != ergonomics ||
      old.gridCols != gridCols ||
      old.gridRows != gridRows;
}

/// One floor cell of a live field, in grid coordinates (x across, z into depth).
class RigLiveFieldCell {
  final double x0;
  final double z0;
  final double x1;
  final double z1;
  final Color color;

  const RigLiveFieldCell({
    required this.x0,
    required this.z0,
    required this.x1,
    required this.z1,
    required this.color,
  });

  Map<String, dynamic> toJson() => {
        'x0': x0,
        'z0': z0,
        'x1': x1,
        'z1': z1,
        'r': color.r,
        'g': color.g,
        'b': color.b,
        'a': color.a,
      };
}

/// Downsampled floor cells for Orbit / Model overlays (grid space).
List<RigLiveFieldCell> sampleRigLiveFieldCells({
  required RigLiveDomain domain,
  required int gridCols,
  required int gridRows,
  AirflowSimSnapshot? airflow,
  LightingSimSnapshot? lighting,
  ErgonomicsSimSnapshot? ergonomics,
  int maxAxis = 28,
}) {
  if (domain == RigLiveDomain.none) return const [];
  switch (domain) {
    case RigLiveDomain.airflow:
      final snap = airflow;
      if (snap == null) return const [];
      return _sampleAirflow(snap, gridCols, gridRows, maxAxis);
    case RigLiveDomain.lighting:
      final snap = lighting;
      if (snap == null) return const [];
      return _sampleLighting(snap, gridCols, gridRows, maxAxis);
    case RigLiveDomain.ergonomics:
      final snap = ergonomics;
      if (snap == null) return const [];
      return _sampleErgonomics(snap, gridCols, gridRows);
    case RigLiveDomain.none:
      return const [];
  }
}

List<RigLiveFieldCell> _sampleAirflow(
  AirflowSimSnapshot snap,
  int gridCols,
  int gridRows,
  int maxAxis,
) {
  final field = snap.field;
  final ySlice = field.ny ~/ 2;
  final voxW = field.roomWidth / field.nx;
  final voxD = field.roomDepth / field.nz;
  final stepX = math.max(1, (field.nx / maxAxis).ceil());
  final stepZ = math.max(1, (field.nz / maxAxis).ceil());
  final out = <RigLiveFieldCell>[];
  for (var z = 0; z < field.nz; z += stepZ) {
    for (var x = 0; x < field.nx; x += stepX) {
      final wx0 = x * voxW;
      final wz0 = z * voxD;
      if (wx0 >= gridCols || wz0 >= gridRows) continue;
      final i = field.index(x, ySlice, z);
      if (field.solid[i]) continue;
      final speed = field.speed[i];
      final temp = _compositeFloorTemp(field, x, z);
      if (speed < 0.05 && temp.abs() < 0.15) continue;
      final x1 = math.min(x + stepX, field.nx);
      final z1 = math.min(z + stepZ, field.nz);
      out.add(
        RigLiveFieldCell(
          x0: wx0,
          z0: wz0,
          x1: math.min(x1 * voxW, gridCols.toDouble()),
          z1: math.min(z1 * voxD, gridRows.toDouble()),
          color: _airflowCellColor(field, x, z),
        ),
      );
    }
  }
  return out;
}

List<RigLiveFieldCell> _sampleLighting(
  LightingSimSnapshot snap,
  int gridCols,
  int gridRows,
  int maxAxis,
) {
  final voxW = snap.roomWidth / snap.nx;
  final voxD = snap.roomDepth / snap.nz;
  final stepX = math.max(1, (snap.nx / maxAxis).ceil());
  final stepZ = math.max(1, (snap.nz / maxAxis).ceil());
  final out = <RigLiveFieldCell>[];
  for (var z = 0; z < snap.nz; z += stepZ) {
    for (var x = 0; x < snap.nx; x += stepX) {
      final wx0 = x * voxW;
      final wz0 = z * voxD;
      if (wx0 >= gridCols || wz0 >= gridRows) continue;
      final v = snap.lux[snap.index(x, z)];
      final x1 = math.min(x + stepX, snap.nx);
      final z1 = math.min(z + stepZ, snap.nz);
      final Color color;
      if (v <= 0.001) {
        color = AppColors.textMuted.withValues(alpha: 0.28);
      } else {
        final base = Color.lerp(
          const Color(0xFF1A1D26),
          AppColors.lightingColor,
          v.clamp(0.0, 1.0),
        )!;
        color = v < 0.18
            ? Color.alphaBlend(
                AppColors.red.withValues(alpha: 0.16),
                base.withValues(alpha: (0.2 + v * 0.65).clamp(0.15, 0.85)),
              )
            : base.withValues(alpha: (0.2 + v * 0.65).clamp(0.15, 0.85));
      }
      out.add(
        RigLiveFieldCell(
          x0: wx0,
          z0: wz0,
          x1: math.min(x1 * voxW, gridCols.toDouble()),
          z1: math.min(z1 * voxD, gridRows.toDouble()),
          color: color,
        ),
      );
    }
  }
  return out;
}

List<RigLiveFieldCell> _sampleErgonomics(
  ErgonomicsSimSnapshot snap,
  int gridCols,
  int gridRows,
) {
  final out = <RigLiveFieldCell>[
    RigLiveFieldCell(
      x0: 0,
      z0: 0,
      x1: gridCols.toDouble(),
      z1: gridRows.toDouble(),
      color: AppColors.ergonomicsColor.withValues(alpha: 0.07),
    ),
  ];
  final circle = snap.reachCircle;
  if (circle != null) {
    final sx = gridCols / snap.roomWidth;
    final sz = gridRows / snap.roomDepth;
    final cx = circle.x * sx;
    final cz = circle.z * sz;
    final r = circle.radius * math.min(sx, sz);
    // Approximate reach disc with a small grid of cells.
    const n = 10;
    for (var iz = -n; iz <= n; iz++) {
      for (var ix = -n; ix <= n; ix++) {
        final px = cx + ix * r / n;
        final pz = cz + iz * r / n;
        if ((px - cx) * (px - cx) + (pz - cz) * (pz - cz) > r * r) continue;
        final half = r / n;
        out.add(
          RigLiveFieldCell(
            x0: (px - half).clamp(0.0, gridCols.toDouble()),
            z0: (pz - half).clamp(0.0, gridRows.toDouble()),
            x1: (px + half).clamp(0.0, gridCols.toDouble()),
            z1: (pz + half).clamp(0.0, gridRows.toDouble()),
            color: AppColors.ergonomicsColor.withValues(alpha: 0.16),
          ),
        );
      }
    }
  }
  return out;
}

class RigLiveDomainBar extends StatelessWidget {
  final RigLiveDomain domain;
  final double score;
  final ValueChanged<RigLiveDomain> onChanged;
  final String detail;

  const RigLiveDomainBar({
    super.key,
    required this.domain,
    required this.score,
    required this.onChanged,
    this.detail = '',
  });

  @override
  Widget build(BuildContext context) {
    Widget chip(RigLiveDomain d, String label, Color color) {
      final on = domain == d;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(d),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: on ? color.withValues(alpha: 0.18) : AppColors.card,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: on ? color : AppColors.border),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: on ? color : AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            chip(RigLiveDomain.none, 'Off', AppColors.textMuted),
            const SizedBox(width: 6),
            chip(RigLiveDomain.airflow, 'Air', AppColors.airflowColor),
            const SizedBox(width: 6),
            chip(RigLiveDomain.lighting, 'Light', AppColors.lightingColor),
            const SizedBox(width: 6),
            chip(RigLiveDomain.ergonomics, 'Ergo', AppColors.ergonomicsColor),
          ],
        ),
        if (domain != RigLiveDomain.none) ...[
          const SizedBox(height: 6),
          Text(
            detail.isEmpty
                ? 'LIVE · Bench My Room field · score ${score.round()}'
                : 'LIVE · $detail — not Bench Improved',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}
