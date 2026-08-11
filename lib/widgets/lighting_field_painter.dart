// lib/widgets/lighting_field_painter.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/lighting_simulator.dart';
import '../theme/app_theme.dart';

enum LightingVizMode { topDown2D, orbit3D }

class LightingFieldPainter extends CustomPainter {
  final LightingSimSnapshot snapshot;
  final LightingVizMode vizMode;
  final double yaw;
  final double pitch;
  final double distance;
  final double pulse;

  LightingFieldPainter({
    required this.snapshot,
    required this.vizMode,
    required this.yaw,
    required this.pitch,
    required this.distance,
    this.pulse = 0.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: snapshot.optimized
            ? [AppColors.lightingColor.withValues(alpha: 0.12), Colors.transparent]
            : [AppColors.red.withValues(alpha: 0.10), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg);

    if (vizMode == LightingVizMode.topDown2D) {
      _paint2D(canvas, size);
    } else {
      _paint3D(canvas, size);
    }
  }

  void _paint2D(Canvas canvas, Size size) {
    final pad = 16.0;
    final rect = Rect.fromLTWH(pad, pad, size.width - pad * 2, size.height - pad * 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      Paint()..color = AppColors.surfaceAlt.withValues(alpha: 0.9),
    );

    final cellW = rect.width / snapshot.nx;
    final cellH = rect.height / snapshot.nz;
    for (int z = 0; z < snapshot.nz; z++) {
      for (int x = 0; x < snapshot.nx; x++) {
        final v = snapshot.lux[snapshot.index(x, z)];
        if (v <= 0.001) {
          canvas.drawRect(
            Rect.fromLTWH(rect.left + x * cellW, rect.top + z * cellH, cellW - 0.3, cellH - 0.3),
            Paint()..color = AppColors.textMuted.withValues(alpha: 0.35),
          );
          continue;
        }
        final color = Color.lerp(
          const Color(0xFF1A1D26),
          AppColors.lightingColor,
          v.clamp(0.0, 1.0),
        )!;
        canvas.drawRect(
          Rect.fromLTWH(rect.left + x * cellW, rect.top + z * cellH, cellW - 0.3, cellH - 0.3),
          Paint()..color = color.withValues(alpha: (0.2 + v * 0.65).clamp(0.15, 0.85)),
        );
        if (v < 0.18 && !snapshot.optimized) {
          canvas.drawRect(
            Rect.fromLTWH(rect.left + x * cellW, rect.top + z * cellH, cellW - 0.3, cellH - 0.3),
            Paint()..color = AppColors.red.withValues(alpha: 0.16),
          );
        }
      }
    }

    // Occluders
    for (final o in snapshot.occluders) {
      final r = Rect.fromLTRB(
        rect.left + (o.minX / snapshot.roomWidth) * rect.width,
        rect.top + (o.minZ / snapshot.roomDepth) * rect.height,
        rect.left + (o.maxX / snapshot.roomWidth) * rect.width,
        rect.top + (o.maxZ / snapshot.roomDepth) * rect.height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(4)),
        Paint()..color = Colors.black.withValues(alpha: 0.35),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(4)),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke,
      );
    }

