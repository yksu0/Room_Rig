import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/room_model.dart';
import '../models/room_scale.dart';
import '../services/gltf_catalog.dart';
import '../theme/app_theme.dart';

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

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _failed = true;
      _error = 'Model scene uses a native WebView (run on Android/iOS).';
      return;
    }
    _initController();
  }

  Future<void> _initController() async {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.bg)
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

  Map<String, dynamic> _scenePayload() {
    final cols = widget.room.gridCols;
    final rows = widget.room.gridRows;
    final roomW = RoomScale.metersFromCells(cols);
    final roomD = RoomScale.metersFromCells(rows);
    final cellW = roomW / cols;
    final cellD = roomD / rows;

    final items = widget.furniture.map((f) {
      final model = GltfCatalog.assetForIcon(f.iconName);
      // Convert Flutter asset path → relative URL from room_viewer.html
      final modelUrl = model == null
          ? null
          : '../gltf/${model.replaceFirst('assets/gltf/', '')}';
      return {
        'id': f.id,
        'kind': f.iconName,
        'model': modelUrl,
        'x': (f.gridX + f.width * 0.5) * cellW,
        'y': 0.0,
        'z': (f.gridY + f.height * 0.5) * cellD,
        'w': f.width * cellW,
        'd': f.height * cellD,
        'h': GltfCatalog.defaultHeightMeters(f.iconName),
        'yaw': f.yawDegrees,
        'selected': f.id == widget.selectedId,
      };
    }).toList();

    return {
      'roomW': roomW,
      'roomD': roomD,
      'roomH': widget.room.heightMeters > 0
          ? widget.room.heightMeters
          : RoomScale.defaultHeightMeters,
      'items': items,
      if (widget.yaw != null) 'yaw': widget.yaw,
      if (widget.pitch != null) 'pitch': widget.pitch,
      if (widget.distance != null) 'distance': widget.distance,
    };
  }

  Future<void> _pushScene() async {
    final c = _controller;
    if (c == null || !_ready) return;
    final json = jsonEncode(_scenePayload());
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
    final c = _controller;
    if (c == null) {
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
          WebViewWidget(controller: c),
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
                'MODEL · Kenney CC0 + Poly Haven',
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
