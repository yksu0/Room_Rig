import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'scan_pipeline.dart';

/// Offloads YOLO to a PC sidecar (`ml/remote_infer_server.py`).
///
/// Returns [] quickly on timeout/errors so [HybridObjectDetector] can fall back
/// to on-device TFLite.
class RemoteObjectDetector implements ObjectDetector {
  final String hostPort;
  final Duration timeout;
  final Duration minInterval;
  final int maxSide;

  DateTime? _lastAttempt;
  List<Detection2D> _lastResults = const [];
  bool _lastOk = false;
  String? _lastError;

  RemoteObjectDetector({
    required this.hostPort,
    this.timeout = const Duration(milliseconds: 1200),
    this.minInterval = const Duration(milliseconds: 180),
    this.maxSide = 640,
  });

  bool get lastOk => _lastOk;
  String? get lastError => _lastError;

  Uri get _detectUri {
    final raw = hostPort.trim();
    final host = raw.startsWith('http') ? raw : 'http://$raw';
    final base = host.endsWith('/') ? host.substring(0, host.length - 1) : host;
    return Uri.parse('$base/v1/detect');
  }

  Future<bool> ping({Duration timeout = const Duration(milliseconds: 600)}) async {
    try {
      final raw = hostPort.trim();
      final host = raw.startsWith('http') ? raw : 'http://$raw';
      final base = host.endsWith('/') ? host.substring(0, host.length - 1) : host;
      final res = await http.get(Uri.parse('$base/health')).timeout(timeout);
      if (res.statusCode != 200) {
        _lastOk = false;
        _lastError = 'health_${res.statusCode}';
        return false;
      }
      final body = jsonDecode(res.body);
      _lastOk = body is Map && body['ok'] == true;
      _lastError = _lastOk ? null : 'health_not_ok';
      return _lastOk;
    } catch (e) {
      _lastOk = false;
      _lastError = e.toString();
      return false;
    }
  }

  /// Nearest-neighbor downscale so USB/Wi‑Fi does not ship megabyte luma frames.
  static (Uint8List, int, int) downscaleLuma(
    List<int> src,
    int sw,
    int sh, {
    int maxSide = 640,
  }) {
    if (sw <= 0 || sh <= 0 || src.isEmpty) {
      return (Uint8List(0), 0, 0);
    }
    final long = math.max(sw, sh);
    if (long <= maxSide && src.length >= sw * sh) {
      final bytes = src is Uint8List
          ? (src.length == sw * sh ? src : Uint8List.sublistView(src, 0, sw * sh))
          : Uint8List.fromList(src.take(sw * sh).toList());
      return (bytes, sw, sh);
    }
    final scale = maxSide / long;
    final dw = math.max(1, (sw * scale).round());
    final dh = math.max(1, (sh * scale).round());
    final out = Uint8List(dw * dh);
    for (int y = 0; y < dh; y++) {
      final sy = math.min(sh - 1, (y / scale).floor());
      for (int x = 0; x < dw; x++) {
        final sx = math.min(sw - 1, (x / scale).floor());
        final si = sy * sw + sx;
        out[y * dw + x] = si < src.length ? src[si] : 0;
      }
    }
    return (out, dw, dh);
  }

  @override
  Future<List<Detection2D>> detect(ScanFrameInput frame) async {
    if (hostPort.trim().isEmpty ||
        frame.bytes.isEmpty ||
        frame.width <= 0 ||
        frame.height <= 0) {
      return const [];
    }

    final now = DateTime.now();
    final last = _lastAttempt;
    if (last != null && now.difference(last) < minInterval) {
      return _lastResults;
    }
    _lastAttempt = now;

    try {
      final scaled = downscaleLuma(
        frame.bytes,
        frame.width,
        frame.height,
        maxSide: maxSide,
      );
      final payload = scaled.$1;
      final width = scaled.$2;
      final height = scaled.$3;
      if (payload.isEmpty || width <= 0 || height <= 0) {
        return const [];
      }

      final t0 = DateTime.now();
      final res = await http
          .post(
            _detectUri,
            headers: {
              'Content-Type': 'application/octet-stream',
              'X-Frame-Width': '$width',
              'X-Frame-Height': '$height',
              'X-Frame-Format': 'luma8',
            },
            body: payload,
          )
          .timeout(timeout);

      if (res.statusCode != 200) {
        _lastOk = false;
        _lastError = 'http_${res.statusCode}';
        debugPrint('RemoteObjectDetector: HTTP ${res.statusCode}');
        return const [];
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map || decoded['ok'] != true) {
        _lastOk = false;
        _lastError = 'bad_json';
        return const [];
      }
      final list = decoded['detections'];
      if (list is! List) {
        _lastResults = const [];
        _lastOk = true;
        return _lastResults;
      }
      final out = <Detection2D>[];
      for (final item in list) {
        if (item is! Map) continue;
        final label = '${item['label'] ?? ''}';
        if (label.isEmpty) continue;
        out.add(
          Detection2D(
            label: label,
            category: 'remote',
            confidence: (item['confidence'] as num?)?.toDouble() ?? 0,
            left: (item['left'] as num?)?.toDouble() ?? 0,
            top: (item['top'] as num?)?.toDouble() ?? 0,
            width: (item['width'] as num?)?.toDouble() ?? 0,
            height: (item['height'] as num?)?.toDouble() ?? 0,
          ),
        );
      }
      final ms = DateTime.now().difference(t0).inMilliseconds;
      debugPrint(
        'RemoteObjectDetector: ${width}x$height ${payload.length}b '
        'rtt=${ms}ms boxes=${out.length} @ $hostPort',
      );
      _lastResults = out;
      _lastOk = true;
      _lastError = null;
      return out;
    } catch (e) {
      _lastOk = false;
      _lastError = e.toString();
      debugPrint('RemoteObjectDetector: FAIL $hostPort → $e');
      return const [];
    }
  }
}
