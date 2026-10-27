import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/saved_room.dart';
import 'supabase_bootstrap.dart';

/// Cloud CRUD for My Rooms (signed-in only). Guests never call this.
class RoomRepository {
  RoomRepository();

  SupabaseClient? get _client => SupabaseBootstrap.clientOrNull;

  Future<List<SavedRoom>> fetchRooms(String userId) async {
    final client = _client;
    if (client == null) return const [];
    final rows = await client
        .from('rooms')
        .select()
        .eq('user_id', userId)
        .order('updated_at', ascending: false);
    return rows.map((row) => _fromRow(Map<String, dynamic>.from(row))).toList();
  }

  Future<void> upsertRoom(String userId, SavedRoom room) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.from('rooms').upsert(
            _toRow(userId, room),
            onConflict: 'id',
          );
    } catch (e) {
      debugPrint('upsertRoom(${room.id}): $e');
      rethrow;
    }
  }

  Future<void> upsertMany(String userId, List<SavedRoom> rooms) async {
    final client = _client;
    if (client == null || rooms.isEmpty) return;
    try {
      await client.from('rooms').upsert(
            rooms.map((r) => _toRow(userId, r)).toList(),
            onConflict: 'id',
          );
    } catch (e) {
      debugPrint('upsertMany(${rooms.length}): $e');
      rethrow;
    }
  }

  Future<void> deleteRoom(String userId, String roomId) async {
    final client = _client;
    if (client == null) return;
    await client.from('rooms').delete().eq('user_id', userId).eq('id', roomId);
  }

  Future<void> ensureProfile({
    required String userId,
    String? displayName,
  }) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.from('profiles').upsert({
        'id': userId,
        if (displayName != null && displayName.trim().isNotEmpty)
          'display_name': displayName.trim(),
      });
    } catch (e) {
      debugPrint('ensureProfile: $e');
    }
  }

  Map<String, dynamic> _toRow(String userId, SavedRoom room) {
    final json = room.toJson();
    return {
      'id': room.id,
      'user_id': userId,
      'name': room.name,
      'preset_name': room.presetName,
      'scan_complete': room.scanComplete,
      'scan_progress': room.scanProgress,
      'layout': json['layout'],
      'furniture': json['furniture'],
      'revisions': json['revisions'] ?? [],
      'installed_upgrades': json['installedUpgrades'] ?? [],
      'original_furniture': json['originalFurniture'],
      'original_scores': json['originalScores'],
      'scores_clean': room.scoresClean,
      'is_optimized': room.isOptimized,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  SavedRoom _fromRow(Map<String, dynamic> row) {
    return SavedRoom.fromJson({
      'id': row['id'],
      'name': row['name'],
      'presetName': row['preset_name'],
      'scanComplete': row['scan_complete'],
      'scanProgress': row['scan_progress'],
      'layout': row['layout'] ?? {},
      'furniture': row['furniture'] ?? [],
      'revisions': row['revisions'] ?? [],
      'installedUpgrades': row['installed_upgrades'] ?? [],
      'originalFurniture': row['original_furniture'],
      'originalScores': row['original_scores'],
      'scoresClean': row['scores_clean'] ?? false,
      'isOptimized': row['is_optimized'] ?? false,
      // Cloud rows always belong to the fetching account.
      'ownerUserId': row['user_id'],
    });
  }
}
