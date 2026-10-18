/// Supabase keys via compile-time defines (never commit secrets).
///
/// ```powershell
/// flutter run -d web-server --web-port 7357 `
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co `
///   --dart-define=SUPABASE_ANON_KEY=eyJ...
/// ```
/// Or: `.\scripts\dev_web.ps1` after creating gitignored `supabase.local.json`.
class SupabaseConfig {
  SupabaseConfig._();

  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// True when both defines are non-empty — cloud auth/sync can initialize.
  static bool get isConfigured =>
      url.trim().isNotEmpty && anonKey.trim().isNotEmpty;
}
