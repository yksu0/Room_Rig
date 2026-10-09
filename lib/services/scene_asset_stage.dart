import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Stages Model WebView assets and serves them over localhost HTTP.
///
/// Android WebView blocks XHR between `file://` URLs (`net::ERR_FAILED`),
/// including real filesystem paths. A loopback HTTP origin fixes Three.js
/// GLTFLoader for `../gltf/*.glb`.
class SceneAssetStage {
  SceneAssetStage._();

  static const _stageName = 'room_rig_scene_v18';
  static Directory? _baseDir;
  static HttpServer? _server;
  static String? _viewerHttpUrl;
  static Future<String?>? _inflight;

  /// HTTP URL to `room_viewer.html`, or null when not needed (web).
  static Future<String?> ensureViewerHtml() {
    if (kIsWeb) return Future<String?>.value(null);
    if (_viewerHttpUrl != null) return Future<String?>.value(_viewerHttpUrl);
    return _inflight ??= _stageAndServe();
  }

  static Future<String?> _stageAndServe() async {
    try {
      final root = await getTemporaryDirectory();
      final base = Directory(p.join(root.path, _stageName));
      final viewer = File(p.join(base.path, 'scene', 'room_viewer.html'));
      final marker = File(p.join(base.path, '.complete'));

      if (!marker.existsSync() || !viewer.existsSync()) {
        if (base.existsSync()) {
          await base.delete(recursive: true);
        }
        await base.create(recursive: true);
        final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
        var copied = 0;
        for (final key in manifest.listAssets()) {
          if (!key.startsWith('assets/scene/') &&
              !key.startsWith('assets/gltf/')) {
            continue;
          }
          final data = await rootBundle.load(key);
          final out = File(
            p.join(base.path, key.replaceFirst('assets/', '')),
          );
          await out.parent.create(recursive: true);
          await out.writeAsBytes(
            data.buffer.asUint8List(
              data.offsetInBytes,
              data.lengthInBytes,
            ),
            flush: true,
          );
          copied++;
        }
        await marker.writeAsString('ok:$copied', flush: true);
        debugPrint('SceneAssetStage copied $copied assets → ${base.path}');
      }

      _baseDir = base;
      await _server?.close(force: true);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      server.listen(_handleRequest, onError: (Object e) {
        debugPrint('SceneAssetStage server error: $e');
      });

      _viewerHttpUrl =
          'http://127.0.0.1:${server.port}/scene/room_viewer.html';
      debugPrint('SceneAssetStage serving $_viewerHttpUrl');
      return _viewerHttpUrl;
    } catch (e, st) {
      debugPrint('SceneAssetStage failed: $e\n$st');
      _inflight = null;
      return null;
    }
  }

  static Future<void> _handleRequest(HttpRequest request) async {
    final base = _baseDir;
    if (base == null) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }

    try {
      var rel = Uri.decodeComponent(request.uri.path);
      if (rel.startsWith('/')) rel = rel.substring(1);
      if (rel.isEmpty || rel.contains('..')) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }

      final file = File(p.join(base.path, rel));
      if (!file.existsSync()) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        _mimeFor(file.path),
      );
      request.response.headers.set(
        HttpHeaders.accessControlAllowOriginHeader,
        '*',
      );
      await request.response.addStream(file.openRead());
      await request.response.close();
    } catch (e) {
      debugPrint('SceneAssetStage serve failed: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  static String _mimeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.html')) return 'text/html; charset=utf-8';
    if (lower.endsWith('.js')) return 'application/javascript; charset=utf-8';
    if (lower.endsWith('.glb')) return 'model/gltf-binary';
    if (lower.endsWith('.gltf')) return 'model/gltf+json';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.bin')) return 'application/octet-stream';
    return 'application/octet-stream';
  }
}
