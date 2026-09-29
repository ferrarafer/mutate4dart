/// Mutation testing for Dart and Flutter projects.
///
/// mutate4dart is a command-line tool (`dart pub global activate
/// mutate4dart`). This library runs the same command in-process:
///
/// ```dart
/// final exitCode = await Mutate4DartRunner().execute(['--diff']);
/// ```
///
/// See the README for the options, operators and report formats. The
/// JSON, Stryker and JUnit reports are the stable way to consume results.
library;

export 'src/cli/runner.dart'
    show ExitCodes, Mutate4DartRunner, defaultJobs, mutate4dartVersion;
export 'src/run/test_command.dart'
    show CommandResult, ProcessRunner, runProcess;
