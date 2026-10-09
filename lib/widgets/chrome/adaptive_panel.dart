// Adaptive supporting panes (Material window-size classes / supporting-pane layout).
// Compact width: trigger chips → modal bottom sheet.
// Expanded width (later): same regions as persistent side rails.
// Refs: Android Adaptive Apps SupportingPaneScaffold; MD3 window size classes.
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Named chrome regions shared by Rig and Bench (supporting-pane roles).
enum ChromeRegion { view, tools, inspect, results }

extension ChromeRegionLabel on ChromeRegion {
  String get label => switch (this) {
        ChromeRegion.view => 'View',
        ChromeRegion.tools => 'Tools',
        ChromeRegion.inspect => 'Inspect',
        ChromeRegion.results => 'Results',
      };

  IconData get icon => switch (this) {
        ChromeRegion.view => Icons.visibility_outlined,
        ChromeRegion.tools => Icons.build_outlined,
        ChromeRegion.inspect => Icons.list_alt_rounded,
        ChromeRegion.results => Icons.insights_outlined,
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
/// Rails stay off until portrait lock is removed in [main.dart].
class AdaptivePanelLayout {
  /// Approximate expanded-width aspect (wide + short).
  static const double expandedMinAspect = 1.25;

  /// Medium width lower bound in logical pixels (Material ~600dp).
  static const double mediumMinWidth = 600;

  /// When true, panes render as side rails instead of modal sheets.
  /// Always false while portrait is locked — wiring is ready for Phase 5.
  static bool useExpandedRails(BoxConstraints constraints) {
    // Intentionally gated off: unlock orientations first, then return:
    // constraints.maxWidth >= mediumMinWidth &&
    // constraints.maxWidth / constraints.maxHeight >= expandedMinAspect;
    return false;
  }

  /// Left rail regions in expanded layout.
  static const leftRail = [ChromeRegion.view, ChromeRegion.tools];

  /// Right rail regions in expanded layout.
  static const rightRail = [ChromeRegion.inspect, ChromeRegion.results];
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
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(ctx).height * (panel.preferTall ? 0.72 : 0.55);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(panel.icon, size: 18, color: AppColors.cyan),
                      const SizedBox(width: 8),
                      Text(
                        panel.title.toUpperCase(),
                        style: TextStyle(
                          color: AppColors.cyan,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.6,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(child: SingleChildScrollView(child: panel.builder(ctx))),
                ],
              ),
            ),
          ),
        );
      },
    );
    openRegion = null;
  }
}

/// Compact-width triggers that open supporting panes (→ sheets). Expanded → rails later.
class AdaptivePanelTriggers extends StatelessWidget {
  final AdaptivePanelController controller;
  final List<ChromeRegion> visible;
  final Color accent;

  const AdaptivePanelTriggers({
    super.key,
    required this.controller,
    required this.visible,
    this.accent = AppColors.cyan,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          _PanelTriggerChip(
            label: visible[i].label,
            icon: visible[i].icon,
            accent: accent,
            onTap: () => controller.openPanel(context, visible[i]),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared explore modes (Edit · Orbit · Check).
enum ChromeViewMode { edit, orbit, check }

extension ChromeViewModeLabel on ChromeViewMode {
  String get label => switch (this) {
        ChromeViewMode.edit => 'Edit',
        ChromeViewMode.orbit => 'Orbit',
        ChromeViewMode.check => 'Check',
      };

  String get purpose => switch (this) {
        ChromeViewMode.edit => 'Arrange furniture on the plan',
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in modes)
              GestureDetector(
                onTap: () => onChanged(m),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected == m
                        ? AppColors.cyan.withValues(alpha: 0.15)
                        : AppColors.card,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: selected == m ? AppColors.cyan : AppColors.border,
                    ),
                  ),
                  child: Text(
                    m.label,
                    style: TextStyle(
                      color: selected == m ? AppColors.cyan : AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
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
          GestureDetector(
            onTap: () => onSelect(p),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                p.label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
