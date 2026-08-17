// lib/widgets/room_orbit_projection.dart
// Pinhole camera used by the Rig's pseudo-3D room view. Kept separate from the
// screen so the projection (and its floor-plane inverse, which drag-to-move
// depends on) can be exercised directly.
import 'dart:math' as math;
import 'dart:ui' show Offset, Size;
import 'package:flutter/material.dart' show Color;

class OrbitVec3 {
  final double x;
  final double y;
  final double z;
  const OrbitVec3(this.x, this.y, this.z);

  OrbitVec3 operator -(OrbitVec3 o) => OrbitVec3(x - o.x, y - o.y, z - o.z);
  OrbitVec3 operator +(OrbitVec3 o) => OrbitVec3(x + o.x, y + o.y, z + o.z);
  OrbitVec3 scale(double s) => OrbitVec3(x * s, y * s, z * s);
}

class RoomFace {
  final List<OrbitVec3> vertices;
  final Color color;
  RoomFace(this.vertices, this.color);
}

class ProjectedFace {
  final List<Offset> points;
  final double depth;
  final Color color;
  ProjectedFace({required this.points, required this.depth, required this.color});
}

class ProjectedPoint {
  final Offset offset;
  final double depth;
  ProjectedPoint(this.offset, this.depth);
}

class CameraPose {
  final double roomWidth;
  final double roomDepth;
  final double roomHeight;
  final double yaw;
  final double pitch;
  final double distance;

  /// Orbit pivot on the floor plane. Defaults to room center when null.
  final double? lookAtX;
  final double? lookAtZ;

  const CameraPose({
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

class RoomProjection {
  RoomProjection._();

  static const fov = 55 * math.pi / 180;

  /// Vertical screen anchor. The horizon sits slightly below center so the
  /// floor gets more of the canvas than the ceiling.
  static const verticalAnchor = 0.58;

  static OrbitVec3 _cross(OrbitVec3 a, OrbitVec3 b) =>
      OrbitVec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);

  static double _dot(OrbitVec3 a, OrbitVec3 b) => a.x * b.x + a.y * b.y + a.z * b.z;

  static OrbitVec3 _normalize(OrbitVec3 v) {
    final m = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
    if (m <= 0.0001) return const OrbitVec3(0, 0, 1);
    return OrbitVec3(v.x / m, v.y / m, v.z / m);
  }

  static double _focal(Size size) => (size.width * 0.5) / math.tan(fov * 0.5);

  static (OrbitVec3, OrbitVec3, OrbitVec3, OrbitVec3) cameraBasis(CameraPose cam) {
    final center = OrbitVec3(cam.pivotX, cam.roomHeight * 0.45, cam.pivotZ);
    final horizontal = cam.distance * math.cos(cam.pitch);
    final eye = OrbitVec3(
      center.x + horizontal * math.sin(cam.yaw),
      center.y + cam.distance * math.sin(cam.pitch),
      center.z + horizontal * math.cos(cam.yaw),
    );
    final forward = _normalize(center - eye);
    const upWorld = OrbitVec3(0, 1, 0);
    final right = _normalize(_cross(forward, upWorld));
    final up = _normalize(_cross(right, forward));
    return (eye, forward, right, up);
  }

  /// Floor-plane right / forward unit vectors for two-finger pan.
  static (OrbitVec3 right, OrbitVec3 forward) floorPanAxes(CameraPose cam) {
    final (_, forward, right, _) = cameraBasis(cam);
    final flatRight = _normalize(OrbitVec3(right.x, 0, right.z));
    final flatFwd = _normalize(OrbitVec3(forward.x, 0, forward.z));
    return (flatRight, flatFwd);
  }

  static ProjectedPoint? project(OrbitVec3 p, Size size, CameraPose cam) {
    final (eye, forward, right, up) = cameraBasis(cam);
    final rel = p - eye;
    final cx = _dot(rel, right);
    final cy = _dot(rel, up);
    final cz = _dot(rel, forward);
    if (cz <= 0.06) return null;

    final focal = _focal(size);
    final sx = size.width * 0.5 + (cx / cz) * focal;
    final sy = size.height * verticalAnchor - (cy / cz) * focal;
    return ProjectedPoint(Offset(sx, sy), cz);
  }

  /// Inverse of [project] against the floor plane (y = 0), returning the world
  /// point as (x, z). Null when the ray never reaches the floor — which happens
  /// when the user drags above the horizon.
  static Offset? unprojectToFloor(Offset screen, Size size, CameraPose cam) {
    final (eye, forward, right, up) = cameraBasis(cam);
    final focal = _focal(size);
    final planeX = (screen.dx - size.width * 0.5) / focal;
    final planeY = (size.height * verticalAnchor - screen.dy) / focal;
    final dir = forward + right.scale(planeX) + up.scale(planeY);
    if (dir.y.abs() < 1e-6) return null;
    final t = -eye.y / dir.y;
    if (t <= 0) return null;
    return Offset(eye.x + dir.x * t, eye.z + dir.z * t);
  }

  static ProjectedFace? projectFace(RoomFace face, Size size, CameraPose cam) {
    final points = <Offset>[];
    double depth = 0;
    for (final v in face.vertices) {
      final p = project(v, size, cam);
      if (p == null) return null;
      points.add(p.offset);
      depth += p.depth;
    }
    depth /= face.vertices.length;
    return ProjectedFace(points: points, depth: depth, color: face.color);
  }
}
