import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/theme/app_layout.dart';

void main() {
  test('portrait phone stays compact', () {
    const size = Size(390, 844);
    expect(AppLayout.isDesktopSize(size), isFalse);
    expect(AppLayout.useSideNav(size), isFalse);
    expect(AppLayout.isLandscapeShell(size), isFalse);
  });

  test('phone landscape uses wide shell with compact rails', () {
    const size = Size(844, 390);
    expect(AppLayout.isLandscapeShell(size), isTrue);
    expect(AppLayout.isDesktopSize(size), isTrue);
    expect(AppLayout.useSideNav(size), isTrue);
    expect(AppLayout.toolsRailWidthForSize(size), AppLayout.toolsRailWidthCompact);
    expect(
      AppLayout.inspectRailWidthForSize(size),
      AppLayout.inspectRailWidthCompact,
    );
  });

  test('desktop width keeps full rails', () {
    const size = Size(1280, 800);
    expect(AppLayout.isDesktopSize(size), isTrue);
    expect(AppLayout.toolsRailWidthForSize(size), AppLayout.toolsRailWidth);
    expect(AppLayout.inspectRailWidthForSize(size), AppLayout.inspectRailWidth);
  });

  test('narrow landscape does not force shell', () {
    const size = Size(500, 320);
    expect(AppLayout.isLandscapeShell(size), isFalse);
    expect(AppLayout.isDesktopSize(size), isFalse);
  });
}
