import 'package:mutate4dart/src/internal/mutate4dart_internal.dart';
import 'package:test/test.dart';

/// `line:operator` of the mutants of [source], with `!` for ignored ones.
List<String> find(String source) => [
  for (final m in const MutantFinder().find(source, file: 'lib/a.dart'))
    '${m.line}:${m.operator}${m.ignored ? '!' : ''}',
];

void main() {
  test('a trailing pragma covers its line, a lone one the next line', () {
    const src =
        'int f(int a, int b) {\n'
        '  if (a > b) return 1; // mutate4dart: ignore\n'
        '  // mutate4dart: ignore\n'
        '  a += b;\n'
        '  return a + 1;\n'
        '}\n';
    expect(find(src), [
      '2:negate_condition!',
      '2:relational_boundary!',
      '4:assignment!',
      '5:arithmetic',
    ]);
  });

  test('operator ids narrow the pragma; the pragma is lenient on form', () {
    const src =
        'int f(int a, int b) {\n'
        '  //mutate4dart:ignore relational_boundary, negate_condition\n'
        '  if (a > b) return a + 1;\n'
        '  /// mutate4dart: ignore arithmetic\n'
        '  return a + b; // mutate4dart: ignore bogus\n'
        '}\n';
    expect(find(src), [
      '3:negate_condition!',
      '3:relational_boundary!',
      '3:arithmetic',
      '5:arithmetic!',
    ]);
  });

  test('other comments and unrelated mutate4dart comments are not pragmas', () {
    const src =
        'int f(int a) {\n'
        '  // mutate4dart: see the README\n'
        '  return a + 1; // ignore: unused\n'
        '}\n'
        '// mutate4dart: ignore\n';
    expect(find(src), ['3:arithmetic']);
  });
}
