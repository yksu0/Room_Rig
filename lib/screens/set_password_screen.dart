import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/clear_auth_url.dart';
import '../utils/password_manager_save.dart';
import '../utils/password_strength.dart';
import '../widgets/password_form_fields.dart';

enum SetPasswordMode { recovery, change, setForGoogle }

/// Collect a new password after recovery, or from Account → Change / Set password.
class SetPasswordScreen extends StatefulWidget {
  const SetPasswordScreen({
    super.key,
    this.mode = SetPasswordMode.change,
  });

  final SetPasswordMode mode;

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String get _title => switch (widget.mode) {
        SetPasswordMode.recovery => 'Choose a new password',
        SetPasswordMode.setForGoogle => 'Set a password',
        SetPasswordMode.change => 'Change password',
      };

  String get _subtitle => switch (widget.mode) {
        SetPasswordMode.recovery =>
          'Your reset link worked. Enter a new password to finish — you stay signed in after this.',
        SetPasswordMode.setForGoogle =>
          'You signed in with Google. Add a password so you can also sign in with email, or recover access without Google.',
        SetPasswordMode.change =>
          'Pick a new password for this account. Give it a moment after saving before closing the app.',
      };

  Future<void> _submit(AuthService auth) async {
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    if (PasswordStrength.score(_password.text) < 2) {
      setState(() => _error = 'Choose a stronger password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await auth.updatePassword(_password.text);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }

    final email = auth.email;
    var savedToManager = false;
    if (email != null &&
        (widget.mode == SetPasswordMode.setForGoogle || auth.hasGoogleIdentity)) {
      savedToManager = await trySavePasswordToManager(
        email: email,
        password: _password.text,
      );
    }

    if (!mounted) return;
    if (widget.mode == SetPasswordMode.recovery) {
      clearAuthUrlResidue();
    }
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          savedToManager
              ? 'Password saved. Your browser may offer to store it.'
              : 'Password updated.',
        ),
      ),
    );
    Navigator.of(context).maybePop(true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final canPop = widget.mode != SetPasswordMode.recovery;

    return PopScope(
      canPop: canPop,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          title: Text(_title),
          automaticallyImplyLeading: canPop,
        ),
        body: AutofillGroup(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                _subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              if (auth.email != null) ...[
                const SizedBox(height: 12),
                Text(
                  auth.email!,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              PasswordFormFields(
                password: _password,
                confirm: _confirm,
                enabled: !_busy,
                onChanged: () => setState(() => _error = null),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.amber, fontSize: 13),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : () => _submit(auth),
                child: Text(_busy ? 'Saving…' : 'Save password'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
