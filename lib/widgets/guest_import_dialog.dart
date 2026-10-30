// lib/widgets/guest_import_dialog.dart
// Copy + dialog for the post-sign-in "Keep this device's room(s)?" prompt.
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Title for the guest-import keep/discard dialog.
String guestImportDialogTitle(int roomCount) {
  return roomCount == 1
      ? "Keep this device's room?"
      : "Keep this device's rooms?";
}

/// Body copy — singular when [roomCount] is 1.
String guestImportDialogBody(int roomCount) {
  if (roomCount == 1) {
    return 'A room made on this device as a guest is still here. '
        'Add it to your account, or discard it from this phone.';
  }
  return '$roomCount rooms made on this device as a guest are still here. '
      'Add them to your account, or discard them from this phone.';
}

/// Barrier-dismissible: false keep/discard dialog.
Widget buildGuestImportDialog({
  required BuildContext context,
  required int roomCount,
  required VoidCallback onDiscard,
  required VoidCallback onKeep,
}) {
  return AlertDialog(
    backgroundColor: AppColors.surface,
    title: Text(
      guestImportDialogTitle(roomCount),
      style: const TextStyle(color: AppColors.textPrimary),
    ),
    content: Text(
      guestImportDialogBody(roomCount),
      style: const TextStyle(color: AppColors.textSecondary),
    ),
    actions: [
      TextButton(
        onPressed: onDiscard,
        child: const Text('Discard'),
      ),
      FilledButton(
        onPressed: onKeep,
        child: const Text('Add to account'),
      ),
    ],
  );
}
