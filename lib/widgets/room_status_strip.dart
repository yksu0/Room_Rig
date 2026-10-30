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
    final honesty = simulated ? HubScoreLabels.roughEst : HubScoreLabels.benchmarkOk;
    final honestyColor = simulated ? AppColors.amber : AppColors.green;
    final scores =
        'Air ${state.airflowScore.round()} · '
        'Light ${state.lightingScore.round()} · '
        'Ergo ${state.ergonomicsScore.round()} · '
        'Space ${state.spatialScore.round()}';

    return Material(
      color: AppColors.card.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTapScores,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final phone = constraints.maxWidth < 412;
            final fs = compact || phone ? 11.0 : 12.0;
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact || phone ? 8 : 10,
                vertical: compact || phone ? 6 : 8,
              ),
              child: Semantics(
                label: '$honesty. $scores'
                    '${conflicts > 0 ? '. $conflicts conflicts' : ''}',
                child: Row(
                  key: const ValueKey('room_status_strip'),
                  children: [
                    Flexible(
                      flex: 0,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: _chip(honesty, honestyColor, fs),
                      ),
                    ),
                    SizedBox(width: phone ? 6 : 8),
                    Expanded(
                      child: Text(
                        scores,
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            phone
                                ? '$conflicts'
                                : '$conflicts conflict${conflicts == 1 ? '' : 's'}',
                            key: const ValueKey('room_status_conflicts'),
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
            );
          },
        ),
      ),
    );
  }

  Widget _chip(String label, Color color, double fs) {
    return Container(
      key: const ValueKey('room_status_honesty_chip'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        maxLines: 1,
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
