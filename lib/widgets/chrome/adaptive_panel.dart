// Adaptive supporting panes (Material window-size classes / supporting-pane layout).
// Compact width: trigger chips → modal bottom sheet.
// Expanded width (later): same regions as persistent side rails.
// Refs: Android Adaptive Apps SupportingPaneScaffold; MD3 window size classes.
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../room_model_scene_pointer_guard.dart';
import '../room_model_scene_stub.dart'
    if (dart.library.html) '../room_model_scene_web.dart' as platform;

/// Named chrome regions shared by Rig and Bench (supporting-pane roles).
enum ChromeRegion { view, tools, inspect, results, compare, snapshot }

extension ChromeRegionLabel on ChromeRegion {
  String get label => switch (this) {
        ChromeRegion.view => 'View',
        ChromeRegion.tools => 'Tools',
        ChromeRegion.inspect => 'Inspect',
        ChromeRegion.results => 'Results',
        ChromeRegion.compare => 'Compare',
        ChromeRegion.snapshot => 'Snapshot',
      };

  IconData get icon => switch (this) {
        ChromeRegion.view => Icons.visibility_outlined,
        ChromeRegion.tools => Icons.build_outlined,
        ChromeRegion.inspect => Icons.list_alt_rounded,
        ChromeRegion.results => Icons.insights_outlined,
        ChromeRegion.compare => Icons.compare_arrows_rounded,
        ChromeRegion.snapshot => Icons.photo_camera_outlined,
      };
}

/// Spec for one adaptive supporting pane.
class AdaptivePanelSpec {
  final ChromeRegion region;
  final String? titleOverride;
  final IconData? iconOverride;
  final WidgetBuilder builder;
  /// Taller modal sheet (compact). Default: shorter sheet.
  final bool preferTall;

  const AdaptivePanelSpec({
    required this.region,
    required this.builder,
    this.titleOverride,
    this.iconOverride,
    this.preferTall = false,
  });

  String get title => titleOverride ?? region.label;
  IconData get icon => iconOverride ?? region.icon;
}

/// Window-size helper (Material compact / medium / expanded).
/// App shell side-nav lives in `main.dart` / [AppLayout].
class AdaptivePanelLayout {
  /// Approximate expanded-width aspect (wide + short).
  static const double expandedMinAspect = 1.25;

  /// Medium width lower bound in logical pixels (Material ~600dp).
  static const double mediumMinWidth = 600;

  /// Desktop Rig hosts View/Tools/Inspect as persistent rails.
  static bool useExpandedRails(BoxConstraints constraints) {
    return constraints.maxWidth >= mediumMinWidth;
  }

  /// Left rail regions in expanded layout.
  static const leftRail = [ChromeRegion.view, ChromeRegion.tools];

  /// Right rail regions in expanded layout.
  static const rightRail = [ChromeRegion.inspect, ChromeRegion.results];
}

/// Persistent desktop supporting pane (replaces modal sheets on wide layouts).
class AdaptiveRailPane extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Color accent;

  const AdaptiveRailPane({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.accent = AppColors.cyan,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: accent),
                const SizedBox(width: 8),
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.borderSubtle),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens one supporting pane at a time in compact width (modal bottom sheet).
class AdaptivePanelController {
  AdaptivePanelController(this.panels);

  final List<AdaptivePanelSpec> panels;
  ChromeRegion? openRegion;

  AdaptivePanelSpec? panelFor(ChromeRegion region) {
    for (final p in panels) {
      if (p.region == region) return p;
    }
    return null;
  }

  Future<void> openPanel(BuildContext context, ChromeRegion region) async {
    final panel = panelFor(region);
    if (panel == null) return;
    openRegion = region;
    // HtmlElementView on web steals clicks above Flutter sheets — park it.
    platform.setRoomModelScenePointerEvents(false);
    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppColors.surface,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (ctx) {
          final maxH = MediaQuery.sizeOf(ctx).height * (panel.preferTall ? 0.78 : 0.6);
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(panel.icon, size: 20, color: AppColors.cyan),
                      const SizedBox(width: 8),
                      Text(
                        panel.title.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.cyan,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.6,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Close',
                        style: IconButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          fixedSize: const Size(44, 44),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, size: 22, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(child: SingleChildScrollView(child: panel.builder(ctx))),
                ],
              ),
            ),
          );
        },
      );
    } finally {
      openRegion = null;
      // NavigatorObserver tracks depth; don't force-enable under another dialog.
      RoomModelScenePointerGuard.instance.restoreIfClear();
    }
  }
}

