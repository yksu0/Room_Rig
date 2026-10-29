import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import 'supabase_bootstrap.dart';

/// Email/password + Google auth. When Supabase is not configured, always guest.
class AuthService extends ChangeNotifier {
  AuthService() {
    _bind();
  }

  StreamSubscription<AuthState>? _sub;
  bool _passwordRecoveryPending = false;
  bool _googleNativeReady = false;

  /// True after an explicit Sign out / Delete account — wipe device immediately.
  /// Transient auth blips (token refresh) leave this false so My Rooms survive.
  bool _intentionalSignOut = false;

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

  /// Whether the next signed-out transition should wipe the device right away.
  bool consumeIntentionalSignOut() {
    final v = _intentionalSignOut;
    _intentionalSignOut = false;
    return v;
  }

  Future<void> signOut() async {
    final client = SupabaseBootstrap.clientOrNull;
    if (client == null) return;
    _passwordRecoveryPending = false;
    _intentionalSignOut = true;
    try {
      if (!kIsWeb && SupabaseConfig.hasGoogleWebClientId) {
        await GoogleSignIn.instance.signOut();
      }
    } catch (_) {}
    await client.auth.signOut();
    notifyListeners();
  }

  /// Deep link that must be allow-listed in Supabase Auth → URL Configuration.
  /// Used for email confirm / password reset on Android (not Google native).
  static const mobileAuthRedirect = 'com.roomrig.room_rig://login-callback/';

  String? get _authRedirectTo =>
      kIsWeb ? Uri.base.origin : mobileAuthRedirect;

  Future<void> _ensureGoogleNativeInitialized() async {
    if (_googleNativeReady || kIsWeb) return;
    final webClientId = SupabaseConfig.googleWebClientId.trim();
    if (webClientId.isEmpty) return;
    await GoogleSignIn.instance.initialize(serverClientId: webClientId);
    _googleNativeReady = true;
  }

  /// Google: native account picker on Android (no Chrome). Web keeps OAuth redirect.
  Future<String?> signInWithGoogle() async {
    final client = SupabaseBootstrap.clientOrNull;
    if (client == null) return 'Cloud auth is not configured on this build.';

    if (!kIsWeb) {
      return _signInWithGoogleNative(client);
    }

    try {
      final launched = await client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _authRedirectTo,
        authScreenLaunchMode: LaunchMode.platformDefault,
      );
      if (!launched) return 'Could not open Google sign-in.';
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return '$e';
    }
  }

  Future<String?> _signInWithGoogleNative(SupabaseClient client) async {
    if (!SupabaseConfig.hasGoogleWebClientId) {
      return 'Missing GOOGLE_WEB_CLIENT_ID. Add the Google Cloud Web client ID '
          '(same as Supabase → Auth → Google) to supabase.local.json, rebuild the APK.';
    }
    try {
      await _ensureGoogleNativeInitialized();
      final google = GoogleSignIn.instance;
      if (!google.supportsAuthenticate()) {
        return 'This device cannot run native Google Sign-In.';
      }
      const scopes = ['email', 'profile'];
      final account = await google.authenticate(scopeHint: scopes);
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        return 'Google did not return an ID token. Check the Web client ID and '
            'that an Android OAuth client exists for com.roomrig.room_rig + your SHA-1.';
      }
      // Prefer existing grants; otherwise prompt for scopes (needed for accessToken).
      final authz = await account.authorizationClient.authorizationForScopes(
            scopes,
          ) ??
          await account.authorizationClient.authorizeScopes(scopes);

      await client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: authz.accessToken,
      );
      notifyListeners();
      return null;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        // Credential Manager often reports config failures (missing Android
        // OAuth client / wrong SHA-1) as "canceled" after account pick.
        return 'Google sign-in failed after account pick. In Google Cloud → '
            'Credentials, create an Android OAuth client for package '
            'com.roomrig.room_rig with debug SHA-1 '
            '6C:10:FA:51:E8:C4:9F:B9:E3:93:18:93:8A:55:3A:3D:AE:64:F8:AE '
            '(same Cloud project as the Web client used in Supabase).';
      }
      if (e.code == GoogleSignInExceptionCode.clientConfigurationError) {
        return e.description ??
            'Google client misconfigured. Add Android OAuth client + SHA-1.';
      }
      return e.description ?? e.toString();
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

  /// Soft-deletes the account (sets `deletion_requested_at` via `delete-account`
  /// Edge Function). Hard purge runs after 7 days. Prefer the OTP flow in
  /// [ProfileService.confirmDeleteWithCode] for in-app deletes.
  Future<String?> deleteAccount() async {
    final client = SupabaseBootstrap.clientOrNull;
    if (client == null) return 'Cloud auth is not configured on this build.';
    try {
      final res = await client.functions.invoke('delete-account');
      if (res.status >= 400) {
        final msg = res.data is Map && (res.data as Map)['error'] != null
            ? '${(res.data as Map)['error']}'
            : 'Could not schedule account deletion (${res.status}).';
        return msg;
      }
      _passwordRecoveryPending = false;
      _intentionalSignOut = true;
      await client.auth.signOut();
      notifyListeners();
      return null;
    } catch (e) {
      return '$e';
    }
  }
}
