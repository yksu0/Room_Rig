// lib/models/saved_room.dart
import 'room_catalog.dart';
import 'room_model.dart';
import 'room_revision.dart';
import 'scan_layout_model.dart';

/// One named lot in My Rooms. The live editor is always one of these.
class SavedRoom {
  static const maxRevisions = 24;

  final String id;
  final String name;
  final String presetName;
  final bool scanComplete;
  final double scanProgress;
  final RoomLayoutModel layout;
  final List<FurnitureItem> furniture;
  final List<String> installedUpgrades;
  final List<FurnitureItem>? originalFurniture;
  final Map<String, double>? originalScores;
  final List<RoomRevision> revisions;

  /// True when Hub can show BENCHMARK OK (Benchmark Apply / Auto-Rig last wrote scores).
  final bool scoresClean;

  /// True when the live layout is still the last applied/optimized arrangement.
  final bool isOptimized;

  /// Auth user id when this lot was saved while signed in; null = guest/device-only.
  final String? ownerUserId;

  /// Pinned Benchmark compare baseline (left side). Null until first Benchmark open / Set baseline.
  final List<FurnitureItem>? benchmarkBaselineFurniture;
  final String? benchmarkBaselineLabel;
  final DateTime? benchmarkBaselineAt;

  const SavedRoom({
    required this.id,
    required this.name,
    required this.presetName,
    required this.scanComplete,
    required this.scanProgress,
    required this.layout,
    required this.furniture,
    this.installedUpgrades = const [],
    this.originalFurniture,
    this.originalScores,
    this.revisions = const [],
    this.scoresClean = false,
    this.isOptimized = false,
    this.ownerUserId,
    this.benchmarkBaselineFurniture,
    this.benchmarkBaselineLabel,
    this.benchmarkBaselineAt,
  });

  /// True guest / device-only lots — safe to offer for upload after sign-in.
  bool get isGuestOwned => ownerUserId == null;

