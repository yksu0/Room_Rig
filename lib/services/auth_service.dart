import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_bootstrap.dart';

/// Email/password + Google auth. When Supabase is not configured, always guest.
class AuthService extends ChangeNotifier {
  AuthService() {
    _bind();
  }

  StreamSubscription<AuthState>? _sub;
  bool _passwordRecoveryPending = false;

  User? get user => SupabaseBootstrap.clientOrNull?.auth.currentUser;
  Session? get session => SupabaseBootstrap.clientOrNull?.auth.currentSession;
  bool get isSignedIn => user != null;
  bool get isGuest => !isSignedIn;
  String? get userId => user?.id;
  String? get email => user?.email;

  /// True after opening a reset-password email link until a new password is set.
  bool get passwordRecoveryPending => _passwordRecoveryPending;

  bool get hasGoogleIdentity =>
      user?.identities?.any((i) => i.provider == 'google') ?? false;

  bool get hasEmailIdentity =>
      user?.identities?.any((i) => i.provider == 'email') ?? false;

  /// Google-only accounts can still set a password via updateUser.
  bool get canSetPassword => isSignedIn;

  void _bind() {
    final client = SupabaseBootstrap.clientOrNull;
    if (client == null) return;
    _sub = client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        _passwordRecoveryPending = true;
      }
      notifyListeners();
    });
  }

  void clearPasswordRecoveryPending() {
    if (!_passwordRecoveryPending) return;
    _passwordRecoveryPending = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<String?> signUp({
    required String email,
    required String password,
  }) async {
    final client = SupabaseBootstrap.clientOrNull;
    if (client == null) return 'Cloud auth is not configured on this build.';
    try {
      // Mobile confirm links must deep-link back into the app (not Site URL / Chrome).
      await client.auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: _authRedirectTo,
      );
      notifyListeners();
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return '$e';
    }
  }

  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    final client = SupabaseBootstrap.clientOrNull;
    if (client == null) return 'Cloud auth is not configured on this build.';
    try {
      await client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      notifyListeners();
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return '$e';
    }
  }

  Future<void> signOut() async {
    final client = SupabaseBootstrap.clientOrNull;
    if (client == null) return;
    _passwordRecoveryPending = false;
    await client.auth.signOut();
    notifyListeners();
  }

  /// Deep link that must be allow-listed in Supabase Auth → URL Configuration.
  /// Android intent-filter: scheme `com.roomrig.room_rig`, host `login-callback`.
  static const mobileAuthRedirect = 'com.roomrig.room_rig://login-callback/';

  String? get _authRedirectTo =>
      kIsWeb ? Uri.base.origin : mobileAuthRedirect;

  /// Google OAuth (Supabase Free tier). Web uses HTTPS origin; Android uses deep link.
  Future<String?> signInWithGoogle() async {
    final client = SupabaseBootstrap.clientOrNull;
    if (client == null) return 'Cloud auth is not configured on this build.';
    try {
      final launched = await client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _authRedirectTo,
        // Custom Tabs / in-app browser returns to the app more reliably than
        // a full external Chrome tab (avoids “stay in browser” confusion).
        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.inAppBrowserView,
      );
      if (!launched) return 'Could not open Google sign-in.';
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return '$e';
    }
  }

  Future<String?> resetPassword(String email) async {
    final client = SupabaseBootstrap.clientOrNull;
    if (client == null) return 'Cloud auth is not configured on this build.';
    final trimmed = email.trim();
    if (trimmed.isEmpty) return 'Enter your email first.';
    try {
      await client.auth.resetPasswordForEmail(
        trimmed,
        redirectTo: _authRedirectTo,
      );
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return '$e';
    }
  }

  /// Sets or changes password (also completes recovery sessions).
  Future<String?> updatePassword(String password) async {
    final client = SupabaseBootstrap.clientOrNull;
    if (client == null) return 'Cloud auth is not configured on this build.';
    if (password.length < 8) {
      return 'Password must be at least 8 characters.';
    }
    try {
      await client.auth.updateUser(UserAttributes(password: password));
      _passwordRecoveryPending = false;
      notifyListeners();
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return '$e';
    }
  }

  /// Deletes the auth user (rooms/profiles cascade). Requires `delete-account` Edge Function.
  Future<String?> deleteAccount() async {
    final client = SupabaseBootstrap.clientOrNull;
    if (client == null) return 'Cloud auth is not configured on this build.';
    try {
      final res = await client.functions.invoke('delete-account');
      if (res.status >= 400) {
        final msg = res.data is Map && (res.data as Map)['error'] != null
            ? '${(res.data as Map)['error']}'
            : 'Could not delete account (${res.status}).';
        return msg;
      }
      _passwordRecoveryPending = false;
      await client.auth.signOut();
      notifyListeners();
      return null;
    } catch (e) {
      return '$e';
    }
  }
}
