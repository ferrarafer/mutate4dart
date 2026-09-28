import 'dart:io';

import 'package:mutate4dart/mutate4dart.dart';

import '../fake_runner.dart';
import '../test_project.dart';

/// Exit code and captured output of an in-process CLI run.
typedef CliResult = ({int exitCode, String stdout, String stderr});

/// Runs mutate4dart in-process on [root] with [fake] as process runner,
/// capturing stdout and stderr.
Future<CliResult> runCli(
  Directory root,
  List<String> args, {
  FakeRunner? fake,
}) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final runner = fake ?? FakeRunner((_, __) => result(0));
  final code = await IOOverrides.runZoned(
    () => Mutate4DartRunner(projectRoot: root.path, run: runner.call)
        .execute(args),
    stdout: () => _BufferStdout(out),
    stderr: () => _BufferStdout(err),
  );
  return (exitCode: code, stdout: out.toString(), stderr: err.toString());
}

/// A project with `lib/calc.dart` (covered), `lib/other.dart` (not
/// imported by any test) and `test/calc_test.dart`.
Directory createCalcProject() => createProject({
      'lib/calc.dart': 'int add(int a, int b) {\n'
          '  if (a > 0) return a + b;\n'
          '  return b - 1;\n'
          '}\n',
      'lib/other.dart': 'bool other() => true;\n',
      'test/calc_test.dart': "import 'package:demo/calc.dart';\n"
          'void main() {}\n',
      'coverage/lcov.info': 'SF:lib/calc.dart\nDA:1,1\nDA:2,1\nDA:3,0\n'
          'end_of_record\nSF:lib/other.dart\nDA:1,1\nend_of_record\n',
    });

/// A [FakeRunner] whose tests fail (kill the mutant) when the
/// `lib/calc.dart` of the run's working directory (the project or a
/// shadow workspace) contains [killedBy], and pass otherwise.
FakeRunner killWhen(String killedBy) {
  late final FakeRunner fake;
  fake = FakeRunner((_, __) {
    final source = File('${fake.cwd}/lib/calc.dart').readAsStringSync();
    return result(source.contains(killedBy) ? 1 : 0);
  });
  return fake;
}

class _BufferStdout implements Stdout {
  _BufferStdout(this._buffer);

  final StringBuffer _buffer;

  @override
  void write(Object? object) => _buffer.write(object);

  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);

  @override
  void noSuchMethod(Invocation invocation) {}
}
