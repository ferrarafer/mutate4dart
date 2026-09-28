import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../fake_runner.dart';
import '../test_project.dart';
import 'cli_test_utils.dart';

void main() {
  test('--collect-coverage runs the covering tests, then mutates', () async {
    final root = createCalcProject();
    addTearDown(() => root.deleteSync(recursive: true));
    writeFiles(root, {
      'pubspec.yaml':
          'name: demo\ndependencies:\n  flutter:\n    sdk: flutter\n',
    });
    File(p.join(root.path, 'coverage/lcov.info')).deleteSync();
    late final FakeRunner fake;
    fake = FakeRunner((args, __) {
      final at = args.indexOf('--coverage-path');
      if (at >= 0) {
        File(args[at + 1])
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('SF:lib/calc.dart\nDA:2,1\nend_of_record\n');
        return result(0);
      }
      final source = File('${fake.cwd}/lib/calc.dart').readAsStringSync();
      return result(source.contains('a - b') ? 1 : 0);
    });
    final run =
        await runCli(root, ['--collect-coverage', '--jobs', '1'], fake: fake);
    expect(run.exitCode, 0);
    expect(run.stderr, contains('Collecting coverage from 1 test file(s)'));
    expect(fake.calls.first.command, contains('--coverage-path'));
    expect(run.stdout, contains('Mutation score: 33.3% (3 mutants)'));
  });

  test('--collect-coverage on a Dart project is a usage error', () async {
    final root = createCalcProject();
    addTearDown(() => root.deleteSync(recursive: true));
    final run = await runCli(root, ['--collect-coverage']);
    expect(run.exitCode, 1);
    expect(run.stderr, contains('needs flutter test'));
  });

  test('--collect-coverage with failing tests exits 1', () async {
    final root = createCalcProject();
    addTearDown(() => root.deleteSync(recursive: true));
    writeFiles(root, {
      'pubspec.yaml':
          'name: demo\ndependencies:\n  flutter:\n    sdk: flutter\n',
    });
    final run = await runCli(root, ['--collect-coverage'],
        fake: FakeRunner((_, __) => result(1, output: 'red')));
    expect(run.exitCode, 1);
    expect(run.stderr, contains('Tests fail on unmutated code'));
  });
}
