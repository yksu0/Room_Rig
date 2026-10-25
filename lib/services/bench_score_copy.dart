import 'benchmark_validator.dart';

/// Plain-language Bench score grades and blurbs for non-technical users.
enum BenchScoreDomain { airflow, lighting, ergonomics, spatial }

class BenchScoreCopy {
  BenchScoreCopy._();

  static String shortLabel(BenchScoreDomain domain) => switch (domain) {
        BenchScoreDomain.airflow => 'Air',
        BenchScoreDomain.lighting => 'Light',
        BenchScoreDomain.ergonomics => 'Comfort',
        BenchScoreDomain.spatial => 'Space',
      };

  static String blurb(BenchScoreDomain domain) => switch (domain) {
        BenchScoreDomain.airflow =>
          'How freely air can move through this layout (rough estimate — not a lab test).',
        BenchScoreDomain.lighting =>
          'How usable light is at desks and seats (rough estimate — not a light meter).',
        BenchScoreDomain.ergonomics =>
          'How easy it is to sit, walk, and reach things (rough estimate — not a medical score).',
        BenchScoreDomain.spatial =>
          'How much clear walking room you have from the door and between furniture.',
      };

  static double passBar(BenchScoreDomain domain) => switch (domain) {
        BenchScoreDomain.airflow => BenchmarkValidator.airflowPass,
        BenchScoreDomain.lighting => BenchmarkValidator.lightingPass,
        BenchScoreDomain.ergonomics => BenchmarkValidator.ergonomicsPass,
        BenchScoreDomain.spatial => BenchmarkValidator.spatialUtilPass,
      };

  /// Needs work / OK / Good / Strong from 0–100 vs domain pass bar.
  static String gradeWord(double score, BenchScoreDomain domain) {
    final s = score.clamp(0, 100);
    final pass = passBar(domain);
    if (s < pass) return 'Needs work';
    if (s < 75) return 'OK';
    if (s < 90) return 'Good';
    return 'Strong';
  }

  static String chromeLine({
    required BenchScoreDomain domain,
    required double score,
  }) =>
      '${shortLabel(domain)} · ${gradeWord(score, domain)} · ${score.round()}';

  static String deltaVsRoom(double score, double? previous) {
    if (previous == null) return '';
    final d = score - previous;
    if (d.abs() < 0.5) return 'Same as your room';
    final n = d.round();
    return n >= 0 ? '+$n vs your room' : '$n vs your room';
  }

  static BenchScoreDomain domainFromBenchmarkMode(String mode) =>
      switch (mode) {
        'lighting' => BenchScoreDomain.lighting,
        'ergonomics' => BenchScoreDomain.ergonomics,
        'spatial' => BenchScoreDomain.spatial,
        _ => BenchScoreDomain.airflow,
      };
}
