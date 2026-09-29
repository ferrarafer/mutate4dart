import 'dart:io';

import 'package:test/test.dart';

import '../fake_runner.dart';
import '../test_project.dart';
import 'cli_test_utils.dart';

void main() {
  late Directory root;

  setUp(() => root = createCalcProject());
  tearDown(() => root.deleteSync(recursive: true));

  test('--exclude skips files matching a glob', () async {
    writeFiles(root, {'lib/l10n/strings.dart': 'bool s() => true;\n'});
    final all = await runCli(root, ['--dry-run', '--no-coverage']);
    expect(all.stdout, contains('lib/calc.dart'));
    final run = await runCli(root, [
      '--dry-run',
      '--no-coverage',
      '--exclude',
      'lib/l10n/**',
      '--exclude',
      'lib/calc.dart',
    ]);
    expect(run.exitCode, 0);
    expect(run.stdout, isNot(contains('lib/calc.dart')));
    expect(
      run.stderr,
      startsWith('1 mutants found, 0 to run'),
      reason: 'only lib/other.dart is left',
    );
  });

  test('--sample runs a seeded random subset and prints the seed', () async {
    final args = ['--dry-run', '--no-coverage', '--sample', '50%'];
    final first = await runCli(root, [...args, '--seed', '7']);
    expect(first.stderr, contains('Sampled 2 of 4 with --seed 7.'));
    final again = await runCli(root, [...args, '--seed', '7']);
    expect(again.stdout, first.stdout);
    expect('\n'.allMatches(first.stdout), hasLength(2));
    final random = await runCli(root, args);
    expect(random.stderr, matches(RegExp(r'Sampled 2 of 4 with --seed \d+\.')));
  });

  for (final jobs in ['1', '2']) {
    test(
      '--min-timeout and --timeout-factor set the timeout (jobs $jobs)',
      () async {
        final fake = FakeRunner((_, _) => result(0, seconds: 20));
        await runCli(root, [
          '--jobs',
          jobs,
          '--operators',
          'arithmetic',
          '--min-timeout',
          '10',
          '--timeout-factor',
          '1.5',
        ], fake: fake);
        expect(fake.calls.last.timeout, const Duration(seconds: 30));
        final floor = FakeRunner((_, _) => result(0, seconds: 1));
        await runCli(root, [
          '--jobs',
          jobs,
          '--min-timeout',
          '45',
        ], fake: floor);
        expect(floor.calls.last.timeout, const Duration(seconds: 45));
      },
    );
  }
}
