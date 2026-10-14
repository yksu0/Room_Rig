// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

html.IFrameElement? _iframe;
bool _registered = false;
bool _messageHooked = false;
void Function()? _onReady;
void Function(Map<String, dynamic> data)? _onMessage;

void registerRoomModelIFrameFactory() {
  if (_registered) return;
  _registered = true;
  ui_web.platformViewRegistry.registerViewFactory(
    'room-model-scene',
    (int viewId) {
      final iframe = html.IFrameElement()
        ..src = 'assets/scene/room_viewer.html'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = '#090B10';
      _iframe = iframe;
      iframe.onLoad.listen((_) {
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
/// pointers while dialogs / sheets are open so buttons receive clicks.
void setRoomModelScenePointerEvents(bool enabled) {
  final iframe = _iframe;
  if (iframe == null) return;
  iframe.style.pointerEvents = enabled ? 'auto' : 'none';
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
