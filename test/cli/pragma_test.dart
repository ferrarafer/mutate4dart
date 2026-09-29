import 'dart:io';

import 'package:mutate4dart/src/internal/mutate4dart_internal.dart';
import 'package:test/test.dart';

import '../test_project.dart';
import 'cli_test_utils.dart';

void main() {
  late Directory root;

  setUp(() {
    root = createCalcProject();
    writeFiles(root, {
      'lib/calc.dart':
          'int add(int a, int b) {\n'
          '  if (a > 0) return a + b; // mutate4dart: ignore arithmetic\n'
          '  return b - 1;\n'
          '}\n',
    });
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('the plan summary counts mutants ignored by pragma', () async {
    final run = await runCli(root, ['--dry-run']);
    expect(run.exitCode, ExitCodes.success);
    expect(
      run.stderr,
      contains(
        'to run (1 without tests importing their file, 1 ignored '
        'by pragma).',
      ),
    );
    expect(run.stdout, isNot(contains('[arithmetic]')));
    expect(run.stdout, contains('[relational_boundary]'));
  });

  test('without pragmas the summary is unchanged', () async {
    writeFiles(root, {'lib/calc.dart': 'int add(int a) => a + 1;\n'});
    final run = await runCli(root, ['--dry-run', '--no-coverage']);
    expect(run.stderr, contains('(1 without tests importing their file).'));
  });
}
