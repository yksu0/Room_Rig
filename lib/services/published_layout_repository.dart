import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/published_layout.dart';
import 'supabase_bootstrap.dart';

/// Feed / publish / rate for Benchmark Community.
class PublishedLayoutRepository {
  PublishedLayoutRepository();

  SupabaseClient? get _client => SupabaseBootstrap.clientOrNull;

  Future<List<PublishedLayout>> fetchBaselines({int limit = 20}) async {
    final client = _client;
    if (client == null) return const [];
    try {
      final rows = await client
          .from('published_layouts')
          .select()
          .eq('hidden', false)
          .eq('is_admin_baseline', true)
          .order('published_at', ascending: true)
          .limit(limit);
      return _hydrateAll(rows);
    } catch (e) {
      debugPrint('fetchBaselines: $e');
      return const [];
    }
  }

  Future<List<PublishedLayout>> fetchRecent({int limit = 30}) async {
    final client = _client;
    if (client == null) return const [];
    try {
      final rows = await client
          .from('published_layouts')
          .select()
          .eq('hidden', false)
          .eq('is_admin_baseline', false)
          .order('published_at', ascending: false)
          .limit(limit);
      return _hydrateAll(rows);
    } catch (e) {
      debugPrint('fetchRecent: $e');
      return const [];
    }
  }

  Future<List<PublishedLayout>> fetchTop({int limit = 30}) async {
    final rows = await fetchRecent(limit: 80);
    final sorted = [...rows]..sort((a, b) {
        final byNet = b.netScore.compareTo(a.netScore);
        if (byNet != 0) return byNet;
        return b.publishedAt.compareTo(a.publishedAt);
      });
    if (sorted.length <= limit) return sorted;
    return sorted.sublist(0, limit);
  }

  /// Previous calendar month's top community layouts (may be empty).
  Future<List<PublishedLayout>> fetchMonthlyFeatured() async {
    final client = _client;
    if (client == null) return const [];
    try {
      final rows = await client.from('monthly_featured_layouts').select();
      return _hydrateAll(rows);
    } catch (e) {
      debugPrint('fetchMonthlyFeatured: $e');
      return const [];
    }
  }

  Future<PublishedLayout?> fetchById(String id) async {
    final client = _client;
    if (client == null) return null;
    try {
      final row = await client
          .from('published_layouts')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;
      final list = await _hydrateAll([row]);
      return list.isEmpty ? null : list.first;
    } catch (e) {
      debugPrint('fetchById($id): $e');
      return null;
    }
  }

  /// Author's Community posts (includes hidden — owner can still see them).
  Future<List<PublishedLayout>> fetchByAuthor(
    String authorId, {
    int limit = 40,
  }) async {
    final client = _client;
    if (client == null) return const [];
    try {
      final rows = await client
          .from('published_layouts')
          .select()
          .eq('author_id', authorId)
          .eq('is_admin_baseline', false)
          .order('published_at', ascending: false)
          .limit(limit);
      return _hydrateAll(rows);
    } catch (e) {
      debugPrint('fetchByAuthor($authorId): $e');
      return const [];
    }
  }

  /// Profile stats: posts + karma received + votes this user cast.
  Future<AuthorSocialSummary> fetchAuthorSocial(String authorId) async {
    final posts = await fetchByAuthor(authorId);
    var up = 0;
    var down = 0;
    for (final p in posts) {
      up += p.upCount;
      down += p.downCount;
    }
    final votesCast = await _countVotesCast(authorId);
    return AuthorSocialSummary(
      postCount: posts.length,
      upReceived: up,
      downReceived: down,
      netReceived: up - down,
      votesCast: votesCast,
      posts: posts,
    );
  }

  Future<int> _countVotesCast(String raterId) async {
    final client = _client;
    if (client == null) return 0;
    try {
      final rows = await client
          .from('layout_ratings')
          .select('layout_id')
          .eq('rater_id', raterId);
      return rows.length;
    } catch (e) {
      debugPrint('countVotesCast: $e');
      return 0;
    }
  }

  Future<PublishedLayout> setHidden({
    required String layoutId,
    required bool hidden,
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase is not configured');
    }
    final updated = await client
        .from('published_layouts')
        .update({'hidden': hidden})
        .eq('id', layoutId)
        .select()
        .single();
    final list = await _hydrateAll([updated]);
    return list.first;
  }

