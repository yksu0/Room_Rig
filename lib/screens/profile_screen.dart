import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/profile_avatar.dart';
import 'auth_screen.dart';
import 'set_password_screen.dart';

/// Profile page (Hub top-right).
///
/// Signed in: avatar + display name (editable), sign-in methods, security,
/// OTP-confirmed delete (7-day soft delete), sign out.
/// Signed out: Sign in / Sign up CTAs.
///
/// Layout intentionally leaves a section slot under the identity block for
/// ratings / published layouts when the Benchmark social layer ships.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  var _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthService>();
      if (auth.isSignedIn && context.read<ProfileService>().profile == null) {
        context.read<ProfileService>().load();
      }
    });
  }

  Future<void> _openAuth({required bool signUp}) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AuthScreen(initialSignUp: signUp)),
    );
  }

  Future<void> _changeOrSetPassword(AuthService auth) async {
    final mode = auth.hasGoogleIdentity && !auth.hasEmailIdentity
        ? SetPasswordMode.setForGoogle
        : SetPasswordMode.change;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SetPasswordScreen(mode: mode)),
    );
  }

  Future<void> _editName(ProfileService profiles) async {
    final ctrl = TextEditingController(
      text: profiles.hasDisplayName ? profiles.displayLabel : '',
    );
    String? error;
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Display name',
              style: TextStyle(color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLength: 32,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Name',
                  labelStyle: TextStyle(color: AppColors.textMuted),
                  counterStyle: TextStyle(color: AppColors.textMuted),
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v),
              ),
              if (error != null)
                Text(error!,
                    style:
                        const TextStyle(color: AppColors.amber, fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (ctrl.text.trim().length < 2) {
                  setLocal(() => error = 'At least 2 characters.');
                  return;
                }
                Navigator.pop(ctx, ctrl.text);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (saved == null || !mounted) return;
    setState(() => _busy = true);
    final err = await profiles.updateDisplayName(saved);
    if (!mounted) return;
    setState(() => _busy = false);
    showAppSnackBar(context, message: err ?? 'Name updated.');
  }

  Future<void> _changePhoto(ProfileService profiles) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.cyan),
              title: const Text('Choose from gallery',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_camera_outlined, color: AppColors.cyan),
              title: const Text('Take a photo',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, message: 'Could not open picker: $e');
      return;
    }
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    final bytes = await picked.readAsBytes();
    final name = picked.name;
    final ext = name.contains('.') ? name.split('.').last : 'jpg';
    final err = await profiles.uploadAvatar(bytes, extension: ext);
    if (!mounted) return;
    setState(() => _busy = false);
    showAppSnackBar(context, message: err ?? 'Photo updated.');
  }

  Future<void> _deleteAccount(AuthService auth, ProfileService profiles) async {
    // Step 0: phone must reach Room Rig cloud (Wi‑Fi / mobile data) so we can
    // email the OTP and set the soft-delete flag. Not a website login.
    setState(() => _busy = true);
    final reachErr = await profiles.cloudReachabilityError();
    if (!mounted) return;
    setState(() => _busy = false);
    if (reachErr != null) {
      showAppSnackBar(
        context,
        message: 'Delete needs an internet connection to Room Rig\'s servers '
            '(not a website). $reachErr',
        duration: const Duration(seconds: 5),
      );
      return;
    }

    // Step 1: explain + send code.
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete account?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'We will email a 6-digit code to ${auth.email ?? 'your address'} to confirm it is you. '
          'After you enter it, your account and synced rooms are scheduled for permanent '
          'deletion in ${ProfileService.deletionGraceDays} days and you are signed out. '
          'Signing in again before then cancels the deletion.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Send code'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    setState(() => _busy = true);
    final sendErr = await profiles.sendDeleteConfirmationCode();
    if (!mounted) return;
    setState(() => _busy = false);
    if (sendErr != null) {
      showAppSnackBar(context, message: sendErr);
      return;
    }

    // Step 2: enter code.
    final code = await _promptForCode(auth.email ?? '');
    if (code == null || !mounted) return;

    setState(() => _busy = true);
    final confirmErr = await profiles.confirmDeleteWithCode(code);
    if (!mounted) return;
    if (confirmErr != null) {
      setState(() => _busy = false);
      showAppSnackBar(context, message: confirmErr);
      return;
    }

    // Step 3: route like a normal sign-out (flush first, wipe device copy).
    var synced = false;
    try {
      synced = await context.read<AppState>().flushRoomsToCloud();
      if (!mounted) return;
      await auth.signOut();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    showAppSnackBar(
      context,
      message: synced
          ? 'Deletion scheduled. Your account is removed in ${ProfileService.deletionGraceDays} days — '
              'sign in before then to cancel.'
          : 'Deletion scheduled (rooms could not sync). Sign in within '
              '${ProfileService.deletionGraceDays} days to cancel.',
      duration: const Duration(seconds: 5),
    );
  }

  Future<String?> _promptForCode(String email) async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Enter the code',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'We sent a 6-digit code to $email. It expires in a few minutes.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                letterSpacing: 6,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                counterText: '',
                hintText: '000000',
                hintStyle: TextStyle(color: AppColors.textMuted, letterSpacing: 6),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Confirm delete'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return code == null || code.trim().isEmpty ? null : code;
  }

  Future<void> _signOut(AuthService auth) async {
    setState(() => _busy = true);
    var synced = false;
    try {
      // Upload before session ends — sign-out wipes the device copy.
      synced = await context.read<AppState>().flushRoomsToCloud();
      if (!mounted) return;
      await auth.signOut();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
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
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('Profile'),
      ),
      body: auth.isSignedIn ? _signedIn(context, auth) : _signedOut(context),
    );
  }

  // ---------------------------------------------------------------------------
  // Signed out
  // ---------------------------------------------------------------------------
  Widget _signedOut(BuildContext context) {
    final rooms = context.watch<AppState>().savedRooms.length;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 12),
        const Center(child: ProfileAvatar(size: 96)),
        const SizedBox(height: 16),
        const Center(
          child: Text(
            'Guest',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            rooms <= 1
                ? 'One room, saved on this device only.'
                : '$rooms rooms, saved on this device only.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () => _openAuth(signUp: true),
          child: const Text('Sign up — free'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => _openAuth(signUp: false),
          child: const Text('Sign in'),
        ),
        const SizedBox(height: 20),
        const Text(
          'An account keeps your rooms synced, lets you add more than one room, '
          'and brings your current room with you.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Signed in
  // ---------------------------------------------------------------------------
  Widget _signedIn(BuildContext context, AuthService auth) {
    final profiles = context.watch<ProfileService>();
    final email = auth.email ?? 'Signed in';
    final providers = <String>[
      if (auth.hasGoogleIdentity) 'Google',
      if (auth.hasEmailIdentity) 'Email',
      if (!auth.hasGoogleIdentity && !auth.hasEmailIdentity) 'Account',
    ];
    final pendingDelete = profiles.profile?.deletionRequestedAt;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Identity block
        Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ProfileAvatar(
                size: 104,
                imageUrl: profiles.avatarUrl,
                // Initial only when they set an app name — never Google.
                label: profiles.hasDisplayName ? profiles.displayLabel : null,
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Material(
                  color: AppColors.cyan,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _busy ? null : () => _changePhoto(profiles),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.photo_camera_rounded,
                          size: 18, color: AppColors.bg),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _busy ? null : () => _editName(profiles),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      profiles.displayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: profiles.hasDisplayName
                            ? AppColors.textPrimary
                            : AppColors.textMuted,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.edit_outlined,
                      size: 16, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Center(
          child: Text(
            email,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
        const SizedBox(height: 2),
        Center(
          child: Text(
            'Sign-in: ${providers.join(' · ')}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ),
        if (profiles.loading) ...[
          const SizedBox(height: 10),
          const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ],
        if (pendingDelete != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.amber.withValues(alpha: 0.5)),
            ),
            child: const Text(
              'A deletion was requested for this account. Signing in cancelled it — '
              'you are safe. Delete again below if you still want to leave.',
              style: TextStyle(color: AppColors.amber, fontSize: 12, height: 1.4),
            ),
          ),
        ],

        // Reserved slot: ratings / published layouts land here later.
        const SizedBox(height: 28),

        const _SectionLabel('SYNC'),
        const SizedBox(height: 8),
        const Text(
          'Rooms sync to your account when signed in. '
          'Give it a moment after a big change before closing the app. '
          'Signing out uploads your rooms one final time, then removes them from this device — '
          'they stay in your account online so the next sign-in can restore them.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 28),
        const _SectionLabel('SECURITY'),
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
          title: const Text('Delete account',
              style: TextStyle(color: AppColors.red)),
          subtitle: const Text(
            'Needs internet to Room Rig cloud. Email code required; account and synced rooms are removed after a 7-day grace period.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          onTap: _busy ? null : () => _deleteAccount(auth, profiles),
        ),
        const SizedBox(height: 28),
        OutlinedButton(
          onPressed: _busy ? null : () => _signOut(auth),
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.cyan,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 2,
      ),
    );
  }
}
