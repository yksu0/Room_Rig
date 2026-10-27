/// What Benchmark scores on one side of the compare pair.
enum BenchmarkCompareKind {
  currentRoom,
  checkpoint,
  autoRig,
  publishedLayout,
}

class BenchmarkCompareSource {
  final BenchmarkCompareKind kind;
  final String? checkpointId;
  final String? publishedLayoutId;
  final String? publishedLayoutTitle;

  const BenchmarkCompareSource.currentRoom()
      : kind = BenchmarkCompareKind.currentRoom,
        checkpointId = null,
        publishedLayoutId = null,
        publishedLayoutTitle = null;

  const BenchmarkCompareSource.autoRig()
      : kind = BenchmarkCompareKind.autoRig,
        checkpointId = null,
        publishedLayoutId = null,
        publishedLayoutTitle = null;

  const BenchmarkCompareSource.checkpoint(String id)
      : kind = BenchmarkCompareKind.checkpoint,
        checkpointId = id,
        publishedLayoutId = null,
        publishedLayoutTitle = null;

  const BenchmarkCompareSource.publishedLayout(
    String id, {
    String? title,
  })  : kind = BenchmarkCompareKind.publishedLayout,
        checkpointId = null,
        publishedLayoutId = id,
        publishedLayoutTitle = title;

  bool get isAutoRig => kind == BenchmarkCompareKind.autoRig;
  bool get isCurrentRoom => kind == BenchmarkCompareKind.currentRoom;
  bool get isCheckpoint => kind == BenchmarkCompareKind.checkpoint;
  bool get isPublishedLayout => kind == BenchmarkCompareKind.publishedLayout;

  @override
  bool operator ==(Object other) =>
      other is BenchmarkCompareSource &&
      other.kind == kind &&
      other.checkpointId == checkpointId &&
      other.publishedLayoutId == publishedLayoutId;

  @override
  int get hashCode => Object.hash(kind, checkpointId, publishedLayoutId);

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        if (checkpointId != null) 'checkpointId': checkpointId,
        if (publishedLayoutId != null) 'publishedLayoutId': publishedLayoutId,
        if (publishedLayoutTitle != null)
          'publishedLayoutTitle': publishedLayoutTitle,
      };

  factory BenchmarkCompareSource.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const BenchmarkCompareSource.currentRoom();
    final kind = json['kind'] as String?;
    switch (kind) {
      case 'autoRig':
        return const BenchmarkCompareSource.autoRig();
      case 'checkpoint':
        final id = json['checkpointId'] as String?;
        if (id == null || id.isEmpty) {
          return const BenchmarkCompareSource.currentRoom();
        }
        return BenchmarkCompareSource.checkpoint(id);
      case 'publishedLayout':
        final id = json['publishedLayoutId'] as String?;
        if (id == null || id.isEmpty) {
          return const BenchmarkCompareSource.currentRoom();
        }
        return BenchmarkCompareSource.publishedLayout(
          id,
          title: json['publishedLayoutTitle'] as String?,
        );
      case 'currentRoom':
      default:
        return const BenchmarkCompareSource.currentRoom();
    }
  }
}
