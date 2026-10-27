/// What Benchmark scores on one side of the compare pair.
enum BenchmarkCompareKind { currentRoom, checkpoint, autoRig }

class BenchmarkCompareSource {
  final BenchmarkCompareKind kind;
  final String? checkpointId;

  const BenchmarkCompareSource.currentRoom()
      : kind = BenchmarkCompareKind.currentRoom,
        checkpointId = null;

  const BenchmarkCompareSource.autoRig()
      : kind = BenchmarkCompareKind.autoRig,
        checkpointId = null;

  const BenchmarkCompareSource.checkpoint(String id)
      : kind = BenchmarkCompareKind.checkpoint,
        checkpointId = id;

  bool get isAutoRig => kind == BenchmarkCompareKind.autoRig;
  bool get isCurrentRoom => kind == BenchmarkCompareKind.currentRoom;
  bool get isCheckpoint => kind == BenchmarkCompareKind.checkpoint;

  @override
  bool operator ==(Object other) =>
      other is BenchmarkCompareSource &&
      other.kind == kind &&
      other.checkpointId == checkpointId;

  @override
  int get hashCode => Object.hash(kind, checkpointId);

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        if (checkpointId != null) 'checkpointId': checkpointId,
      };

  factory BenchmarkCompareSource.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const BenchmarkCompareSource.currentRoom();
    final kind = json['kind'] as String?;
    switch (kind) {
      case 'autoRig':
        return const BenchmarkCompareSource.autoRig();
      case 'checkpoint':
        final id = json['checkpointId'] as String?;
        if (id == null || id.isEmpty) return const BenchmarkCompareSource.currentRoom();
        return BenchmarkCompareSource.checkpoint(id);
      case 'currentRoom':
      default:
        return const BenchmarkCompareSource.currentRoom();
    }
  }
}
