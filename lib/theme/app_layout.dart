import 'package:flutter/widgets.dart';

/// Breakpoints for mobile-first Room Rig that grows into a real desktop site.
///
/// Portrait phones: bottom tabs, sheets, stacked chrome.
/// Landscape phones / wide windows: left app nav + Rig/Bench rails (Chrome-like).
class AppLayout {
  AppLayout._();

  /// Full desktop / website layout (Chrome window, large tablets).
  static const double desktopMinWidth = 900;

  /// Phone landscape can use the wide shell once width clears this.
  static const double landscapeShellMinWidth = 600;

  /// Left tools rail on Rig (View + Tools) — full desktop.
  static const double toolsRailWidth = 300;

  /// Right inspect rail on Rig — full desktop.
  static const double inspectRailWidth = 320;

  /// Compact rails for phone landscape so the center viewport still fits.
  static const double toolsRailWidthCompact = 220;
  static const double inspectRailWidthCompact = 236;

  /// Readable Hub / Bench text column when full-bleed would be too sparse.
  static const double readingMaxWidth = 1200;

  /// Wide Chrome/desktop width, or phone/tablet landscape shell.
  static bool isDesktop(BuildContext context) =>
      isDesktopSize(MediaQuery.sizeOf(context));

  static bool isDesktopSize(Size size) =>
      size.width >= desktopMinWidth || isLandscapeShell(size);

  /// Landscape with enough width for side nav + rails (phone rotate).
  static bool isLandscapeShell(Size size) =>
      size.width > size.height && size.width >= landscapeShellMinWidth;

  static bool useSideNav(Size size) => isDesktopSize(size);

  static double toolsRailWidthFor(BuildContext context) =>
      toolsRailWidthForSize(MediaQuery.sizeOf(context));

  static double inspectRailWidthFor(BuildContext context) =>
      inspectRailWidthForSize(MediaQuery.sizeOf(context));

  static double toolsRailWidthForSize(Size size) {
    if (size.width >= desktopMinWidth) return toolsRailWidth;
    if (isLandscapeShell(size)) return toolsRailWidthCompact;
    return toolsRailWidth;
  }

  static double inspectRailWidthForSize(Size size) {
    if (size.width >= desktopMinWidth) return inspectRailWidth;
    if (isLandscapeShell(size)) return inspectRailWidthCompact;
    return inspectRailWidth;
  }
}
