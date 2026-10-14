import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared confirm dialogs for destructive / overwrite actions.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String body,
  String cancelLabel = 'Cancel',
  String confirmLabel = 'Continue',
  bool danger = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpace.xl, vertical: AppSpace.xl),
      titlePadding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.sm),
      contentPadding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.md),
      actionsPadding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
      title: Text(title, style: AppType.title(ctx).copyWith(fontSize: 18)),
      content: Text(body, style: AppType.body(ctx)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            confirmLabel,
            style: TextStyle(
              color: danger ? AppColors.red : AppColors.cyan,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
  return ok == true;
}
