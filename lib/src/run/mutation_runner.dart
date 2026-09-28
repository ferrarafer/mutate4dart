import 'dart:io';

import 'package:path/path.dart' as p;

import '../mutation/mutant.dart';
import 'test_command.dart';

/// What happened to a mutant.
enum MutantStatus {
  /// A test failed: the suite detects this change.
  killed,

  /// Every test passed: the suite misses this change.
  survived,

  /// The tests ran past the timeout (usually an infinite loop): counted
  /// as killed.
  timeout,

  /// The mutated code did not compile: excluded from the score.
  invalid,
}

/// A mutant together with its test outcome.
class MutantResult {
  /// Creates a [MutantResult].
  const MutantResult(this.mutant, this.status, this.tests);

  /// The applied mutant.
  final Mutant mutant;

  /// The outcome.
  final MutantStatus status;

  /// The test files that were run.
  final List<String> tests;

  /// Whether the suite detected the mutant (killed or timed out).
  bool get detected =>
      status == MutantStatus.killed || status == MutantStatus.timeout;
}

/// Thrown when the selected tests fail on the unmutated code: every
/// mutant would look killed, so the run is meaningless.
class RedBaselineException implements Exception {
  /// Creates a [RedBaselineException].
  const RedBaselineException(this.tests, this.output);

  /// The failing test files.
  final List<String> tests;

  /// Output of the failing run.
  final String output;

  @override
  String toString() => 'Tests fail on unmutated code: ${tests.join(' ')}';
}

/// Applies mutants one at a time and runs their tests.
///
/// The original of every mutated file is backed up under
/// `.mutate4dart/backup/` before it is changed and restored afterwards,
/// even when a run throws. [recoverBackups] restores files left behind
/// by an interrupted run.
class MutationRunner {
  /// Creates a [MutationRunner] for the project at [projectRoot].
  MutationRunner({
    required this.projectRoot,
    required this.command,
    this.run = runProcess,
    this.minTimeout = const Duration(seconds: 30),
    this.timeoutFactor = 3,
  });

  /// Project root; mutant files are relative to it.
  final String projectRoot;

  /// Command that runs test files.
  final TestCommand command;

  /// Process runner (injectable for tests).
  final ProcessRunner run;

  /// Lower bound for a mutant's timeout.
  final Duration minTimeout;

  /// A mutant's timeout is this multiple of its tests' baseline duration.
  final int timeoutFactor;

  final Map<String, Duration> _baselines = {};

  String get _backupDir => p.join(projectRoot, '.mutate4dart', 'backup');

  /// Restores files backed up by an interrupted run; returns their paths.
  List<String> recoverBackups() {
    final dir = Directory(_backupDir);
    if (!dir.existsSync()) return const [];
    final restored = <String>[];
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: _backupDir);
      entity.copySync(p.join(projectRoot, relative));
      entity.deleteSync();
      restored.add(relative);
    }
    dir.deleteSync(recursive: true);
    return restored;
  }

  /// Runs [tests] on the unmutated code once and records how long they
  /// take. Throws a [RedBaselineException] when they fail.
  Future<void> verifyBaseline(List<String> tests) async {
    final key = tests.join('\n');
    if (_baselines.containsKey(key)) return;
    final result = await _runTests(tests, const Duration(minutes: 30));
    if (result.timedOut || result.exitCode != 0) {
      throw RedBaselineException(tests, result.output);
    }
    _baselines[key] = result.elapsed;
  }

  /// Applies [mutant] to its file, runs [tests] and restores the file.
  /// [verifyBaseline] must have succeeded for [tests].
  Future<MutantResult> runMutant(Mutant mutant, List<String> tests) async {
    final path = p.join(projectRoot, mutant.file);
    final original = File(path).readAsStringSync();
    final backup = File(p.join(_backupDir, mutant.file));
    backup.parent.createSync(recursive: true);
    backup.writeAsStringSync(original);
    try {
      File(path).writeAsStringSync(mutant.apply(original));
      final result = await _runTests(tests, _timeoutFor(tests));
      return MutantResult(mutant, _statusOf(result), tests);
    } finally {
      File(path).writeAsStringSync(original);
      backup.deleteSync();
    }
  }

  Duration _timeoutFor(List<String> tests) {
    final baseline = _baselines[tests.join('\n')] ?? Duration.zero;
    final scaled = baseline * timeoutFactor;
    return scaled > minTimeout ? scaled : minTimeout;
  }

  Future<CommandResult> _runTests(List<String> tests, Duration timeout) => run(
        command.executable,
        command.argumentsFor(tests),
        workingDirectory: projectRoot,
        timeout: timeout,
      );

  static MutantStatus _statusOf(CommandResult result) {
    if (result.timedOut) return MutantStatus.timeout;
    if (result.exitCode == 0) return MutantStatus.survived;
    return isCompileFailure(result.output)
        ? MutantStatus.invalid
        : MutantStatus.killed;
  }
}
