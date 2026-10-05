import 'dart:convert';

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

  DateTime? _lastAttempt;
  List<Detection2D> _lastResults = const [];
  bool _lastOk = false;
  String? _lastError;

  RemoteObjectDetector({
    required this.hostPort,
    this.timeout = const Duration(milliseconds: 700),
    this.minInterval = const Duration(milliseconds: 450),
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
      final payload = frame.bytes is Uint8List
          ? frame.bytes as Uint8List
          : Uint8List.fromList(List<int>.from(frame.bytes));

      final res = await http
          .post(
            _detectUri,
            headers: {
              'Content-Type': 'application/octet-stream',
              'X-Frame-Width': '${frame.width}',
              'X-Frame-Height': '${frame.height}',
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
      debugPrint(
        'RemoteObjectDetector: ok ${res.bodyBytes.length}b '
        'boxes=${out.length} @ $hostPort',
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
