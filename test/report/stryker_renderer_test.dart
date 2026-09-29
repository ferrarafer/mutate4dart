import 'dart:convert';
import 'dart:io';

import 'package:mutate4dart/src/internal/mutate4dart_internal.dart';
import 'package:test/test.dart';

import '../test_project.dart';

const _source = "String f(int a) {\n  return a > 1 ? '</script>' : '';\n}\n";

MutantResult _result(MutantStatus status, {List<String>? tests}) {
  final offset = _source.indexOf('>');
  return MutantResult(
    Mutant(
      file: 'lib/a.dart',
      line: 2,
      offset: offset,
      length: 1,
      replacement: '>=',
      operator: 'relational_boundary',
    ),
    status,
    tests ?? const ['test/a_test.dart'],
  );
}

void main() {
  late Directory root;

  setUp(() => root = createProject({'lib/a.dart': _source}));
  tearDown(() => root.deleteSync(recursive: true));

  MutationReport build(List<MutantResult> results) =>
      MutationReport.build(results, projectRoot: root.path);

  test('json follows the Stryker schema with 1-based positions', () {
    final json =
        jsonDecode(
              StrykerRenderer(root.path).json(
                build([
                  _result(MutantStatus.killed),
                  _result(
                    MutantStatus.invalid,
                    tests: ['test/a_test.dart', 'test/b.dart'],
                  ),
                ]),
              ),
            )
            as Map<String, dynamic>;
    expect(json['schemaVersion'], '2');
    expect(json['thresholds'], {'high': 80, 'low': 60});
    expect(json['projectRoot'], root.path);
    final file = (json['files'] as Map)['lib/a.dart'] as Map<String, dynamic>;
    expect(file['language'], 'dart');
    expect(file['source'], _source);
    final mutants = file['mutants'] as List;
    expect(mutants.first, {
      'id': '1',
      'mutatorName': 'relational_boundary',
      'replacement': '>=',
      'location': {
        'start': {'line': 2, 'column': 12},
        'end': {'line': 2, 'column': 13},
      },
      'status': 'Killed',
      'coveredBy': ['test/a_test.dart'],
      'killedBy': ['test/a_test.dart'],
    });
    expect(mutants[1]['id'], '2');
    expect(mutants[1]['status'], 'CompileError');
    expect(mutants[1], isNot(contains('killedBy')));
    expect((json['testFiles'] as Map).keys, [
      'test/a_test.dart',
      'test/b.dart',
    ]);
    expect((json['testFiles'] as Map)['test/b.dart'], {
      'tests': [
        {'id': 'test/b.dart', 'name': 'test/b.dart'},
      ],
    });
  });

  test('maps survived and timeout statuses', () {
    final json =
        jsonDecode(
              StrykerRenderer(root.path).json(
                build([
                  _result(MutantStatus.survived),
                  _result(MutantStatus.timeout),
                ]),
              ),
            )
            as Map<String, dynamic>;
    final mutants = ((json['files'] as Map)['lib/a.dart'] as Map)['mutants'];
    expect((mutants as List).map((m) => m['status']), ['Survived', 'Timeout']);
    expect(
      mutants[0],
      isNot(contains('killedBy')),
      reason: 'a survivor was not killed, even by a single test file',
    );
    expect(mutants[1]['killedBy'], ['test/a_test.dart']);
  });
}
