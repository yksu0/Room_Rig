import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared floating snackbars that dismiss quickly and never trap the tab bar.
///
/// Prefer this over raw [ScaffoldMessenger.showSnackBar] for app-wide notices.
void showAppSnackBar(
  BuildContext context, {
  required String message,
  Duration duration = const Duration(seconds: 3),
  SnackBarAction? action,
  Color? backgroundColor,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        action: action,
        backgroundColor: backgroundColor ?? AppColors.cardElevated,
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.horizontal,
        showCloseIcon: action == null,
        closeIconColor: AppColors.textMuted,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      ),
    );
}

/// Clears a stuck banner so bottom / side nav stays tappable.
void clearAppSnackBars(BuildContext context) {
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
}
