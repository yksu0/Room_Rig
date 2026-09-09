import 'room_model.dart';
import 'rig_catalog.dart';
import 'scan_layout_model.dart';

/// A named checkpoint of a room's furniture over time.
class RoomRevision {
  final String id;
  final String label;
  final DateTime savedAt;
  final List<FurnitureItem> furniture;
  final RoomLayoutModel? layout;
  final Map<String, double>? scores;

  const RoomRevision({
    required this.id,
    required this.label,
    required this.savedAt,
    required this.furniture,
    this.layout,
    this.scores,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'savedAt': savedAt.toUtc().toIso8601String(),
        'furniture': furniture.map((f) => f.toJson()).toList(growable: false),
        if (layout != null) 'layout': layout!.toJson(),
        if (scores != null) 'scores': scores,
      };

  factory RoomRevision.fromJson(Map<String, dynamic> json) {
    final furnitureRaw = json['furniture'];
    final scoresRaw = json['scores'];
    final layoutRaw = json['layout'];
    return RoomRevision(
      id: json['id'] as String? ?? 'rev',
      label: json['label'] as String? ?? 'Checkpoint',
      savedAt: DateTime.tryParse(json['savedAt'] as String? ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      furniture: furnitureRaw is List
          ? RigCatalog.retainV1(
              furnitureRaw
                  .whereType<Map>()
                  .map((e) => FurnitureItem.fromJson(e.cast<String, dynamic>()))
                  .toList(),
            )
          : const [],
      layout: layoutRaw is Map
          ? RoomLayoutModel.fromJson(layoutRaw.cast<String, dynamic>())
          : null,
      scores: scoresRaw is Map
          ? scoresRaw.map((k, v) => MapEntry('$k', (v as num?)?.toDouble() ?? 0))
          : null,
    );
  }
}
