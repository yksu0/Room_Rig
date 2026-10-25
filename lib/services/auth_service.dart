import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_bootstrap.dart';

/// Email/password auth. When Supabase is not configured, always guest.
class AuthService extends ChangeNotifier {
  AuthService() {
    _bind();
  }

  StreamSubscription<AuthState>? _sub;

  User? get user => SupabaseBootstrap.clientOrNull?.auth.currentUser;
  Session? get session => SupabaseBootstrap.clientOrNull?.auth.currentSession;
  bool get isSignedIn => user != null;
  bool get isGuest => !isSignedIn;
  String? get userId => user?.id;
  String? get email => user?.email;

  void _bind() {
    final client = SupabaseBootstrap.clientOrNull;
    if (client == null) return;
    _sub = client.auth.onAuthStateChange.listen((_) {
      notifyListeners();
    });
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
      await client.auth.signUp(email: email.trim(), password: password);
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
    await client.auth.signOut();
    notifyListeners();
  }

  /// Google OAuth (Supabase Free tier). Web uses redirect; mobile uses same PKCE flow.
  Future<String?> signInWithGoogle() async {
    final client = SupabaseBootstrap.clientOrNull;
    if (client == null) return 'Cloud auth is not configured on this build.';
    try {
      final launched = await client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? Uri.base.origin : null,
        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
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
    try {
      await client.auth.resetPasswordForEmail(email.trim());
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return '$e';
    }
  }
}
