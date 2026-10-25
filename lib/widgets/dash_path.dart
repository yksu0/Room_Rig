// Tiny dashed polyline helper for door swing “other half” cues.
import 'dart:math' as math;
import 'dart:ui';

void drawDashedPolyline(
  Canvas canvas,
  List<Offset> points,
  Paint paint, {
  double dash = 5,
  double gap = 3.5,
}) {
  if (points.length < 2) return;
  for (var i = 0; i < points.length - 1; i++) {
    final a = points[i];
    final b = points[i + 1];
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) continue;
    final ux = dx / len;
    final uy = dy / len;
    var t = 0.0;
    var draw = true;
    while (t < len) {
      final seg = math.min(draw ? dash : gap, len - t);
      if (draw) {
        canvas.drawLine(
          Offset(a.dx + ux * t, a.dy + uy * t),
          Offset(a.dx + ux * (t + seg), a.dy + uy * (t + seg)),
          paint,
        );
      }
      t += seg;
      draw = !draw;
    }
  }
}
