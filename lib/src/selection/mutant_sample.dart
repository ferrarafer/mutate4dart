import 'dart:math';

/// A reproducible random subset of the planned mutants, for an unbiased
/// estimate of the score of a project too large to mutate fully.
class MutantSample {
  /// A sample of [count] mutants.
  const MutantSample.count(int this.count, {required this.seed})
    : percent = null;

  /// A sample of [percent] of the mutants (0 < percent <= 100).
  const MutantSample.percent(double this.percent, {required this.seed})
    : count = null;

  /// Parses `N` (a count >= 1) or `P%` (0 < P <= 100). Throws a
  /// [FormatException] otherwise.
  factory MutantSample.parse(String raw, {required int seed}) {
    if (raw.endsWith('%')) {
      final value = double.tryParse(raw.substring(0, raw.length - 1));
      if (value != null && value > 0 && value <= 100) {
        return MutantSample.percent(value, seed: seed);
      }
    } else {
      final value = int.tryParse(raw);
      if (value != null && value >= 1) {
        return MutantSample.count(value, seed: seed);
      }
    }
    throw FormatException(
      'expected a count >= 1 or a percentage in '
      '(0, 100] such as 20%, got "$raw"',
    );
  }

  /// Mutants to keep, or `null` for a percentage.
  final int? count;

  /// Share of mutants to keep, or `null` for a count.
  final double? percent;

  /// Seed of the random choice: the same seed, plan and Dart SDK pick
  /// the same mutants.
  final int seed;

  /// How many of [total] mutants the sample keeps (a percentage rounds
  /// up, so a non-empty plan keeps at least one).
  int sizeOf(int total) =>
      count != null ? min(count!, total) : (total * percent! / 100).ceil();

  /// A random subset of [items] of [sizeOf] their length, in their
  /// original order.
  List<T> pick<T>(List<T> items) {
    final indices = List.generate(items.length, (i) => i);
    final random = Random(seed);
    // Fisher-Yates, spelled out so the choice depends only on Random.
    for (var i = indices.length - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final swap = indices[i];
      indices[i] = indices[j];
      indices[j] = swap;
    }
    final kept = indices.take(sizeOf(items.length)).toList()..sort();
    return [for (final i in kept) items[i]];
  }
}
