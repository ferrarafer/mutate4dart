import 'package:mutate4dart/mutate4dart.dart';
import 'package:test/test.dart';

/// The mutated versions of [source] (whole file text per mutant).
List<String> mutate(String source, {Set<MutationOperator>? only}) {
  final mutants =
      MutantFinder(operators: only).find(source, file: 'lib/a.dart');
  return [for (final m in mutants) m.apply(source)];
}

void main() {
  test('negates if, while and ?: conditions with their original text', () {
    const src = 'int f(int a) {\n'
        '  while (a > 9) a--;\n'
        '  if (a  >  1) return 1;\n'
        '  return a > 0 ? 1 : 0;\n'
        '}\n';
    final mutated = mutate(src, only: {MutationOperator.negateCondition});
    expect(mutated, hasLength(3));
    expect(mutated[0], contains('while (!(a > 9))'));
    expect(mutated[1], contains('if (!(a  >  1))'), reason: 'keeps spacing');
    expect(mutated[2], contains('!(a > 0) ? 1 : 0'));
  });

  test('does not negate conditions other operators already cover', () {
    const src = 'void f(int a, bool b) {\n'
        '  if (a == 1) return;\n'
        '  if ((a != 2)) return;\n'
        '  if (!b) return;\n'
        '}\n';
    expect(mutate(src, only: {MutationOperator.negateCondition}), isEmpty);
  });

  test('skips annotations, asserts and if-case patterns', () {
    const src = '@Deprecated(1 > 0 ? "a" : "b")\n'
        'void f(int a, Object o) {\n'
        '  assert(a > 0);\n'
        '  if (o case int _) return;\n'
        '}\n';
    expect(mutate(src), isEmpty);
  });

  test('skips growable: booleans but keeps other named booleans', () {
    const src = 'List<int> f(Iterable<int> xs) {\n'
        '  g(sorted: true);\n'
        '  return xs.toList(growable: false);\n'
        '}\n';
    expect(mutate(src, only: {MutationOperator.booleanLiteral}), [
      'List<int> f(Iterable<int> xs) {\n'
          '  g(sorted: false);\n'
          '  return xs.toList(growable: false);\n'
          '}\n',
    ]);
  });
}
