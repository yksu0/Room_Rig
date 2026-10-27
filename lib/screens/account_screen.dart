import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_snack_bar.dart';
import 'set_password_screen.dart';

/// Signed-in profile: password, delete account, sign out.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  var _busy = false;

  Future<void> _changeOrSetPassword(AuthService auth) async {
    final mode = auth.hasGoogleIdentity && !auth.hasEmailIdentity
        ? SetPasswordMode.setForGoogle
        : SetPasswordMode.change;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SetPasswordScreen(mode: mode)),
    );
  }

  Future<void> _deleteAccount(AuthService auth) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Delete account?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'This permanently deletes your Room Rig account and synced rooms. '
          'This cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _busy = true);
    final err = await auth.deleteAccount();
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      showAppSnackBar(context, message: err);
      return;
    }
    Navigator.of(context).popUntil((r) => r.isFirst);
    showAppSnackBar(context, message: 'Account deleted.');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final email = auth.email ?? 'Signed in';
    final providers = <String>[
      if (auth.hasGoogleIdentity) 'Google',
      if (auth.hasEmailIdentity) 'Email',
      if (!auth.hasGoogleIdentity && !auth.hasEmailIdentity) 'Account',
    ];

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('Account'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'PROFILE',
            style: TextStyle(
              color: AppColors.cyan,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            email,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Sign-in: ${providers.join(' · ')}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          const Text(
            'Rooms sync to your account when signed in. '
            'Give it a moment after a big change before closing the app. '
            'Signing out removes rooms from this device; they stay in your account online.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 28),
          const Text(
            'SECURITY',
            style: TextStyle(
              color: AppColors.cyan,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_outline, color: AppColors.cyan),
            title: Text(
              auth.hasGoogleIdentity && !auth.hasEmailIdentity
                  ? 'Set a password'
                  : 'Change password',
              style: const TextStyle(color: AppColors.textPrimary),
            ),
            subtitle: Text(
              auth.hasGoogleIdentity && !auth.hasEmailIdentity
                  ? 'Optional — also sign in with email, or recover without Google'
                  : 'Update the password for this account',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
            onTap: _busy ? null : () => _changeOrSetPassword(auth),
          ),
          const Divider(color: AppColors.border),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.phonelink_lock, color: AppColors.cyan),
            title: const Text(
              'Sign out after 15 minutes unused (shared phone)',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
            ),
            subtitle: const Text(
              'Off by default. Turn on only if others may use this device.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            value: context.watch<AppState>().sharedPhoneLock,
            activeThumbColor: AppColors.cyan,
            onChanged: _busy
                ? null
                : (v) => context.read<AppState>().setSharedPhoneLock(v),
          ),
          const Divider(color: AppColors.border),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline, color: AppColors.red),
            title: const Text(
              'Delete account',
              style: TextStyle(color: AppColors.red),
            ),
            subtitle: const Text(
              'Permanently remove your account and synced rooms',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            onTap: _busy ? null : () => _deleteAccount(auth),
          ),
          const SizedBox(height: 28),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    var synced = false;
                    try {
                      // Upload before session ends — sign-out wipes the device copy.
                      synced =
                          await context.read<AppState>().flushRoomsToCloud();
                      if (!context.mounted) return;
                      await auth.signOut();
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                    if (!context.mounted) return;
                    Navigator.of(context).popUntil((r) => r.isFirst);
                    showAppSnackBar(
                      context,
                      message: synced
                          ? 'Signed out. Rooms left this device but stay in your account. '
                              'Shared photos or files are not removed from the phone; '
                              'delete those yourself if needed.'
                          : 'Signed out. Cloud sync failed — rooms may not restore on '
                              'the next sign-in. Check network and try again while signed in.',
                      duration: const Duration(seconds: 4),
                    );
                  },
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
