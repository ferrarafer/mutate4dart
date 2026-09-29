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

  test('one suite per file, one case per mutant, with counts', () {
    final xml = render(MutantStatus.values);
    expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>\n'));
    const counts = 'tests="4" failures="1" errors="0" skipped="1"';
    expect(xml, contains('<testsuites name="mutate4dart" $counts>'));
    expect(xml, contains('<testsuite name="lib/a.dart" $counts>'));
    expect(
      xml,
      contains(
        '<testcase classname="(top-level).f" '
        'name="line 2 relational_boundary: &gt; -&gt; &gt;=" '
        'file="lib/a.dart" line="2">',
      ),
    );
    expect('<testcase '.allMatches(xml), hasLength(4));
    expect(
      xml,
      contains(
        '<skipped message="Invalid: the mutant does not '
        'compile"/>',
      ),
    );
    expect(xml.trimRight(), endsWith('</testsuites>'));
  });

  test('a survivor fails with its diff, tests run and hint, escaped', () {
    final xml = render([MutantStatus.survived]);
    expect(xml, contains('<failure type="survived"'));
    expect(
      xml,
      contains(
        '- return a &gt; 1 &amp;&amp; &quot;&lt;&amp;&gt;&quot; != &quot;&quot;;',
      ),
    );
    expect(xml, contains('+ return a &gt;= 1'));
    expect(xml, contains('Tests run: test/a_test.dart, test/b_test.dart'));
    expect(xml, contains('Hint: Assert the result for the boundary value'));
    expect(xml, isNot(contains('\x01')));
  });
}
