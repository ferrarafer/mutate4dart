import 'package:mutate4dart/src/internal/mutate4dart_internal.dart';
import 'package:test/test.dart';

void main() {
  final items = List.generate(100, (i) => i);

  test('parses a count or a percentage', () {
    expect(MutantSample.parse('7', seed: 1).count, 7);
    expect(MutantSample.parse('12.5%', seed: 1).percent, 12.5);
    for (final bad in ['0', '-3', 'x', '0%', '101%', '%', '2.5']) {
      expect(
        () => MutantSample.parse(bad, seed: 1),
        throwsFormatException,
        reason: bad,
      );
    }
  });

  test('sizes: counts cap at the total, percentages round up', () {
    expect(const MutantSample.count(7, seed: 1).sizeOf(100), 7);
    expect(const MutantSample.count(7, seed: 1).sizeOf(3), 3);
    expect(const MutantSample.percent(10, seed: 1).sizeOf(95), 10);
    expect(const MutantSample.percent(1, seed: 1).sizeOf(3), 1);
    expect(const MutantSample.percent(50, seed: 1).sizeOf(0), 0);
  });

  test('picks a seeded subset in the original order', () {
    final a = const MutantSample.count(10, seed: 42).pick(items);
    expect(a, hasLength(10));
    expect(a.toSet(), hasLength(10));
    expect(a, orderedEquals([...a]..sort()));
    expect(
      const MutantSample.count(10, seed: 42).pick(items),
      a,
      reason: 'same seed, same sample',
    );
    expect(const MutantSample.count(10, seed: 43).pick(items), isNot(a));
    expect(a, isNot(List.generate(10, (i) => i)), reason: 'not a prefix');
    expect(const MutantSample.percent(100, seed: 1).pick(items), items);
  });
}
