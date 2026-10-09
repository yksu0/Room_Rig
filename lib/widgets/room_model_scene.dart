import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../models/room_model.dart';
import '../models/room_scale.dart';
import '../models/surface_mount.dart';
import '../services/gltf_catalog.dart';
import '../services/scene_asset_stage.dart';
import '../theme/app_theme.dart';
import 'chrome/adaptive_panel.dart';
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
  final ChromeViewMode exploreChrome;
  final CameraPreset? pendingPreset;
  final bool showMiniMap;
  final int focusToken;
  final VoidCallback? onPresetApplied;

  const RoomModelScene({
    super.key,
    required this.room,
    required this.furniture,
    this.selectedId,
    this.yaw,
    this.pitch,
    this.distance,
    this.exploreChrome = ChromeViewMode.check,
    this.pendingPreset,
    this.showMiniMap = false,
    this.focusToken = 0,
    this.onPresetApplied,
  });

  @override
  State<RoomModelScene> createState() => RoomModelSceneState();
}

class RoomModelSceneState extends State<RoomModelScene> {
  WebViewController? _controller;
  bool _ready = false;
  bool _failed = false;
  String? _error;
  bool _webRegistered = false;
  CameraPreset? _lastPreset;
  int _lastFocusToken = 0;

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
            // Subresource misses (GLB/texture) must not blank the whole Model view.
            if (err.isForMainFrame != true) {
              debugPrint('Model asset error: ${err.description} ${err.url}');
              return;
            }
            if (!mounted) return;
            setState(() {
              _failed = true;
              _error = err.description;
            });
          },
        ),
      );

    try {
      if (controller.platform is AndroidWebViewController) {
        await (controller.platform as AndroidWebViewController)
            .setAllowFileAccess(true);
      }

      // Android: localhost HTTP so Three.js can fetch ../gltf/*.glb
      // (file:// XHR is blocked with net::ERR_FAILED).
      final stagedUrl = (!kIsWeb &&
              defaultTargetPlatform == TargetPlatform.android)
          ? await SceneAssetStage.ensureViewerHtml()
          : null;

      if (stagedUrl != null) {
        await controller.loadRequest(Uri.parse(stagedUrl));
      } else {
        await controller.loadFlutterAsset('assets/scene/room_viewer.html');
      }
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
        oldWidget.distance != widget.distance ||
        oldWidget.exploreChrome != widget.exploreChrome ||
        oldWidget.showMiniMap != widget.showMiniMap ||
        oldWidget.pendingPreset != widget.pendingPreset ||
        oldWidget.focusToken != widget.focusToken) {
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
        final alongIsX = span.inwardZ.abs() > 0.5;
        final alongCell = alongIsX ? cellW : cellD;
        final a0g = alongIsX
            ? (span.x0 < span.x1 ? span.x0 : span.x1)
            : (span.z0 < span.z1 ? span.z0 : span.z1);
        final a1g = alongIsX
            ? (span.x0 < span.x1 ? span.x1 : span.x0)
            : (span.z0 < span.z1 ? span.z1 : span.z0);
        var along0 = a0g * alongCell;
        var along1 = a1g * alongCell;
        final footprintAlong = (alongIsX ? f.width : f.height) * alongCell;
        final clearAlong = profile.clearWidthMeters ?? footprintAlong;
        final midAlong = (along0 + along1) * 0.5;
        final half = clearAlong * 0.5;
        final maxAlong = alongIsX ? roomW : roomD;
        along0 = (midAlong - half).clamp(0.0, maxAlong);
        along1 = (midAlong + half).clamp(0.0, maxAlong);

        final midX = (span.x0 + span.x1) * 0.5 * cellW;
        final midZ = (span.z0 + span.z1) * 0.5 * cellD;
        final insetM = profile.wallCut == WallCutKind.through
            ? 0.04
            : mount.protrusion * (alongIsX ? cellD : cellW) * 0.28;
        x = midX + span.inwardX * insetM;
        z = midZ + span.inwardZ * insetM;
        y = mount.bottomY;
        itemW = clearAlong;
        itemD = profile.wallCut == WallCutKind.through
            ? 0.14
            : (0.12 + mount.protrusion * 0.12).clamp(0.1, 0.4);
        yaw = switch (span.wall) {
          RoomWall.north => 0,
          RoomWall.south => 180,
          RoomWall.east => 90,
          RoomWall.west => -90,
        };

        String? wallName;
        if (profile.cutsWall) {
          wallName = _wallName(span.wall);
          final pad = profile.wallCutPadMeters;
          final clearH = profile.openingHeightMeters;
          final y0 = mount.bottomY;
          final y1 = (y0 + clearH).clamp(y0 + 0.1, 3.2);
          openings.add({
            'wall': wallName,
            'along0': (along0 - pad).clamp(0.0, maxAlong),
            'along1': (along1 + pad).clamp(0.0, maxAlong),
            'y0': (y0 - (profile.wallCut == WallCutKind.niche ? 0.01 : 0)).clamp(
              0.0,
              3.0,
            ),
            'y1': (y1 + pad).clamp(0.0, 3.2),
            'glass': profile.wallCut == WallCutKind.through && profile.isGlass,
            'through': profile.wallCut == WallCutKind.through,
            'kind': profile.wallCut.name,
          });
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
          'h': profile.openingHeightMeters,
          'yaw': yaw,
          'selected': f.id == widget.selectedId,
          'mount': 'wall',
          'wall': wallName ?? _wallName(span.wall),
          'opening': profile.isOpening || profile.isGlass,
          'glass': profile.isGlass,
          'cutKind': profile.cutsWall ? profile.wallCut.name : null,
          'lightTransmit': profile.lightTransmit,
          ...profile.fitPayload(),
          // Wall openings always use clear W×H from the profile.
          'fit': MeshFitMode.wallOpening.name,
          'tw': profile.clearWidthMeters ?? profile.targetWidthMeters ?? itemW,
          'th': profile.openingHeightMeters,
        };
      } else if (mount.isCeiling) {
        y = mount.bottomY;
      } else if (mount.isDesk) {
        y = mount.bottomY;
      }

      // Single height source: MeshProfile (not a parallel Orbit table).
      final itemH = profile.heightMeters;

      return {
        'id': f.id,
        'kind': f.iconName,
        'model': modelUrl,
        'x': x,
        'y': y,
        'z': z,
        'w': itemW,
        'd': itemD,
        'h': itemH,
        'yaw': yaw,
        'selected': f.id == widget.selectedId,
        'mount': mount.isCeiling
            ? 'ceiling'
            : mount.isDesk
                ? 'desk'
                : 'floor',
        'opening': profile.isOpening || profile.isGlass,
        'lightTransmit': profile.lightTransmit,
        ...profile.fitPayload(),
      };
    }).toList();

    final payload = <String, dynamic>{
      'roomW': roomW,
      'roomD': roomD,
      'roomH': widget.room.heightMeters > 0
          ? widget.room.heightMeters
          : RoomScale.defaultHeightMeters,
      'items': items,
      'openings': openings,
      'assetBase': GltfCatalog.sceneAssetBase,
      'exploreMode': 'orbit',
      'miniMap': widget.showMiniMap,
      if (widget.yaw != null) 'yaw': widget.yaw,
      if (widget.pitch != null) 'pitch': widget.pitch,
      if (widget.distance != null) 'distance': widget.distance,
    };

    final preset = widget.pendingPreset;
    if (preset != null && preset != _lastPreset) {
      payload['preset'] = switch (preset) {
        CameraPreset.birdseye => 'birdseye',
        CameraPreset.cornerA => 'cornerA',
        CameraPreset.cornerB => 'cornerB',
        CameraPreset.eyeLevel => 'eyeLevel',
        CameraPreset.door => 'door',
        CameraPreset.ceiling => 'ceiling',
      };
    }

    if (widget.focusToken != _lastFocusToken &&
        widget.selectedId != null &&
        widget.selectedId!.isNotEmpty) {
      payload['focusId'] = widget.selectedId;
    }

    return payload;
  }

  Future<void> _runJs(String code) async {
    if (kIsWeb) return;
    final c = _controller;
    if (c == null || !_ready) return;
    try {
      await c.runJavaScript(code);
    } catch (e) {
      debugPrint('RoomModelScene js failed: $e');
    }
  }

  Future<void> _pushScene() async {
    if (!_ready) return;
    final payload = _scenePayload();
    final preset = widget.pendingPreset;
    final focusToken = widget.focusToken;

    if (kIsWeb) {
      platform.pushRoomModelSceneWeb(payload);
    } else {
      final c = _controller;
      if (c == null) return;
      final json = jsonEncode(payload);
      try {
        await c.runJavaScript('window.setRoomScene($json);');
      } catch (e) {
        debugPrint('RoomModelScene push failed: $e');
      }
    }

    if (preset != null && preset != _lastPreset) {
      _lastPreset = preset;
      widget.onPresetApplied?.call();
    }
    if (focusToken != _lastFocusToken) {
      _lastFocusToken = focusToken;
    }
  }

  Future<void> applyPreset(CameraPreset preset) => _runJs(
        "window.applyCameraPreset('${switch (preset) {
          CameraPreset.birdseye => 'birdseye',
          CameraPreset.cornerA => 'cornerA',
          CameraPreset.cornerB => 'cornerB',
          CameraPreset.eyeLevel => 'eyeLevel',
          CameraPreset.door => 'door',
          CameraPreset.ceiling => 'ceiling',
        }}');",
      );

  Future<void> focusSelected() async {
    final id = widget.selectedId;
    if (id == null) return;
    await _runJs("window.focusItem(${jsonEncode(id)});");
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
            : WebViewWidget(
                controller: _controller!,
                // Let multi-touch (pinch / two-finger pan) reach the WebView
                // instead of competing with Flutter scroll arenas.
                gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                  Factory<OneSequenceGestureRecognizer>(
                    EagerGestureRecognizer.new,
                  ),
                },
              );

    if (sceneChild == null) {
      return const ColoredBox(
        color: AppColors.bg,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.cyan),
        ),
      );
    }

    final modeLabel = switch (widget.exploreChrome) {
      ChromeViewMode.orbit => 'ORBIT · 1-finger · pinch',
      ChromeViewMode.check => 'MODEL · exterior · mesh sims',
      ChromeViewMode.edit => 'MODEL',
    };

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
              child: Text(
                modeLabel,
                style: const TextStyle(
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
