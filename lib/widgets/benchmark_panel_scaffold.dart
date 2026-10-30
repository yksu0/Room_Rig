// lib/widgets/benchmark_panel_scaffold.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/benchmark_compare_source.dart';
import '../models/room_model.dart';
import '../models/upgrade_catalog.dart';
import '../services/benchmark_layouts.dart';
import '../services/benchmark_score_copy.dart';
import '../services/benchmark_validator.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import 'auto_rig_lock_summary.dart';
import 'benchmark_validation_card.dart';
import 'benchmark_room_views.dart';
import 'chrome/adaptive_panel.dart';
import 'chrome/benchmark_results_chrome.dart';
import 'community_benchmark_panel.dart';
import 'glass_card.dart';
import 'room_icons.dart';
import 'score_ring.dart';

export 'chrome/adaptive_panel.dart' show ChromeRegion;

/// Step indices shared by all benchmark panels.
const int benchmarkStepLayout = 0;
const int benchmarkStepMiddle = 1;
const int benchmarkStepResults = 2;

/// Universal wizard chip labels (no numeric prefixes — mobile truncates them).
const List<String> kBenchmarkStepLabels = ['Layout', 'Analyze', 'Results'];

/// Layout / Analyze / Results — inset sliding-pill track (style D).
class BenchmarkStepTabs extends StatelessWidget {
  final Color accentColor;
  final int step;
  final List<String> labels;
  final bool resultsEnabled;
  final ValueChanged<int> onStepChanged;

  const BenchmarkStepTabs({
    super.key,
    required this.accentColor,
    required this.step,
    required this.labels,
    required this.resultsEnabled,
    required this.onStepChanged,
  });

  @override
  Widget build(BuildContext context) {
    return BenchmarkSegmentBar(
      children: [
        for (var i = 0; i < labels.length; i++)
          Opacity(
            opacity: (i == benchmarkStepResults && !resultsEnabled) ? 0.45 : 1,
            child: BenchmarkChip(
              label: labels[i],
              selected: step == i,
              color: accentColor,
              onTap: () {
                if (i == benchmarkStepResults && !resultsEnabled) return;
                onStepChanged(i);
              },
            ),
          ),
      ],
    );
  }
}

/// Equal-width inset track for mutually exclusive Workspace controls.
class BenchmarkSegmentBar extends StatelessWidget {
  final List<Widget> children;
  final double gap;

  const BenchmarkSegmentBar({
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

/// Segment thumb inside [BenchmarkSegmentBar] — solid selected fill, no neon glow.
class BenchmarkChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final bool compact;

  const BenchmarkChip({
    super.key,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label benchmark mode',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? AppSpace.xxs : AppSpace.xs,
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
      ),
    );
  }
}

/// Left / Right variant selector (labels follow Compare pickers when provided).
class BenchmarkVariantChips extends StatelessWidget {
  final BenchmarkLayoutKind selected;
  final ValueChanged<BenchmarkLayoutKind> onChanged;
  final String leftLabel;
  final String rightLabel;

  const BenchmarkVariantChips({
    super.key,
    required this.selected,
    required this.onChanged,
    this.leftLabel = 'Left',
    this.rightLabel = 'Right',
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final left = leftLabel == 'Left'
        ? state.benchmarkCompareSourceLabel(state.benchmarkCompareLeft)
        : leftLabel;
    final right = rightLabel == 'Right'
        ? state.benchmarkCompareSourceLabel(state.benchmarkCompareRight)
        : rightLabel;
    return BenchmarkSegmentBar(
      children: [
        BenchmarkChip(
          label: left,
          selected: selected == BenchmarkLayoutKind.currentRoom,
          color: AppColors.cyan,
          onTap: () => onChanged(BenchmarkLayoutKind.currentRoom),
        ),
        BenchmarkChip(
          label: right,
          selected: selected == BenchmarkLayoutKind.autoRig,
          color: AppColors.green,
          onTap: () => onChanged(BenchmarkLayoutKind.autoRig),
        ),
      ],
    );
  }
}

/// Compact House Control–style score hero (phone ~56–72px; larger OK in rails).
class BenchmarkScoreHero extends StatelessWidget {
  final String label;
  final double score;
  final double? previousScore;
  final Color color;
  final bool expand;

