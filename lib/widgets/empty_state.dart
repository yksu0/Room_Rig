// lib/widgets/empty_state.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'room_icons.dart';

class EmptyState extends StatelessWidget {
  final String iconSvg;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color accent;

  const EmptyState({
    super.key,
    required this.iconSvg,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.accent = AppColors.cyan,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: accent.withValues(alpha: 0.35)),
            ),
            child: Center(child: SvgIcon(iconSvg, size: 30, color: accent)),
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppType.title(context).copyWith(fontSize: 18),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppType.body(context),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpace.lg),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: accent.withValues(alpha: 0.18),
                foregroundColor: accent,
                side: BorderSide(color: accent.withValues(alpha: 0.45)),
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class ErrorStateCard extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const ErrorStateCard({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 22),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppType.bodyStrong(context).copyWith(fontSize: 13),
                ),
                const SizedBox(height: AppSpace.xxs),
                Text(message, style: AppType.caption(context)),
                if (onRetry != null) ...[
                  const SizedBox(height: AppSpace.sm),
                  TextButton(
                    onPressed: onRetry,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.red,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Try again'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
