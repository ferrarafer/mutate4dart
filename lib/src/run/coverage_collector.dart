import 'dart:io';

import 'package:path/path.dart' as p;

import 'mutation_runner.dart';
import 'test_command.dart';

/// Where [CoverageCollector] writes its LCOV file, relative to the project.
const String collectedLcovPath = '.mutate4dart/lcov.info';

/// Runs only the test files that cover the files to mutate, with coverage,
/// instead of requiring an LCOV file from the whole suite.
///
/// Flutter only: it relies on `flutter test --coverage --coverage-path`.
/// The user's own `coverage/` is never touched.
class CoverageCollector {
  /// Creates a collector for the project at [projectRoot].
  const CoverageCollector({
    required this.projectRoot,
    required this.command,
    this.run = runProcess,
  });

  /// Project root.
  final String projectRoot;

  /// The test command (must run `flutter test`).
  final TestCommand command;

  /// Process runner (injectable for tests).
  final ProcessRunner run;

  /// Whether [command] can collect coverage this way.
  bool get supported =>
      command.executable == 'flutter' || command.arguments.contains('flutter');

  /// Runs [tests] with coverage and returns the absolute LCOV path, or
  /// `null` when there are no tests to run. Throws a
  /// [RedBaselineException] when the tests fail.
  Future<String?> collect(List<String> tests) async {
    if (tests.isEmpty) return null;
    final lcov = p.join(projectRoot, collectedLcovPath);
    final result = await run(
      command.executable,
      command.argumentsFor(['--coverage', '--coverage-path', lcov, ...tests]),
      workingDirectory: projectRoot,
      timeout: const Duration(minutes: 30),
    );
    if (result.timedOut || result.exitCode != 0) {
      throw RedBaselineException(tests, result.output);
    }
    if (!File(lcov).existsSync()) {
      throw RedBaselineException(
        tests,
        'No coverage was written to $lcov.\n${result.output}',
      );
    }
    return lcov;
  }
}
