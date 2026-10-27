// lib/widgets/benchmark_validation_card.dart
import 'package:flutter/material.dart';
import '../services/benchmark_validator.dart';
import '../theme/app_theme.dart';
import 'glass_card.dart';

/// Verdict derived from the checks themselves, so the badge can never disagree
/// with the rows underneath it.
enum BenchmarkVerdict { pass, needsWork, fail }

extension BenchmarkValidationVerdict on BenchmarkValidation {
  BenchmarkVerdict get verdict {
    if (failCount > 0) return BenchmarkVerdict.fail;
    if (checks.every((c) => c.status == BenchmarkCheckStatus.pass)) return BenchmarkVerdict.pass;
    return BenchmarkVerdict.needsWork;
  }
}

/// Shared PASS / NEEDS WORK / FAIL pill used by every benchmark results header.
class BenchmarkResultBadge extends StatelessWidget {
  final BenchmarkValidation validation;

  const BenchmarkResultBadge({super.key, required this.validation});

  static Color colorFor(BenchmarkVerdict v) => switch (v) {
        BenchmarkVerdict.pass => AppColors.green,
        BenchmarkVerdict.needsWork => AppColors.amber,
        BenchmarkVerdict.fail => AppColors.red,
      };

  static String labelFor(BenchmarkVerdict v) => switch (v) {
        BenchmarkVerdict.pass => 'PASS',
        BenchmarkVerdict.needsWork => 'NEEDS WORK',
        BenchmarkVerdict.fail => 'FAIL',
      };

  @override
  Widget build(BuildContext context) {
    final verdict = validation.verdict;
    final color = colorFor(verdict);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        labelFor(verdict),
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}

class BenchmarkValidationCard extends StatelessWidget {
  final BenchmarkValidation validation;

  const BenchmarkValidationCard({super.key, required this.validation});

  @override
  Widget build(BuildContext context) {
    final verdict = validation.verdict;
    final badgeColor = BenchmarkResultBadge.colorFor(verdict);
    return GlassCard(
      borderColor: badgeColor.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                verdict == BenchmarkVerdict.pass ? Icons.verified_rounded : Icons.rule_rounded,
                color: badgeColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Layout geometry checks',
                  style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
              BenchmarkResultBadge(validation: validation),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${validation.passCount}/${validation.checks.length} checks passed · score ${validation.score.toStringAsFixed(0)}',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ...validation.checks.map((c) => _CheckRow(check: c)),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final BenchmarkCheck check;
  const _CheckRow({required this.check});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (check.status) {
      BenchmarkCheckStatus.pass => (AppColors.green, Icons.check_circle_outline),
      BenchmarkCheckStatus.warn => (AppColors.amber, Icons.warning_amber_rounded),
      BenchmarkCheckStatus.fail => (AppColors.red, Icons.cancel_outlined),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  check.label,
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  check.detail,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Text(
            check.value.toStringAsFixed(0),
            style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
