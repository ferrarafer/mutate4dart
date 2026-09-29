import 'package:crap4dart/crap4dart.dart';
import 'package:mutate4dart/mutate4dart.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_project.dart';

Mutant _at(int line, {String file = 'lib/a.dart'}) => Mutant(
      file: file,
      line: line,
      offset: 0,
      length: 1,
      replacement: '-',
      operator: 'arithmetic',
    );

void main() {
  test('CoverageMap loads project-relative LCOV entries only', () {
    final root = createProject({
      'coverage/lcov.info': 'SF:lib/a.dart\nDA:1,3\nDA:2,0\nend_of_record\n'
          'SF:/pub-cache/x/lib/a.dart\nDA:2,9\nend_of_record\n',
    });
    addTearDown(() => root.deleteSync(recursive: true));
    final coverage =
        CoverageMap.load(p.join(root.path, 'coverage/lcov.info'), root.path);
    expect(coverage.isCovered('lib/a.dart', 1), isTrue);
    expect(coverage.isCovered('lib/a.dart', 2), isFalse);
    expect(coverage.isCovered('lib/b.dart', 1), isFalse);
  });

  test('keeps covered mutants only', () {
    const filter = MutantFilter(
      coverage: CoverageMap({
        'lib/a.dart': {1: 1, 2: 0},
      }),
    );
    expect(filter.apply([_at(1), _at(2), _at(3)]).map((m) => m.line), [1]);
  });

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
          filePath: 'lib/a.dart'),
      MethodInfo(
          className: '',
          methodName: 'never',
          startLine: 6,
          endLine: 9,
          filePath: 'lib/a.dart'),
    ];
    final kept = filter.apply(
      [_at(2), _at(3), _at(7), _at(8), _at(11)],
      methods: methods,
    );
    expect(kept.map((m) => m.line), [2, 3],
        reason: 'line 3 (unlisted, method ran) is kept; line 7 (hit 0), '
            'line 8 (unlisted, method never ran) and line 11 (outside '
            'methods) are not');
  });

  test('keeps mutants on changed lines only', () {
    final filter = MutantFilter(
      diff: DiffLineMap(projectRoot: '/p', addedLines: {
        'lib/a.dart': {2},
      }),
    );
    expect(filter.apply([_at(1), _at(2), _at(2, file: 'lib/b.dart')]),
        hasLength(1));
  });

  test('without filters everything is kept', () {
    expect(const MutantFilter().apply([_at(1), _at(2)]), hasLength(2));
  });
}
