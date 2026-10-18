import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/supabase_bootstrap.dart';
import '../theme/app_theme.dart';

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
  var _signUp = false;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit(AuthService auth) async {
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
                : 'Cloud auth is not configured on this build. You can keep using guest mode.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
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
          TextField(
            controller: _password,
            obscureText: true,
            enabled: cloud && !_busy,
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
