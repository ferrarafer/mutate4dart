import 'dart:convert';
import 'dart:io';

import 'package:mutate4dart/mutate4dart.dart';
import 'package:test/test.dart';

import 'cli_test_utils.dart';

void main() {
  late Directory root;

  setUp(() => root = createCalcProject());
  tearDown(() => root.deleteSync(recursive: true));

  test('json output and --threshold', () async {
    final run = await runCli(root, ['--format', 'json', '--threshold', '50'],
        fake: killWhen('a - b'));
    expect(run.exitCode, ExitCodes.thresholdMissed);
    final json = jsonDecode(run.stdout) as Map<String, dynamic>;
    final method = (json['methods'] as List).single as Map<String, dynamic>;
    expect(method['method'], '(top-level).add');
    expect((method['mutants'] as List).map((m) => m['status']),
        containsAll(['killed', 'survived']));
  });

  test('--format stryker and html write the Stryker report', () async {
    final stryker =
        await runCli(root, ['--format', 'stryker'], fake: killWhen('a - b'));
    final json = jsonDecode(stryker.stdout) as Map<String, dynamic>;
    final mutants =
        ((json['files'] as Map)['lib/calc.dart'] as Map)['mutants'] as List;
    expect(
        mutants.map((m) => m['status']), containsAll(['Killed', 'Survived']));
    expect(mutants.first['coveredBy'], ['test/calc_test.dart']);
    final html =
        await runCli(root, ['--format', 'html'], fake: killWhen('a - b'));
    expect(html.stdout, startsWith('<!DOCTYPE html>'));
    expect(html.stdout, contains('mutation-test-report-app'));
  });

  test('--format markdown writes the report as Markdown', () async {
    final run =
        await runCli(root, ['--format', 'markdown'], fake: killWhen('a - b'));
    expect(run.stdout, startsWith('## Mutation testing (mutate4dart)'));
    expect(run.stdout, contains('```diff'));
  });

  test('--format junit writes JUnit XML with survivors as failures', () async {
    final run =
        await runCli(root, ['--format', 'junit'], fake: killWhen('a - b'));
    expect(run.stdout, startsWith('<?xml'));
    expect(run.stdout, contains('<testsuite name="lib/calc.dart"'));
    expect(run.stdout, contains('<failure type="survived"'));
  });
}
