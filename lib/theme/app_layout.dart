import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Breakpoints for mobile-first Room Rig on wide Chrome / desktop windows.
///
/// Phones keep full-bleed. Browser/desktop centers a phone-width column so
/// controls and canvases do not stretch across an ultrawide monitor.
class AppLayout {
  AppLayout._();

  /// Fill the window below this width (real phones / narrow windows).
  static const double fillBelow = 560;

  /// Centered phone column max width when the window is wider than [fillBelow].
  static const double phoneColumnMax = 480;

  /// Comfortable content width when a side nav is showing.
  static const double desktopColumnMax = 720;

  /// Switch bottom tabs → left NavigationRail.
  static const double sideNavMinWidth = 900;

  static bool get isBrowserSurface => kIsWeb;

  static bool useSideNav(Size size) => size.width >= sideNavMinWidth;

  /// Max width for the primary column (screens + bottom bar when stacked).
  static double contentMaxWidth(Size size) {
    if (size.width < fillBelow) return double.infinity;
    if (useSideNav(size)) return desktopColumnMax;
    return phoneColumnMax;
  }

  /// True when we are letterboxing the mobile UI in a wide window.
  static bool isLetterboxed(Size size) =>
      size.width >= fillBelow && !useSideNav(size);
}
