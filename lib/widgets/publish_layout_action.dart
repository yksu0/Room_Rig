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

  final initial = context.read<AppState>().currentRoomData.name;
  final title = await showDialog<String>(
    context: context,
    builder: (ctx) => _PublishTitleDialog(initial: initial),
  );
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

/// Owns the title [TextEditingController] for the full dialog lifetime.
class _PublishTitleDialog extends StatefulWidget {
  final String initial;
  const _PublishTitleDialog({required this.initial});

  @override
  State<_PublishTitleDialog> createState() => _PublishTitleDialogState();
}

class _PublishTitleDialogState extends State<_PublishTitleDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _ctrl.text.trim();
    if (trimmed.isEmpty) return;
    Navigator.pop(context, trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text(
        'Publish layout',
        style: TextStyle(color: AppColors.textPrimary),
      ),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: const InputDecoration(
          labelText: 'Title',
          hintText: 'My gaming setup',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Publish'),
        ),
      ],
    );
  }
}
