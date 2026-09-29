import 'package:crap_dart/crap_dart.dart';
import 'package:mutate4dart/src/internal/mutate4dart_internal.dart';
import 'package:test/test.dart';

Mutant _at(int line, {String file = 'lib/a.dart'}) => Mutant(
  file: file,
  line: line,
  offset: 0,
  length: 1,
  replacement: '-',
  operator: 'arithmetic',
);

void main() {
  test('a line the LCOV does not list is covered when its method ran', () {
    const filter = MutantFilter(
      coverage: CoverageMap({
        'lib/a.dart': {2: 1, 7: 0},
      }),
    );
    const methods = [
      MethodInfo(
        className: '',
        methodName: 'ran',
        startLine: 1,
        endLine: 4,
        filePath: 'lib/a.dart',
      ),
      MethodInfo(
        className: '',
        methodName: 'never',
        startLine: 6,
        endLine: 9,
        filePath: 'lib/a.dart',
      ),
    ];
    final kept = filter.apply([
      _at(2),
      _at(3),
      _at(7),
      _at(8),
      _at(11),
    ], methods: methods);
    expect(
      kept.map((m) => m.line),
      [2, 3],
      reason:
          'line 3 (unlisted, method ran) is kept; line 7 (hit 0), '
          'line 8 (unlisted, method never ran) and line 11 (outside '
          'methods) are not',
    );
  });
}
