import 'dart:io';

import 'package:mutate4dart/mutate4dart.dart';
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

  Future<MutantStatus> statusFor(CommandResult mutantResult) async {
    final fake = FakeRunner((_, call) => call == 0 ? result(0) : mutantResult);
    final r = runner(fake);
    await r.verifyBaseline(['test/a_test.dart']);
    return (await r.runMutant(_mutant, ['test/a_test.dart'])).status;
  }

  test('classifies killed, survived, timeout and invalid mutants', () async {
    expect(
        await statusFor(result(1, output: 'Expected: 2')), MutantStatus.killed);
    expect(await statusFor(result(0)), MutantStatus.survived);
    expect(
        await statusFor(const CommandResult(
            exitCode: -1,
            output: '',
            elapsed: Duration(seconds: 9),
            timedOut: true)),
        MutantStatus.timeout);
    expect(await statusFor(result(1, output: 'Error: Compilation failed')),
        MutantStatus.invalid);
  });

  test('runs the tests on the mutated file and restores it', () async {
    String? seen;
    final fake = FakeRunner((args, call) {
      if (call == 1) seen = source();
      return result(call == 0 ? 0 : 1);
    });
    final r = runner(fake);
    await r.verifyBaseline(['test/a_test.dart']);
    final outcome = await r.runMutant(_mutant, ['test/a_test.dart']);
    expect(seen, 'int f(int a) => a - 1;\n');
    expect(source(), _source);
    expect(outcome.detected, isTrue);
    expect(outcome.tests, ['test/a_test.dart']);
    expect(fake.calls.last.command, 'dart test test/a_test.dart');
    expect(Directory(p.join(root.path, '.mutate4dart/backup/lib')).listSync(),
        isEmpty);
  });

  test('restores the file even when the test run throws', () async {
    final fake = FakeRunner((_, call) =>
        call == 0 ? result(0) : throw const ProcessException('x', []));
    final r = runner(fake);
    await r.verifyBaseline(['t']);
    await expectLater(
        r.runMutant(_mutant, ['t']), throwsA(isA<ProcessException>()));
    expect(source(), _source);
  });
}
