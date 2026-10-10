// Shared Bench results readability: legend, verdict-first, compare scrub, layers.
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Always-visible good / ok / poor color scale.
class BenchLegend extends StatelessWidget {
  final String? caption;

  const BenchLegend({super.key, this.caption});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (caption ?? 'Scale').toUpperCase(),
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: const [
              _LegendSwatch(color: AppColors.green, label: 'Good'),
              SizedBox(width: 12),
              _LegendSwatch(color: AppColors.amber, label: 'OK'),
              SizedBox(width: 12),
              _LegendSwatch(color: AppColors.red, label: 'Poor'),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendSwatch extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendSwatch({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Verdict line first; details expand behind.
class BenchVerdictHeader extends StatefulWidget {
  final String verdict;
  final String? detail;
  final Color accent;
  final List<Widget> children;

  const BenchVerdictHeader({
    super.key,
    required this.verdict,
    this.detail,
    required this.accent,
    this.children = const [],
  });

  @override
  State<BenchVerdictHeader> createState() => _BenchVerdictHeaderState();
}

class _BenchVerdictHeaderState extends State<BenchVerdictHeader> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: widget.children.isEmpty && (widget.detail == null || widget.detail!.isEmpty)
              ? null
              : () => setState(() => _expanded = !_expanded),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: widget.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: widget.accent.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.trending_up_rounded, size: 18, color: widget.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.verdict,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (widget.children.isNotEmpty || (widget.detail?.isNotEmpty ?? false))
                  Icon(
                    _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: AppColors.textMuted,
                  ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          if (widget.detail != null && widget.detail!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              widget.detail!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
          ...widget.children.map(
            (c) => Padding(padding: const EdgeInsets.only(top: 10), child: c),
          ),
        ],
      ],
    );
  }
}

/// My Room ↔ Improved scrub (0 = my room, 1 = improved).
class BenchCompareScrub extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final Color accent;

  const BenchCompareScrub({
    super.key,
    required this.value,
    required this.onChanged,
    this.accent = AppColors.cyan,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'My Room',
              style: TextStyle(
                color: value < 0.5 ? accent : AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Text(
              'Improved',
              style: TextStyle(
                color: value >= 0.5 ? AppColors.green : AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: accent,
            inactiveTrackColor: AppColors.border,
            thumbColor: accent,
            overlayColor: accent.withValues(alpha: 0.15),
          ),
          child: Slider(
            value: value.clamp(0.0, 1.0),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// Layer toggles for sim overlays.
class BenchLayerToggles extends StatelessWidget {
  final bool showParticles;
  final bool showHeatmap;
  final bool showPaths;
  final ValueChanged<bool>? onParticles;
  final ValueChanged<bool>? onHeatmap;
  final ValueChanged<bool>? onPaths;

  const BenchLayerToggles({
    super.key,
    this.showParticles = true,
    this.showHeatmap = true,
    this.showPaths = true,
    this.onParticles,
    this.onHeatmap,
    this.onPaths,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (onParticles != null)
          _LayerChip(
            label: 'Particles',
            on: showParticles,
            onTap: () => onParticles!(!showParticles),
          ),
        if (onHeatmap != null)
          _LayerChip(
            label: 'Heat map',
            on: showHeatmap,
            onTap: () => onHeatmap!(!showHeatmap),
          ),
        if (onPaths != null)
          _LayerChip(
            label: 'Paths',
            on: showPaths,
            onTap: () => onPaths!(!showPaths),
          ),
      ],
    );
  }
}

class _LayerChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _LayerChip({required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: on ? AppColors.cyan.withValues(alpha: 0.15) : AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: on ? AppColors.cyan : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: on ? AppColors.cyan : AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet listing score reasons with one CTA each.
Future<void> showWhyScoreSheet(
  BuildContext context, {
  required String title,
  required List<String> reasons,
  required Color accent,
  VoidCallback? onFixOnRig,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 12),
              if (reasons.isEmpty)
                const Text(
                  'No detailed reasons for this run.',
                  style: TextStyle(color: AppColors.textSecondary),
                )
              else
                ...reasons.take(6).map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_circle_outline, size: 16, color: accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            r,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ),
                        if (onFixOnRig != null)
                          TextButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              onFixOnRig();
                            },
                            child: const Text('Fix'),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
