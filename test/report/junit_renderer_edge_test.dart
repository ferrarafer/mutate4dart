import 'dart:io';

import 'package:mutate4dart/src/internal/mutate4dart_internal.dart';
import 'package:test/test.dart';

import '../test_project.dart';

const _source = 'bool f(int a) {\n  return a > 1 && "<&>" != "\x01";\n}\n';

MutantResult _result(MutantStatus status) => MutantResult(
  Mutant(
    file: 'lib/a.dart',
    line: 2,
    offset: _source.indexOf('>'),
    length: 1,
    replacement: '>=',
    operator: 'relational_boundary',
  ),
  status,
  const ['test/a_test.dart', 'test/b_test.dart'],
);

void main() {
  late Directory root;

  setUp(() => root = createProject({'lib/a.dart': _source}));
  tearDown(() => root.deleteSync(recursive: true));

  String render(List<MutantStatus> statuses) => JUnitRenderer(root.path).render(
    MutationReport.build([
      for (final s in statuses) _result(s),
    ], projectRoot: root.path),
  );

  test('a removed statement is named (removed)', () {
    writeFiles(root, {
      'lib/b.dart': 'void g(List<int> l) {\n  l.clear();\n}\n',
    });
    final removed = MutantResult(
      const Mutant(
        file: 'lib/b.dart',
        line: 2,
        offset: 24,
        length: 10,
        replacement: '',
        operator: 'remove_call',
      ),
      MutantStatus.killed,
      const [],
    );
    final xml = JUnitRenderer(
      root.path,
    ).render(MutationReport.build([removed], projectRoot: root.path));
    expect(
      xml,
      contains('name="line 2 remove_call: l.clear(); -&gt; (removed)"'),
    );
  });

  test('a report without mutants is an empty testsuites element', () {
    expect(
      render([]),
      contains(
        '<testsuites name="mutate4dart" '
        'tests="0" failures="0" errors="0" skipped="0">\n</testsuites>',
      ),
    );
  });
}