    // Lights
    for (final light in snapshot.lights) {
      final o = Offset(
        rect.left + (light.x / snapshot.roomWidth) * rect.width,
        rect.top + (light.z / snapshot.roomDepth) * rect.height,
      );
      final color = switch (light.kind) {
        'window' => AppColors.green,
        'ceiling' => AppColors.lightingColor,
        _ => AppColors.amber,
      };
      final radius = 10.0 + pulse * 4;
      canvas.drawCircle(
        o,
        radius * 2.2,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: 0.35), Colors.transparent],
          ).createShader(Rect.fromCircle(center: o, radius: radius * 2.2)),
      );
      canvas.drawCircle(o, 5, Paint()..color = color);
      final tp = TextPainter(
        text: TextSpan(
          text: light.label,
          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(o.dx - tp.width / 2, o.dy - 18));
    }
  }

  void _paint3D(Canvas canvas, Size size) {
    final cam = _Cam(
      roomWidth: snapshot.roomWidth,
      roomDepth: snapshot.roomDepth,
      roomHeight: 2.8,
      yaw: yaw,
      pitch: pitch,
      distance: distance,
    );

    // Room wireframe
    final corners = [
      const _V(0, 0, 0),
      _V(snapshot.roomWidth, 0, 0),
      _V(snapshot.roomWidth, 0, snapshot.roomDepth),
      _V(0, 0, snapshot.roomDepth),
      const _V(0, 2.8, 0),
      _V(snapshot.roomWidth, 2.8, 0),
      _V(snapshot.roomWidth, 2.8, snapshot.roomDepth),
      _V(0, 2.8, snapshot.roomDepth),
    ];
    final projected = corners.map((v) => _project(v, size, cam)).toList();
    final edge = Paint()
      ..color = AppColors.border.withValues(alpha: 0.85)
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

    // Floor lux points
    for (int z = 0; z < snapshot.nz; z += 2) {
      for (int x = 0; x < snapshot.nx; x += 2) {
        final v = snapshot.lux[snapshot.index(x, z)];
        if (v < 0.05) continue;
        final wx = (x + 0.5) * snapshot.roomWidth / snapshot.nx;
        final wz = (z + 0.5) * snapshot.roomDepth / snapshot.nz;
        final p = _project(_V(wx, 0.02, wz), size, cam);
        if (p == null) continue;
        canvas.drawCircle(
          p.$1,
          2.0 + v,
          Paint()..color = AppColors.lightingColor.withValues(alpha: (0.15 + v * 0.55).clamp(0.1, 0.7)),
        );
      }
    }

    // Furniture boxes
    for (final o in snapshot.occluders) {
      final a = _project(_V(o.minX, 0, o.minZ), size, cam);
      final b = _project(_V(o.maxX, 0, o.minZ), size, cam);
      final c = _project(_V(o.maxX, 0, o.maxZ), size, cam);
      final d = _project(_V(o.minX, 0, o.maxZ), size, cam);
      final a2 = _project(_V(o.minX, o.height, o.minZ), size, cam);
      final b2 = _project(_V(o.maxX, o.height, o.minZ), size, cam);
      final c2 = _project(_V(o.maxX, o.height, o.maxZ), size, cam);
      final d2 = _project(_V(o.minX, o.height, o.maxZ), size, cam);
      if ([a, b, c, d, a2, b2, c2, d2].any((p) => p == null)) continue;
      final top = Path()
        ..moveTo(a2!.$1.dx, a2.$1.dy)
        ..lineTo(b2!.$1.dx, b2.$1.dy)
        ..lineTo(c2!.$1.dx, c2.$1.dy)
        ..lineTo(d2!.$1.dx, d2.$1.dy)
        ..close();
      canvas.drawPath(top, Paint()..color = AppColors.surfaceAlt.withValues(alpha: 0.65));
      final e = Paint()
        ..color = AppColors.textMuted.withValues(alpha: 0.5)
        ..strokeWidth = 1;
      canvas.drawLine(a!.$1, b!.$1, e);
      canvas.drawLine(b.$1, c!.$1, e);
      canvas.drawLine(c.$1, d!.$1, e);
      canvas.drawLine(d.$1, a.$1, e);
      canvas.drawLine(a.$1, a2.$1, e);
      canvas.drawLine(b.$1, b2.$1, e);
      canvas.drawLine(c.$1, c2.$1, e);
      canvas.drawLine(d.$1, d2.$1, e);
    }

    for (final light in snapshot.lights) {
      final p = _project(_V(light.x, light.y, light.z), size, cam);
      if (p == null) continue;
      final color = switch (light.kind) {
        'window' => AppColors.green,
        'ceiling' => AppColors.lightingColor,
        _ => AppColors.amber,
      };
      canvas.drawCircle(p.$1, 8 + pulse * 3, Paint()..color = color.withValues(alpha: 0.25));
      canvas.drawCircle(p.$1, 4.5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant LightingFieldPainter old) =>
      old.snapshot != snapshot ||
      old.vizMode != vizMode ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.distance != distance ||
      old.pulse != pulse;
}

class _V {
  final double x, y, z;
  const _V(this.x, this.y, this.z);
  _V operator -(_V o) => _V(x - o.x, y - o.y, z - o.z);
}

class _Cam {
  final double roomWidth, roomDepth, roomHeight, yaw, pitch, distance;
  _Cam({
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

(Offset, double)? _project(_V p, Size size, _Cam cam) {
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
