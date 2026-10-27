import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_bootstrap.dart';

/// Row from `public.profiles` for the signed-in user.
class UserProfile {
  final String id;
  final String? displayName;
  final String? avatarUrl;
  final DateTime? deletionRequestedAt;
  final bool isAdmin;

  const UserProfile({
    required this.id,
    this.displayName,
    this.avatarUrl,
    this.deletionRequestedAt,
    this.isAdmin = false,
  });

  /// Name + avatar are required to publish or rate community layouts.
  bool get isComplete =>
      (displayName ?? '').trim().isNotEmpty && (avatarUrl ?? '').isNotEmpty;

  UserProfile copyWith({
    String? displayName,
    String? avatarUrl,
    DateTime? deletionRequestedAt,
    bool? isAdmin,
    bool clearDeletion = false,
  }) {
    return UserProfile(
      id: id,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      deletionRequestedAt:
          clearDeletion ? null : (deletionRequestedAt ?? this.deletionRequestedAt),
      isAdmin: isAdmin ?? this.isAdmin,
    );
  }

  static UserProfile fromRow(Map<String, dynamic> row) {
    final raw = row['deletion_requested_at'];
    return UserProfile(
      id: row['id'] as String,
      displayName: row['display_name'] as String?,
      avatarUrl: row['avatar_url'] as String?,
      deletionRequestedAt: raw is String ? DateTime.tryParse(raw) : null,
      isAdmin: row['is_admin'] as bool? ?? false,
    );
  }
}

/// Profile (name + avatar) and the OTP-confirmed soft-delete flow.
///
/// Everything here needs the network; callers surface the returned message.
class ProfileService extends ChangeNotifier {
  static const avatarsBucket = 'avatars';
  static const deletionGraceDays = 7;

  UserProfile? _profile;
  bool _loading = false;

  UserProfile? get profile => _profile;
  bool get loading => _loading;

  SupabaseClient? get _client => SupabaseBootstrap.clientOrNull;
  User? get _user => _client?.auth.currentUser;

  /// App-owned display name only — never Google / OAuth metadata.
  String get displayLabel {
    final p = _profile?.displayName?.trim();
    if (p != null && p.isNotEmpty) return p;
    return 'Add name';
  }

  /// True when the user has set a Room Rig display name in Profile.
  bool get hasDisplayName =>
      (_profile?.displayName ?? '').trim().isNotEmpty;

  /// App-owned avatar URL only (avatars bucket). Never Google photo.
  String? get avatarUrl {
    final a = _profile?.avatarUrl;
    if (a != null && a.isNotEmpty) return a;
    return null;
  }

  /// Publish / rate need a complete Profile (name + avatar).
  bool get canPublishOrRate => _profile?.isComplete == true;

  bool get isAdmin => _profile?.isAdmin == true;

  void clear() {
    _profile = null;
    _loading = false;
    notifyListeners();
  }

