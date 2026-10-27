import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../screens/auth_screen.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Hard block for guests who already own their one room.
///
/// Returns true when the caller may proceed (signed in, or guest still under
/// the limit). Otherwise shows the sign-up popup and returns false; if the user
/// signs up from the popup and comes back signed in, returns true.
Future<bool> ensureCanCreateRoom(BuildContext context) async {
  final state = context.read<AppState>();
  if (state.canCreateAnotherRoom) return true;
  final signedIn = await showGuestSignupGate(
    context,
    title: 'Create a free account to add more rooms',
    body: 'Guests can set up and edit one room on this device. '
        'Sign up to add more rooms and keep them synced to your account — '
        'your current room comes with you.',
  );
  if (!context.mounted) return false;
  return signedIn && context.read<AppState>().canCreateAnotherRoom;
}

/// Shows the signup popup. Returns true if the user is signed in afterwards.
Future<bool> showGuestSignupGate(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  final choice = await showDialog<_GateChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(title, style: const TextStyle(color: AppColors.textPrimary)),
      content: Text(body, style: const TextStyle(color: AppColors.textSecondary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, _GateChoice.notNow),
          child: const Text('Not now'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, _GateChoice.signIn),
          child: const Text('Sign in'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, _GateChoice.signUp),
          child: const Text('Sign up'),
        ),
      ],
    ),
  );
  if (choice == null || choice == _GateChoice.notNow || !context.mounted) {
    return false;
  }
  await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => AuthScreen(
        initialSignUp: choice == _GateChoice.signUp,
        reason: 'Guest limit: one room per device. Sign in to add more.',
      ),
    ),
  );
  if (!context.mounted) return false;
  return context.read<AuthService>().isSignedIn;
}

enum _GateChoice { notNow, signIn, signUp }
