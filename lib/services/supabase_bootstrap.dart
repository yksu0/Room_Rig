import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Initializes Supabase when dart-defines are present; otherwise guest-only.
class SupabaseBootstrap {
  SupabaseBootstrap._();

  static bool _ready = false;
  static bool get isReady => _ready;

  static SupabaseClient? get clientOrNull =>
      _ready ? Supabase.instance.client : null;

  static Future<bool> ensureInitialized() async {
    if (_ready) return true;
    if (!SupabaseConfig.isConfigured) {
      debugPrint(
        'Supabase: not configured (set SUPABASE_URL + SUPABASE_ANON_KEY). '
        'Running guest-only.',
      );
      return false;
    }
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    _ready = true;
    return true;
  }
}
