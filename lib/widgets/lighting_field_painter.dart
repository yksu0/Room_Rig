// lib/widgets/lighting_field_painter.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/room_model.dart';
import '../services/lighting_simulator.dart';
import '../theme/app_theme.dart';
import 'bench_room_views.dart';

enum LightingVizMode { topDown2D, orbit3D }

class LightingFieldPainter extends CustomPainter {
  final LightingSimSnapshot snapshot;
  final List<FurnitureItem> furniture;
  final LightingVizMode vizMode;
  final double yaw;
  final double pitch;
  final double distance;
  final double? lookAtX;
  final double? lookAtZ;
  final double pulse;

  LightingFieldPainter({
    required this.snapshot,
    required this.furniture,
    required this.vizMode,
    required this.yaw,
    required this.pitch,
    required this.distance,
    this.lookAtX,
    this.lookAtZ,
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
    final gridCols = snapshot.roomWidth.round().clamp(1, 64);
    final gridRows = snapshot.roomDepth.round().clamp(1, 64);
    final rect = BenchRoom2DGeometry.fieldRectFor(
      size: size,
      gridCols: gridCols,
      gridRows: gridRows,
    );
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
        if (v < 0.18) {
          canvas.drawRect(
            Rect.fromLTWH(rect.left + x * cellW, rect.top + z * cellH, cellW - 0.3, cellH - 0.3),
            Paint()..color = AppColors.red.withValues(alpha: 0.16),
          );
        }
      }
    }

    BenchFurnitureRenderer.paint2D(
      canvas,
      roomRect: rect,
      gridCols: gridCols,
      gridRows: gridRows,
      furniture: furniture,
    );
  }

  void _paint3D(Canvas canvas, Size size) {
    final gridCols = snapshot.roomWidth.round().clamp(1, 64);
    final gridRows = snapshot.roomDepth.round().clamp(1, 64);
    const roomHeight = 2.8;

    BenchFurnitureRenderer.paint3DScene(
      canvas,
      size,
      roomWidth: snapshot.roomWidth,
      roomDepth: snapshot.roomDepth,
      roomHeight: roomHeight,
      gridCols: gridCols,
      gridRows: gridRows,
      yaw: yaw,
      pitch: pitch,
      distance: distance,
      lookAtX: lookAtX,
      lookAtZ: lookAtZ,
      furniture: furniture,
    );

    final cam = _Cam(
      roomWidth: snapshot.roomWidth,
      roomDepth: snapshot.roomDepth,
      roomHeight: roomHeight,
      yaw: yaw,
      pitch: pitch,
      distance: distance,
      lookAtX: lookAtX,
      lookAtZ: lookAtZ,
    );

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
  }

  @override
  bool shouldRepaint(covariant LightingFieldPainter old) =>
      old.snapshot != snapshot ||
      old.furniture != furniture ||
      old.vizMode != vizMode ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.distance != distance ||
      old.lookAtX != lookAtX ||
      old.lookAtZ != lookAtZ ||
      old.pulse != pulse;
}

class _V {
  final double x, y, z;
  const _V(this.x, this.y, this.z);
  _V operator -(_V o) => _V(x - o.x, y - o.y, z - o.z);
}

class _Cam {
  final double roomWidth, roomDepth, roomHeight, yaw, pitch, distance;
  final double? lookAtX, lookAtZ;
  _Cam({
    required this.roomWidth,
    required this.roomDepth,
    required this.roomHeight,
    required this.yaw,
    required this.pitch,
    required this.distance,
    this.lookAtX,
    this.lookAtZ,
  });

  double get pivotX => lookAtX ?? roomWidth * 0.5;
  double get pivotZ => lookAtZ ?? roomDepth * 0.5;
}

_V _cross(_V a, _V b) => _V(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
double _dot(_V a, _V b) => a.x * b.x + a.y * b.y + a.z * b.z;
_V _norm(_V v) {
  final m = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
  if (m < 1e-4) return const _V(0, 0, 1);
  return _V(v.x / m, v.y / m, v.z / m);
}

(Offset, double)? _project(_V p, Size size, _Cam cam) {
  final center = _V(cam.pivotX, cam.roomHeight * 0.45, cam.pivotZ);
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
