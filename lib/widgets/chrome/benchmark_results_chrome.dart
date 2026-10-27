// Shared Benchmark results readability: legend, verdict-first, layer toggles.
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Always-visible good / ok / poor color scale.
class BenchmarkLegend extends StatelessWidget {
  final String? caption;

  const BenchmarkLegend({super.key, this.caption});

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
          const Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _LegendSwatch(color: AppColors.green, label: 'Good'),
              _LegendSwatch(color: AppColors.amber, label: 'OK'),
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
class BenchmarkVerdictHeader extends StatefulWidget {
  final String verdict;
  final String? detail;
  final Color accent;
  final List<Widget> children;

  const BenchmarkVerdictHeader({
    super.key,
    required this.verdict,
    this.detail,
    required this.accent,
    this.children = const [],
  });

  @override
  State<BenchmarkVerdictHeader> createState() => _BenchmarkVerdictHeaderState();
}

class _BenchmarkVerdictHeaderState extends State<BenchmarkVerdictHeader> {
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

/// Layer toggles for sim overlays (only pass callbacks that are wired).
class BenchmarkLayerToggles extends StatelessWidget {
  final bool showParticles;
  final bool showHeatmap;
  final bool showPaths;
  final ValueChanged<bool>? onParticles;
  final ValueChanged<bool>? onHeatmap;
  final ValueChanged<bool>? onPaths;

  const BenchmarkLayerToggles({
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
    final chips = <Widget>[
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
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: chips[i]),
        ],
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        decoration: BoxDecoration(
          color: on ? AppColors.cyan.withValues(alpha: 0.15) : AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: on ? AppColors.cyan : AppColors.border),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
  VoidCallback? onFixOnRoom,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    barrierColor: Colors.black.withValues(alpha: 0.55),
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
                        if (onFixOnRoom != null)
                          TextButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              onFixOnRoom();
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
