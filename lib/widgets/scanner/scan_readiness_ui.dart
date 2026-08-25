import 'package:flutter/material.dart';
import '../../models/scan_layout_model.dart';
import '../../services/scan_guidance.dart';
import '../../services/scan_pipeline.dart';
import '../../theme/app_theme.dart';

class ReadinessMetricRow extends StatelessWidget {
  final String label;
  final double value;
  final double target;
  final Color color;

  const ReadinessMetricRow({
    super.key,
    required this.label,
    required this.value,
    required this.target,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = value.clamp(0.0, 1.0);
    final reached = ratio >= target;

    return Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 5,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(
                reached ? color : color.withValues(alpha: 0.55),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${(ratio * 100).toInt()}%',
          style: TextStyle(
            color: reached ? color : AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class ScanReadinessMeter extends StatelessWidget {
  final double coverageRatio;
  final double qualityRatio;
  final double stabilityRatio;
  final List<String> hints;
  final bool showHints;
  final double requiredCoverageToFinish;
  final double qualityEnterThreshold;
  final VoidCallback onToggleHints;

  const ScanReadinessMeter({
    super.key,
    required this.coverageRatio,
    required this.qualityRatio,
    required this.stabilityRatio,
    required this.hints,
    required this.showHints,
    required this.requiredCoverageToFinish,
    required this.qualityEnterThreshold,
    required this.onToggleHints,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'READINESS DETAILS',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onToggleHints,
                child: Row(
                  children: [
                    Text(
                      showHints ? 'Hide Tips' : 'Show Tips',
                      style: TextStyle(
                        color: AppColors.cyan,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      showHints ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 16,
                      color: AppColors.cyan,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ReadinessMetricRow(
            label: 'Coverage',
            value: coverageRatio,
            target: requiredCoverageToFinish,
            color: AppColors.cyan,
          ),
          const SizedBox(height: 6),
          ReadinessMetricRow(
            label: 'Quality',
            value: qualityRatio,
            target: qualityEnterThreshold,
            color: AppColors.green,
          ),
          const SizedBox(height: 6),
          ReadinessMetricRow(
            label: 'Stability',
            value: stabilityRatio,
            target: 1.0,
            color: AppColors.amber,
          ),
          if (showHints && hints.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...hints.map(
              (hint) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.tips_and_updates_outlined, size: 12, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        hint,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ScanCornerChecklist extends StatelessWidget {
  final CoverageGrid grid;

  const ScanCornerChecklist({super.key, required this.grid});

  @override
  Widget build(BuildContext context) {
    final corners = ScanGuidance.cornerChecklist(grid);
    final done = corners.where((c) => c.done).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'CORNERS',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const Spacer(),
              Text(
                '$done/4',
                style: TextStyle(
                  color: done == 4 ? AppColors.green : AppColors.cyan,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: corners
                .map(
                  (c) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: c.done
                              ? AppColors.green.withValues(alpha: 0.16)
                              : AppColors.card,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: c.done
                                ? AppColors.green.withValues(alpha: 0.55)
                                : AppColors.border,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              c.done ? Icons.check_rounded : Icons.crop_square_rounded,
                              size: 12,
                              color: c.done ? AppColors.green : AppColors.textMuted,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              c.label,
                              style: TextStyle(
                                color: c.done ? AppColors.green : AppColors.textSecondary,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

List<String> buildReadinessHints({
  required bool canFinishScan,
  required double coverageRatio,
  required double qualityRatio,
  required double stabilityRatio,
  required double requiredCoverageToFinish,
  required double qualityEnterThreshold,
  required int requiredStableQualityFrames,
  required int stableQualityFrames,
  required List<ScanQualityIssue> latestQualityIssues,
}) {
  if (canFinishScan) {
    return const ['All conditions met. Tap Finish Scan to continue.'];
  }

  final hints = <String>[];

  if (coverageRatio < requiredCoverageToFinish) {
    final needPct = ((requiredCoverageToFinish - coverageRatio).clamp(0.0, 1.0) * 100).toInt();
    hints.add('Cover more floor area: scan roughly $needPct% more of the room.');
  }

  if (qualityRatio < qualityEnterThreshold) {
    if (latestQualityIssues.contains(ScanQualityIssue.trackingLost)) {
      hints.add('Tracking unstable: move slower and keep the camera pointed at fixed room features.');
    } else if (latestQualityIssues.contains(ScanQualityIssue.motionBlur)) {
      hints.add('Motion blur detected: reduce camera speed and avoid quick turns.');
    } else if (latestQualityIssues.contains(ScanQualityIssue.poorLighting)) {
      hints.add('Low light detected: increase lighting or face brighter sections of the room.');
    } else if (latestQualityIssues.contains(ScanQualityIssue.lowTexture)) {
      hints.add('Low texture view: include edges, corners, and objects with detail.');
    } else {
      hints.add('Quality below threshold: hold the camera steady for a few seconds.');
    }
  }

  if (stabilityRatio < 1) {
    final missingFrames = (requiredStableQualityFrames - stableQualityFrames)
        .clamp(0, requiredStableQualityFrames);
    hints.add('Maintain good quality for $missingFrames more stable frames.');
  }

  return hints;
}
