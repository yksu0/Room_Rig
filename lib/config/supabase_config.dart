/// Supabase keys via compile-time defines (never commit secrets).
///
/// ```powershell
/// flutter run -d web-server --web-port 7357 `
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co `
///   --dart-define=SUPABASE_ANON_KEY=eyJ... `
///   --dart-define=GOOGLE_WEB_CLIENT_ID=xxxx.apps.googleusercontent.com
/// ```
/// Or: `.\scripts\dev_web.ps1` after creating gitignored `supabase.local.json`.
class SupabaseConfig {
  SupabaseConfig._();

  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Google Cloud **Web** OAuth client ID (same one pasted into Supabase → Google).
  /// Required for native Android Google Sign-In (avoids Chrome OAuth).
  static const googleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// True when both defines are non-empty — cloud auth/sync can initialize.
  static bool get isConfigured =>
      url.trim().isNotEmpty && anonKey.trim().isNotEmpty;

  static bool get hasGoogleWebClientId => googleWebClientId.trim().isNotEmpty;
}