  SavedRoom copyWith({
    String? name,
    String? presetName,
    bool? scanComplete,
    double? scanProgress,
    RoomLayoutModel? layout,
    List<FurnitureItem>? furniture,
    List<String>? installedUpgrades,
    List<FurnitureItem>? originalFurniture,
    Map<String, double>? originalScores,
    List<RoomRevision>? revisions,
    bool? scoresClean,
    bool? isOptimized,
    String? ownerUserId,
    List<FurnitureItem>? benchmarkBaselineFurniture,
    String? benchmarkBaselineLabel,
    DateTime? benchmarkBaselineAt,
    bool clearOriginal = false,
    bool clearOwner = false,
    bool clearBenchmarkBaseline = false,
  }) {
    return SavedRoom(
      id: id,
      name: name ?? this.name,
      presetName: presetName ?? this.presetName,
      scanComplete: scanComplete ?? this.scanComplete,
      scanProgress: scanProgress ?? this.scanProgress,
      layout: layout ?? this.layout,
      furniture: furniture ?? this.furniture,
      installedUpgrades: installedUpgrades ?? this.installedUpgrades,
      originalFurniture:
          clearOriginal ? null : (originalFurniture ?? this.originalFurniture),
      originalScores:
          clearOriginal ? null : (originalScores ?? this.originalScores),
      revisions: revisions ?? this.revisions,
      scoresClean: scoresClean ?? this.scoresClean,
      isOptimized: isOptimized ?? this.isOptimized,
      ownerUserId: clearOwner ? null : (ownerUserId ?? this.ownerUserId),
      benchmarkBaselineFurniture: clearBenchmarkBaseline
          ? null
          : (benchmarkBaselineFurniture ?? this.benchmarkBaselineFurniture),
      benchmarkBaselineLabel: clearBenchmarkBaseline
          ? null
          : (benchmarkBaselineLabel ?? this.benchmarkBaselineLabel),
      benchmarkBaselineAt: clearBenchmarkBaseline
          ? null
          : (benchmarkBaselineAt ?? this.benchmarkBaselineAt),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'presetName': presetName,
        'scanComplete': scanComplete,
        'scanProgress': scanProgress,
        'layout': layout.toJson(),
        'furniture': furniture.map((f) => f.toJson()).toList(growable: false),
        'installedUpgrades': installedUpgrades,
        'scoresClean': scoresClean,
        'isOptimized': isOptimized,
        if (ownerUserId != null) 'ownerUserId': ownerUserId,
        if (originalFurniture != null)
          'originalFurniture':
              originalFurniture!.map((f) => f.toJson()).toList(growable: false),
        if (originalScores != null) 'originalScores': originalScores,
        if (revisions.isNotEmpty)
          'revisions': revisions.map((r) => r.toJson()).toList(growable: false),
        if (benchmarkBaselineFurniture != null)
          'benchmarkBaselineFurniture': benchmarkBaselineFurniture!
              .map((f) => f.toJson())
              .toList(growable: false),
        if (benchmarkBaselineLabel != null) 'benchmarkBaselineLabel': benchmarkBaselineLabel,
        if (benchmarkBaselineAt != null)
          'benchmarkBaselineAt': benchmarkBaselineAt!.toUtc().toIso8601String(),
      };

  factory SavedRoom.fromJson(Map<String, dynamic> json) {
    final furnitureRaw = json['furniture'];
    final originalRaw = json['originalFurniture'];
    final scoresRaw = json['originalScores'];
    final revisionsRaw = json['revisions'];
    final baselineRaw = json['benchmarkBaselineFurniture'];
    final originalFurniture = originalRaw is List
        ? RoomCatalog.retainV1(
            originalRaw
                .whereType<Map>()
                .map((e) => FurnitureItem.fromJson(e.cast<String, dynamic>()))
                .toList(),
          )
        : null;
    final scoresClean = json['scoresClean'] as bool? ?? false;
    return SavedRoom(
      id: json['id'] as String? ?? 'room',
      name: json['name'] as String? ?? 'Room',
      presetName: json['presetName'] as String? ?? 'gamingSetup',
      scanComplete: json['scanComplete'] as bool? ?? false,
      scanProgress: (json['scanProgress'] as num?)?.toDouble() ?? 0,
      layout: RoomLayoutModel.fromJson(
        (json['layout'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      furniture: furnitureRaw is List
          ? RoomCatalog.retainV1(
              furnitureRaw
                  .whereType<Map>()
                  .map((e) => FurnitureItem.fromJson(e.cast<String, dynamic>()))
                  .toList(),
            )
          : const [],
      installedUpgrades: (json['installedUpgrades'] as List?)
              ?.map((e) => '$e')
              .toList(growable: false) ??
          const [],
      originalFurniture: originalFurniture,
      originalScores: scoresRaw is Map
          ? scoresRaw.map((k, v) => MapEntry('$k', (v as num?)?.toDouble() ?? 0))
          : null,
      revisions: revisionsRaw is List
          ? revisionsRaw
              .whereType<Map>()
              .map((e) => RoomRevision.fromJson(e.cast<String, dynamic>()))
              .toList(growable: false)
          : const [],
      scoresClean: scoresClean,
      // Prefer explicit flag; never claim Applied when scores are still rough.
      isOptimized: json['isOptimized'] as bool? ??
          (scoresClean && originalFurniture != null),
      ownerUserId: json['ownerUserId'] as String?,
      benchmarkBaselineFurniture: baselineRaw is List
          ? RoomCatalog.retainV1(
              baselineRaw
                  .whereType<Map>()
                  .map((e) => FurnitureItem.fromJson(e.cast<String, dynamic>()))
                  .toList(),
            )
          : null,
      benchmarkBaselineLabel: json['benchmarkBaselineLabel'] as String?,
      benchmarkBaselineAt:
          DateTime.tryParse(json['benchmarkBaselineAt'] as String? ?? '')?.toLocal(),
    );
  }
}