  /// Fetch (or create a blank) app profile row. Never copies Google name/photo.
  /// Sign-in inside the 7-day delete window cancels pending deletion.
  Future<void> load({bool cancelPendingDeletion = true}) async {
    final client = _client;
    final user = _user;
    if (client == null || user == null) {
      clear();
      return;
    }
    _loading = true;
    notifyListeners();
    try {
      final row = await client
          .from('profiles')
          .select(
            'id, display_name, avatar_url, deletion_requested_at, is_admin',
          )
          .eq('id', user.id)
          .maybeSingle();
      var p = row == null
          ? UserProfile(id: user.id)
          : UserProfile.fromRow(Map<String, dynamic>.from(row));

      final patch = <String, dynamic>{};
      if (cancelPendingDeletion && p.deletionRequestedAt != null) {
        patch['deletion_requested_at'] = null;
      }
      // Ensure the row exists; leave display_name / avatar_url null until
      // the user sets them in Profile (app-owned identity).
      if (patch.isNotEmpty || row == null) {
        await client.from('profiles').upsert({'id': user.id, ...patch});
        if (patch.containsKey('deletion_requested_at')) {
          p = p.copyWith(clearDeletion: true);
        }
      }
      _profile = p;
    } catch (e) {
      debugPrint('ProfileService.load: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String?> updateDisplayName(String name) async {
    final client = _client;
    final user = _user;
    if (client == null || user == null) return 'Sign in to edit your profile.';
    final trimmed = name.trim();
    if (trimmed.length < 2) return 'Name must be at least 2 characters.';
    if (trimmed.length > 32) return 'Name must be 32 characters or fewer.';
    try {
      await client
          .from('profiles')
          .upsert({'id': user.id, 'display_name': trimmed});
      _profile = (_profile ?? UserProfile(id: user.id))
          .copyWith(displayName: trimmed);
      notifyListeners();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not save name. Check your connection. ($e)';
    }
  }

  /// Upload to `avatars/<uid>/avatar.<ext>` and store the public URL.
  Future<String?> uploadAvatar(Uint8List bytes, {required String extension}) async {
    final client = _client;
    final user = _user;
    if (client == null || user == null) return 'Sign in to set a photo.';
    if (bytes.isEmpty) return 'That image is empty.';
    if (bytes.lengthInBytes > 2 * 1024 * 1024) {
      return 'Choose an image under 2 MB.';
    }
    final ext = extension.toLowerCase().replaceAll('.', '');
    final mime = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    final safeExt = mime == 'image/png'
        ? 'png'
        : mime == 'image/webp'
            ? 'webp'
            : 'jpg';
    final path = '${user.id}/avatar.$safeExt';
    try {
      await client.storage.from(avatarsBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: true),
          );
      final base = client.storage.from(avatarsBucket).getPublicUrl(path);
      // Cache-bust so the new photo shows immediately after replace.
      final url = '$base?v=${DateTime.now().millisecondsSinceEpoch}';
      await client.from('profiles').upsert({'id': user.id, 'avatar_url': url});
      _profile = (_profile ?? UserProfile(id: user.id)).copyWith(avatarUrl: url);
      notifyListeners();
      return null;
    } on StorageException catch (e) {
      return e.message;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return 'Upload failed. Check your connection. ($e)';
    }
  }

  // ---------------------------------------------------------------------------
  // Delete account: email OTP confirm → soft delete (7-day grace) → sign out.
  // ---------------------------------------------------------------------------

  /// Reachability probe for delete: phone must reach Room Rig's cloud
  /// (Supabase), not a specific website. Null = ok; otherwise a short reason.
  Future<String?> cloudReachabilityError() async {
    final client = _client;
    final user = _user;
    if (client == null) {
      return 'Cloud is not configured on this build.';
    }
    if (user == null) {
      return 'You are signed out.';
    }
    try {
      await client
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));
      return null;
    } on TimeoutException {
      return 'Timed out reaching Room Rig cloud. Check Wi‑Fi or mobile data.';
    } catch (e) {
      return 'Cannot reach Room Rig cloud ($e). Check Wi‑Fi or mobile data.';
    }
  }

  /// True when [cloudReachabilityError] is null.
  Future<bool> isOnline() async => await cloudReachabilityError() == null;

  /// Emails a one-time code (Magic Link template with `{{ .Token }}`).
  /// Works for Google-only accounts too — it only needs the account email.
  Future<String?> sendDeleteConfirmationCode() async {
    final client = _client;
    final email = _user?.email;
    if (client == null) return 'Cloud auth is not configured on this build.';
    if (email == null || email.isEmpty) {
      return 'This account has no email on file, so it cannot be confirmed.';
    }
    try {
      await client.auth.signInWithOtp(email: email, shouldCreateUser: false);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not send the code. Check your connection. ($e)';
    }
  }

  /// Verifies the emailed code, then marks the profile for deletion.
  /// Returns null on success; the caller signs out afterwards.
  Future<String?> confirmDeleteWithCode(String code) async {
    final client = _client;
    final user = _user;
    if (client == null || user == null) return 'Sign in first.';
    final email = user.email;
    if (email == null) return 'This account has no email on file.';
    final token = code.trim();
    if (token.length < 6) return 'Enter the 6-digit code from the email.';
    try {
      final res = await client.auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.email,
      );
      if (res.user == null || res.user!.id != user.id) {
        return 'That code did not match this account.';
      }
      await client.from('profiles').upsert({
        'id': user.id,
        'deletion_requested_at': DateTime.now().toUtc().toIso8601String(),
      });
      _profile = (_profile ?? UserProfile(id: user.id)).copyWith(
        deletionRequestedAt: DateTime.now().toUtc(),
      );
      notifyListeners();
      return null;
    } on AuthException catch (e) {
      return e.message;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not confirm. ($e)';
    }
  }
}
