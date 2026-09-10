import '../models/room_model.dart';
import '../models/saved_room.dart';
import '../widgets/bench_panel_scaffold.dart';

/// Side-by-side comparison of two saved lots.
class RoomCompareResult {
  final SavedRoom a;
  final SavedRoom b;
  final String layoutDiff;
  final Map<String, double> scoresA;
  final Map<String, double> scoresB;

  const RoomCompareResult({
    required this.a,
    required this.b,
    required this.layoutDiff,
    required this.scoresA,
    required this.scoresB,
  });

  double delta(String key) => (scoresB[key] ?? 0) - (scoresA[key] ?? 0);
}

class RoomCompare {
  RoomCompare._();

  static Map<String, double> estimateScores(List<FurnitureItem> furniture) {
    // Lightweight Hub-style estimate from footprint impacts (matches simulated feel).
    double sum(String field) {
      var total = 55.0;
      for (final f in furniture) {
        switch (field) {
          case 'airflow':
            total += f.airflowImpact * 4;
            break;
          case 'lighting':
            total += f.lightingImpact * 4;
            break;
          case 'ergonomics':
            total += f.ergonomicsImpact * 4;
            break;
        }
      }
      return total.clamp(20.0, 98.0);
    }

    final airflow = sum('airflow');
    final lighting = sum('lighting');
    final ergonomics = sum('ergonomics');
    final spatial = (70.0 - furniture.length * 1.2).clamp(25.0, 95.0);
    final overall = (airflow + lighting + ergonomics + spatial) / 4;
    return {
      'overall': overall,
      'airflow': airflow,
      'lighting': lighting,
      'ergonomics': ergonomics,
      'spatial': spatial,
    };
  }

  static RoomCompareResult compare(SavedRoom a, SavedRoom b) {
    return RoomCompareResult(
      a: a,
      b: b,
      layoutDiff: summarizeLayoutDiff(a.furniture, b.furniture),
      scoresA: estimateScores(a.furniture),
      scoresB: estimateScores(b.furniture),
    );
  }
}
