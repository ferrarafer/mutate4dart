import 'package:mutate4dart/mutate4dart.dart';
import 'package:test/test.dart';

/// The mutants of [source] as `line:operator`, without the `collection`
/// operator: swapping `isEmpty` never touches promotion.
List<String> _ops(String source) => [
      for (final m in const MutantFinder(
        operators: {
          MutationOperator.equality,
          MutationOperator.logical,
          MutationOperator.negateCondition,
          MutationOperator.relationalBoundary,
          MutationOperator.removeNot,
        },
      ).find(source, file: 'lib/a.dart'))
        '${m.line}:${m.operator}',
    ];

void main() {
  test('null checks in a chain keep their logic', () {
    // Every mutation of this condition breaks the promotion of `x`.
    expect(
        _ops('void f(List? x) {\n'
            '  if (x == null || x.isEmpty) return;\n'
            '}\n'),
        isEmpty);
  });

  test('a lone null check is not flipped or negated', () {
    expect(
        _ops('void f(int? t, Map m) {\n'
            '  if (t != null) m[0] = t;\n'
            '}\n'),
        isEmpty);
  });

  test('is-tests promote too', () {
    expect(_ops('bool f(Object o) => o is String && o.isEmpty;\n'), isEmpty);
    expect(_ops('bool f(Object o) => !(o is int) || o > 0;\n'),
        isNot(contains('1:logical')));
  });

  test('parts without promotion are still mutated', () {
    expect(
      _ops('void f(int? x, int y) {\n'
          '  if (x == null || y > 0) return;\n'
          '  if (y > 1 && y < 9) return;\n'
          '}\n'),
      containsAll([
        '2:relational_boundary', // y > 0 -> y >= 0
        '3:negate_condition',
        '3:logical',
      ]),
    );
  });
}
