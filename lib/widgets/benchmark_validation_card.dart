// lib/widgets/benchmark_validation_card.dart
import 'package:flutter/material.dart';
import '../services/benchmark_validator.dart';
import '../theme/app_theme.dart';
import 'glass_card.dart';

class BenchmarkValidationCard extends StatelessWidget {
  final BenchmarkValidation validation;

  const BenchmarkValidationCard({super.key, required this.validation});

  @override
  Widget build(BuildContext context) {
    final badgeColor = validation.passed ? AppColors.green : AppColors.amber;
    return GlassCard(
      borderColor: badgeColor.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                validation.passed ? Icons.verified_rounded : Icons.rule_rounded,
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  validation.passed ? 'PASS' : 'NEEDS WORK',
                  style: TextStyle(color: badgeColor, fontWeight: FontWeight.w800, fontSize: 11),
                ),
              ),
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
  final BenchCheck check;
  const _CheckRow({required this.check});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (check.status) {
      BenchCheckStatus.pass => (AppColors.green, Icons.check_circle_outline),
      BenchCheckStatus.warn => (AppColors.amber, Icons.warning_amber_rounded),
      BenchCheckStatus.fail => (AppColors.red, Icons.cancel_outlined),
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
