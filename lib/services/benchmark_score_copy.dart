import 'benchmark_validator.dart';

/// Plain-language Benchmark score grades and blurbs for non-technical users.
enum BenchmarkScoreDomain { airflow, lighting, ergonomics, spatial }

class BenchmarkScoreCopy {
  BenchmarkScoreCopy._();

  static String shortLabel(BenchmarkScoreDomain domain) => switch (domain) {
        BenchmarkScoreDomain.airflow => 'Air',
        BenchmarkScoreDomain.lighting => 'Light',
        BenchmarkScoreDomain.ergonomics => 'Comfort',
        BenchmarkScoreDomain.spatial => 'Space',
      };

  static String blurb(BenchmarkScoreDomain domain) => switch (domain) {
        BenchmarkScoreDomain.airflow =>
          'How freely air can move through this layout (rough estimate — not a lab test).',
        BenchmarkScoreDomain.lighting =>
          'How usable light is at desks and seats (rough estimate — not a light meter).',
        BenchmarkScoreDomain.ergonomics =>
          'How easy it is to sit, walk, and reach things (rough estimate — not a medical score).',
        BenchmarkScoreDomain.spatial =>
          'How much clear walking room you have from the door and between furniture.',
      };

  static double passBar(BenchmarkScoreDomain domain) => switch (domain) {
        BenchmarkScoreDomain.airflow => BenchmarkValidator.airflowPass,
        BenchmarkScoreDomain.lighting => BenchmarkValidator.lightingPass,
        BenchmarkScoreDomain.ergonomics => BenchmarkValidator.ergonomicsPass,
        BenchmarkScoreDomain.spatial => BenchmarkValidator.spatialUtilPass,
      };

  /// Needs work / OK / Good / Strong from 0–100 vs domain pass bar.
  static String gradeWord(double score, BenchmarkScoreDomain domain) {
    final s = score.clamp(0, 100);
    final pass = passBar(domain);
    if (s < pass) return 'Needs work';
    if (s < 75) return 'OK';
    if (s < 90) return 'Good';
    return 'Strong';
  }

  static String chromeLine({
    required BenchmarkScoreDomain domain,
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

  static BenchmarkScoreDomain domainFromBenchmarkMode(String mode) =>
      switch (mode) {
        'lighting' => BenchmarkScoreDomain.lighting,
        'ergonomics' => BenchmarkScoreDomain.ergonomics,
        'spatial' => BenchmarkScoreDomain.spatial,
        _ => BenchmarkScoreDomain.airflow,
      };
}
