import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../models/upgrade_catalog.dart';
import '../theme/app_theme.dart';

/// Compact score / conflict strip (House Control–style always-on status).
class RoomStatusStrip extends StatelessWidget {
  const RoomStatusStrip({
    super.key,
    this.onTapScores,
    this.onTapConflicts,
    this.compact = false,
  });

  final VoidCallback? onTapScores;
  final VoidCallback? onTapConflicts;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final conflicts = state.layoutConflicts.length;
    final simulated = state.scoresAreSimulated;
    final fs = compact ? 11.0 : 12.0;

    return Material(
      color: AppColors.card.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTapScores,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 6 : 8,
          ),
          child: Row(
            children: [
              _chip(
                simulated ? HubScoreLabels.roughEst : HubScoreLabels.benchmarkOk,
                simulated ? AppColors.amber : AppColors.green,
                fs,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Air ${state.airflowScore.round()} · '
                  'Light ${state.lightingScore.round()} · '
                  'Ergo ${state.ergonomicsScore.round()} · '
                  'Space ${state.spatialScore.round()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: fs,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (conflicts > 0) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: onTapConflicts ?? onTapScores,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      '$conflicts conflict${conflicts == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: AppColors.amber,
                        fontSize: fs,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, Color color, double fs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: fs - 1,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Corner badge for Model stage — mirrors Hub ROUGH EST / BENCHMARK OK honesty.
class ModelHonestyBadge extends StatelessWidget {
  const ModelHonestyBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final simulated = state.scoresAreSimulated;
    final color = simulated ? AppColors.amber : AppColors.green;
    final label = simulated ? HubScoreLabels.roughEst : HubScoreLabels.benchmarkOk;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.bg.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
