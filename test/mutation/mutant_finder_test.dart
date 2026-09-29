import 'package:mutate4dart/src/internal/mutate4dart_internal.dart';
import 'package:test/test.dart';

/// The mutated versions of [source] (whole file text per mutant).
List<String> mutate(String source, {Set<MutationOperator>? only}) {
  final mutants = MutantFinder(
    operators: only,
  ).find(source, file: 'lib/a.dart');
  return [for (final m in mutants) m.apply(source)];
}

void main() {
  test('swaps relational boundaries, equality and logical operators', () {
    const src = 'bool f(int a, int b) => a < b && a != 0;\n';
    expect(mutate(src, only: {MutationOperator.relationalBoundary}), [
      'bool f(int a, int b) => a <= b && a != 0;\n',
    ]);
    expect(mutate(src, only: {MutationOperator.equality}), [
      'bool f(int a, int b) => a < b && a == 0;\n',
    ]);
    expect(mutate(src, only: {MutationOperator.logical}), [
      'bool f(int a, int b) => a < b || a != 0;\n',
    ]);
  });

  test('swaps arithmetic, but not string concatenation', () {
    expect(
      mutate(
        'int f(int a) => a * 2 + 1;\n',
        only: {MutationOperator.arithmetic},
      ),
      ['int f(int a) => a / 2 + 1;\n', 'int f(int a) => a * 2 - 1;\n'],
    );
    expect(
      mutate(
        "String f(String a) => a + '!';\n",
        only: {MutationOperator.arithmetic},
      ),
      isEmpty,
    );
  });

  test('swaps compound assignments and increments', () {
    const src = 'void f(int a) { a += 2; a++; --a; }\n';
    expect(mutate(src, only: {MutationOperator.assignment}), [
      'void f(int a) { a -= 2; a++; --a; }\n',
    ]);
    expect(mutate(src, only: {MutationOperator.increment}), [
      'void f(int a) { a += 2; a--; --a; }\n',
      'void f(int a) { a += 2; a++; ++a; }\n',
    ]);
  });

  test('flips booleans, removes ! and keeps the ?? fallback', () {
    expect(
      mutate('bool f() => true;\n', only: {MutationOperator.booleanLiteral}),
      ['bool f() => false;\n'],
    );
    expect(
      mutate('bool f(bool a) => !a;\n', only: {MutationOperator.removeNot}),
      ['bool f(bool a) => a;\n'],
    );
    expect(
      mutate(
        'int f(int? a) => a ?? 0;\n',
        only: {MutationOperator.nullCoalescing},
      ),
      ['int f(int? a) => 0;\n'],
    );
  });

  test('reports 1-based lines in source order', () {
    const src = 'int f(int a) {\n  return a + 1;\n}\nbool g() => true;\n';
    final mutants = const MutantFinder().find(src, file: 'lib/a.dart');
    expect(
      [for (final m in mutants) (m.line, m.operator)],
      [(2, 'arithmetic'), (4, 'boolean_literal')],
    );
    expect(mutants.first.file, 'lib/a.dart');
    expect(mutants.first.original(src), '+');
    expect(mutants.first.toString(), 'lib/a.dart:2 [arithmetic] -> -');
  });
}
