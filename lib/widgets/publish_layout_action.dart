import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'guest_signup_gate.dart';

/// Publish the active Room layout to Benchmark Community.
///
/// Runs guest + Profile-complete gates, then a title dialog.
/// Returns true when a row was inserted.
Future<bool> publishCurrentLayoutToCommunity(BuildContext context) async {
  if (!await ensureProfileCompleteForPublish(context)) return false;
  if (!context.mounted) return false;

  final titleCtrl = TextEditingController(
    text: context.read<AppState>().currentRoomData.name,
  );
  final title = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text(
        'Publish layout',
        style: TextStyle(color: AppColors.textPrimary),
      ),
      content: TextField(
        controller: titleCtrl,
        autofocus: true,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: const InputDecoration(
          labelText: 'Title',
          hintText: 'My gaming setup',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, titleCtrl.text.trim()),
          child: const Text('Publish'),
        ),
      ],
    ),
  );
  titleCtrl.dispose();
  if (title == null || title.isEmpty || !context.mounted) return false;

  final uid = context.read<AuthService>().userId;
  if (uid == null) return false;

  try {
    await context.read<AppState>().publishCurrentRoom(
          authorId: uid,
          title: title,
        );
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Published to Community')),
    );
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Publish failed: $e')),
    );
    return false;
  }
}
