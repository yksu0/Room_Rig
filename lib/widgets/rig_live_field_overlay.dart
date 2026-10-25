// Lightweight live Air / Light / Ergo overlay for Rig Edit (ROUGH EST.).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/room_model.dart';
import '../services/airflow_simulator.dart';
import '../services/ergonomics_simulator.dart';
import '../services/lighting_simulator.dart';
import '../theme/app_theme.dart';

enum RigLiveDomain { none, airflow, lighting, ergonomics }

/// Cached sim snapshots so drag-end refresh stays responsive.
class RigLiveFieldCache {
  RigLiveDomain domain = RigLiveDomain.none;
  String fingerprint = '';
  AirflowSimSnapshot? airflow;
  LightingSimSnapshot? lighting;
  ErgonomicsSimSnapshot? ergonomics;
  double score = 0;

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
      return;
    }
    if (this.domain == domain && this.fingerprint == fingerprint) return;
    this.domain = domain;
    this.fingerprint = fingerprint;
    switch (domain) {
      case RigLiveDomain.airflow:
        airflow = AirflowSimulator.build(
          furniture: furniture,
          optimized: false,
          particleCount: 0,
          ambientCount: 0,
        );
        lighting = null;
        ergonomics = null;
        score = airflow!.metrics.circulationScore.clamp(0, 100);
      case RigLiveDomain.lighting:
        lighting = LightingSimulator.build(
          furniture: furniture,
          optimized: false,
        );
        airflow = null;
        ergonomics = null;
        score = lighting!.metrics.exposureScore.clamp(0, 100);
      case RigLiveDomain.ergonomics:
        ergonomics = ErgonomicsSimulator.build(
          furniture: furniture,
          optimized: false,
        );
        airflow = null;
        lighting = null;
        score = ergonomics!.metrics.comfortScore.clamp(0, 100);
      case RigLiveDomain.none:
        break;
    }
  }
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

  void _paintAirflow(Canvas canvas) {
    final snap = airflow;
    if (snap == null) return;
    final field = snap.field;
    final midY = field.ny ~/ 2;
    final cellW = roomRect.width / field.nx;
    final cellH = roomRect.height / field.nz;
    var maxSpeed = 0.001;
    for (var z = 0; z < field.nz; z++) {
      for (var x = 0; x < field.nx; x++) {
        final i = field.index(x, midY, z);
        if (!field.solid[i]) {
          maxSpeed = math.max(maxSpeed, field.speed[i]);
        }
      }
    }
    for (var z = 0; z < field.nz; z++) {
      for (var x = 0; x < field.nx; x++) {
        final i = field.index(x, midY, z);
        if (field.solid[i]) continue;
        final t = (field.speed[i] / maxSpeed).clamp(0.0, 1.0);
        final color = Color.lerp(
          AppColors.airflowColor.withValues(alpha: 0.05),
          AppColors.airflowColor.withValues(alpha: 0.42),
          t,
        )!;
        canvas.drawRect(
          Rect.fromLTWH(
            roomRect.left + x * cellW,
            roomRect.top + z * cellH,
            cellW + 0.5,
            cellH + 0.5,
          ),
          Paint()..color = color,
        );
      }
    }
  }

  void _paintLighting(Canvas canvas) {
    final snap = lighting;
    if (snap == null) return;
    final cellW = roomRect.width / snap.nx;
    final cellH = roomRect.height / snap.nz;
    var maxLux = 0.001;
    for (final v in snap.lux) {
      maxLux = math.max(maxLux, v);
    }
    for (var z = 0; z < snap.nz; z++) {
      for (var x = 0; x < snap.nx; x++) {
        final v = snap.lux[snap.index(x, z)];
        final t = (v / maxLux).clamp(0.0, 1.0);
        final color = Color.lerp(
          AppColors.lightingColor.withValues(alpha: 0.04),
          AppColors.lightingColor.withValues(alpha: 0.40),
          t,
        )!;
        canvas.drawRect(
          Rect.fromLTWH(
            roomRect.left + x * cellW,
            roomRect.top + z * cellH,
            cellW + 0.5,
            cellH + 0.5,
          ),
          Paint()..color = color,
        );
      }
    }
  }

  void _paintErgonomics(Canvas canvas) {
    final snap = ergonomics;
    if (snap == null) return;
    // Soft wash + reach / path hints (room metres → roomRect).
    canvas.drawRRect(
      RRect.fromRectAndRadius(roomRect, const Radius.circular(8)),
      Paint()..color = AppColors.ergonomicsColor.withValues(alpha: 0.08),
    );
    final sx = roomRect.width / snap.roomWidth;
    final sz = roomRect.height / snap.roomDepth;
    final circle = snap.reachCircle;
    if (circle != null) {
      final cx = roomRect.left + circle.x * sx;
      final cy = roomRect.top + circle.z * sz;
      final r = circle.radius * math.min(sx, sz);
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..color = AppColors.ergonomicsColor.withValues(alpha: 0.18)
          ..style = PaintingStyle.fill,
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
    for (final path in snap.paths.take(3)) {
      if (path.points.length < 2) continue;
      final p = Path()
        ..moveTo(
          roomRect.left + path.points.first.x * sx,
          roomRect.top + path.points.first.z * sz,
        );
      for (var i = 1; i < path.points.length; i++) {
        p.lineTo(
          roomRect.left + path.points[i].x * sx,
          roomRect.top + path.points[i].z * sz,
        );
      }
      canvas.drawPath(
        p,
        Paint()
          ..color = AppColors.ergonomicsColor.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
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
  final midY = field.ny ~/ 2;
  var maxSpeed = 0.001;
  for (var z = 0; z < field.nz; z++) {
    for (var x = 0; x < field.nx; x++) {
      final i = field.index(x, midY, z);
      if (!field.solid[i]) maxSpeed = math.max(maxSpeed, field.speed[i]);
    }
  }
  final stepX = math.max(1, (field.nx / maxAxis).ceil());
  final stepZ = math.max(1, (field.nz / maxAxis).ceil());
  final out = <RigLiveFieldCell>[];
  for (var z = 0; z < field.nz; z += stepZ) {
    for (var x = 0; x < field.nx; x += stepX) {
      final i = field.index(x, midY, z);
      if (field.solid[i]) continue;
      final t = (field.speed[i] / maxSpeed).clamp(0.0, 1.0);
      if (t < 0.04) continue;
      final x1 = math.min(x + stepX, field.nx);
      final z1 = math.min(z + stepZ, field.nz);
      out.add(
        RigLiveFieldCell(
          x0: x / field.nx * gridCols,
          z0: z / field.nz * gridRows,
          x1: x1 / field.nx * gridCols,
          z1: z1 / field.nz * gridRows,
          color: Color.lerp(
            AppColors.airflowColor.withValues(alpha: 0.08),
            AppColors.airflowColor.withValues(alpha: 0.48),
            t,
          )!,
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
  var maxLux = 0.001;
  for (final v in snap.lux) {
    maxLux = math.max(maxLux, v);
  }
  final stepX = math.max(1, (snap.nx / maxAxis).ceil());
  final stepZ = math.max(1, (snap.nz / maxAxis).ceil());
  final out = <RigLiveFieldCell>[];
  for (var z = 0; z < snap.nz; z += stepZ) {
    for (var x = 0; x < snap.nx; x += stepX) {
      final v = snap.lux[snap.index(x, z)];
      final t = (v / maxLux).clamp(0.0, 1.0);
      if (t < 0.04) continue;
      final x1 = math.min(x + stepX, snap.nx);
      final z1 = math.min(z + stepZ, snap.nz);
      out.add(
        RigLiveFieldCell(
          x0: x / snap.nx * gridCols,
          z0: z / snap.nz * gridRows,
          x1: x1 / snap.nx * gridCols,
          z1: z1 / snap.nz * gridRows,
          color: Color.lerp(
            AppColors.lightingColor.withValues(alpha: 0.06),
            AppColors.lightingColor.withValues(alpha: 0.45),
            t,
          )!,
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

  const RigLiveDomainBar({
    super.key,
    required this.domain,
    required this.score,
    required this.onChanged,
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
            'LIVE EST. ${score.round()} — Edit 2D / Orbit / Model · updates as you arrange',
            style: TextStyle(
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
