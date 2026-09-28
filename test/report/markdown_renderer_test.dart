import 'dart:io';

import 'package:mutate4dart/mutate4dart.dart';
import 'package:test/test.dart';

import '../test_project.dart';

const _source = 'int f(int a) {\n  return a + 1;\n}\n'
    'int g(int b) {\n  return b * 2;\n}\n';

MutantResult _result(String op, MutantStatus status) {
  final offset = _source.indexOf(op);
  return MutantResult(
    Mutant(
      file: 'lib/a.dart',
      line: _source.substring(0, offset).split('\n').length,
      offset: offset,
      length: 1,
      replacement: op == '+' ? '-' : '/',
      operator: 'arithmetic',
    ),
    status,
    const ['test/a_test.dart'],
  );
}

void main() {
  late Directory root;

  setUp(() => root = createProject({'lib/a.dart': _source}));
  tearDown(() => root.deleteSync(recursive: true));

  String render(List<MutantResult> results) => MarkdownRenderer(root.path)
      .render(MutationReport.build(results, projectRoot: root.path));

  test('an empty run says there was nothing to mutate', () {
    expect(render(const []), contains('No mutants to run'));
  });

  test('a fully detected run has no table', () {
    final md = render([_result('+', MutantStatus.killed)]);
    expect(
        md,
        contains('**Score: 100.0%**, 1 mutants: 1 detected, '
            '0 survived, 0 invalid.'));
    expect(md, contains('Every mutant was detected'));
    expect(md, isNot(contains('| Score |')));
  });

  test('lists methods with survivors and the survivors as diffs', () {
    final md = render([
      _result('+', MutantStatus.survived),
      _result('*', MutantStatus.killed),
      _result('*', MutantStatus.invalid),
    ]);
    expect(md, startsWith('## Mutation testing (mutate4dart)'));
    expect(
        md,
        contains('**Score: 50.0%**, 3 mutants: 1 detected, '
            '1 survived, 1 invalid.'));
    expect(
        md,
        contains('| 0.0% | 1 | N/A | 1 | `(top-level).f` | '
            '`lib/a.dart:1` |'));
    expect(md, contains('1 more method(s) had every mutant detected.'));
    expect(md, contains('<summary>Survivors: changes no test detects (1)'));
    expect(md, contains('```diff\n- return a + 1;\n+ return a - 1;\n```'));
  });
}
