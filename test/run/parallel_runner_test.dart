import 'dart:io';

import 'package:mutate4dart/src/internal/mutate4dart_internal.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../fake_runner.dart';
import '../test_project.dart';

const _source = 'int f(int a) => a + 1 + 2;\n';

MutantJob _job(int nth) {
  final offset = _source.indexOf('+', nth == 0 ? 0 : _source.indexOf('+') + 1);
  return (
    mutant: Mutant(
      file: 'lib/a.dart',
      line: 1,
      offset: offset,
      length: 1,
      replacement: '-',
      operator: 'arithmetic',
    ),
    tests: const ['test/a_test.dart'],
  );
}

void main() {
  late Directory root;

  setUp(() => root = createProject({'lib/a.dart': _source}));
  tearDown(() => root.deleteSync(recursive: true));

  test('runs jobs in shadows, in plan order, originals untouched', () async {
    final seen = <String>{};
    late final FakeRunner fake;
    fake = FakeRunner((_, _) {
      seen.add(fake.cwd!);
      final source = File(p.join(fake.cwd!, 'lib/a.dart')).readAsStringSync();
      // Kill the mutant of the second `+` only.
      return result(source.contains('+ 1 - 2') ? 1 : 0);
    });
    final finished = <MutantResult>[];
    final results = await ParallelMutationRunner(
      projectRoot: root.path,
      command: const TestCommand('dart', ['test']),
      jobs: 2,
      run: fake.call,
    ).runAll([_job(0), _job(1)], onResult: finished.add);
    expect(results.map((r) => r.status), [
      MutantStatus.survived,
      MutantStatus.killed,
    ]);
    expect(finished, hasLength(2));
    expect(seen, hasLength(2), reason: 'one shadow per worker');
    expect(
      seen.any((d) => p.isWithin(root.path, d) || d == root.path),
      isFalse,
    );
    expect(File(p.join(root.path, 'lib/a.dart')).readAsStringSync(), _source);
    expect(
      seen.every((d) => !Directory(d).existsSync()),
      isTrue,
      reason: 'shadows are deleted',
    );
  });

  test('a red baseline aborts and still removes the shadows', () async {
    late final FakeRunner fake;
    fake = FakeRunner((_, _) => result(1, output: 'red'));
    await expectLater(
      ParallelMutationRunner(
        projectRoot: root.path,
        command: const TestCommand('dart', ['test']),
        jobs: 3,
        run: fake.call,
      ).runAll([_job(0), _job(1), _job(0)]),
      throwsA(isA<RedBaselineException>()),
    );
    expect(Directory(fake.cwd!).existsSync(), isFalse);
  });

  test('defaultJobs is half the cores, between 1 and 4', () {
    expect(
      [
        for (final c in [1, 2, 6, 11, 32]) defaultJobs(c),
      ],
      [1, 1, 3, 4, 4],
    );
  });
}
