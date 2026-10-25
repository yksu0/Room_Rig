// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

/// Every Model iframe ever created (Rig + Bench can both mount via IndexedStack).
final List<html.IFrameElement> _iframes = [];
html.IFrameElement? _iframe;
bool _registered = false;
bool _messageHooked = false;
bool _pointersEnabled = true;
void Function()? _onReady;
void Function(Map<String, dynamic> data)? _onMessage;

void registerRoomModelIFrameFactory() {
  if (_registered) return;
  _registered = true;
  ui_web.platformViewRegistry.registerViewFactory(
    'room-model-scene',
    (int viewId) {
      final iframe = html.IFrameElement()
        // Absolute path — relative `assets/scene/...` breaks when the app
        // route is not `/`, and GLB XHR then 404s leaving empty selection rings.
        ..src = '/assets/assets/scene/room_viewer.html'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = '#090B10';
      _iframes.add(iframe);
      _iframe = iframe;
      // Honor current overlay state (dialog may already be open).
      _applyPointerEvents(iframe, _pointersEnabled);
      iframe.onLoad.listen((_) {
        _applyPointerEvents(iframe, _pointersEnabled);
        _onReady?.call();
      });
      return iframe;
    },
  );
}

Object? createRoomModelIFrame({
  required void Function() onReady,
}) {
  _onReady = onReady;
  registerRoomModelIFrameFactory();
  return null;
}

void pushRoomModelSceneWeb(Map<String, dynamic> payload) {
  final iframe = _iframe;
  final win = iframe?.contentWindow;
  if (win == null) return;
  win.postMessage(jsonEncode(payload), '*');
}

/// HtmlElementView sits above Flutter hit-testing on web — turn off iframe
/// (and its platform-view host) while dialogs / sheets are open so buttons
/// receive clicks.
void setRoomModelScenePointerEvents(bool enabled) {
  _pointersEnabled = enabled;
  _pruneDetachedIframes();
  for (final iframe in _iframes) {
    _applyPointerEvents(iframe, enabled);
  }
  // Catch any iframe the factory list missed (hot restart / remount).
  for (final node in html.document.querySelectorAll('iframe')) {
    if (node is! html.IFrameElement) continue;
    final src = node.src ?? '';
    if (!src.contains('room_viewer.html')) continue;
    if (!_iframes.contains(node)) {
      _iframes.add(node);
    }
    _applyPointerEvents(node, enabled);
  }
}

void _pruneDetachedIframes() {
  _iframes.removeWhere((e) => e.isConnected != true);
  if (_iframe != null && _iframe!.isConnected != true) {
    _iframe = _iframes.isEmpty ? null : _iframes.last;
  }
}

void _applyPointerEvents(html.IFrameElement iframe, bool enabled) {
  final value = enabled ? 'auto' : 'none';
  iframe.style.pointerEvents = value;
  // Flutter web hosts the iframe inside flt-platform-view; that host also
  // steals hits unless pointer-events is cleared on the ancestors.
  html.Element? el = iframe.parent;
  while (el != null) {
    final tag = el.tagName.toLowerCase();
    if (tag == 'flt-platform-view' ||
        tag == 'flt-platform-view-slot' ||
        tag == 'slot') {
      el.style.pointerEvents = value;
    }
    // Stop at the glass pane / flutter-view — don't disable the whole app.
    if (tag == 'flt-glass-pane' || tag == 'flutter-view') break;
    el = el.parent;
  }
}

void setRoomModelSceneMessageHandler(
  void Function(Map<String, dynamic> data)? handler,
) {
  _onMessage = handler;
  if (_messageHooked) return;
  _messageHooked = true;
  html.window.onMessage.listen((html.MessageEvent event) {
    final raw = event.data;
    if (raw is! String) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final data = Map<String, dynamic>.from(decoded);
      final type = data['type'];
      if (type is! String) return;
      if (type == 'ready' ||
          type == 'select' ||
          type == 'deselect' ||
          type == 'dragStart' ||
          type == 'drag' ||
          type == 'dragEnd') {
        _onMessage?.call(data);
      }
    } catch (_) {}
  });
}
