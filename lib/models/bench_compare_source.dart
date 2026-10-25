/// What Bench scores on one side of the compare pair.
enum BenchCompareKind { currentRig, checkpoint, autoRig }

class BenchCompareSource {
  final BenchCompareKind kind;
  final String? checkpointId;

  const BenchCompareSource.currentRig()
      : kind = BenchCompareKind.currentRig,
        checkpointId = null;

  const BenchCompareSource.autoRig()
      : kind = BenchCompareKind.autoRig,
        checkpointId = null;

  const BenchCompareSource.checkpoint(String id)
      : kind = BenchCompareKind.checkpoint,
        checkpointId = id;

  bool get isAutoRig => kind == BenchCompareKind.autoRig;
  bool get isCurrentRig => kind == BenchCompareKind.currentRig;
  bool get isCheckpoint => kind == BenchCompareKind.checkpoint;

  @override
  bool operator ==(Object other) =>
      other is BenchCompareSource &&
      other.kind == kind &&
      other.checkpointId == checkpointId;

  @override
  int get hashCode => Object.hash(kind, checkpointId);

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        if (checkpointId != null) 'checkpointId': checkpointId,
      };

  factory BenchCompareSource.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const BenchCompareSource.currentRig();
    final kind = json['kind'] as String?;
    switch (kind) {
      case 'autoRig':
        return const BenchCompareSource.autoRig();
      case 'checkpoint':
        final id = json['checkpointId'] as String?;
        if (id == null || id.isEmpty) return const BenchCompareSource.currentRig();
        return BenchCompareSource.checkpoint(id);
      case 'currentRig':
      default:
        return const BenchCompareSource.currentRig();
    }
  }
}
