import 'dart:io';

import 'package:mutate4dart/src/internal/mutate4dart_internal.dart';

/// A [ProcessRunner] that records calls and answers from [respond], which
/// receives the arguments and the call index.
class FakeRunner {
  /// Creates a [FakeRunner].
  FakeRunner(this.respond);

  /// Produces the result of each call.
  final CommandResult Function(List<String> arguments, int call) respond;

  /// Every call as `executable args...`, with its timeout.
  final List<({String command, Duration timeout})> calls = [];

  /// Working directory of the current call (a shadow workspace in
  /// parallel runs).
  String? cwd;

  /// The runner to inject.
  Future<CommandResult> call(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    required Duration timeout,
  }) async {
    cwd = workingDirectory;
    calls.add((
      command: [executable, ...arguments].join(' '),
      timeout: timeout,
    ));
    return respond(arguments, calls.length - 1);
  }
}

/// A finished run with [exitCode] and [output] that took [seconds].
CommandResult result(int exitCode, {String output = '', int seconds = 1}) =>
    CommandResult(
      exitCode: exitCode,
      output: output,
      elapsed: Duration(seconds: seconds),
    );

/// A [FakeRunner] that writes a minimal LCOV file wherever
/// `--coverage-path` points, and passes every other run.
FakeRunner writesCoverage({
  String lcov = 'SF:lib/a.dart\nDA:1,1\nend_of_record\n',
}) => FakeRunner((args, _) {
  final at = args.indexOf('--coverage-path');
  if (at >= 0) {
    File(args[at + 1])
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(lcov);
  }
  return result(0);
});
