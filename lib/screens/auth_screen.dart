import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/supabase_bootstrap.dart';
import '../theme/app_theme.dart';
import '../utils/password_strength.dart';
import '../widgets/password_form_fields.dart';

/// Email/password sign-in. Guest continues without an account.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.onContinueAsGuest});

  final VoidCallback? onContinueAsGuest;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  var _signUp = false;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit(AuthService auth) async {
    if (_signUp) {
      if (_password.text != _confirm.text) {
        setState(() => _error = 'Passwords do not match.');
        return;
      }
      if (PasswordStrength.score(_password.text) < 2) {
        setState(() => _error = 'Choose a stronger password.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = _signUp
        ? await auth.signUp(email: _email.text, password: _password.text)
        : await auth.signIn(email: _email.text, password: _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null && mounted) {
      Navigator.of(context).maybePop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final cloud = SupabaseBootstrap.isReady;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(_signUp ? 'Create account' : 'Sign in'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            cloud
                ? 'Save rooms to your account. Guests stay on this device only.'
                : 'Cloud auth is not configured on this build (add supabase.local.json). Guest mode still works; Google needs cloud keys.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    if (!cloud) {
                      setState(() {
                        _error =
                            'Cloud auth is not configured. Add SUPABASE_URL + SUPABASE_ANON_KEY (see supabase/README.md), enable Google in the dashboard, then restart.';
                      });
                      return;
                    }
                    setState(() {
                      _busy = true;
                      _error = null;
                    });
                    final err = await auth.signInWithGoogle();
                    if (!mounted) return;
                    setState(() {
                      _busy = false;
                      _error = err;
                    });
                    if (err == null && auth.isSignedIn) {
                      if (!mounted) return;
                      Navigator.of(context).maybePop(true);
                    }
                  },
            icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
            label: const Text('Continue with Google'),
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Expanded(child: Divider(color: AppColors.border)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'or email',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),
              Expanded(child: Divider(color: AppColors.border)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enabled: cloud && !_busy,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Email',
              labelStyle: TextStyle(color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: 12),
          if (_signUp)
            PasswordFormFields(
              password: _password,
              confirm: _confirm,
              enabled: cloud && !_busy,
              onChanged: () => setState(() => _error = null),
            )
          else
            TextField(
              controller: _password,
              obscureText: true,
              enabled: cloud && !_busy,
              autofillHints: const [AutofillHints.password],
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Password',
                labelStyle: TextStyle(color: AppColors.textMuted),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.amber, fontSize: 13)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: (!cloud || _busy) ? null : () => _submit(auth),
            child: Text(_busy ? 'Please wait…' : (_signUp ? 'Sign up' : 'Sign in')),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _signUp = !_signUp;
                      _error = null;
                    }),
            child: Text(
              _signUp ? 'Have an account? Sign in' : 'Need an account? Sign up',
            ),
          ),
          if (!_signUp && cloud)
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      final err = await auth.resetPassword(_email.text);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            err ?? 'Password reset email sent (if the account exists).',
                          ),
                        ),
                      );
                    },
              child: const Text('Forgot password'),
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              widget.onContinueAsGuest?.call();
              Navigator.of(context).maybePop(false);
            },
            child: const Text('Continue as guest'),
          ),
        ],
      ),
    );
  }
}
