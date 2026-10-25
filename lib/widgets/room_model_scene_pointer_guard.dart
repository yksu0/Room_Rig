import 'package:flutter/widgets.dart';

import 'room_model_scene_stub.dart'
    if (dart.library.html) 'room_model_scene_web.dart' as platform;

/// Disables the Model-scene iframe pointers while popup routes (dialogs,
/// bottom sheets) are on screen so Chrome clicks hit Flutter instead of
/// orbiting the three.js view underneath.
///
/// Shared singleton so sheets that toggle pointers manually can respect
/// remaining overlay depth instead of force-enabling under an open dialog.
class RoomModelScenePointerGuard extends NavigatorObserver {
  RoomModelScenePointerGuard._();
  static final RoomModelScenePointerGuard instance =
      RoomModelScenePointerGuard._();

  factory RoomModelScenePointerGuard() => instance;

  int _overlayDepth = 0;

  int get overlayDepth => _overlayDepth;

  bool get overlaysOpen => _overlayDepth > 0;

  void _apply() {
    platform.setRoomModelScenePointerEvents(_overlayDepth == 0);
  }

  /// For sheets that park the iframe themselves — restore only when no other
  /// popup routes remain.
  void restoreIfClear() {
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
