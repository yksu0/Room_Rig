import 'room_model.dart';

/// Snapshot payload stored in `published_layouts.layout`.
class PublishedLayoutSnapshot {
  final String name;
  final String? presetName;
  final int gridCols;
  final int gridRows;
  final List<FurnitureItem> furniture;

  const PublishedLayoutSnapshot({
    required this.name,
    this.presetName,
    required this.gridCols,
    required this.gridRows,
    required this.furniture,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        if (presetName != null) 'presetName': presetName,
        'gridCols': gridCols,
        'gridRows': gridRows,
        'furniture': furniture.map((f) => f.toJson()).toList(growable: false),
      };

  factory PublishedLayoutSnapshot.fromJson(Map<String, dynamic> json) {
    final raw = json['furniture'];
    final items = <FurnitureItem>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          items.add(FurnitureItem.fromJson(e.cast<String, dynamic>()));
        }
      }
    }
    return PublishedLayoutSnapshot(
      name: json['name'] as String? ?? 'Layout',
      presetName: json['presetName'] as String?,
      gridCols: (json['gridCols'] as num?)?.toInt() ?? 6,
      gridRows: (json['gridRows'] as num?)?.toInt() ?? 8,
      furniture: items,
    );
  }
}

/// Community / baseline row with optional rating aggregates.
class PublishedLayout {
  final String id;
  final String? authorId;
  final String? authorName;
  final String? authorAvatarUrl;
  final String title;
  final String? description;
  final PublishedLayoutSnapshot layout;
  final Map<String, dynamic>? scores;
  final List<String> tags;
  final bool isAdminBaseline;
  final DateTime? featuredUntil;
  final DateTime publishedAt;
  final bool hidden;
  final int upCount;
  final int downCount;
  final int netScore;
  final int? myVote;
  final List<String> myTags;

  const PublishedLayout({
    required this.id,
    this.authorId,
    this.authorName,
    this.authorAvatarUrl,
    required this.title,
    this.description,
    required this.layout,
    this.scores,
    this.tags = const [],
    this.isAdminBaseline = false,
    this.featuredUntil,
    required this.publishedAt,
    this.hidden = false,
    this.upCount = 0,
    this.downCount = 0,
    this.netScore = 0,
    this.myVote,
    this.myTags = const [],
  });

  PublishedLayout copyWith({
    int? upCount,
    int? downCount,
    int? netScore,
    int? myVote,
    List<String>? myTags,
    bool clearMyVote = false,
  }) {
    return PublishedLayout(
      id: id,
      authorId: authorId,
      authorName: authorName,
      authorAvatarUrl: authorAvatarUrl,
      title: title,
      description: description,
      layout: layout,
      scores: scores,
      tags: tags,
      isAdminBaseline: isAdminBaseline,
      featuredUntil: featuredUntil,
      publishedAt: publishedAt,
      hidden: hidden,
      upCount: upCount ?? this.upCount,
      downCount: downCount ?? this.downCount,
      netScore: netScore ?? this.netScore,
      myVote: clearMyVote ? null : (myVote ?? this.myVote),
      myTags: myTags ?? this.myTags,
    );
  }

  static PublishedLayout fromRow(
    Map<String, dynamic> row, {
    Map<String, dynamic>? stats,
    Map<String, dynamic>? myRating,
    Map<String, dynamic>? author,
  }) {
    final layoutRaw = row['layout'];
    final layoutMap = layoutRaw is Map
        ? Map<String, dynamic>.from(layoutRaw)
        : <String, dynamic>{};
    final scoresRaw = row['scores'];
    final tagsRaw = row['tags'];
    final featured = row['featured_until'];
    final published = row['published_at'];
    return PublishedLayout(
      id: row['id'] as String,
      authorId: row['author_id'] as String?,
      authorName: author?['display_name'] as String?,
      authorAvatarUrl: author?['avatar_url'] as String?,
      title: row['title'] as String? ?? 'Untitled',
      description: row['description'] as String?,
      layout: PublishedLayoutSnapshot.fromJson(layoutMap),
      scores: scoresRaw is Map
          ? Map<String, dynamic>.from(scoresRaw)
          : null,
      tags: tagsRaw is List
          ? tagsRaw.map((e) => e.toString()).toList(growable: false)
          : const [],
      isAdminBaseline: row['is_admin_baseline'] as bool? ?? false,
      featuredUntil: featured is String ? DateTime.tryParse(featured) : null,
      publishedAt: published is String
          ? (DateTime.tryParse(published) ?? DateTime.now().toUtc())
          : DateTime.now().toUtc(),
      hidden: row['hidden'] as bool? ?? false,
      upCount: (stats?['up_count'] as num?)?.toInt() ?? 0,
      downCount: (stats?['down_count'] as num?)?.toInt() ?? 0,
      netScore: (stats?['net_score'] as num?)?.toInt() ?? 0,
      myVote: (myRating?['vote'] as num?)?.toInt(),
      myTags: myRating?['tags'] is List
          ? (myRating!['tags'] as List).map((e) => e.toString()).toList()
          : const [],
    );
  }
}

/// Optional rating tags shown in the Community rate sheet.
const kLayoutRatingTagOptions = [
  'airflow',
  'lighting',
  'ergonomics',
  'spatial',
];

/// Suggested topic tags when composing a Community post.
const kCommunityPostTagOptions = [
  'airflow',
  'lighting',
  'ergonomics',
  'spatial',
  'gaming',
  'office',
  'bedroom',
  'small-room',
  'before-after',
  'budget',
];
