import 'dart:io';

import 'package:test/test.dart';

import '../fake_runner.dart';
import '../test_project.dart';
import 'cli_test_utils.dart';

Future<void> _git(Directory root, List<String> args) async {
  final r = await Process.run('git', args, workingDirectory: root.path);
  if (r.exitCode != 0) throw StateError('git $args: ${r.stderr}');
}

void main() {
  test('--diff mutates only changed lines', () async {
    final root = createCalcProject();
    addTearDown(() => root.deleteSync(recursive: true));
    await _git(root, ['init', '-q', '.']);
    await _git(root, ['add', '.']);
    await _git(root, [
      '-c', 'user.email=t@e.st', '-c', 'user.name=t', //
      'commit', '-qm', 'base',
    ]);
    final clean = await runCli(root, ['--dry-run', '--diff']);
    expect(clean.stdout, isEmpty);
    File('${root.path}/lib/calc.dart').writeAsStringSync(
      'int add(int a, int b) {\n  if (a > 0) return a * b;\n  return b;\n}\n',
    );
    final changed = await runCli(root, ['--dry-run', '--diff-base', 'HEAD']);
    expect(changed.stdout, contains('lib/calc.dart:2 [arithmetic] -> /'));
  });

  test('--diff outside a git repository is a usage error', () async {
    final root = createCalcProject();
    addTearDown(() => root.deleteSync(recursive: true));
    final run = await runCli(root, ['--diff']);
    expect(run.exitCode, 1);
    expect(run.stderr, contains('git diff failed'));
  });

  test(
    '--diff with --collect-coverage only runs tests of changed files',
    () async {
      final root = createCalcProject();
      addTearDown(() => root.deleteSync(recursive: true));
      writeFiles(root, {
        'pubspec.yaml':
            'name: demo\ndependencies:\n  flutter:\n    sdk: flutter\n',
        'test/other_test.dart':
            "import 'package:demo/other.dart';\nvoid main() {}\n",
      });
      await _git(root, ['init', '-q', '.']);
      await _git(root, ['add', '.']);
      await _git(root, [
        '-c', 'user.email=t@e.st', '-c', 'user.name=t', //
        'commit', '-qm', 'base',
      ]);
      File('${root.path}/lib/calc.dart').writeAsStringSync(
        'int add(int a, int b) {\n  if (a > 0) return a * b;\n  return b;\n}\n',
      );
      final fake = writesCoverage();
      await runCli(root, [
        '--diff',
        '--collect-coverage',
        '--dry-run',
      ], fake: fake);
      final collect = fake.calls.first.command;
      expect(collect, contains('test/calc_test.dart'));
      expect(collect, isNot(contains('other_test.dart')));
    },
  );
}