/// Compact-width triggers that open supporting panes (→ sheets). Expanded → rails later.
class AdaptivePanelTriggers extends StatelessWidget {
  final AdaptivePanelController controller;
  final List<ChromeRegion> visible;
  final Color accent;

  /// Optional per-region tap handlers (e.g. open a drawer instead of the sheet).
  final Map<ChromeRegion, VoidCallback>? regionActions;

  /// Optional label overrides for chips (defaults to [ChromeRegion.label]).
  final Map<ChromeRegion, String>? regionLabels;

  const AdaptivePanelTriggers({
    super.key,
    required this.controller,
    required this.visible,
    this.accent = AppColors.cyan,
    this.regionActions,
    this.regionLabels,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          _PanelTriggerChip(
            label: regionLabels?[visible[i]] ?? visible[i].label,
            icon: visible[i].icon,
            accent: accent,
            onTap: () {
              final action = regionActions?[visible[i]];
              if (action != null) {
                action();
                return;
              }
              controller.openPanel(context, visible[i]);
            },
          ),
        ],
      ],
    );
  }
}

class _PanelTriggerChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _PanelTriggerChip({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared explore modes (2D plan · Orbit · Check/Model).
enum ChromeViewMode { edit, orbit, check }

extension ChromeViewModeLabel on ChromeViewMode {
  String get label => switch (this) {
        ChromeViewMode.edit => '2D',
        ChromeViewMode.orbit => 'Orbit',
        ChromeViewMode.check => 'Check',
      };

  String get purpose => switch (this) {
        ChromeViewMode.edit => '2D floor plan — arrange furniture',
        ChromeViewMode.orbit => 'Orbit the 3D room',
        ChromeViewMode.check => 'High-fidelity Model review',
      };
}

class ChromeViewModeChips extends StatelessWidget {
  final ChromeViewMode selected;
  final ValueChanged<ChromeViewMode> onChanged;
  final List<ChromeViewMode> modes;

  const ChromeViewModeChips({
    super.key,
    required this.selected,
    required this.onChanged,
    this.modes = const [
      ChromeViewMode.edit,
      ChromeViewMode.orbit,
      ChromeViewMode.check,
    ],
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('chrome_view_mode_bar'),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Row(
            children: [
              for (var i = 0; i < modes.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(
                  child: Material(
                    key: ValueKey('chrome_view_${modes[i].name}'),
                    color: selected == modes[i]
                        ? AppColors.cyan.withValues(alpha: 0.28)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: InkWell(
                      onTap: () => onChanged(modes[i]),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: Container(
                        alignment: Alignment.center,
                        constraints: const BoxConstraints(minHeight: 44),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        child: Text(
                          modes[i].label,
                          style: TextStyle(
                            color: selected == modes[i]
                                ? AppColors.cyan
                                : AppColors.textMuted,
                            fontSize: 13,
                            fontWeight:
                                selected == modes[i] ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          selected.purpose,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Named camera presets for Model (orbit).
enum CameraPreset { birdseye, cornerA, cornerB, eyeLevel, door, ceiling }

extension CameraPresetLabel on CameraPreset {
  String get label => switch (this) {
        CameraPreset.birdseye => 'Birdseye',
        CameraPreset.cornerA => 'Corner A',
        CameraPreset.cornerB => 'Corner B',
        CameraPreset.eyeLevel => 'Eye-level',
        CameraPreset.door => 'Door view',
        CameraPreset.ceiling => 'Ceiling',
      };
}

class CameraPresetChips extends StatelessWidget {
  final ValueChanged<CameraPreset> onSelect;

  const CameraPresetChips({super.key, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in CameraPreset.values)
          Material(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: InkWell(
              onTap: () => onSelect(p),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  p.label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
