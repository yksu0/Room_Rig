// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

html.IFrameElement? _iframe;
bool _registered = false;
void Function()? _onReady;

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
