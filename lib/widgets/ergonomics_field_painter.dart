// lib/widgets/ergonomics_field_painter.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/ergonomics_simulator.dart';
import '../theme/app_theme.dart';

enum ErgonomicsVizMode { topDown2D, orbit3D }

class ErgonomicsFieldPainter extends CustomPainter {
  final ErgonomicsSimSnapshot snapshot;
  final ErgonomicsVizMode vizMode;
  final double yaw;
  final double pitch;
  final double distance;
  final double pulse;

  ErgonomicsFieldPainter({
    required this.snapshot,
    required this.vizMode,
    required this.yaw,
    required this.pitch,
    required this.distance,
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
    final pad = 14.0;
    final legendW = 118.0;
    final rect = Rect.fromLTWH(pad, pad, size.width - pad * 2 - legendW, size.height - pad * 2);
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

    // Furniture as quiet silhouettes — labels only on path anchors.
    const anchorIds = {'bed', 'desk', 'pc', 'chair', 'window', 'door'};
    for (final f in snapshot.furniture) {
      final r = Rect.fromPoints(
        map(f.gridX, f.gridY),
        map(f.gridX + f.width, f.gridY + f.height),
      );
      final isAnchor = anchorIds.contains(f.id);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r.deflate(1.5), const Radius.circular(5)),
        Paint()
          ..color = isAnchor
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.black.withValues(alpha: 0.22),
      );
      if (!isAnchor) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(r.deflate(1.5), const Radius.circular(5)),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
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
      tp.paint(canvas, Offset(r.center.dx - tp.width / 2, r.center.dy - tp.height / 2));
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

    _pathLegend(canvas, size, paths, legendLeft: rect.right + 10);
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
    final edges = [
      [0, 1], [1, 2], [2, 3], [3, 0],
      [4, 5], [5, 6], [6, 7], [7, 4],
      [0, 4], [1, 5], [2, 6], [3, 7],
    ];
    final wire = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 1.3;
    for (final e in edges) {
      final a = projected[e[0]];
      final b = projected[e[1]];
      if (a == null || b == null) continue;
      canvas.drawLine(a.$1, b.$1, wire);
    }

    for (final f in snapshot.furniture) {
      final h = f.id == 'bed'
          ? 0.7
          : (f.id == 'desk' || f.id == 'chair' ? 0.85 : 0.55);
      final box = [
        _V(f.gridX, 0, f.gridY),
        _V(f.gridX + f.width, 0, f.gridY),
        _V(f.gridX + f.width, 0, f.gridY + f.height),
        _V(f.gridX, 0, f.gridY + f.height),
        _V(f.gridX, h, f.gridY),
        _V(f.gridX + f.width, h, f.gridY),
        _V(f.gridX + f.width, h, f.gridY + f.height),
        _V(f.gridX, h, f.gridY + f.height),
      ];
      final isKey = f.id == 'desk' || f.id == 'chair' || f.id == 'bed' || f.id == 'pc';
      final fill = isKey
          ? Colors.white.withValues(alpha: 0.16)
          : Colors.white.withValues(alpha: 0.07);
      final top = [4, 5, 6, 7]
          .map((i) => _project(box[i], size, cam))
          .whereType<(Offset, double)>()
          .map((e) => e.$1)
          .toList();
      if (top.length == 4) {
        canvas.drawPath(Path()..addPolygon(top, true), Paint()..color = fill);
      }
      for (final e in [
        [0, 1], [1, 2], [2, 3], [3, 0],
        [4, 5], [5, 6], [6, 7], [7, 4],
        [0, 4], [1, 5], [2, 6], [3, 7],
      ]) {
        final a = _project(box[e[0]], size, cam);
        final b = _project(box[e[1]], size, cam);
        if (a == null || b == null) continue;
        canvas.drawLine(
          a.$1,
          b.$1,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.28)
            ..strokeWidth = 1,
        );
      }
    }

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

  void _pathLegend(Canvas canvas, Size size, List<ErgonomicsPath> paths, {required double legendLeft}) {
    var y = 22.0;
    final title = TextPainter(
      text: TextSpan(
        text: 'ROUTES',
        style: TextStyle(
          color: AppColors.textMuted,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    title.paint(canvas, Offset(legendLeft, y));
    y += 18;

    for (int i = 0; i < paths.length; i++) {
      final route = paths[i];
      final color = route.clear ? _pathColors[i % _pathColors.length] : AppColors.red;
      canvas.drawCircle(Offset(legendLeft + 5, y + 6), 4, Paint()..color = color);
      final tp = TextPainter(
        text: TextSpan(
          text: route.label,
          style: TextStyle(
            color: AppColors.textPrimary.withValues(alpha: 0.9),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: size.width - legendLeft - 16);
      tp.paint(canvas, Offset(legendLeft + 14, y));
      y += tp.height + 10;
    }

    if (paths.isEmpty) {
      final empty = TextPainter(
        text: TextSpan(
          text: 'No routes',
          style: TextStyle(color: AppColors.textMuted, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      empty.paint(canvas, Offset(legendLeft, y));
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
