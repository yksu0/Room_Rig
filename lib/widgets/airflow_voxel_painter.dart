// lib/widgets/airflow_voxel_painter.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/airflow_simulator.dart';
import '../theme/app_theme.dart';

enum AirflowVizMode { topDown2D, orbit3D }

/// Renders voxel temperature/speed field + live hot/cold particles.
class AirflowVoxelPainter extends CustomPainter {
  final AirflowSimSnapshot snapshot;
  final AirflowVizMode vizMode;
  final double yaw;
  final double pitch;
  final double distance;
  final double time;
  final bool showVoxels;
  final bool showDeadZones;

  AirflowVoxelPainter({
    required this.snapshot,
    required this.vizMode,
    required this.yaw,
    required this.pitch,
    required this.distance,
    required this.time,
    this.showVoxels = true,
    this.showDeadZones = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: snapshot.optimized
            ? [AppColors.cyanDim.withValues(alpha: 0.14), Colors.transparent]
            : [AppColors.red.withValues(alpha: 0.12), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg);

    if (vizMode == AirflowVizMode.topDown2D) {
      _paint2D(canvas, size);
    } else {
      _paint3D(canvas, size);
    }
  }

  void _paint2D(Canvas canvas, Size size) {
    final field = snapshot.field;
    final pad = 16.0;
    final rect = Rect.fromLTWH(pad, pad, size.width - pad * 2, size.height - pad * 2);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      Paint()..color = AppColors.surfaceAlt.withValues(alpha: 0.85),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      Paint()
        ..color = AppColors.cyan.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    final cellW = rect.width / field.nx;
    final cellH = rect.height / field.nz;
    final ySlice = field.ny ~/ 2;

    if (showVoxels) {
      for (int z = 0; z < field.nz; z++) {
        for (int x = 0; x < field.nx; x++) {
          final i = field.index(x, ySlice, z);
          if (field.solid[i]) {
            canvas.drawRect(
              Rect.fromLTWH(rect.left + x * cellW, rect.top + z * cellH, cellW - 0.4, cellH - 0.4),
              Paint()..color = AppColors.textMuted.withValues(alpha: 0.45),
            );
            continue;
          }

          final temp = field.temperature[i];
          final speed = field.speed[i];
          final color = Color.lerp(AppColors.cyan, AppColors.red, ((temp + 1) / 2).clamp(0.0, 1.0))!;
          final alpha = (0.08 + speed * 0.35 + temp.abs() * 0.12).clamp(0.05, 0.55);
          canvas.drawRect(
            Rect.fromLTWH(rect.left + x * cellW, rect.top + z * cellH, cellW - 0.4, cellH - 0.4),
            Paint()..color = color.withValues(alpha: alpha),
          );

          if (showDeadZones && speed < 0.12) {
            canvas.drawRect(
              Rect.fromLTWH(rect.left + x * cellW, rect.top + z * cellH, cellW - 0.4, cellH - 0.4),
              Paint()..color = AppColors.red.withValues(alpha: snapshot.optimized ? 0.05 : 0.18),
            );
          }
        }
      }
    }

    // Furniture as solid blockers (filled so collisions are obvious).
    for (final box in snapshot.boxes) {
      if (box.kind == 'ac' || box.kind == 'sink' || box.kind == 'fan') continue;
      final r = Rect.fromLTRB(
        rect.left + (box.min.x / field.roomWidth) * rect.width,
        rect.top + (box.min.z / field.roomDepth) * rect.height,
        rect.left + (box.max.x / field.roomWidth) * rect.width,
        rect.top + (box.max.z / field.roomDepth) * rect.height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(4)),
        Paint()..color = AppColors.textPrimary.withValues(alpha: 0.22),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(4)),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      final label = TextPainter(
        text: TextSpan(
          text: box.label,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 8, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: (r.width - 4).clamp(12, 80));
      label.paint(canvas, Offset(r.left + 3, r.top + 3));
    }

    // Flow arrows on a coarse subsample.
    final arrowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    for (int z = 1; z < field.nz; z += 3) {
      for (int x = 1; x < field.nx; x += 3) {
        final i = field.index(x, ySlice, z);
        if (field.solid[i] || field.speed[i] < 0.08) continue;
        final cx = rect.left + (x + 0.5) * cellW;
        final cy = rect.top + (z + 0.5) * cellH;
        final len = (6.0 + field.speed[i] * 10).clamp(5.0, 16.0);
        final dx = field.vx[i];
        final dz = field.vz[i];
        final mag = math.sqrt(dx * dx + dz * dz);
        if (mag < 1e-4) continue;
        final ex = cx + (dx / mag) * len;
        final ey = cy + (dz / mag) * len;
        canvas.drawLine(Offset(cx, cy), Offset(ex, ey), arrowPaint);
      }
    }

    Offset map2d(AirflowVec3 p) => Offset(
          rect.left + (p.x / field.roomWidth) * rect.width,
          rect.top + (p.z / field.roomDepth) * rect.height,
        );

    // Oscillating stand-fan sweep wedge (±45°).
    for (final box in snapshot.boxes.where((b) => b.kind == 'fan')) {
      final origin = map2d(box.center);
      final aim = AirflowSimulator.fanAimDirection(box, time);
      final reach = math.min(rect.width, rect.height) * 0.28;
      final angle = math.atan2(aim.z, aim.x);
      // Map world XZ aim into screen 2D (x → right, z → down).
      final path = Path()..moveTo(origin.dx, origin.dy);
      path.arcTo(
        Rect.fromCircle(center: origin, radius: reach),
        angle - math.pi / 8,
        math.pi / 4,
        false,
      );
      path.close();
      canvas.drawPath(path, Paint()..color = AppColors.airflowColor.withValues(alpha: 0.12));
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.airflowColor.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      final tip = Offset(origin.dx + math.cos(angle) * reach, origin.dy + math.sin(angle) * reach);
      canvas.drawLine(
        origin,
        tip,
        Paint()
          ..color = AppColors.airflowColor.withValues(alpha: 0.75)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }

    // Ambient smoke first, thermal parcels on top (PC-case airflow style).
    final ordered2d = [
      ...snapshot.particles.where((p) => p.isAmbient),
      ...snapshot.particles.where((p) => !p.isAmbient),
    ];
    for (final p in ordered2d) {
      final color = _parcelColor(p);
      final alpha = p.isAmbient
          ? 0.22
          : (0.18 + p.intensity * 0.75).clamp(0.1, 0.95);

      // Trail shows wrap-around / collision path.
      if (p.trail.length >= 2) {
        for (int t = 1; t < p.trail.length; t++) {
          final a = map2d(p.trail[t - 1]);
          final b = map2d(p.trail[t]);
          final trailAlpha = alpha * (t / p.trail.length) * (p.isAmbient ? 0.45 : 0.65);
          canvas.drawLine(
            a,
            b,
            Paint()
              ..color = color.withValues(alpha: trailAlpha)
              ..strokeWidth = p.isAmbient ? 0.9 : (1.2 + p.intensity)
              ..strokeCap = StrokeCap.round,
          );
        }
      }

      final o = map2d(p.position);
      final radius = p.isAmbient
          ? 1.35
          : (1.4 + p.intensity * 2.4) * (p.isCold ? 0.95 : 1.05);
      canvas.drawCircle(o, radius, Paint()..color = color.withValues(alpha: alpha));
    }

    _drawAnchors2D(canvas, rect, field);
  }

  Color _parcelColor(AirflowParticle p) {
    if (p.isAmbient) {
      // Smoke tracers: neutral gray, lightly tinted if they picked up heat/cold.
      final tint = Color.lerp(
            AppColors.cyan,
            AppColors.red,
            ((p.temperature + 1) / 2).clamp(0.0, 1.0),
          ) ??
          const Color(0xFFB8C0CC);
      return Color.lerp(const Color(0xFFB8C0CC), tint, p.temperature.abs().clamp(0.0, 0.7))!;
    }
    final hotCold = Color.lerp(
          AppColors.cyan,
          AppColors.red,
          ((p.temperature + 1) / 2).clamp(0.0, 1.0),
        ) ??
        AppColors.cyan;
    // As intensity drops, fade toward neutral room air (not stuck neon cyan).
    return Color.lerp(const Color(0xFF9AA3B5), hotCold, p.intensity.clamp(0.0, 1.0))!;
  }

  void _drawAnchors2D(Canvas canvas, Rect rect, AirflowVoxelField field) {
    for (final box in snapshot.boxes) {
      Color? color;
      String? label;
      if (box.kind == 'ac') {
        color = AppColors.cyan;
        label = 'AC';
      } else if (box.kind == 'sink') {
        color = AppColors.green;
        label = 'Window';
      } else if (box.kind == 'heat') {
        color = AppColors.red;
        label = 'PC';
      } else if (box.kind == 'fan') {
        color = AppColors.airflowColor;
        label = 'Fan';
      }
      if (color == null || label == null) continue;
      final c = box.center;
      final o = Offset(
        rect.left + (c.x / field.roomWidth) * rect.width,
        rect.top + (c.z / field.roomDepth) * rect.height,
      );
      _drawAnchor(canvas, o, color, label);
    }
  }

  void _paint3D(Canvas canvas, Size size) {
    final field = snapshot.field;
    final cam = _Cam3(
      roomWidth: field.roomWidth,
      roomDepth: field.roomDepth,
      roomHeight: field.roomHeight,
      yaw: yaw,
      pitch: pitch,
      distance: distance,
    );

    // Room wireframe.
    final corners = [
      const _V(0, 0, 0),
      _V(field.roomWidth, 0, 0),
      _V(field.roomWidth, 0, field.roomDepth),
      _V(0, 0, field.roomDepth),
      _V(0, field.roomHeight, 0),
      _V(field.roomWidth, field.roomHeight, 0),
      _V(field.roomWidth, field.roomHeight, field.roomDepth),
      _V(0, field.roomHeight, field.roomDepth),
    ];
    final projected = corners.map((v) => _project(v, size, cam)).toList();
    final edge = Paint()
      ..color = AppColors.border.withValues(alpha: 0.8)
      ..strokeWidth = 1.2;
    void line(int a, int b) {
      final pa = projected[a];
      final pb = projected[b];
      if (pa == null || pb == null) return;
      canvas.drawLine(pa.$1, pb.$1, edge);
    }

    line(0, 1);
    line(1, 2);
    line(2, 3);
    line(3, 0);
    line(4, 5);
    line(5, 6);
    line(6, 7);
    line(7, 4);
    line(0, 4);
    line(1, 5);
    line(2, 6);
    line(3, 7);

    // Furniture boxes — more opaque so particles visibly wrap.
    for (final box in snapshot.boxes) {
      if (box.kind == 'ac' || box.kind == 'sink' || box.kind == 'fan') continue;
      _drawBox(canvas, size, cam, box.min, box.max, AppColors.surfaceAlt.withValues(alpha: 0.72));
    }

    // Mid-height voxel points (subsampled).
    if (showVoxels) {
      final ySlice = field.ny ~/ 2;
      for (int z = 0; z < field.nz; z += 2) {
        for (int x = 0; x < field.nx; x += 2) {
          final i = field.index(x, ySlice, z);
          if (field.solid[i]) continue;
          final s = field.speed[i];
          final t = field.temperature[i];
          if (s < 0.05 && t.abs() < 0.15) continue;
          final c = field.voxelCenter(x, ySlice, z);
          final p = _project(_V(c.x, c.y, c.z), size, cam);
          if (p == null) continue;
          final color = Color.lerp(AppColors.cyan, AppColors.red, ((t + 1) / 2).clamp(0.0, 1.0))!;
          final alpha = (0.12 + s * 0.35 + t.abs() * 0.15).clamp(0.08, 0.5);
          canvas.drawCircle(p.$1, 2.0, Paint()..color = color.withValues(alpha: alpha));
        }
      }
    }

    // Dead zone blobs for baseline.
    if (showDeadZones && !snapshot.optimized) {
      final dead = _project(const _V(4.6, 0.9, 6.2), size, cam);
      if (dead != null) {
        canvas.drawCircle(dead.$1, 34, Paint()..color = AppColors.red.withValues(alpha: 0.16));
      }
      final heat = _project(const _V(2.4, 1.1, 3.6), size, cam);
      if (heat != null) {
        canvas.drawCircle(heat.$1, 28, Paint()..color = AppColors.orange.withValues(alpha: 0.14));
      }
    }

    // Draw ambient tracers first (smoke fill), then thermal parcels on top.
    final ordered = [
      ...snapshot.particles.where((p) => p.isAmbient),
      ...snapshot.particles.where((p) => !p.isAmbient),
    ];
    for (final particle in ordered) {
      final color = _parcelColor(particle);
      final alpha = particle.isAmbient
          ? 0.2
          : (0.15 + particle.intensity * 0.78).clamp(0.08, 0.95);

      if (particle.trail.length >= 2) {
        Offset? prev;
        for (int t = 0; t < particle.trail.length; t++) {
          final pt = particle.trail[t];
          final proj = _project(_V(pt.x, pt.y, pt.z), size, cam);
          if (proj == null) {
            prev = null;
            continue;
          }
          if (prev != null) {
            canvas.drawLine(
              prev,
              proj.$1,
              Paint()
                ..color = color.withValues(alpha: alpha * (t / particle.trail.length) * (particle.isAmbient ? 0.4 : 0.6))
                ..strokeWidth = particle.isAmbient ? 0.85 : (1.3 + particle.intensity)
                ..strokeCap = StrokeCap.round,
            );
          }
          prev = proj.$1;
        }
      }

      final p = _project(
        _V(particle.position.x, particle.position.y, particle.position.z),
        size,
        cam,
      );
      if (p == null) continue;
      final radius = particle.isAmbient ? 1.2 : (1.3 + particle.intensity * 2.5);
      canvas.drawCircle(p.$1, radius, Paint()..color = color.withValues(alpha: alpha));
    }

    // Fan aim indicator in 3D.
    for (final box in snapshot.boxes.where((b) => b.kind == 'fan')) {
      final aim = AirflowSimulator.fanAimDirection(box, time);
      final c = box.center;
      final tip = AirflowVec3(c.x + aim.x * 1.4, c.y + 0.1, c.z + aim.z * 1.4);
      final a = _project(_V(c.x, c.y, c.z), size, cam);
      final b = _project(_V(tip.x, tip.y, tip.z), size, cam);
      if (a != null && b != null) {
        canvas.drawLine(
          a.$1,
          b.$1,
          Paint()
            ..color = AppColors.airflowColor.withValues(alpha: 0.8)
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round,
        );
      }
      if (a != null) _drawAnchor(canvas, a.$1, AppColors.airflowColor, 'Fan');
    }

    for (final box in snapshot.boxes) {
      Color? color;
      String? label;
      if (box.kind == 'ac') {
        color = AppColors.cyan;
        label = 'AC';
      } else if (box.kind == 'sink') {
        color = AppColors.green;
        label = 'Window';
      } else if (box.kind == 'heat') {
        color = AppColors.red;
        label = 'PC';
      }
      if (color == null || label == null) continue;
      final c = box.center;
      final p = _project(_V(c.x, c.y, c.z), size, cam);
      if (p != null) _drawAnchor(canvas, p.$1, color, label);
    }
  }

  void _drawBox(Canvas canvas, Size size, _Cam3 cam, AirflowVec3 min, AirflowVec3 max, Color fill) {
    final corners = [
      _V(min.x, min.y, min.z),
      _V(max.x, min.y, min.z),
      _V(max.x, min.y, max.z),
      _V(min.x, min.y, max.z),
      _V(min.x, max.y, min.z),
      _V(max.x, max.y, min.z),
      _V(max.x, max.y, max.z),
      _V(min.x, max.y, max.z),
    ];
    final p = corners.map((v) => _project(v, size, cam)).toList();
    if (p[4] != null && p[5] != null && p[6] != null && p[7] != null) {
      final path = Path()
        ..moveTo(p[4]!.$1.dx, p[4]!.$1.dy)
        ..lineTo(p[5]!.$1.dx, p[5]!.$1.dy)
        ..lineTo(p[6]!.$1.dx, p[6]!.$1.dy)
        ..lineTo(p[7]!.$1.dx, p[7]!.$1.dy)
        ..close();
      canvas.drawPath(path, Paint()..color = fill);
    }
    final edge = Paint()
      ..color = AppColors.textMuted.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    void e(int a, int b) {
      if (p[a] == null || p[b] == null) return;
      canvas.drawLine(p[a]!.$1, p[b]!.$1, edge);
    }

    e(0, 1);
    e(1, 2);
    e(2, 3);
    e(3, 0);
    e(4, 5);
    e(5, 6);
    e(6, 7);
    e(7, 4);
    e(0, 4);
    e(1, 5);
    e(2, 6);
    e(3, 7);
  }

  void _drawAnchor(Canvas canvas, Offset center, Color color, String label) {
    canvas.drawCircle(center, 6.5, Paint()..color = color.withValues(alpha: 0.95));
    canvas.drawCircle(
      center,
      14,
      Paint()
        ..color = color.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - 22));
  }

  @override
  bool shouldRepaint(covariant AirflowVoxelPainter old) =>
      old.time != time ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.distance != distance ||
      old.vizMode != vizMode ||
      old.snapshot != snapshot ||
      old.showVoxels != showVoxels ||
      old.showDeadZones != showDeadZones;
}

class _V {
  final double x, y, z;
  const _V(this.x, this.y, this.z);
  _V operator -(_V o) => _V(x - o.x, y - o.y, z - o.z);
}

class _Cam3 {
  final double roomWidth, roomDepth, roomHeight, yaw, pitch, distance;
  _Cam3({
    required this.roomWidth,
    required this.roomDepth,
    required this.roomHeight,
    required this.yaw,
    required this.pitch,
    required this.distance,
  });
}

_V _cross(_V a, _V b) => _V(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
double _dot(_V a, _V b) => a.x * b.x + a.y * b.y + a.z * b.z;
_V _norm(_V v) {
  final m = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
  if (m < 1e-4) return const _V(0, 0, 1);
  return _V(v.x / m, v.y / m, v.z / m);
}

(Offset, double)? _project(_V p, Size size, _Cam3 cam) {
  final center = _V(cam.roomWidth * 0.5, cam.roomHeight * 0.45, cam.roomDepth * 0.5);
  final horizontal = cam.distance * math.cos(cam.pitch);
  final eye = _V(
    center.x + horizontal * math.sin(cam.yaw),
    center.y + cam.distance * math.sin(cam.pitch),
    center.z + horizontal * math.cos(cam.yaw),
  );
  final forward = _norm(center - eye);
  final right = _norm(_cross(forward, const _V(0, 1, 0)));
  final up = _norm(_cross(right, forward));
  final rel = p - eye;
  final cx = _dot(rel, right);
  final cy = _dot(rel, up);
  final cz = _dot(rel, forward);
  if (cz <= 0.06) return null;
  const fov = 55 * math.pi / 180;
  final focal = (size.width * 0.5) / math.tan(fov * 0.5);
  return (
    Offset(size.width * 0.5 + (cx / cz) * focal, size.height * 0.58 - (cy / cz) * focal),
    cz,
  );
}