  const BenchmarkScoreHero({
    super.key,
    required this.label,
    required this.score,
    this.previousScore,
    required this.color,
    this.expand = false,
  });

  BenchmarkScoreDomain get _domain => BenchmarkScoreCopy.domainFromBenchmarkMode(
        switch (label.toLowerCase()) {
          'lighting' || 'light' => 'lighting',
          'ergonomics' || 'comfort' || 'ergo' => 'ergonomics',
          'space' || 'spatial' => 'spatial',
          _ => 'airflow',
        },
      );

  @override
  Widget build(BuildContext context) {
    final prev = previousScore;
    final domain = _domain;
    final grade = BenchmarkScoreCopy.gradeWord(score, domain);
    final vsRoom = BenchmarkScoreCopy.deltaVsRoom(score, prev);
    final height = expand ? 96.0 : 72.0;
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
                  grade,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
                Text(
                  '${score.round()}${vsRoom.isEmpty ? '' : ' · $vsRoom'}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (expand)
            Expanded(
              child: Text(
                BenchmarkScoreCopy.blurb(domain),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  height: 1.3,
                ),
                textAlign: TextAlign.end,
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                width: 72,
                child: LinearProgressIndicator(
                  value: (score / 100).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: AppColors.borderSubtle,
                  color: color,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tiny score badge for the mobile View/Inspect chrome row (~44px tall).
class BenchmarkChromeScore extends StatelessWidget {
  const BenchmarkChromeScore({super.key, required this.accentColor});

  final Color accentColor;

  void _openScoreHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'WHAT THESE SCORES MEAN',
                style: TextStyle(
                  color: AppColors.cyan,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'These are layout estimates (0–100). Higher is better. '
                '${HubScoreLabels.roughEst} means a live guess; ${HubScoreLabels.benchmarkOk} means a Benchmark run locked the number.',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 12),
              for (final d in BenchmarkScoreDomain.values) ...[
                Text(
                  BenchmarkScoreCopy.shortLabel(d),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  BenchmarkScoreCopy.blurb(d),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.3),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final domain = BenchmarkScoreCopy.domainFromBenchmarkMode(state.benchmarkMode);
    final score = switch (domain) {
      BenchmarkScoreDomain.lighting => state.lightingScore,
      BenchmarkScoreDomain.ergonomics => state.ergonomicsScore,
      BenchmarkScoreDomain.spatial => state.spatialScore,
      BenchmarkScoreDomain.airflow => state.airflowScore,
    };
    final short = switch (domain) {
      BenchmarkScoreDomain.airflow => 'Air',
      BenchmarkScoreDomain.lighting => 'Light',
      BenchmarkScoreDomain.ergonomics => 'Ergo',
      BenchmarkScoreDomain.spatial => 'Space',
    };

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () => _openScoreHelp(context),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44, maxWidth: 88),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: accentColor.withValues(alpha: 0.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$short ${score.round()}',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.help_outline_rounded, size: 14, color: accentColor.withValues(alpha: 0.85)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Prefixed lock summary for Benchmark Inspect sheets.
class BenchmarkInspectLockBlock extends StatelessWidget {
  const BenchmarkInspectLockBlock({super.key, required this.furniture});

  final List<FurnitureItem> furniture;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: AutoRigLockSummary(furniture: furniture, compact: true),
        ),
      ),
    );
  }
}

/// View-mode chips on their own row (Room-style: view ≠ content variant).
class BenchmarkViewChips extends StatelessWidget {
  final List<Widget> children;

  const BenchmarkViewChips({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final compact = children.length >= 4;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: BenchmarkSegmentBar(
        gap: compact ? 5 : 6,
        children: [
          for (final child in children)
            if (child is BenchmarkChip)
              BenchmarkChip(
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

/// True when Benchmark layouts already match the live Room furniture + weight mix.
bool benchmarkLayoutsInSync(BenchmarkLayouts? layouts, {
  required String furnitureFingerprint,
  required String weightsCacheKey,
  required int alternateCursor,
}) {
  if (layouts == null) return false;
  return furnitureFingerprint == layouts.fingerprint &&
      weightsCacheKey == layouts.weightsCacheKey &&
      alternateCursor == layouts.requestedAlternateIndex;
}

/// Side-by-side Left | Right floor plans (replaces the old scrub compare).
class BenchmarkSideBySidePlans extends StatelessWidget {
  final int gridCols;
  final int gridRows;
  final List<FurnitureItem> currentRoom;
  final List<FurnitureItem> autoRig;
  final Color accentColor;
  final String leftLabel;
  final String rightLabel;

  const BenchmarkSideBySidePlans({
    super.key,
    required this.gridCols,
    required this.gridRows,
    required this.currentRoom,
    required this.autoRig,
    this.accentColor = AppColors.cyan,
    this.leftLabel = 'Left',
    this.rightLabel = 'Right',
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final left = leftLabel == 'Left'
        ? state.benchmarkCompareSourceLabel(state.benchmarkCompareLeft)
        : leftLabel;
    final right = rightLabel == 'Right'
        ? state.benchmarkCompareSourceLabel(state.benchmarkCompareRight)
        : rightLabel;
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
                  label: left,
                  color: AppColors.cyan,
                  furniture: currentRoom,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _pane(
                  label: right,
                  color: AppColors.green,
                  furniture: autoRig,
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
              painter: BenchmarkRoom2DPainter(
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

/// Auto-Rig mix line + optional Try alternate (parity with Room star dialog).
class BenchmarkAutoRigMixBar extends StatelessWidget {
  final BenchmarkLayouts? layouts;
  final VoidCallback? onTryAlternate;

  const BenchmarkAutoRigMixBar({
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

/// Gradient primary action button (run benchmark, apply layout, etc.).
class BenchmarkPrimaryButton extends StatelessWidget {
  final String label;
  final String icon;
  final VoidCallback? onTap;

  const BenchmarkPrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Semantics(
      button: true,
      enabled: !disabled,
      label: label,
      child: GestureDetector(
        key: const ValueKey('benchmark_apply_btn'),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
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
      ),
    );
  }
}

/// Compact refresh control paired with the apply button.
class BenchmarkRefreshButton extends StatelessWidget {
  final VoidCallback onTap;

  const BenchmarkRefreshButton({super.key, required this.onTap});

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
class BenchmarkApplyRow extends StatelessWidget {
  final VoidCallback? onApply;
  final VoidCallback onRefresh;
  final String? blockedReason;

  const BenchmarkApplyRow({
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
              child: BenchmarkPrimaryButton(
                label: 'APPLY BENCHMARK SUGGESTION TO ROOM',
                icon: RoomSvg.star,
                onTap: onApply,
              ),
            ),
            const SizedBox(width: 8),
            BenchmarkRefreshButton(onTap: onRefresh),
          ],
        ),
        if (onApply == null && blockedReason != null) ...[
          const SizedBox(height: AppSpace.xs),
          Text(
            blockedReason!,
            key: const ValueKey('benchmark_apply_blocked_reason'),
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

/// Simulated run progress bar shown during async benchmark runs.
class BenchmarkProgressBar extends StatelessWidget {
  final double progress;
  final String label;
  final Color accentColor;

  const BenchmarkProgressBar({
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
class BenchmarkRunAction extends StatelessWidget {
  final String buttonLabel;
  final String icon;
  final VoidCallback? onRun;
  final String? hint;

  const BenchmarkRunAction({
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
        BenchmarkPrimaryButton(label: buttonLabel, icon: icon, onTap: onRun),
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
class BenchmarkMetricTile extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final bool invert;

  const BenchmarkMetricTile({
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

/// Score ring configuration for [BenchmarkResultsCard].
class BenchmarkScoreRingSpec {
  final double score;
  final Color color;
  final String label;
  final double size;

  const BenchmarkScoreRingSpec({
    required this.score,
    required this.color,
    required this.label,
    this.size = 78,
  });
}

/// Left vs right metric bar used on Results scoreboards.
///
/// [left]/[right] drive the bar (0–100 scale). Optional [leftDisplay] /
/// [rightDisplay] override the numeric caption when the bar is remapped.
class BenchmarkMetricComparisonRow extends StatelessWidget {
  final String label;
  final double left;
  final double right;
  final Color color;
  final bool lowerIsBetter;
  final double? leftDisplay;
  final double? rightDisplay;

  const BenchmarkMetricComparisonRow({
    super.key,
    required this.label,
    required this.left,
    required this.right,
    required this.color,
    this.lowerIsBetter = false,
    this.leftDisplay,
    this.rightDisplay,
  });

  @override
  Widget build(BuildContext context) {
    final shownLeft = leftDisplay ?? left;
    final shownRight = rightDisplay ?? right;
    final delta = shownRight - shownLeft;
    final good = lowerIsBetter ? delta <= 0 : delta >= 0;
    final display = lowerIsBetter ? -delta : delta;
    return Row(
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                Container(height: 8, color: AppColors.border),
                FractionallySizedBox(
                  widthFactor: (left / 100).clamp(0.0, 1.0),
                  child: Container(height: 8, color: AppColors.textMuted),
                ),
                FractionallySizedBox(
                  widthFactor: (right / 100).clamp(0.0, 1.0),
                  child: Container(height: 8, color: color.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          child: Text(
            '${shownLeft.toStringAsFixed(0)}→${shownRight.toStringAsFixed(0)}',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${good ? '+' : ''}${display.toStringAsFixed(1)}',
          style: TextStyle(
            color: good ? AppColors.green : AppColors.red,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// Results comparison: dual rings + metric rows for the Compare pair.
class BenchmarkResultsCard extends StatelessWidget {
  final String title;
  final BenchmarkValidation validation;
  final List<BenchmarkScoreRingSpec> rings;
  final String summaryText;
  final Color? accentColor;
  final List<String> whyReasons;
  final VoidCallback? onOpenWhySheet;
  /// e.g. "Now comparing: Current Room vs Auto-Rig"
  final String? compareHeader;
  final List<Widget> metricRows;

  const BenchmarkResultsCard({
    super.key,
    required this.title,
    required this.validation,
    required this.rings,
    required this.summaryText,
    this.accentColor,
    this.whyReasons = const [],
    this.onOpenWhySheet,
    this.compareHeader,
    this.metricRows = const [],
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? AppColors.cyan;
    return GlassCard(
      borderColor: BenchmarkResultBadge.colorFor(validation.verdict).withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BenchmarkVerdictHeader(
            verdict: summaryText,
            detail: title,
            accent: accent,
            children: [
              if (compareHeader != null) ...[
                Text(
                  compareHeader!,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
              ],
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
                  BenchmarkResultBadge(validation: validation),
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
              if (metricRows.isNotEmpty) ...[
                const SizedBox(height: 14),
                for (var i = 0; i < metricRows.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  metricRows[i],
                ],
              ],
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

/// Floating snackbar after applying an Auto-Rig proposal.
/// Always returns to Room ([onOpenRoom]) so Apply is a one-hop finish.
void showBenchmarkApplySnackBar(
  BuildContext context, {
  required String message,
  required Color accentColor,
  required VoidCallback onOpenRoom,
  Future<void> Function()? onShareImage,
  VoidCallback? onKeepAsBaseline,
}) {
  onOpenRoom();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 4),
      content: Row(
        children: [
          Expanded(child: Text(message)),
          if (onKeepAsBaseline != null) ...[
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                onKeepAsBaseline();
              },
              child: const Text(
                'Save snapshot',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ),
          ],
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
      dismissDirection: DismissDirection.horizontal,
      showCloseIcon: true,
      closeIconColor: Colors.white70,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    ),
  );
}

/// Fingerprint of the active compare pair (for resim cache invalidation).
String benchmarkCompareFingerprint(AppState state) {
  final left =
      state.resolveBenchmarkCompareFurniture(state.benchmarkCompareLeft) ?? const [];
  final rightKey = state.benchmarkCompareRight.isAutoRig
      ? 'auto'
      : BenchmarkLayoutBuilder.fingerprintOf(
          state.resolveBenchmarkCompareFurniture(state.benchmarkCompareRight) ??
              const [],
        );
  return '${BenchmarkLayoutBuilder.fingerprintOf(left)}|$rightKey|'
      '${state.benchmarkCompareLeft.kind.name}|'
      '${state.benchmarkCompareRight.kind.name}|'
      '${state.benchmarkCompareLeft.checkpointId ?? ''}|'
      '${state.benchmarkCompareRight.checkpointId ?? ''}';
}

/// Legacy alias used by panels still importing [benchmarkSyncFurniture].
List<FurnitureItem> benchmarkSyncFurniture(AppState state) {
  return state.resolveBenchmarkCompareFurniture(state.benchmarkCompareLeft) ??
      state.committedFurniture.where((f) => !f.hidden).toList(growable: false);
}

/// Compare sheet: pick Left and Right sources.
class BenchmarkComparePanel extends StatelessWidget {
  final Color accentColor;
  final VoidCallback? onTryAlternate;
  final BenchmarkLayouts? layouts;

  const BenchmarkComparePanel({
    super.key,
    required this.accentColor,
    this.onTryAlternate,
    this.layouts,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final canAlt = onTryAlternate != null && (layouts?.canTryAlternate ?? false);
    final leftName = state.benchmarkCompareSourceLabel(state.benchmarkCompareLeft);
    final rightName = state.benchmarkCompareSourceLabel(state.benchmarkCompareRight);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Now comparing',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$leftName  vs  $rightName',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          state.benchmarkCompareRight.isAutoRig || state.benchmarkCompareLeft.isAutoRig
              ? 'Preview — Room unchanged until Apply (Auto-Rig side only)'
              : 'Scoring two layouts — Apply is only for Auto-Rig proposals',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.35),
        ),
        const SizedBox(height: 16),
        _sidePicker(
          context,
          state,
          title: 'Left',
          source: state.benchmarkCompareLeft,
          onPick: state.setBenchmarkCompareLeft,
        ),
        const SizedBox(height: 14),
        _sidePicker(
          context,
          state,
          title: 'Right',
          source: state.benchmarkCompareRight,
          onPick: state.setBenchmarkCompareRight,
        ),
        if (canAlt) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onTryAlternate,
              child: const Text('Try alternate Auto-Rig'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        const Text(
          'Snapshots come from Room → Snapshot (Hub checkpoints). Apply writes an Auto-Rig side onto your Room.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }

  Widget _sidePicker(
    BuildContext context,
    AppState state, {
    required String title,
    required BenchmarkCompareSource source,
    required ValueChanged<BenchmarkCompareSource> onPick,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            color: accentColor,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        OutlinedButton(
          onPressed: () => _pickSource(context, state, onPick),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(state.benchmarkCompareSourceLabel(source)),
          ),
        ),
      ],
    );
  }

  Future<void> _pickSource(
    BuildContext context,
    AppState state,
    ValueChanged<BenchmarkCompareSource> onPick,
  ) async {
    final revs = state.activeRoomRevisions;
    final picked = await showModalBottomSheet<BenchmarkCompareSource>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Compare source',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              ListTile(
                title: const Text('Current Room', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () => Navigator.pop(ctx, const BenchmarkCompareSource.currentRoom()),
              ),
              ListTile(
                title: const Text('Auto-Rig', style: TextStyle(color: AppColors.textPrimary)),
                subtitle: const Text(
                  'Same engine as Room Tools → Auto-Rig',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                onTap: () => Navigator.pop(ctx, const BenchmarkCompareSource.autoRig()),
              ),
              ListTile(
                title: const Text('Community layout…', style: TextStyle(color: AppColors.textPrimary)),
                subtitle: const Text(
                  'Baselines and published rooms (signed in)',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await showCommunityComparePicker(
                    context,
                    onPick: onPick,
                  );
                },
              ),
              if (revs.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Snapshots',
                    style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w800),
                  ),
                ),
                for (final r in revs.reversed)
                  ListTile(
                    title: Text(r.label, style: const TextStyle(color: AppColors.textPrimary)),
                    subtitle: Text(
                      '${r.furniture.length} items',
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                    onTap: () => Navigator.pop(ctx, BenchmarkCompareSource.checkpoint(r.id)),
                  ),
              ] else
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Text(
                    'No snapshots yet — use Room → Snapshot to save one.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null) return;
    onPick(picked);
  }
}

/// Confirm before pushing an improved benchmark layout to the Room.
Future<bool> confirmBenchmarkApply(
  BuildContext context, {
  required BenchmarkValidation validation,
  bool isEmpty = false,
}) async {
  if (isEmpty) {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Cannot apply layout', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'No furniture in this room yet. Create or stock a room before applying Auto-Rig. '
          'Add furniture on Room (or load a preset), then Set baseline before applying.',
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
          'The Auto-Rig layout still has overlapping furniture or blocked doorways. '
          'Fix conflicts on the Room or re-run the benchmark.',
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
      title: const Text('Apply Auto-Rig to Room?', style: TextStyle(color: AppColors.textPrimary)),
      content: const Text(
        'This replaces your current furniture layout with the Auto-Rig proposal, '
        'saves a checkpoint, and returns you to Room.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Apply Benchmark suggestion to Room'),
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
Widget benchmarkWhyWinsCard({
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
bool improvedLayoutIsNoOp(BenchmarkLayouts? layouts) {
  if (layouts == null) return false;
  return BenchmarkLayoutBuilder.fingerprintOf(layouts.currentRoom) ==
      BenchmarkLayoutBuilder.fingerprintOf(layouts.autoRig);
}

Widget benchmarkImprovedNoOpBanner({String message = 'Auto-Rig matches Baseline — nothing new to apply.'}) {
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

/// Room-style desktop shell: left controls · center viewport · right inspect.
class BenchmarkDesktopShell extends StatelessWidget {
  final Color accentColor;
  final Widget controls;
  final Widget viewport;
  final Widget inspect;
  final String controlsTitle;
  final String inspectTitle;

  const BenchmarkDesktopShell({
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

/// Orchestrates the common benchmark panel column: tabs, step content, progress, results, apply.
///
/// On desktop, when [desktopControls] / [desktopViewport] / [desktopInspect] are
/// provided, uses a Room-style three-rail shell instead of a stacked column.
class BenchmarkPanelScaffold extends StatelessWidget {
  final Color accentColor;
  final int step;
  final List<String> stepLabels;
  final bool resultsEnabled;
  final bool running;
  final ValueChanged<int> onStepChanged;

  /// Shown on the layout step (mobile / fallback).
  final Widget? layoutBody;
  final BenchmarkRunAction? layoutRunAction;

  /// Shown on the middle step and during results (when not running for sim panels).
  final Widget? middleBody;
  final BenchmarkRunAction? middleRunAction;

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
  /// the View / Compare / Inspect chips instead of a full-width hero.
  final bool showChromeScore;

  /// Optional Auto-Rig layouts for the Compare sheet (Try alternate, captions).
  final BenchmarkLayouts? compareLayouts;
  final VoidCallback? onTryAlternate;

  const BenchmarkPanelScaffold({
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
    this.compareLayouts,
    this.onTryAlternate,
  });

  bool get _hasShellSlots =>
      desktopControls != null && desktopViewport != null && desktopInspect != null;

  bool _useDesktopShell(BuildContext context) =>
      AppLayout.isDesktop(context) && _hasShellSlots;

  /// Appends [layoutRunAction] / [middleRunAction] once so panels do not embed RUN
  /// in [desktopControls] (that duplicated body RUN on mobile View sheets).
  Widget _controlsWithRun(Widget controls) {
    final run = step == benchmarkStepLayout
        ? layoutRunAction
        : (step == benchmarkStepMiddle ? middleRunAction : null);
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

  /// Room-style View / Compare / Inspect sheets; canvas + step/RUN stay in the page body
  /// (Tools used to re-host the same tabs/RUN and looked like duplicate actions).
  Widget _mobileShellChrome(BuildContext context) {
    final controller = AdaptivePanelController([
      AdaptivePanelSpec(
        region: ChromeRegion.view,
        preferTall: true,
        builder: (ctx) => SingleChildScrollView(child: desktopControls!),
      ),
      AdaptivePanelSpec(
        region: ChromeRegion.compare,
        preferTall: true,
        builder: (ctx) => SingleChildScrollView(
          child: BenchmarkComparePanel(
            accentColor: accentColor,
            layouts: compareLayouts,
            onTryAlternate: onTryAlternate,
          ),
        ),
      ),
      AdaptivePanelSpec(
        region: ChromeRegion.inspect,
        preferTall: true,
        builder: (ctx) => SingleChildScrollView(child: desktopInspect!),
      ),
    ]);

    final hasResultsBlock = step == benchmarkStepResults &&
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
                ChromeRegion.compare,
                ChromeRegion.inspect,
              ],
            ),
            if (showChromeScore) ...[
              const SizedBox(width: 6),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: BenchmarkChromeScore(accentColor: accentColor),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        BenchmarkStepTabs(
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
          BenchmarkProgressBar(
            progress: progress!,
            label: progressLabel!,
            accentColor: accentColor,
          ),
        ],
        if (step == benchmarkStepLayout && layoutRunAction != null) ...[
          const SizedBox(height: 12),
          layoutRunAction!,
        ],
        if (step == benchmarkStepMiddle && middleRunAction != null) ...[
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
                  if (onRefresh != null && (onApply != null || applyBlockedReason != null)) ...[
                    const SizedBox(height: 12),
                    BenchmarkApplyRow(
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
    final steps = BenchmarkStepTabs(
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
            child: Row(
              children: [
                Expanded(child: steps),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      backgroundColor: AppColors.surface,
                      isScrollControlled: true,
                      builder: (ctx) => SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          child: BenchmarkComparePanel(
                            accentColor: accentColor,
                            layouts: compareLayouts,
                            onTryAlternate: onTryAlternate,
                          ),
                        ),
                      ),
                    );
                  },
                  icon: Icon(Icons.compare_arrows_rounded, color: accentColor, size: 18),
                  label: Text('Compare', style: TextStyle(color: accentColor, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          Expanded(
            child: BenchmarkDesktopShell(
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
          if (step == benchmarkStepLayout && layoutBody != null) ...[
            layoutBody!,
            if (layoutRunAction != null) ...[
              const SizedBox(height: 16),
              layoutRunAction!,
            ],
          ],
          if (step == benchmarkStepMiddle && middleBody != null) ...[
            middleBody!,
            if (middleRunAction != null) ...[
              const SizedBox(height: 16),
              middleRunAction!,
            ],
            if (running && progress != null && progressLabel != null) ...[
              const SizedBox(height: 16),
              BenchmarkProgressBar(
                progress: progress!,
                label: progressLabel!,
                accentColor: accentColor,
              ),
            ],
          ],
          if (step == benchmarkStepResults) ...[
            ?middleBody,
            if (running && progress != null && progressLabel != null) ...[
              const SizedBox(height: 16),
              BenchmarkProgressBar(
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
              if (onRefresh != null && (onApply != null || applyBlockedReason != null)) ...[
                const SizedBox(height: 16),
                BenchmarkApplyRow(
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
