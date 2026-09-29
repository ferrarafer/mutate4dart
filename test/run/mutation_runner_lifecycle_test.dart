import 'dart:io';

import 'package:mutate4dart/src/internal/mutate4dart_internal.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../fake_runner.dart';
import '../test_project.dart';

const _source = 'int f(int a) => a + 1;\n';

final _mutant = Mutant(
  file: 'lib/a.dart',
  line: 1,
  offset: _source.indexOf('+'),
  length: 1,
  replacement: '-',
  operator: 'arithmetic',
);

void main() {
  late Directory root;

  setUp(() => root = createProject({'lib/a.dart': _source}));
  tearDown(() => root.deleteSync(recursive: true));

  String source() => File(p.join(root.path, 'lib/a.dart')).readAsStringSync();

  MutationRunner runner(FakeRunner fake) => MutationRunner(
    projectRoot: root.path,
    command: const TestCommand('dart', ['test']),
    run: fake.call,
    timeout: const MutantTimeout(min: Duration(seconds: 5)),
  );

  test('scales the timeout with the baseline duration', () async {
    final fake = FakeRunner((_, call) => result(0, seconds: 4));
    final r = runner(fake);
    await r.verifyBaseline(['t']);
    await r.verifyBaseline(['t']); // cached: no second baseline run
    await r.runMutant(_mutant, ['t']);
    expect(fake.calls, hasLength(2));
    expect(fake.calls.last.timeout, const Duration(seconds: 12));
  });

  test('a red baseline is an error', () async {
    final fake = FakeRunner((_, _) => result(1, output: 'boom'));
    await expectLater(
      runner(fake).verifyBaseline(['t']),
      throwsA(
        isA<RedBaselineException>()
            .having((e) => e.output, 'output', 'boom')
            .having((e) => e.toString(), 'text', contains('t')),
      ),
    );
  });

  test('recovers files left behind by an interrupted run', () {
    writeFiles(root, {
      'lib/a.dart': 'broken',
      '.mutate4dart/backup/lib/a.dart': _source,
    });
    final r = runner(FakeRunner((_, _) => result(0)));
    expect(r.recoverBackups(), ['lib/a.dart']);
    expect(source(), _source);
    expect(
      Directory(p.join(root.path, '.mutate4dart/backup')).existsSync(),
      isFalse,
    );
    expect(r.recoverBackups(), isEmpty);
  });
}
