// lib/widgets/bench_panel_scaffold.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/room_model.dart';
import '../services/bench_layouts.dart';
import '../services/benchmark_validator.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import 'benchmark_validation_card.dart';
import 'bench_room_views.dart';
import 'chrome/adaptive_panel.dart';
import 'chrome/bench_results_chrome.dart';
import 'glass_card.dart';
import 'room_icons.dart';
import 'score_ring.dart';

export 'chrome/adaptive_panel.dart' show ChromeRegion;

/// Step indices shared by all bench panels.
const int benchStepLayout = 0;
const int benchStepMiddle = 1;
const int benchStepResults = 2;

/// Layout / Simulate|Analyze / Results — inset sliding-pill track (style D).
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
    return BenchSegmentBar(
      children: [
        for (var i = 0; i < labels.length; i++)
          Opacity(
            opacity: (i == benchStepResults && !resultsEnabled) ? 0.45 : 1,
            child: BenchChip(
              label: labels[i],
              selected: step == i,
              color: accentColor,
              onTap: () {
                if (i == benchStepResults && !resultsEnabled) return;
                onStepChanged(i);
              },
            ),
          ),
      ],
    );
  }
}

/// Equal-width inset track for mutually exclusive Workspace controls.
class BenchSegmentBar extends StatelessWidget {
  final List<Widget> children;
  final double gap;

  const BenchSegmentBar({
    super.key,
    required this.children,
    this.gap = 2,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }
}

/// Segment thumb inside [BenchSegmentBar] — solid selected fill, no neon glow.
class BenchChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final bool compact;

  const BenchChip({
    super.key,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 8,
          vertical: compact ? 9 : 10,
        ),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.28) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? color : AppColors.textMuted,
            fontSize: compact ? 11 : 12,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// My Room / Improved variant selector.
class BenchVariantChips extends StatelessWidget {
  final BenchLayoutKind selected;
  final ValueChanged<BenchLayoutKind> onChanged;

  const BenchVariantChips({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return BenchSegmentBar(
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
      ],
    );
  }
}

/// Compact House Control–style score hero (phone ~56–72px; larger OK in rails).
class BenchScoreHero extends StatelessWidget {
  final String label;
  final double score;
  final double? previousScore;
  final Color color;
  final bool expand;

