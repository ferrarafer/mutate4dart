import 'package:mutate4dart/mutate4dart.dart';

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
    calls
        .add((command: [executable, ...arguments].join(' '), timeout: timeout));
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