  Future<PublishedLayout> updatePost({
    required String layoutId,
    required String title,
    String? description,
    List<String> tags = const [],
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase is not configured');
    }
    final desc = description?.trim();
    final updated = await client
        .from('published_layouts')
        .update({
          'title': title.trim(),
          'description': (desc == null || desc.isEmpty) ? null : desc,
          'tags': tags,
        })
        .eq('id', layoutId)
        .select()
        .single();
    final list = await _hydrateAll([updated]);
    return list.first;
  }

  Future<void> deleteLayout(String layoutId) async {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase is not configured');
    }
    await client.from('published_layouts').delete().eq('id', layoutId);
  }

  Future<PublishedLayout> publish({
    required String authorId,
    required String title,
    String? description,
    required PublishedLayoutSnapshot layout,
    Map<String, dynamic>? scores,
    List<String> tags = const [],
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase is not configured');
    }
    final desc = description?.trim();
    final inserted = await client
        .from('published_layouts')
        .insert({
          'author_id': authorId,
          'title': title.trim(),
          'description': (desc == null || desc.isEmpty) ? null : desc,
          'layout': layout.toJson(),
          'scores': ?scores,
          'tags': tags,
          'is_admin_baseline': false,
        })
        .select()
        .single();
    final list = await _hydrateAll([inserted]);
    return list.first;
  }

  Future<PublishedLayout> rate({
    required String layoutId,
    required String raterId,
    required int vote,
    List<String> tags = const [],
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase is not configured');
    }
    if (vote != 1 && vote != -1) {
      throw ArgumentError.value(vote, 'vote', 'must be ±1');
    }
    await client.from('layout_ratings').upsert(
      {
        'layout_id': layoutId,
        'rater_id': raterId,
        'vote': vote,
        'tags': tags,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'layout_id,rater_id',
    );
    final refreshed = await fetchById(layoutId);
    if (refreshed == null) {
      throw StateError('Layout missing after rate');
    }
    return refreshed;
  }

  /// Remove this user's vote (tap same ▲/▼ again).
  Future<PublishedLayout> clearRating({
    required String layoutId,
    required String raterId,
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase is not configured');
    }
    await client
        .from('layout_ratings')
        .delete()
        .eq('layout_id', layoutId)
        .eq('rater_id', raterId);
    final refreshed = await fetchById(layoutId);
    if (refreshed == null) {
      throw StateError('Layout missing after clear rating');
    }
    return refreshed;
  }

  Future<List<PublishedLayout>> _hydrateAll(List<dynamic> rows) async {
    final maps = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (row is Map) {
        maps.add(Map<String, dynamic>.from(row));
      }
    }
    if (maps.isEmpty) return const [];

    final client = _client;
    final ids = <String>[];
    final authorIds = <String>{};
    for (final row in maps) {
      final id = row['id'] as String?;
      if (id != null) ids.add(id);
      final authorId = row['author_id'] as String?;
      if (authorId != null) authorIds.add(authorId);
    }

    final statsById = <String, Map<String, dynamic>>{};
    final myById = <String, Map<String, dynamic>>{};
    final authorById = <String, Map<String, dynamic>>{};

    if (client != null && ids.isNotEmpty) {
      try {
        final statsRows = await client
            .from('layout_rating_stats')
            .select()
            .inFilter('layout_id', ids);
        for (final s in statsRows) {
          final m = Map<String, dynamic>.from(s);
          final lid = m['layout_id'] as String?;
          if (lid != null) statsById[lid] = m;
        }
      } catch (e) {
        debugPrint('hydrate stats: $e');
      }

      final uid = client.auth.currentUser?.id;
      if (uid != null) {
        try {
          final ratingRows = await client
              .from('layout_ratings')
              .select()
              .eq('rater_id', uid)
              .inFilter('layout_id', ids);
          for (final r in ratingRows) {
            final m = Map<String, dynamic>.from(r);
            final lid = m['layout_id'] as String?;
            if (lid != null) myById[lid] = m;
          }
        } catch (e) {
          debugPrint('hydrate my ratings: $e');
        }
      }

      if (authorIds.isNotEmpty) {
        try {
          final authorRows = await client
              .from('community_profiles')
              .select('id, display_name, avatar_url')
              .inFilter('id', authorIds.toList(growable: false));
          for (final a in authorRows) {
            final m = Map<String, dynamic>.from(a);
            final aid = m['id'] as String?;
            if (aid != null) authorById[aid] = m;
          }
        } catch (e) {
          debugPrint('hydrate authors: $e');
        }
      }
    }

    return [
      for (final row in maps)
        PublishedLayout.fromRow(
          row,
          stats: statsById[row['id'] as String?],
          myRating: myById[row['id'] as String?],
          author: authorById[row['author_id'] as String?],
        ),
    ];
  }
}
