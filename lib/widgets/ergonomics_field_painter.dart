// lib/widgets/ergonomics_field_painter.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/ergonomics_simulator.dart';
import '../theme/app_theme.dart';
import 'bench_room_views.dart';
import 'furniture_shapes.dart';

enum ErgonomicsVizMode { topDown2D, orbit3D }

class ErgonomicsFieldPainter extends CustomPainter {
  final ErgonomicsSimSnapshot snapshot;
  final ErgonomicsVizMode vizMode;
  final double yaw;
  final double pitch;
  final double distance;
  final double? lookAtX;
  final double? lookAtZ;
  final double pulse;

  ErgonomicsFieldPainter({
    required this.snapshot,
    required this.vizMode,
    required this.yaw,
    required this.pitch,
    required this.distance,
    this.lookAtX,
    this.lookAtZ,
    this.pulse = 0.5,
  });

  /// Keep the busiest routes only so the view stays readable.
  List<ErgonomicsPath> get _focusPaths {
    final sorted = [...snapshot.paths]..sort((a, b) => b.frequency.compareTo(a.frequency));
    return sorted.take(3).toList(growable: false);
  }

  static const _pathColors = [
    AppColors.ergonomicsColor,
    AppColors.cyan,
    AppColors.amber,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: snapshot.optimized
            ? [AppColors.ergonomicsColor.withValues(alpha: 0.10), Colors.transparent]
            : [AppColors.amber.withValues(alpha: 0.08), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg);

    if (vizMode == ErgonomicsVizMode.topDown2D) {
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
      Paint()..color = AppColors.surfaceAlt.withValues(alpha: 0.92),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      Paint()
        ..color = AppColors.border.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke,
    );

    Offset map(double x, double z) => Offset(
          rect.left + (x / snapshot.roomWidth) * rect.width,
          rect.top + (z / snapshot.roomDepth) * rect.height,
        );

    // Furniture silhouettes + anchor labels on key path nodes.
    const anchorIds = {'bed', 'desk', 'pc', 'chair', 'window', 'door'};
    BenchFurnitureRenderer.paint2D(
      canvas,
      roomRect: rect,
      gridCols: gridCols,
      gridRows: gridRows,
      furniture: snapshot.furniture,
    );
    for (final f in snapshot.furniture) {
      if (!anchorIds.contains(f.id)) continue;
      final r = FurnitureShapes.planCell(
        room: rect,
        item: f,
        roomWidth: snapshot.roomWidth,
        roomDepth: snapshot.roomDepth,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: f.id,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: r.width);
      tp.paint(canvas, Offset(r.center.dx - tp.width / 2, r.bottom - tp.height - 2));
    }

    final paths = _focusPaths;
    for (int i = 0; i < paths.length; i++) {
      final route = paths[i];
      if (route.points.length < 2) continue;
      final color = route.clear ? _pathColors[i % _pathColors.length] : AppColors.red;
      final pts = route.points.map((p) => map(p.x, p.z)).toList();
      final curve = _smoothCurve(pts);

      // Soft glow under the stroke
      canvas.drawPath(
        curve,
        Paint()
          ..color = color.withValues(alpha: 0.18 + pulse * 0.06)
          ..strokeWidth = 7 + route.frequency * 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );

      final stroke = Paint()
        ..color = color.withValues(alpha: 0.85)
        ..strokeWidth = 2.4 + route.frequency * 1.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      if (route.clear) {
        canvas.drawPath(curve, stroke);
      } else {
        _drawDashedPath(canvas, curve, stroke);
      }

      // Endpoints
      canvas.drawCircle(pts.first, 4, Paint()..color = color);
      canvas.drawCircle(pts.last, 4, Paint()..color = color);
      canvas.drawCircle(pts.first, 2, Paint()..color = Colors.white.withValues(alpha: 0.85));
      canvas.drawCircle(pts.last, 2, Paint()..color = Colors.white.withValues(alpha: 0.85));
    }

    _pathLegend(canvas, size, paths, roomRect: rect);
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
      furniture: snapshot.furniture,
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

    final paths = _focusPaths;
    for (int i = 0; i < paths.length; i++) {
      final route = paths[i];
      if (route.points.length < 2) continue;
      final color = route.clear ? _pathColors[i % _pathColors.length] : AppColors.red;

      // Densify in world space, then project — keeps curves smooth in orbit view.
      final world = _catmullSamples(route.points);
      final screen = <Offset>[];
      for (final pt in world) {
        final p = _project(_V(pt.x, 0.08, pt.z), size, cam);
        if (p != null) screen.add(p.$1);
      }
      if (screen.length < 2) continue;
      final curve = _smoothCurve(screen);
      canvas.drawPath(
        curve,
        Paint()
          ..color = color.withValues(alpha: 0.22)
          ..strokeWidth = 6 + route.frequency * 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawPath(
        curve,
        Paint()
          ..color = color.withValues(alpha: 0.9)
          ..strokeWidth = 2.2 + route.frequency * 1.6
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  void _pathLegend(Canvas canvas, Size size, List<ErgonomicsPath> paths, {required Rect roomRect}) {
    var x = roomRect.left;
    final y = math.min(roomRect.bottom + 6, size.height - 52);
    if (y + 40 > size.height) return;

    for (int i = 0; i < paths.length; i++) {
      final route = paths[i];
      final color = route.clear ? _pathColors[i % _pathColors.length] : AppColors.red;
      canvas.drawCircle(Offset(x + 5, y + 8), 4, Paint()..color = color);
      final tp = TextPainter(
        text: TextSpan(
          text: route.label,
          style: TextStyle(
            color: AppColors.textPrimary.withValues(alpha: 0.9),
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 120);
      tp.paint(canvas, Offset(x + 12, y));
      x += tp.width + 22;
      if (x > roomRect.right - 40) break;
    }
  }

  /// Catmull-Rom → cubic Bezier path through screen points.
  Path _smoothCurve(List<Offset> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    if (pts.length == 1) {
      path.moveTo(pts.first.dx, pts.first.dy);
      return path;
    }
    if (pts.length == 2) {
      path.moveTo(pts[0].dx, pts[0].dy);
      path.lineTo(pts[1].dx, pts[1].dy);
      return path;
    }

    path.moveTo(pts.first.dx, pts.first.dy);
    for (int i = 0; i < pts.length - 1; i++) {
      final p0 = pts[i == 0 ? 0 : i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = pts[i + 2 < pts.length ? i + 2 : i + 1];
      final c1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );
      final c2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  List<({double x, double z})> _catmullSamples(List<({double x, double z})> pts) {
    if (pts.length < 3) return pts;
    final out = <({double x, double z})>[];
    for (int i = 0; i < pts.length - 1; i++) {
      final p0 = pts[i == 0 ? 0 : i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = pts[i + 2 < pts.length ? i + 2 : i + 1];
      const steps = 8;
      for (int s = 0; s < steps; s++) {
        final t = s / steps;
        out.add(_catmullPoint(p0, p1, p2, p3, t));
      }
    }
    out.add(pts.last);
    return out;
  }

  ({double x, double z}) _catmullPoint(
    ({double x, double z}) p0,
    ({double x, double z}) p1,
    ({double x, double z}) p2,
    ({double x, double z}) p3,
    double t,
  ) {
    final t2 = t * t;
    final t3 = t2 * t;
    double axis(double a0, double a1, double a2, double a3) {
      return 0.5 *
          ((2 * a1) +
              (-a0 + a2) * t +
              (2 * a0 - 5 * a1 + 4 * a2 - a3) * t2 +
              (-a0 + 3 * a1 - 3 * a2 + a3) * t3);
    }

    return (x: axis(p0.x, p1.x, p2.x, p3.x), z: axis(p0.z, p1.z, p2.z, p3.z));
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      const dash = 8.0;
      const gap = 6.0;
      while (dist < metric.length) {
        final next = math.min(dist + dash, metric.length);
        canvas.drawPath(metric.extractPath(dist, next), paint);
        dist = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant ErgonomicsFieldPainter oldDelegate) {
    return oldDelegate.snapshot != snapshot ||
        oldDelegate.vizMode != vizMode ||
        oldDelegate.yaw != yaw ||
        oldDelegate.pitch != pitch ||
        oldDelegate.distance != distance ||
        oldDelegate.lookAtX != lookAtX ||
        oldDelegate.lookAtZ != lookAtZ ||
        oldDelegate.pulse != pulse;
  }
}

class _V {
  final double x, y, z;
  const _V(this.x, this.y, this.z);
  _V operator -(_V o) => _V(x - o.x, y - o.y, z - o.z);
}

class _Cam {
  final double roomWidth, roomDepth, roomHeight;
  final double yaw, pitch, distance;
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
