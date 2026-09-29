import 'dart:io';

import 'package:mutate4dart/src/internal/mutate4dart_internal.dart';
import 'package:test/test.dart';

import '../test_project.dart';
import 'cli_test_utils.dart';

void main() {
  late Directory root;

  setUp(() => root = createCalcProject());
  tearDown(() => root.deleteSync(recursive: true));

  void config(String yaml) => writeFiles(root, {'mutate4dart.yaml': yaml});

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
