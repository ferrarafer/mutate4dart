import '../mutation/mutant.dart';
import 'mutation_runner.dart';
import 'shadow_workspace.dart';
import 'test_command.dart';

/// A mutant to run with the test files that cover it.
typedef MutantJob = ({Mutant mutant, List<String> tests});

/// Runs mutants on [jobs] workers at once, each in its own
/// [ShadowWorkspace], so the original project is never modified.
///
/// Workers take the next mutant from a shared queue (the plan order, so
/// the riskiest run first). Before a worker's first mutant for a set of
/// test files, it runs them unmutated. That check validates the shadow and
/// warms its build cache, and a failure aborts the run with a
/// [RedBaselineException].
class ParallelMutationRunner {
  /// Creates a runner for the project at [projectRoot].
  ParallelMutationRunner({
    required this.projectRoot,
    required this.command,
    required this.jobs,
    this.run = runProcess,
    this.timeout = const MutantTimeout(),
  });

  /// Project root.
  final String projectRoot;

  /// Command that runs test files.
  final TestCommand command;

  /// Number of concurrent workers.
  final int jobs;

  /// Process runner (injectable for tests).
  final ProcessRunner run;

  /// Timeout of each mutant's test run.
  final MutantTimeout timeout;

  final List<ShadowWorkspace> _workspaces = [];

  /// Runs [plan] and returns its results in plan order. [onResult] is
  /// called as each mutant finishes.
  Future<List<MutantResult>> runAll(
    List<MutantJob> plan, {
    void Function(MutantResult result)? onResult,
  }) async {
    final files = {for (final job in plan) job.mutant.file};
    final results = List<MutantResult?>.filled(plan.length, null);
    var next = 0;
    var aborted = false;
    Future<void> worker(MutationRunner runner) async {
      while (!aborted && next < plan.length) {
        final index = next++;
        final job = plan[index];
        try {
          await runner.verifyBaseline(job.tests);
          final result = await runner.runMutant(job.mutant, job.tests);
          results[index] = result;
          onResult?.call(result);
        } catch (_) {
          aborted = true;
          rethrow;
        }
      }
    }

    try {
      final workers = [
        for (var i = 0; i < jobs && i < plan.length; i++)
          worker(MutationRunner(
            projectRoot: _newWorkspace(files).projectRoot,
            command: command,
            run: run,
            timeout: timeout,
          )),
      ];
      // Not eager: after an error the other workers finish their current
      // mutant (aborted stops new work) before the shadows are deleted.
      await Future.wait(workers);
      return results.cast<MutantResult>();
    } finally {
      dispose();
    }
  }

  /// Deletes every shadow workspace (safe to call more than once, e.g.
  /// from a SIGINT handler).
  void dispose() {
    for (final workspace in _workspaces) {
      workspace.delete();
    }
    _workspaces.clear();
  }

  ShadowWorkspace _newWorkspace(Set<String> files) {
    final workspace =
        ShadowWorkspace.create(projectRoot: projectRoot, files: files);
    _workspaces.add(workspace);
    return workspace;
  }
}
