import 'package:mutate4dart/src/internal/mutate4dart_internal.dart';
import 'package:test/test.dart';

/// The `remove_call` mutants of [source] (whole file text per mutant).
List<String> removeCalls(String source) {
  final mutants = const MutantFinder(
    operators: {MutationOperator.removeCall},
  ).find(source, file: 'lib/a.dart');
  return [for (final m in mutants) m.apply(source)];
}

void main() {
  test('removes call statements in blocks, keeping the line count', () {
    const src =
        'Future<void> f(Repo r, void Function() cb) async {\n'
        '  r.save(\n'
        '    1,\n'
        '  );\n'
        '  cb();\n'
        '  await r.sync();\n'
        '}\n';
    expect(removeCalls(src), [
      'Future<void> f(Repo r, void Function() cb) async {\n'
          '  \n\n\n'
          '  cb();\n'
          '  await r.sync();\n'
          '}\n',
      'Future<void> f(Repo r, void Function() cb) async {\n'
          '  r.save(\n'
          '    1,\n'
          '  );\n'
          '  \n'
          '  await r.sync();\n'
          '}\n',
      'Future<void> f(Repo r, void Function() cb) async {\n'
          '  r.save(\n'
          '    1,\n'
          '  );\n'
          '  cb();\n'
          '  \n'
          '}\n',
    ]);
  });

  test('removes calls in case bodies', () {
    const src =
        'void f(int a, Repo r) {\n'
        '  switch (a) {\n'
        '    case 1:\n'
        '      r.save(a);\n'
        '  }\n'
        '}\n';
    expect(removeCalls(src), [
      'void f(int a, Repo r) {\n'
          '  switch (a) {\n'
          '    case 1:\n'
          '      \n'
          '  }\n'
          '}\n',
    ]);
  });

  test('keeps super calls, logging, non-call statements and if bodies', () {
    const src =
        'void f(bool b, Repo r, int x) {\n'
        '  super.dispose();\n'
        '  print(x);\n'
        '  debugPrint(x);\n'
        '  x = 2;\n'
        '  x++;\n'
        '  if (b) r.save(x);\n'
        '  while (b) r.save(x);\n'
        '}\n';
    expect(removeCalls(src), isEmpty);
  });

  test('is reported at the statement line and listed with the others', () {
    const src = 'void f(Repo r) {\n  r.save(1 + 2);\n}\n';
    final mutants = const MutantFinder().find(src, file: 'lib/a.dart');
    expect(
      [for (final m in mutants) (m.line, m.operator)],
      [(2, 'remove_call'), (2, 'arithmetic')],
    );
    expect(mutants.first.original(src), 'r.save(1 + 2);');
    expect(mutants.first.replacement, '');
  });
}
