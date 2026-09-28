import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The outcome of one test command run.
class CommandResult {
  /// Creates a [CommandResult].
  const CommandResult({
    required this.exitCode,
    required this.output,
    required this.elapsed,
    this.timedOut = false,
  });

  /// Process exit code (meaningless when [timedOut]).
  final int exitCode;

  /// Combined stdout and stderr.
  final String output;

  /// Wall-clock duration of the run.
  final Duration elapsed;

  /// Whether the run was killed after its timeout.
  final bool timedOut;
}

/// Runs [executable] with [arguments] in [workingDirectory], killing it
/// after [timeout]. Injected so tests never spawn real test suites.
typedef ProcessRunner = Future<CommandResult> Function(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required Duration timeout,
});

/// Default [ProcessRunner] backed by [Process.start].
Future<CommandResult> runProcess(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required Duration timeout,
}) async {
  final watch = Stopwatch()..start();
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: Platform.isWindows,
  );
  final output = StringBuffer();
  final done = Future.wait([
    process.stdout.transform(utf8.decoder).forEach(output.write),
    process.stderr.transform(utf8.decoder).forEach(output.write),
  ]);
  var timedOut = false;
  final exitCode = await process.exitCode.timeout(timeout, onTimeout: () {
    timedOut = true;
    process.kill(ProcessSignal.sigkill);
    return -1;
  });
  if (!timedOut) await done;
  return CommandResult(
    exitCode: exitCode,
    output: output.toString(),
    elapsed: watch.elapsed,
    timedOut: timedOut,
  );
}

/// The command that runs a set of test files.
class TestCommand {
  /// Creates a [TestCommand] running `executable arguments... <tests>`.
  const TestCommand(this.executable, this.arguments);

  /// `flutter test --no-pub` for Flutter projects (pubspec depends on
  /// `flutter`), `dart test` otherwise.
  factory TestCommand.detect(String projectRoot) => _isFlutter(projectRoot)
      ? const TestCommand('flutter', ['test', '--no-pub'])
      : const TestCommand('dart', ['test']);

  /// Parses a user-provided command line such as `fvm flutter test`
  /// (split on whitespace; test files are appended).
  factory TestCommand.parse(String commandLine) {
    final parts = commandLine.trim().split(RegExp(r'\s+'));
    return TestCommand(parts.first, parts.skip(1).toList());
  }

  /// Executable to spawn.
  final String executable;

  /// Arguments before the test files.
  final List<String> arguments;

  /// The full argument list for [tests].
  List<String> argumentsFor(List<String> tests) => [...arguments, ...tests];

  @override
  String toString() => [executable, ...arguments].join(' ');

  static bool _isFlutter(String projectRoot) {
    final pubspec = File(p.join(projectRoot, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return false;
    final yaml = loadYaml(pubspec.readAsStringSync());
    if (yaml is! YamlMap) return false;
    final deps = yaml['dependencies'];
    return deps is YamlMap && deps.containsKey('flutter');
  }
}

/// Whether [output] of a failed test run means the code did not compile
/// (the mutant is invalid, not detected by a test).
bool isCompileFailure(String output) =>
    output.contains('Compilation failed') ||
    (RegExp(r'Failed to load "[^"]*":').hasMatch(output) &&
        output.contains('Error: '));
