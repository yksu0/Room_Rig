import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/room_model.dart';
import '../models/room_scale.dart';
import '../models/surface_mount.dart';
import '../services/gltf_catalog.dart';
import '../theme/app_theme.dart';
import 'room_model_scene_stub.dart'
    if (dart.library.html) 'room_model_scene_web.dart' as platform;

/// Interactive three.js room with Kenney CC0 furniture GLBs + textured shell.
///
/// Used by Rig (Model view) and Bench layout previews. Editing still happens in
/// 2D / orbit paint modes; this view is the high-fidelity visualization.
class RoomModelScene extends StatefulWidget {
  final RoomData room;
  final List<FurnitureItem> furniture;
  final String? selectedId;
  final double? yaw;
  final double? pitch;
  final double? distance;

  const RoomModelScene({
    super.key,
    required this.room,
    required this.furniture,
    this.selectedId,
    this.yaw,
    this.pitch,
    this.distance,
  });

  @override
  State<RoomModelScene> createState() => _RoomModelSceneState();
}

class _RoomModelSceneState extends State<RoomModelScene> {
  WebViewController? _controller;
  bool _ready = false;
  bool _failed = false;
  String? _error;
  bool _webRegistered = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      platform.createRoomModelIFrame(onReady: () {
        _ready = true;
        _pushScene();
      });
      _webRegistered = true;
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        _ready = true;
        _pushScene();
      });
      return;
    }
    _initController();
  }

  Future<void> _initController() async {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF87B8E0))
      ..addJavaScriptChannel(
        'RoomRigChannel',
        onMessageReceived: (msg) {
          try {
            final data = jsonDecode(msg.message) as Map<String, dynamic>;
            if (data['type'] == 'ready') {
              _ready = true;
              _pushScene();
            }
          } catch (_) {}
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _ready = true;
            _pushScene();
          },
          onWebResourceError: (err) {
            if (!mounted) return;
            setState(() {
              _failed = true;
              _error = err.description;
            });
          },
        ),
      );

    try {
      await controller.loadFlutterAsset('assets/scene/room_viewer.html');
      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _error = '$e';
      });
    }
  }

  @override
  void didUpdateWidget(covariant RoomModelScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room != widget.room ||
        oldWidget.furniture != widget.furniture ||
        oldWidget.selectedId != widget.selectedId ||
        oldWidget.yaw != widget.yaw ||
        oldWidget.pitch != widget.pitch ||
        oldWidget.distance != widget.distance) {
      _pushScene();
    }
  }

  String _wallName(RoomWall wall) {
    switch (wall) {
      case RoomWall.north:
        return 'north';
      case RoomWall.south:
        return 'south';
      case RoomWall.east:
        return 'east';
      case RoomWall.west:
        return 'west';
    }
  }

  Map<String, dynamic> _scenePayload() {
    final cols = widget.room.gridCols;
    final rows = widget.room.gridRows;
    final roomW = RoomScale.metersFromCells(cols);
    final roomD = RoomScale.metersFromCells(rows);
    final cellW = roomW / cols;
    final cellD = roomD / rows;
    final openings = <Map<String, dynamic>>[];

    final items = widget.furniture.map((f) {
      final profile = GltfCatalog.profileForItem(f);
      final modelUrl = GltfCatalog.sceneUrlForIcon(f.iconName);
      final mount = SurfaceMounts.of(
        f,
        gridCols: cols,
        gridRows: rows,
        furniture: widget.furniture,
      );

      double x = (f.gridX + f.width * 0.5) * cellW;
      double y = 0;
      double z = (f.gridY + f.height * 0.5) * cellD;
      var yaw = f.yawDegrees;
      var itemW = f.width * cellW;
      var itemD = f.height * cellD;

      if (mount.isWall && mount.span != null) {
        final span = mount.span!;
        final midX = (span.x0 + span.x1) * 0.5 * cellW;
        final midZ = (span.z0 + span.z1) * 0.5 * cellD;
        // Sit in the wall plane, slightly inset so the frame reads from inside.
        x = midX + span.inwardX * cellW * 0.08;
        z = midZ + span.inwardZ * cellD * 0.08;
        y = mount.bottomY;
        itemW = span.length * (span.inwardZ.abs() > 0.5 ? cellW : cellD);
        itemD = 0.2;
        yaw = switch (span.wall) {
          RoomWall.north => 0,
          RoomWall.south => 180,
          RoomWall.east => 90,
          RoomWall.west => -90,
        };

        final along0 = span.inwardZ.abs() > 0.5
            ? (span.x0 < span.x1 ? span.x0 : span.x1) * cellW
            : (span.z0 < span.z1 ? span.z0 : span.z1) * cellD;
        final along1 = span.inwardZ.abs() > 0.5
            ? (span.x0 < span.x1 ? span.x1 : span.x0) * cellW
            : (span.z0 < span.z1 ? span.z1 : span.z0) * cellD;

        if (profile.isOpening || profile.isGlass) {
          openings.add({
            'wall': _wallName(span.wall),
            'along0': along0,
            'along1': along1,
            'y0': mount.bottomY,
            'y1': mount.topY,
            'glass': profile.isGlass || f.iconName == 'window',
          });
        }
      } else if (mount.isCeiling) {
        y = mount.bottomY;
      } else if (mount.isDesk) {
        y = mount.bottomY;
      }

      return {
        'id': f.id,
        'kind': f.iconName,
        'model': modelUrl,
        'x': x,
        'y': y,
        'z': z,
        'w': itemW,
        'd': itemD,
        'h': profile.heightMeters,
        'yaw': yaw,
        'selected': f.id == widget.selectedId,
        'mount': mount.isWall
            ? 'wall'
            : mount.isCeiling
                ? 'ceiling'
                : 'floor',
        'opening': profile.isOpening || profile.isGlass,
        'lightTransmit': profile.lightTransmit,
      };
    }).toList();

    return {
      'roomW': roomW,
      'roomD': roomD,
      'roomH': widget.room.heightMeters > 0
          ? widget.room.heightMeters
          : RoomScale.defaultHeightMeters,
      'items': items,
      'openings': openings,
      if (widget.yaw != null) 'yaw': widget.yaw,
      if (widget.pitch != null) 'pitch': widget.pitch,
      if (widget.distance != null) 'distance': widget.distance,
    };
  }

  Future<void> _pushScene() async {
    if (!_ready) return;
    final payload = _scenePayload();
    if (kIsWeb) {
      platform.pushRoomModelSceneWeb(payload);
      return;
    }
    final c = _controller;
    if (c == null) return;
    final json = jsonEncode(payload);
    try {
      await c.runJavaScript('window.setRoomScene($json);');
    } catch (e) {
      debugPrint('RoomModelScene push failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Container(
        color: AppColors.bg,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Text(
          _error ?? 'Model scene unavailable',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    }

    final sceneChild = kIsWeb
        ? (_webRegistered
            ? const HtmlElementView(viewType: 'room-model-scene')
            : const SizedBox.shrink())
        : _controller == null
            ? null
            : WebViewWidget(controller: _controller!);

    if (sceneChild == null) {
      return const ColoredBox(
        color: AppColors.bg,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.cyan),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Stack(
        fit: StackFit.expand,
        children: [
          sceneChild,
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text(
                'MODEL · exterior · mesh sims',
                style: TextStyle(
                  color: AppColors.cyan,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
