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
      return _hydrate(Map<String, dynamic>.from(row));
    } catch (e) {
      debugPrint('fetchById($id): $e');
      return null;
    }
  }

  Future<PublishedLayout> publish({
    required String authorId,
    required String title,
    required PublishedLayoutSnapshot layout,
    Map<String, dynamic>? scores,
    List<String> tags = const [],
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase is not configured');
    }
    final inserted = await client
        .from('published_layouts')
        .insert({
          'author_id': authorId,
          'title': title.trim(),
          'layout': layout.toJson(),
          'scores': ?scores,
          'tags': tags,
          'is_admin_baseline': false,
        })
        .select()
        .single();
    return _hydrate(Map<String, dynamic>.from(inserted));
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
    await client.from('layout_ratings').upsert({
      'layout_id': layoutId,
      'rater_id': raterId,
      'vote': vote,
      'tags': tags,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final refreshed = await fetchById(layoutId);
    if (refreshed == null) {
      throw StateError('Layout missing after rate');
    }
    return refreshed;
  }

  Future<List<PublishedLayout>> _hydrateAll(List<dynamic> rows) async {
    final list = <PublishedLayout>[];
    for (final row in rows) {
      if (row is Map) {
        list.add(await _hydrate(Map<String, dynamic>.from(row)));
      }
    }
    return list;
  }

  Future<PublishedLayout> _hydrate(Map<String, dynamic> row) async {
    final client = _client;
    Map<String, dynamic>? stats;
    Map<String, dynamic>? myRating;
    Map<String, dynamic>? author;
    final id = row['id'] as String?;
    final authorId = row['author_id'] as String?;
    if (client != null && id != null) {
      try {
        final s = await client
            .from('layout_rating_stats')
            .select()
            .eq('layout_id', id)
            .maybeSingle();
        if (s != null) stats = Map<String, dynamic>.from(s);
      } catch (_) {}
      final uid = client.auth.currentUser?.id;
      if (uid != null) {
        try {
          final r = await client
              .from('layout_ratings')
              .select()
              .eq('layout_id', id)
              .eq('rater_id', uid)
              .maybeSingle();
          if (r != null) myRating = Map<String, dynamic>.from(r);
        } catch (_) {}
      }
      if (authorId != null) {
        try {
          final a = await client
              .from('profiles')
              .select('id, display_name, avatar_url')
              .eq('id', authorId)
              .maybeSingle();
          if (a != null) author = Map<String, dynamic>.from(a);
        } catch (_) {}
      }
    }
    return PublishedLayout.fromRow(
      row,
      stats: stats,
      myRating: myRating,
      author: author,
    );
  }
}
