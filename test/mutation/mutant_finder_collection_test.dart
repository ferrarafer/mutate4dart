import 'package:mutate4dart/mutate4dart.dart';
import 'package:test/test.dart';

/// The mutated versions of [source] (whole file text per mutant).
List<String> mutate(String source, {Set<MutationOperator>? only}) {
  final mutants =
      MutantFinder(operators: only).find(source, file: 'lib/a.dart');
  return [for (final m in mutants) m.apply(source)];
}

void main() {
  test('swaps isEmpty/isNotEmpty and first/last on any target', () {
    const src = 'bool f(List<int> xs, Box b) =>\n'
        '    xs.isEmpty || b.items.isNotEmpty || xs.first == g().last;\n';
    expect(mutate(src, only: {MutationOperator.collection}), [
      'bool f(List<int> xs, Box b) =>\n'
          '    xs.isNotEmpty || b.items.isNotEmpty || xs.first == g().last;\n',
      'bool f(List<int> xs, Box b) =>\n'
          '    xs.isEmpty || b.items.isEmpty || xs.first == g().last;\n',
      'bool f(List<int> xs, Box b) =>\n'
          '    xs.isEmpty || b.items.isNotEmpty || xs.last == g().last;\n',
      'bool f(List<int> xs, Box b) =>\n'
          '    xs.isEmpty || b.items.isNotEmpty || xs.first == g().first;\n',
    ]);
  });

  test('swaps any/every on calls with a target only', () {
    const src = 'bool f(List<int> xs) => xs.any(p) && every(xs);\n';
    expect(mutate(src, only: {MutationOperator.collection}),
        ['bool f(List<int> xs) => xs.every(p) && every(xs);\n']);
  });

  test('turns ??= into a plain assignment', () {
    expect(
        mutate('void f(int? a) { a ??= 1; }\n',
            only: {MutationOperator.assignment}),
        ['void f(int? a) { a = 1; }\n']);
  });

  test('every operator has a stable id and a hint', () {
    for (final operator in MutationOperator.values) {
      expect(MutationOperator.byId(operator.id), operator);
      expect(operator.hint, isNotEmpty);
    }
    expect(MutationOperator.byId('nope'), isNull);
  });
}
