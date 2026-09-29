import 'dart:io';

import 'package:mutate4dart/src/internal/mutate4dart_internal.dart';
import 'package:test/test.dart';

import '../fake_runner.dart';
import '../test_project.dart';
import 'cli_test_utils.dart';

void main() {
  late Directory root;

  setUp(() => root = createCalcProject());
  tearDown(() => root.deleteSync(recursive: true));

  test('usage errors exit 1', () async {
    for (final args in [
      ['--bogus'],
      ['--operators', 'nope'],
      ['--max-mutants', '0'],
      ['--lcov', 'missing.info'],
      ['--exclude', 'lib/['],
      ['--min-timeout', '0'],
      ['--timeout-factor', '0.5'],
      ['--timeout-factor', 'x'],
      ['--sample', '0'],
      ['--sample', '5', '--seed', 'x'],
      ['--sample', '5', '--max-mutants', '5'],
    ]) {
      final run = await runCli(root, args);
      expect(run.exitCode, ExitCodes.usageError, reason: '$args');
      expect(run.stderr, startsWith('Error: '));
    }
  });

  test('--no-coverage mutates uncovered lines too', () async {
    final run = await runCli(root, ['--dry-run', '--no-coverage']);
    expect(run.stdout, contains('lib/calc.dart:3'));
  });

  test('restores files from an interrupted run first', () async {
    writeFiles(root, {'.mutate4dart/backup/lib/other.dart': 'bool o() => 1;'});
    final run = await runCli(root, ['--dry-run']);
    expect(run.stderr, contains('Restored lib/other.dart'));
  });
  test('a red baseline aborts with exit 1', () async {
    final run = await runCli(
      root,
      [],
      fake: FakeRunner((_, _) => result(1, output: 'boom')),
    );
    expect(run.exitCode, ExitCodes.usageError);
    expect(run.stderr, contains('Fix the failing tests first'));
  });
}
