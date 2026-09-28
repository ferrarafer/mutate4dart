import 'dart:convert';
import 'dart:io';

import 'package:mutate4dart/mutate4dart.dart';
import 'package:test/test.dart';

import '../test_project.dart';

const _source = 'int top = 1 + 2;\n'
    'int f(int a) {\n'
    '  return a + 1;\n'
    '}\n';

MutantResult _at(int line, MutantStatus status) {
  final offset = _source.split('\n').take(line - 1).join('\n').length +
      (line > 1 ? 1 : 0) +
      _source.split('\n')[line - 1].indexOf('+');
  return MutantResult(
    Mutant(
      file: 'lib/a.dart',
      line: line,
      offset: offset,
      length: 1,
      replacement: '-',
      operator: 'arithmetic',
    ),
    status,
    const ['test/a_test.dart'],
  );
}

void main() {
  late Directory root;

  setUp(() => root = createProject({
        'lib/a.dart': _source,
        'coverage/lcov.info': 'SF:lib/a.dart\nDA:3,1\nend_of_record\n',
      }));
  tearDown(() => root.deleteSync(recursive: true));

  MutationReport build(List<MutantResult> results) => MutationReport.build(
        results,
        projectRoot: root.path,
        lcovPath: '${root.path}/coverage/lcov.info',
      );

  test('groups per method, top-level code separately', () {
    final report = build([
      _at(3, MutantStatus.killed),
      _at(3, MutantStatus.survived),
      _at(3, MutantStatus.invalid),
      _at(1, MutantStatus.timeout),
    ]);
    final byName = {for (final m in report.methods) m.name: m};
    final f = byName['(top-level).f']!;
    expect(f.scored, 2, reason: 'invalid mutants are not scored');
    expect(f.score, 50);
    expect(f.crap, 1.0);
    expect(f.complexity, 1);
    expect(byName['(top-level)']!.score, 100, reason: 'timeout = detected');
    expect(report.score, closeTo(66.7, 0.1));
  });

  test('an all-invalid method and an empty report have no score', () {
    expect(build([_at(3, MutantStatus.invalid)]).methods.single.score, isNull);
    expect(build(const []).score, isNull);
  });

  test('console lists survivors with original and mutated lines', () {
    final text = ReportRenderer(root.path)
        .console(build([_at(3, MutantStatus.survived)]));
    expect(text, contains('  0.0%'));
    expect(text, contains('(top-level).f'));
    expect(
        text,
        contains('lib/a.dart:3 [arithmetic]\n'
            '    - return a + 1;\n'
            '    + return a - 1;'));
    expect(text, contains('Mutation score: 0.0% (1 mutants)'));
  });

  test('json carries per-mutant status', () {
    final json = jsonDecode(ReportRenderer(root.path)
        .json(build([_at(3, MutantStatus.killed)]))) as Map<String, dynamic>;
    expect(json['score'], 100.0);
    final mutant =
        ((json['methods'] as List).single as Map)['mutants'].single as Map;
    expect(mutant, {
      'line': 3,
      'operator': 'arithmetic',
      'replacement': '-',
      'status': 'killed',
      'tests': ['test/a_test.dart'],
    });
  });
}