  const BenchScoreHero({
    super.key,
    required this.label,
    required this.score,
    this.previousScore,
    required this.color,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final prev = previousScore;
    final delta = prev == null ? null : score - prev;
    final height = expand ? 88.0 : 64.0;
    final valueSize = expand ? 36.0 : 28.0;
    return Container(
      height: height,
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: expand ? 12 : 8,
      ),
      decoration: AppColors.activeGlowDecoration(
        color: color,
        fill: AppColors.card,
        radius: AppRadius.md,
        borderAlpha: 0.4,
        blur: 14,
        glowAlpha: 0.18,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  score.round().toString(),
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: valueSize,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ),
          if (delta != null)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    delta >= 0 ? '+${delta.round()}' : '${delta.round()}',
                    style: TextStyle(
                      color: delta >= 0 ? AppColors.green : AppColors.amber,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: (score / 100).clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: AppColors.borderSubtle,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Tiny score badge for the mobile View/Inspect chrome row (~44px tall).
class BenchChromeScore extends StatelessWidget {
  const BenchChromeScore({super.key, required this.accentColor});

  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final (label, score, prev) = switch (state.benchmarkMode) {
      'lighting' => (
          'Light',
          state.lightingScore,
          state.baselineLightingScore,
        ),
      'ergonomics' => (
          'Ergo',
          state.ergonomicsScore,
          state.baselineErgonomicsScore,
        ),
      'spatial' => ('Space', state.spatialScore, null),
      _ => ('Air', state.airflowScore, state.baselineAirflowScore),
    };
    final showDelta = prev != null && (score - prev).abs() >= 0.5;
    final delta = showDelta ? score - prev : null;

    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: accentColor.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: accentColor,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            score.round().toString(),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          if (delta != null) ...[
            const SizedBox(width: 4),
            Text(
              delta >= 0 ? '+${delta.round()}' : '${delta.round()}',
              style: TextStyle(
                color: delta >= 0 ? AppColors.green : AppColors.amber,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// View-mode chips on their own row (Rig-style: view ≠ content variant).
class BenchViewChips extends StatelessWidget {
  final List<Widget> children;

  const BenchViewChips({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final compact = children.length >= 4;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: BenchSegmentBar(
        gap: compact ? 5 : 6,
        children: [
          for (final child in children)
            if (child is BenchChip)
              BenchChip(
                label: child.label,
                selected: child.selected,
                color: child.color,
                onTap: child.onTap,
                compact: compact || child.compact,
              )
            else
              child,
        ],
      ),
    );
  }
}

/// True when Bench layouts already match the live Rig furniture + weight mix.
bool benchLayoutsInSync(BenchLayouts? layouts, {
  required String furnitureFingerprint,
  required String weightsCacheKey,
  required int alternateCursor,
}) {
  if (layouts == null) return false;
  return furnitureFingerprint == layouts.fingerprint &&
      weightsCacheKey == layouts.weightsCacheKey &&
      alternateCursor == layouts.requestedAlternateIndex;
}

/// Side-by-side My Room | Improved floor plans (replaces the old scrub compare).
class BenchSideBySidePlans extends StatelessWidget {
  final int gridCols;
  final int gridRows;
  final List<FurnitureItem> myRoom;
  final List<FurnitureItem> improved;
  final Color accentColor;

  const BenchSideBySidePlans({
    super.key,
    required this.gridCols,
    required this.gridRows,
    required this.myRoom,
    required this.improved,
    this.accentColor = AppColors.cyan,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : 280.0;
        return SizedBox(
          height: h,
          child: Row(
            children: [
              Expanded(
                child: _pane(
                  label: 'My Room',
                  color: AppColors.cyan,
                  furniture: myRoom,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _pane(
                  label: 'Improved',
                  color: AppColors.green,
                  furniture: improved,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pane({
    required String label,
    required Color color,
    required List<FurnitureItem> furniture,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ColoredBox(
        color: AppColors.surface,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: BenchRoom2DPainter(
                gridCols: gridCols,
                gridRows: gridRows,
                furniture: furniture,
              ),
              child: const SizedBox.expand(),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.7)),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Auto-Rig mix line + optional Try alternate (parity with Rig star dialog).
class BenchAutoRigMixBar extends StatelessWidget {
  final BenchLayouts? layouts;
  final VoidCallback? onTryAlternate;

  const BenchAutoRigMixBar({
    super.key,
    required this.layouts,
    this.onTryAlternate,
  });

  @override
  Widget build(BuildContext context) {
    final L = layouts;
    if (L == null) return const SizedBox.shrink();
    final canAlt = onTryAlternate != null && L.canTryAlternate;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              L.improvedCaption,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
          if (canAlt) ...[
            const SizedBox(width: AppSpace.xs),
            TextButton(
              onPressed: onTryAlternate,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.cyan,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(44, 40),
              ),
              child: const Text(
                'Try alternate',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ],
      ),
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
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: disabled ? AppColors.border : Colors.transparent),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgIcon(icon, size: 18, color: disabled ? AppColors.textMuted : Colors.white),
            const SizedBox(width: AppSpace.xs),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: disabled ? AppColors.textMuted : Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  letterSpacing: 1.1,
                ),
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
                label: 'APPLY BENCH SUGGESTION TO RIG',
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

/// Results comparison: verdict-first, legend, rings, expandable validation.
class BenchResultsCard extends StatelessWidget {
  final String title;
  final BenchmarkValidation validation;
  final List<BenchScoreRingSpec> rings;
  final String summaryText;
  final Color? accentColor;
  final List<String> whyReasons;
  final VoidCallback? onOpenWhySheet;

  const BenchResultsCard({
    super.key,
    required this.title,
    required this.validation,
    required this.rings,
    required this.summaryText,
    this.accentColor,
    this.whyReasons = const [],
    this.onOpenWhySheet,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? AppColors.cyan;
    return GlassCard(
      borderColor: BenchResultBadge.colorFor(validation.verdict).withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BenchVerdictHeader(
            verdict: summaryText,
            detail: title,
            accent: accent,
            children: [
              const BenchLegend(caption: 'Score scale'),
              const SizedBox(height: 12),
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
                        fontSize: 15,
                      ),
                    ),
                  ),
                  BenchResultBadge(validation: validation),
                ],
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final n = rings.isEmpty ? 1 : rings.length;
                  final maxRing = ((constraints.maxWidth - 8 * (n - 1)) / n)
                      .clamp(48.0, 78.0);
                  return Row(
                    children: [
                      for (var i = 0; i < rings.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: ScoreRing(
                              score: rings[i].score,
                              size: math.min(rings[i].size, maxRing),
                              color: rings[i].color,
                              label: rings[i].label,
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              BenchmarkValidationCard(validation: validation),
              if (whyReasons.isNotEmpty || onOpenWhySheet != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onOpenWhySheet ??
                        () => showWhyScoreSheet(
                              context,
                              title: 'Why this score',
                              reasons: whyReasons,
                              accent: accent,
                            ),
                    icon: Icon(Icons.help_outline_rounded, size: 16, color: accent),
                    label: Text('Why this score', style: TextStyle(color: accent)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Floating snackbar after applying an improved layout.
/// Always returns to Rig ([onOpenRig]) so Apply is a one-hop finish.
void showBenchApplySnackBar(
  BuildContext context, {
  required String message,
  required Color accentColor,
  required VoidCallback onOpenRig,
  Future<void> Function()? onShareImage,
}) {
  onOpenRig();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 5),
      content: Row(
        children: [
          Expanded(child: Text(message)),
          if (onShareImage != null) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Share before/after image',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: const Icon(Icons.ios_share_rounded, color: Colors.white, size: 18),
              onPressed: () async {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                await onShareImage();
              },
            ),
          ],
        ],
      ),
      backgroundColor: accentColor.withValues(alpha: 0.9),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Confirm before pushing an improved bench layout to the Rig.
Future<bool> confirmBenchApply(
  BuildContext context, {
  required BenchmarkValidation validation,
  bool fellBackToSample = false,
}) async {
  if (fellBackToSample) {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Cannot apply demo layout', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Your Rig is empty, so Bench is showing a reference room. '
          'Add furniture on Rig (or load a preset) before applying.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
    return false;
  }

  if (validation.hasHardLayoutConflicts) {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Cannot apply layout', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'The improved layout still has overlapping furniture or blocked doorways. '
          'Fix conflicts on the Rig or re-run the bench.',
          style: TextStyle(color: AppColors.textSecondary),
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
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Apply Bench suggestion to Rig?', style: TextStyle(color: AppColors.textPrimary)),
      content: const Text(
        'This replaces your current furniture layout with the Bench suggestion, '
        'saves a checkpoint, and returns you to Rig.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Apply Bench suggestion to Rig'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Short "why this wins" line from optimizer reasons (for Apply snackbars).
String summarizeWhyWins(List<String> reasons, {int max = 2}) {
  if (reasons.isEmpty) return '';
  final clipped = reasons
      .map((r) => r.trim())
      .where((r) => r.isNotEmpty)
      .take(max)
      .toList();
  if (clipped.isEmpty) return '';
  return clipped.join(' · ');
}

/// Results-step card listing why the improved layout scores better.
Widget benchWhyWinsCard({
  required List<String> reasons,
  required Color accentColor,
  String title = 'Why this wins',
}) {
  if (reasons.isEmpty) return const SizedBox.shrink();
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: accentColor.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: accentColor.withValues(alpha: 0.40)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: accentColor,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        ...reasons.take(4).map(
          (r) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_outline_rounded, size: 14, color: accentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    r,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// Human-readable summary of furniture moves between two layouts.
String summarizeLayoutDiff(List<FurnitureItem> before, List<FurnitureItem> after) {
  final beforeById = {for (final f in before) f.id: f};
  final afterById = {for (final f in after) f.id: f};
  var moved = 0;
  final movedNames = <String>[];
  for (final entry in afterById.entries) {
    final prior = beforeById[entry.key];
    if (prior == null) continue;
    final next = entry.value;
    final shifted = (next.gridX - prior.gridX).abs() > 0.05 ||
        (next.gridY - prior.gridY).abs() > 0.05 ||
        (next.yawDegrees - prior.yawDegrees).abs() > 0.5 ||
        (next.width - prior.width).abs() > 0.05 ||
        (next.height - prior.height).abs() > 0.05;
    if (!shifted) continue;
    moved++;
    if (movedNames.length < 3) movedNames.add(next.name);
  }
  final added = afterById.keys.where((id) => !beforeById.containsKey(id)).length;
  final removed = beforeById.keys.where((id) => !afterById.containsKey(id)).length;
  if (moved == 0 && added == 0 && removed == 0) {
    return 'layout unchanged';
  }
  final parts = <String>[];
  if (moved > 0) {
    final names = movedNames.join(', ');
    parts.add(moved == 1 ? 'moved $names' : 'moved $moved items ($names${moved > 3 ? '…' : ''})');
  }
  if (added > 0) parts.add('+$added');
  if (removed > 0) parts.add('-$removed');
  return parts.join(' · ');
}

/// True when improved furniture matches my-room — Apply would be a no-op.
bool improvedLayoutIsNoOp(BenchLayouts? layouts) {
  if (layouts == null) return false;
  return BenchLayoutBuilder.fingerprintOf(layouts.myRoom) ==
      BenchLayoutBuilder.fingerprintOf(layouts.improved);
}

Widget benchImprovedNoOpBanner({String message = 'Improved layout matches your room — nothing new to apply.'}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.amber.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.amber.withValues(alpha: 0.45)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.amber),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Rig-style desktop shell: left controls · center viewport · right inspect.
class BenchDesktopShell extends StatelessWidget {
  final Color accentColor;
  final Widget controls;
  final Widget viewport;
  final Widget inspect;
  final String controlsTitle;
  final String inspectTitle;

  const BenchDesktopShell({
    super.key,
    required this.accentColor,
    required this.controls,
    required this.viewport,
    required this.inspect,
    this.controlsTitle = 'Workspace',
    this.inspectTitle = 'Inspect',
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: AppLayout.toolsRailWidthFor(context),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(
                right: BorderSide(color: AppColors.borderSubtle),
              ),
            ),
            child: AdaptiveRailPane(
              title: controlsTitle,
              icon: Icons.tune_rounded,
              accent: accentColor,
              child: controls,
            ),
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: AppColors.bg,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: ColoredBox(
                  color: AppColors.surface,
                  child: viewport,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: AppLayout.inspectRailWidthFor(context),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: AppColors.borderSubtle),
              ),
            ),
            child: AdaptiveRailPane(
              title: inspectTitle,
              icon: Icons.analytics_outlined,
              accent: accentColor,
              child: inspect,
            ),
          ),
        ),
      ],
    );
  }
}

/// Orchestrates the common bench panel column: tabs, step content, progress, results, apply.
///
/// On desktop, when [desktopControls] / [desktopViewport] / [desktopInspect] are
/// provided, uses a Rig-style three-rail shell instead of a stacked column.
class BenchPanelScaffold extends StatelessWidget {
  final Color accentColor;
  final int step;
  final List<String> stepLabels;
  final bool resultsEnabled;
  final bool running;
  final ValueChanged<int> onStepChanged;

  /// Shown on the layout step (mobile / fallback).
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

  /// Desktop three-rail slots (current step). When non-null on desktop width, used
  /// instead of the stacked [layoutBody] / [middleBody] / [resultsBody] column.
  final Widget? desktopControls;
  final Widget? desktopViewport;
  final Widget? desktopInspect;

  /// When true (default), mobile chrome shows a compact domain score opposite
  /// the View / Inspect chips instead of a full-width hero.
  final bool showChromeScore;

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
    this.desktopControls,
    this.desktopViewport,
    this.desktopInspect,
    this.showChromeScore = true,
  });

  bool get _hasShellSlots =>
      desktopControls != null && desktopViewport != null && desktopInspect != null;

  bool _useDesktopShell(BuildContext context) =>
      AppLayout.isDesktop(context) && _hasShellSlots;

  /// Appends [layoutRunAction] / [middleRunAction] once so panels do not embed RUN
  /// in [desktopControls] (that duplicated body RUN on mobile View sheets).
  Widget _controlsWithRun(Widget controls) {
    final run = step == benchStepLayout
        ? layoutRunAction
        : (step == benchStepMiddle ? middleRunAction : null);
    if (run == null) return controls;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        controls,
        const SizedBox(height: 16),
        run,
      ],
    );
  }

  /// Rig-style View / Inspect sheets; canvas + step/RUN stay in the page body
  /// (Tools used to re-host the same tabs/RUN and looked like duplicate actions).
  Widget _mobileShellChrome(BuildContext context) {
    final controller = AdaptivePanelController([
      AdaptivePanelSpec(
        region: ChromeRegion.view,
        preferTall: true,
        builder: (ctx) => SingleChildScrollView(child: desktopControls!),
      ),
      AdaptivePanelSpec(
        region: ChromeRegion.inspect,
        preferTall: true,
        builder: (ctx) => SingleChildScrollView(child: desktopInspect!),
      ),
    ]);

    final hasResultsBlock = step == benchStepResults &&
        !running &&
        (resultsExtra != null ||
            resultsBody != null ||
            (onApply != null && onRefresh != null));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AdaptivePanelTriggers(
              controller: controller,
              accent: accentColor,
              visible: const [
                ChromeRegion.view,
                ChromeRegion.inspect,
              ],
            ),
            if (showChromeScore) ...[
              const Spacer(),
              BenchChromeScore(accentColor: accentColor),
            ],
          ],
        ),
        const SizedBox(height: 10),
        BenchStepTabs(
          accentColor: accentColor,
          step: step,
          labels: stepLabels,
          resultsEnabled: resultsEnabled || running,
          onStepChanged: onStepChanged,
        ),
        const SizedBox(height: 12),
        Expanded(
          flex: hasResultsBlock ? 3 : 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: ColoredBox(
              color: AppColors.surface,
              child: desktopViewport!,
            ),
          ),
        ),
        if (running && progress != null && progressLabel != null) ...[
          const SizedBox(height: 12),
          BenchProgressBar(
            progress: progress!,
            label: progressLabel!,
            accentColor: accentColor,
          ),
        ],
        if (step == benchStepLayout && layoutRunAction != null) ...[
          const SizedBox(height: 12),
          layoutRunAction!,
        ],
        if (step == benchStepMiddle && middleRunAction != null) ...[
          const SizedBox(height: 12),
          middleRunAction!,
        ],
        if (hasResultsBlock) ...[
          const SizedBox(height: 12),
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (resultsExtra != null) ...[
                    resultsExtra!,
                    const SizedBox(height: 12),
                  ],
                  ?resultsBody,
                  if (onApply != null && onRefresh != null) ...[
                    const SizedBox(height: 12),
                    BenchApplyRow(
                      onApply: applyEnabled ? onApply : null,
                      onRefresh: onRefresh!,
                      blockedReason: applyEnabled ? null : applyBlockedReason,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final steps = BenchStepTabs(
      accentColor: accentColor,
      step: step,
      labels: stepLabels,
      resultsEnabled: resultsEnabled || running,
      onStepChanged: onStepChanged,
    );

    if (_useDesktopShell(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: steps,
          ),
          Expanded(
            child: BenchDesktopShell(
              accentColor: accentColor,
              controls: _controlsWithRun(desktopControls!),
              viewport: desktopViewport!,
              inspect: desktopInspect!,
            ),
          ),
        ],
      );
    }

    if (_hasShellSlots) {
      return _mobileShellChrome(context);
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          steps,
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
              BenchProgressBar(
                progress: progress!,
                label: progressLabel!,
                accentColor: accentColor,
              ),
            ],
          ],
          if (step == benchStepResults) ...[
            ?middleBody,
            if (running && progress != null && progressLabel != null) ...[
              const SizedBox(height: 16),
              BenchProgressBar(
                progress: progress!,
                label: progressLabel!,
                accentColor: accentColor,
              ),
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
      ),
    );
  }
}
