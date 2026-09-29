import 'dart:io';

import 'package:mutate4dart/src/internal/mutate4dart_internal.dart';
import 'package:test/test.dart';

import 'cli_test_utils.dart';

void main() {
  late Directory root;

  setUp(() => root = createCalcProject());
  tearDown(() => root.deleteSync(recursive: true));

  test('--version and --help', () async {
    expect((await runCli(root, ['--version'])).stdout, 'mutate4dart 0.12.1\n');
    final help = await runCli(root, ['--help']);
    expect(help.exitCode, ExitCodes.success);
    expect(help.stdout, contains('--test-command'));
  });

  test('dry run lists covered mutants with their tests', () async {
    final run = await runCli(root, ['--dry-run']);
    expect(run.exitCode, ExitCodes.success);
    // Line 2 only (line 3 is uncovered); other.dart has no tests.
    expect(run.stdout, contains('lib/calc.dart:2 [relational_boundary] -> >='));
    expect(run.stdout, contains('lib/calc.dart:2 [arithmetic] -> -'));
    expect(run.stdout, isNot(contains('lib/calc.dart:3')));
    expect(run.stderr, contains('(1 without tests importing their file)'));
  });

  test('runs mutants and reports survivors per method', () async {
    final fake = killWhen('a - b');
    final run = await runCli(root, ['lib/calc.dart'], fake: fake);
    expect(run.exitCode, ExitCodes.success);
    expect(fake.calls.first.command, 'dart test test/calc_test.dart');
    expect(run.stdout, contains('(top-level).add'));
    expect(run.stdout, contains('Survivors (the tests miss these changes):'));
    expect(run.stdout, contains('+ if (a >= 0) return a + b;'));
    expect(run.stdout, contains('Mutation score: 33.3% (3 mutants)'));
    expect(run.stderr, contains('[1/3] lib/calc.dart:2'));
    expect(
      File('${root.path}/lib/calc.dart').readAsStringSync(),
      contains('if (a > 0) return a + b;'),
    );
  });

  test('--operators and --max-mutants narrow the plan', () async {
    final run = await runCli(root, [
      '--dry-run',
      '--operators',
      'arithmetic,relational_boundary',
      '--max-mutants',
      '1',
    ]);
    expect(run.stdout.trim().split('\n'), hasLength(1));
  });

  test('--jobs 1 mutates in place and restores the file', () async {
    final fake = killWhen('a - b');
    final run = await runCli(root, ['--jobs', '1'], fake: fake);
    expect(run.stdout, contains('Mutation score: 33.3% (3 mutants)'));
    expect(fake.cwd, root.path);
  });
}
