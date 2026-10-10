import 'package:flutter/widgets.dart';

/// Breakpoints for mobile-first Room Rig that grows into a real desktop site.
///
/// Below [desktopMinWidth]: phone layout (bottom tabs, sheets, stacked chrome).
/// At/above it: left app nav + full-width workspace (Rig rails, wider Bench/Hub).
class AppLayout {
  AppLayout._();

  /// Desktop / website layout kicks in here (Chrome window, tablet landscape).
  static const double desktopMinWidth = 900;

  /// Left tools rail on Rig (View + Tools).
  static const double toolsRailWidth = 300;

  /// Right inspect rail on Rig (room items / conflicts).
  static const double inspectRailWidth = 320;

  /// Readable Hub / Bench text column when full-bleed would be too sparse.
  static const double readingMaxWidth = 1200;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktopMinWidth;

  static bool isDesktopSize(Size size) => size.width >= desktopMinWidth;

  static bool useSideNav(Size size) => isDesktopSize(size);
}
