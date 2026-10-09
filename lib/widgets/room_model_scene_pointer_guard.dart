import 'package:flutter/widgets.dart';

import 'room_model_scene_stub.dart'
    if (dart.library.html) 'room_model_scene_web.dart' as platform;

/// Disables the Model-scene iframe pointers while popup routes (dialogs,
/// bottom sheets) are on screen so Chrome clicks hit Flutter instead of
/// orbiting the three.js view underneath.
class RoomModelScenePointerGuard extends NavigatorObserver {
  int _overlayDepth = 0;

  void _apply() {
    platform.setRoomModelScenePointerEvents(_overlayDepth == 0);
  }

  bool _isOverlay(Route<dynamic> route) => route is PopupRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isOverlay(route)) {
      _overlayDepth++;
      _apply();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isOverlay(route) && _overlayDepth > 0) {
      _overlayDepth--;
      _apply();
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isOverlay(route) && _overlayDepth > 0) {
      _overlayDepth--;
      _apply();
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null && _isOverlay(oldRoute) && _overlayDepth > 0) {
      _overlayDepth--;
    }
    if (newRoute != null && _isOverlay(newRoute)) {
      _overlayDepth++;
    }
    _apply();
  }
}
