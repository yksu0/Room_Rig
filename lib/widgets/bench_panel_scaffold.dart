// lib/widgets/bench_panel_scaffold.dart
import 'package:flutter/material.dart';
import '../services/bench_layouts.dart';
import '../services/benchmark_validator.dart';
import '../theme/app_theme.dart';
import 'benchmark_validation_card.dart';
import 'glass_card.dart';
import 'room_icons.dart';
import 'score_ring.dart';

/// Step indices shared by all bench panels.
const int benchStepLayout = 0;
const int benchStepMiddle = 1;
const int benchStepResults = 2;

/// Layout / Simulate|Analyze / Results tab row.
class BenchStepTabs extends StatelessWidget {
  final Color accentColor;
  final int step;
  final List<String> labels;
  final bool resultsEnabled;
  final ValueChanged<int> onStepChanged;

  const BenchStepTabs({
    super.key,
    required this.accentColor,
    required this.step,
    required this.labels,
    required this.resultsEnabled,
    required this.onStepChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(labels.length, (i) {
        final selected = step == i;
        final isLast = i == labels.length - 1;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              if (i == benchStepResults && !resultsEnabled) return;
              onStepChanged(i);
            },
            child: Container(
              margin: EdgeInsets.only(right: isLast ? 0 : 8),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: selected ? accentColor.withValues(alpha: 0.12) : AppColors.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected ? accentColor : AppColors.border),
              ),
              child: Text(
                labels[i],
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? accentColor : AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Single selectable chip used for variants, 2D/3D toggles, etc.
class BenchChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const BenchChip({
    super.key,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? color : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// My Room / Improved / Sample variant selector.
class BenchVariantChips extends StatelessWidget {
  final BenchLayoutKind selected;
  final ValueChanged<BenchLayoutKind> onChanged;
  final List<Widget>? trailing;

  const BenchVariantChips({
    super.key,
    required this.selected,
    required this.onChanged,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        BenchChip(
          label: 'My Room',
          selected: selected == BenchLayoutKind.myRoom,
          color: AppColors.cyan,
          onTap: () => onChanged(BenchLayoutKind.myRoom),
        ),
        BenchChip(
          label: 'Improved',
          selected: selected == BenchLayoutKind.improved,
          color: AppColors.green,
          onTap: () => onChanged(BenchLayoutKind.improved),
        ),
        BenchChip(
          label: 'Sample',
          selected: selected == BenchLayoutKind.sample,
          color: AppColors.amber,
          onTap: () => onChanged(BenchLayoutKind.sample),
        ),
        if (trailing != null) ...trailing!,
      ],
    );
  }
}

/// Gradient primary action button (run bench, apply layout, etc.).
class BenchPrimaryButton extends StatelessWidget {
  final String label;
  final String icon;
  final VoidCallback? onTap;

  const BenchPrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: disabled ? null : AppColors.accentGradient,
          color: disabled ? AppColors.card : null,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: disabled ? AppColors.border : Colors.transparent),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgIcon(icon, size: 18, color: disabled ? AppColors.textMuted : Colors.white),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: disabled ? AppColors.textMuted : Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact refresh control paired with the apply button.
class BenchRefreshButton extends StatelessWidget {
  final VoidCallback onTap;

  const BenchRefreshButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary, size: 20),
      ),
    );
  }
}

/// Apply improved layout + refresh row used on the results step.
class BenchApplyRow extends StatelessWidget {
  final VoidCallback? onApply;
  final VoidCallback onRefresh;
  final String? blockedReason;

