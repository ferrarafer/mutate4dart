import 'dart:io';

import 'package:mutate4dart/mutate4dart.dart';
import 'package:test/test.dart';

import '../fake_runner.dart';
import '../test_project.dart';
import 'cli_test_utils.dart';

/// The `file:line [operator]` of each planned mutant in a dry run.
List<String> _planned(CliResult run) => [
      for (final line in run.stdout.trim().split('\n'))
        if (line.isNotEmpty) line.split(' ->').first,
    ];

void main() {
  late Directory root;

  setUp(() => root = createCalcProject());
  tearDown(() => root.deleteSync(recursive: true));

  void config(String yaml) => writeFiles(root, {'mutate4dart.yaml': yaml});

  test('mutate4dart.yaml sets option defaults', () async {
    config('operators: [arithmetic]\ncoverage: false\ncollect_coverage: false\n'
        'exclude:\n  - lib/other.dart\n');
    final run = await runCli(root, ['--dry-run']);
    expect(_planned(run),
        ['lib/calc.dart:2 [arithmetic]', 'lib/calc.dart:3 [arithmetic]']);
  });

  test('the command line wins over the config file', () async {
    config('operators: arithmetic\npaths: [lib/other.dart]\n');
    final run = await runCli(root,
        ['--dry-run', '--operators', 'negate_condition', 'lib/calc.dart']);
    expect(_planned(run), ['lib/calc.dart:2 [negate_condition]']);
    final paths =
        await runCli(root, ['--dry-run', '--operators', 'boolean_literal']);
    expect(paths.stderr, startsWith('1 mutants found, 0 to run'),
        reason: 'paths from the config file: only lib/other.dart');
  });

  test('--config reads another file; snake_case keys map to flags', () async {
    writeFiles(root, {'ci/m4d.yaml': 'min_timeout: 45\njobs: 1\n'});
    final fake = FakeRunner((_, __) => result(0));
    await runCli(root, ['--config', 'ci/m4d.yaml'], fake: fake);
    expect(fake.calls.last.timeout, const Duration(seconds: 45));
  });

  test('--no-collect-coverage overrides the config file', () async {
    config('collect_coverage: true\n');
    final on = await runCli(root, ['--dry-run']);
    expect(on.stderr, contains('--collect-coverage needs flutter test'));
    final off = await runCli(root, ['--dry-run', '--no-collect-coverage']);
    expect(off.exitCode, ExitCodes.success);
  });

  test('an empty config file is fine', () async {
    config('');
    expect((await runCli(root, ['--dry-run'])).exitCode, ExitCodes.success);
  });

  test('invalid config files are usage errors naming the problem', () async {
    final cases = {
      'bogus: 1\n': 'unknown key "bogus"',
      'version: true\n': 'unknown key "version"',
      'coverage: 1\n': 'coverage must be a bool',
      'exclude: {a: b}\n': 'exclude must be a value',
      'max_mutants: [1, 2]\n': '--max-mutants must be a positive integer',
      'format: pdf\n': 'mutate4dart.yaml: "pdf" is not an allowed value',
      '- a\n': 'expected a map',
      'a: [\n': 'mutate4dart.yaml: ',
    };
    for (final MapEntry(key: yaml, value: message) in cases.entries) {
      config(yaml);
      final run = await runCli(root, ['--dry-run']);
      expect(run.exitCode, ExitCodes.usageError, reason: yaml);
      expect(run.stderr, contains(message), reason: yaml);
    }
    final missing = await runCli(root, ['--config', 'nope.yaml']);
    expect(missing.stderr, contains('No config file at nope.yaml'));
  });
}
