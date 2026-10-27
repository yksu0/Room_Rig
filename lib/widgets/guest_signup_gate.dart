import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../screens/auth_screen.dart';
import '../screens/profile_screen.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
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

/// Publish / rate / clone / Compare / Apply need a signed-in account.
Future<bool> ensureSignedInForCommunity(
  BuildContext context, {
  required String actionLabel,
}) async {
  if (context.read<AuthService>().isSignedIn) return true;
  return showGuestSignupGate(
    context,
    title: 'Sign in to $actionLabel',
    body: 'You can browse Community layouts as a guest. '
        'Sign in to $actionLabel, keep rooms synced, and build your Profile.',
  );
}

/// Publish / rate also need display name + avatar on Profile.
Future<bool> ensureProfileCompleteForPublish(BuildContext context) async {
  if (!await ensureSignedInForCommunity(context, actionLabel: 'continue')) {
    return false;
  }
  if (!context.mounted) return false;
  final profile = context.read<ProfileService>();
  if (profile.canPublishOrRate) return true;

  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text(
        'Complete your Profile',
        style: TextStyle(color: AppColors.textPrimary),
      ),
      content: const Text(
        'Publishing and rating need a display name and avatar. '
        'Set them on Profile, then come back here.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Open Profile'),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return false;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const ProfileScreen()),
  );
  if (!context.mounted) return false;
  await context.read<ProfileService>().load();
  if (!context.mounted) return false;
  return context.read<ProfileService>().canPublishOrRate;
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