  const BenchApplyRow({
    super.key,
    required this.onApply,
    required this.onRefresh,
    this.blockedReason,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: BenchPrimaryButton(
                label: 'APPLY IMPROVED LAYOUT',
                icon: RoomSvg.star,
                onTap: onApply,
              ),
            ),
            const SizedBox(width: 8),
            BenchRefreshButton(onTap: onRefresh),
          ],
        ),
        if (onApply == null && blockedReason != null) ...[
          const SizedBox(height: 8),
          Text(
            blockedReason!,
            style: TextStyle(
              color: AppColors.amber.withValues(alpha: 0.95),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

/// Simulated run progress bar shown during async bench runs.
class BenchProgressBar extends StatelessWidget {
  final double progress;
  final String label;
  final Color accentColor;

  const BenchProgressBar({
    super.key,
    required this.progress,
    required this.label,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const Spacer(),
            Text(
              '${(progress * 100).toInt()}%',
              style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: AppColors.border,
          valueColor: AlwaysStoppedAnimation(accentColor),
          minHeight: 4,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }
}

/// Run button + optional hint for the layout step (or analyze step for spatial).
class BenchRunAction extends StatelessWidget {
  final String buttonLabel;
  final String icon;
  final VoidCallback? onRun;
  final String? hint;

  const BenchRunAction({
    super.key,
    required this.buttonLabel,
    required this.icon,
    this.onRun,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BenchPrimaryButton(label: buttonLabel, icon: icon, onTap: onRun),
        if (hint != null) ...[
          const SizedBox(height: 8),
          Text(
            hint!,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}

/// Metric tile under simulation views.
class BenchMetricTile extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final bool invert;

  const BenchMetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.invert = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            value.toStringAsFixed(0),
            style: TextStyle(
              color: invert && value > 25 ? AppColors.red : color,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Score ring configuration for [BenchResultsCard].
class BenchScoreRingSpec {
  final double score;
  final Color color;
  final String label;
  final double size;

  const BenchScoreRingSpec({
    required this.score,
    required this.color,
    required this.label,
    this.size = 78,
  });
}

/// Results comparison header with trophy, badge, score rings, and validation.
class BenchResultsCard extends StatelessWidget {
  final String title;
  final BenchmarkValidation validation;
  final List<BenchScoreRingSpec> rings;
  final String summaryText;

  const BenchResultsCard({
    super.key,
    required this.title,
    required this.validation,
    required this.rings,
    required this.summaryText,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderColor: BenchResultBadge.colorFor(validation.verdict).withValues(alpha: 0.4),
      child: Column(
        children: [
          Row(
            children: [
              SvgIcon(RoomSvg.trophy, size: 22, color: AppColors.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              BenchResultBadge(validation: validation),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: rings
                .map(
                  (r) => ScoreRing(
                    score: r.score,
                    size: r.size,
                    color: r.color,
                    label: r.label,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          Text(
            summaryText,
            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 14),
          BenchmarkValidationCard(validation: validation),
        ],
      ),
    );
  }
}

/// Floating snackbar with OPEN RIG action after applying an improved layout.
void showBenchApplySnackBar(
  BuildContext context, {
  required String message,
  required Color accentColor,
  required VoidCallback onOpenRig,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: accentColor.withValues(alpha: 0.9),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: 'OPEN RIG',
        textColor: Colors.black,
        onPressed: onOpenRig,
      ),
    ),
  );
}

/// Confirm before pushing an improved bench layout to the Rig.
Future<bool> confirmBenchApply(
  BuildContext context, {
  required BenchmarkValidation validation,
}) async {
  if (validation.hasHardLayoutConflicts) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cannot apply layout'),
        content: const Text(
          'The improved layout still has overlapping furniture or blocked doorways. '
          'Fix conflicts on the Rig or re-run the bench.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
    return false;
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Apply to Rig?'),
      content: const Text(
        'This replaces your current furniture layout with the improved arrangement from the bench.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply')),
      ],
    ),
  );
  return ok == true;
}

/// Orchestrates the common bench panel column: tabs, step content, progress, results, apply.
class BenchPanelScaffold extends StatelessWidget {
  final Color accentColor;
  final int step;
  final List<String> stepLabels;
  final bool resultsEnabled;
  final bool running;
  final ValueChanged<int> onStepChanged;

  /// Shown on the layout step.
  final Widget? layoutBody;
  final BenchRunAction? layoutRunAction;

  /// Shown on the middle step and during results (when not running for sim panels).
  final Widget? middleBody;
  final BenchRunAction? middleRunAction;

  /// Progress shown while [running] is true on middle/results steps.
  final double? progress;
  final String? progressLabel;

  /// Shown on the results step when not [running].
  final Widget? resultsBody;
  final Widget? resultsExtra;
  final VoidCallback? onApply;
  final VoidCallback? onRefresh;
  final bool applyEnabled;
  final String? applyBlockedReason;

  const BenchPanelScaffold({
    super.key,
    required this.accentColor,
    required this.step,
    required this.stepLabels,
    required this.resultsEnabled,
    required this.running,
    required this.onStepChanged,
    this.layoutBody,
    this.layoutRunAction,
    this.middleBody,
    this.middleRunAction,
    this.progress,
    this.progressLabel,
    this.resultsBody,
    this.resultsExtra,
    this.onApply,
    this.onRefresh,
    this.applyEnabled = true,
    this.applyBlockedReason,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BenchStepTabs(
          accentColor: accentColor,
          step: step,
          labels: stepLabels,
          resultsEnabled: resultsEnabled || running,
          onStepChanged: onStepChanged,
        ),
        const SizedBox(height: 16),
        if (step == benchStepLayout && layoutBody != null) ...[
          layoutBody!,
          if (layoutRunAction != null) ...[
            const SizedBox(height: 16),
            layoutRunAction!,
          ],
        ],
        if (step == benchStepMiddle && middleBody != null) ...[
          middleBody!,
          if (middleRunAction != null) ...[
            const SizedBox(height: 16),
            middleRunAction!,
          ],
          if (running && progress != null && progressLabel != null) ...[
            const SizedBox(height: 16),
            BenchProgressBar(progress: progress!, label: progressLabel!, accentColor: accentColor),
          ],
        ],
        if (step == benchStepResults) ...[
          ?middleBody,
          if (running && progress != null && progressLabel != null) ...[
            const SizedBox(height: 16),
            BenchProgressBar(progress: progress!, label: progressLabel!, accentColor: accentColor),
          ],
          if (!running) ...[
            if (middleBody != null) const SizedBox(height: 20),
            if (resultsExtra != null) ...[
              resultsExtra!,
              const SizedBox(height: 12),
            ],
            ?resultsBody,
            if (onApply != null && onRefresh != null) ...[
              const SizedBox(height: 16),
              BenchApplyRow(
                onApply: applyEnabled ? onApply : null,
                onRefresh: onRefresh!,
                blockedReason: applyEnabled ? null : applyBlockedReason,
              ),
            ],
          ],
        ],
      ],
    );
  }
}
