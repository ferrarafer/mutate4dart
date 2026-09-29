import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crap4dart/crap4dart.dart';
import 'package:path/path.dart' as p;

import '../mutation/mutant.dart';
import '../mutation/mutant_finder.dart';
import '../report/markdown_renderer.dart';
import '../report/mutation_report.dart';
import '../report/stryker_renderer.dart';
import '../run/coverage_collector.dart';
import '../run/mutation_runner.dart';
import '../run/parallel_runner.dart';
import '../run/test_command.dart';
import '../selection/mutant_filters.dart';
import '../selection/test_selector.dart';
import 'mutation_plan.dart';

/// Current mutate4dart version.
const String mutate4dartVersion = '0.6.0';

/// Process exit codes.
abstract final class ExitCodes {
  /// Success, or the score met `--threshold`.
  static const int success = 0;

  /// Usage or configuration error, or red tests on unmutated code.
  static const int usageError = 1;

  /// The mutation score is below `--threshold`.
  static const int thresholdMissed = 2;
}

/// Default parallelism: half the cores, at most 4. Measured on a Flutter
/// app (11 cores): 4 workers were fastest; more contend for CPU and
/// memory, since every `flutter test` compiles on its own.
int defaultJobs([int? cores]) =>
    ((cores ?? Platform.numberOfProcessors) ~/ 2).clamp(1, 4);

/// The mutate4dart command line.
class Mutate4DartRunner {
  /// Creates a runner for [projectRoot] (default: the current directory).
  /// [run] spawns test commands (injectable for tests).
  Mutate4DartRunner({this.projectRoot, this.run = runProcess});

  /// Project root override.
  final String? projectRoot;

  /// Process runner used for test commands.
  final ProcessRunner run;

  static final ArgParser _parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.')
    ..addFlag('version', negatable: false, help: 'Print the version.')
    ..addOption('lcov',
        defaultsTo: 'coverage/lcov.info',
        help: 'LCOV file: only covered lines are mutated.')
    ..addFlag('coverage',
        defaultsTo: true, help: 'Skip mutants on lines no test executes.')
    ..addFlag('collect-coverage',
        negatable: false,
        help: 'Collect coverage by running only the tests that import the '
            'target files, into $collectedLcovPath (Flutter projects), '
            'instead of reading --lcov.')
    ..addFlag('diff',
        negatable: false, help: 'Only mutate lines changed since HEAD.')
    ..addOption('diff-base',
        help: 'Only mutate lines changed since this git ref.')
    ..addOption('test-command',
        help: 'Test command; test files are appended '
            '(default: flutter test --no-pub, or dart test).')
    ..addOption('reach',
        allowed: ['direct', 'transitive'],
        defaultsTo: 'direct',
        help: 'Run tests that import the file directly, or through any '
            'chain of imports.')
    ..addOption('operators',
        help: 'Comma-separated operator ids (default: all).')
    ..addOption('max-mutants',
        help: 'Run only the N mutants in the riskiest (highest CRAP) '
            'methods.')
    ..addOption('threshold',
        defaultsTo: '0',
        help: 'Minimum mutation score (0-100); below it exits 2.')
    ..addOption('format',
        allowed: ['console', 'json', 'markdown', 'stryker', 'html'],
        defaultsTo: 'console',
        help: 'Report format; all but console write only the report to '
            'stdout. markdown suits a CI job summary or PR comment, stryker '
            'is the Stryker JSON schema (dashboard), html a page showing '
            'it with the mutation-testing-elements viewer.')
    ..addOption('jobs',
        abbr: 'j',
        help: 'Mutants run at once, each in an isolated shadow copy of '
            'the project; 1 mutates in place (default: min(4, cores/2)).')
    ..addFlag('dry-run',
        negatable: false,
        help: 'List the planned mutants and their tests without running.');

  /// Runs mutate4dart with [args]; returns the exit code.
  Future<int> execute(List<String> args) async {
    final ArgResults options;
    try {
      options = _parser.parse(args);
    } on FormatException catch (e) {
      return _usageError(e.message);
    }
    if (options['help'] as bool) {
      stdout.writeln('Usage: mutate4dart [paths...] [options]\n\n'
          '${_parser.usage}');
      return ExitCodes.success;
    }
    if (options['version'] as bool) {
      stdout.writeln('mutate4dart $mutate4dartVersion');
      return ExitCodes.success;
    }
    try {
      return await _mutate(options);
    } on _UsageError catch (e) {
      return _usageError(e.message);
    }
  }

  Future<int> _mutate(ArgResults options) async {
    final root = projectRoot ?? Directory.current.path;
    final runner = MutationRunner(
      projectRoot: root,
      command: _testCommand(options, root),
      run: run,
    );
    for (final file in runner.recoverBackups()) {
      stderr.writeln('Restored $file from an interrupted run.');
    }
    final diff = await _diff(options, root);
    final files = _targetFiles(options, root, diff);
    final selector = TestSelector.build(root);
    final reach = TestReach.values.byName(options['reach'] as String);
    final lcov = options['collect-coverage'] as bool
        ? await _collectCoverage(runner.command, root, [
            for (final f in files) ...selector.testsFor(f, reach: reach),
          ])
        : _lcovPath(options, root);
    final plan = MutationPlan.build(
      projectRoot: root,
      files: files,
      finder: MutantFinder(operators: _operators(options)),
      filter: MutantFilter(
        coverage: lcov == null ? null : CoverageMap.load(lcov, root),
        diff: diff,
      ),
      selector: selector,
      reach: reach,
      lcovPath: lcov,
      maxMutants: _intOption(options, 'max-mutants'),
    );
    _printPlan(plan);
    if (options['dry-run'] as bool) {
      _printDryRun(plan);
      return ExitCodes.success;
    }
    final results = await _runMutants(options, plan, runner);
    if (results == null) return ExitCodes.usageError;
    final report =
        MutationReport.build(results, projectRoot: root, lcovPath: lcov);
    stdout.write(_render(options['format'] as String, report, root));
    final threshold = double.tryParse(options['threshold'] as String) ?? 0;
    return (report.score ?? 100) < threshold
        ? ExitCodes.thresholdMissed
        : ExitCodes.success;
  }

  /// Runs the plan in place (`--jobs 1`) or on parallel shadows.
  Future<List<MutantResult>?> _runMutants(
    ArgResults options,
    MutationPlan plan,
    MutationRunner runner,
  ) {
    final jobs = _intOption(options, 'jobs') ?? defaultJobs();
    return jobs == 1
        ? _runPlan(plan, runner)
        : _runParallel(plan, runner.command, runner.projectRoot, jobs);
  }

  /// The files to mutate: `paths` (default `lib`), narrowed to changed
  /// files in diff mode. Also keeps --collect-coverage from running the
  /// tests of untouched files.
  static List<String> _targetFiles(
    ArgResults options,
    String root,
    DiffLineMap? diff,
  ) =>
      [
        for (final f in MutationPlan.dartFiles(
            root, options.rest.isEmpty ? const ['lib'] : options.rest))
          if (diff == null || diff.hasRealChanges(f)) f,
      ];

  static String _render(String format, MutationReport report, String root) =>
      switch (format) {
        'json' => '${ReportRenderer(root).json(report)}\n',
        'markdown' => MarkdownRenderer(root).render(report),
        'stryker' => '${StrykerRenderer(root).json(report)}\n',
        'html' => StrykerRenderer(root).html(report),
        _ => ReportRenderer(root).console(report),
      };

  Future<List<MutantResult>?> _runPlan(
    MutationPlan plan,
    MutationRunner runner,
  ) async {
    final interrupt = ProcessSignal.sigint.watch().listen((_) {
      runner.recoverBackups();
      stderr.writeln('\nInterrupted: sources restored.');
      exit(130);
    });
    try {
      for (final tests in {for (final m in plan.mutants) m.tests.join('\n')}) {
        await runner.verifyBaseline(tests.split('\n'));
      }
      final results = <MutantResult>[];
      for (final (i, planned) in plan.mutants.indexed) {
        final result = await runner.runMutant(planned.mutant, planned.tests);
        _progress(i + 1, plan.mutants.length, result);
        results.add(result);
      }
      return results;
    } on RedBaselineException catch (e) {
      _printRedBaseline(e);
      return null;
    } finally {
      await interrupt.cancel();
    }
  }

  Future<List<MutantResult>?> _runParallel(
    MutationPlan plan,
    TestCommand command,
    String root,
    int jobs,
  ) async {
    final parallel = ParallelMutationRunner(
      projectRoot: root,
      command: command,
      jobs: jobs,
      run: run,
    );
    final interrupt = ProcessSignal.sigint.watch().listen((_) {
      parallel.dispose();
      stderr.writeln('\nInterrupted: shadow workspaces removed.');
      exit(130);
    });
    var done = 0;
    try {
      return await parallel.runAll(
        [for (final m in plan.mutants) (mutant: m.mutant, tests: m.tests)],
        onResult: (r) => _progress(++done, plan.mutants.length, r),
      );
    } on RedBaselineException catch (e) {
      _printRedBaseline(e);
      return null;
    } finally {
      await interrupt.cancel();
    }
  }

  void _progress(int done, int total, MutantResult r) =>
      stderr.writeln('[$done/$total] ${r.mutant.file}:${r.mutant.line} '
          '${r.mutant.operator}: ${r.status.name}');

  void _printRedBaseline(RedBaselineException e) => stderr
    ..writeln('Error: $e')
    ..writeln('Fix the failing tests first: every mutant would look '
        'killed.')
    ..writeln(e.output);

  TestCommand _testCommand(ArgResults options, String root) {
    final custom = options['test-command'] as String?;
    return custom == null
        ? TestCommand.detect(root)
        : TestCommand.parse(custom);
  }

  Future<String?> _collectCoverage(
    TestCommand command,
    String root,
    List<String> tests,
  ) async {
    final collector =
        CoverageCollector(projectRoot: root, command: command, run: run);
    if (!collector.supported) {
      throw const _UsageError('--collect-coverage needs flutter test. For '
          'Dart projects run dart test --coverage and format_coverage, then '
          'pass --lcov.');
    }
    stderr.writeln('Collecting coverage from ${tests.toSet().length} test '
        'file(s)...');
    try {
      return await collector.collect(tests.toSet().toList()..sort());
    } on RedBaselineException catch (e) {
      throw _UsageError('$e\n${e.output}');
    }
  }

  String? _lcovPath(ArgResults options, String root) {
    if (!(options['coverage'] as bool)) return null;
    final path = p.join(root, options['lcov'] as String);
    if (File(path).existsSync()) return path;
    throw _UsageError('No coverage file at ${options['lcov']}. Run the '
        'tests with coverage first (flutter test --coverage / dart test '
        '--coverage), pass --lcov, or use --no-coverage.');
  }

  Future<DiffLineMap?> _diff(ArgResults options, String root) async {
    final base = options['diff-base'] as String? ??
        ((options['diff'] as bool) ? 'HEAD' : null);
    if (base == null) return null;
    try {
      return await const GitDiffParser().diff(root, base: base);
    } on ProcessException catch (e) {
      throw _UsageError('git diff failed: ${e.message}');
    }
  }

  Set<MutationOperator>? _operators(ArgResults options) {
    final ids = options['operators'] as String?;
    if (ids == null) return null;
    return {
      for (final id in ids.split(',').map((s) => s.trim()))
        MutationOperator.byId(id) ??
            (throw _UsageError('Unknown operator "$id". Known: '
                '${MutationOperator.values.map((o) => o.id).join(', ')}')),
    };
  }

  int? _intOption(ArgResults options, String name) {
    final raw = options[name] as String?;
    if (raw == null) return null;
    final value = int.tryParse(raw);
    if (value == null || value < 1) {
      throw _UsageError('--$name must be a positive integer, got "$raw".');
    }
    return value;
  }

  void _printPlan(MutationPlan plan) {
    stderr.writeln('${plan.found} mutants found, ${plan.mutants.length} '
        'to run (${plan.withoutTests} without tests importing their file).');
    for (final file in plan.unparsed) {
      stderr.writeln('Skipped $file: it does not parse.');
    }
  }

  void _printDryRun(MutationPlan plan) {
    for (final m in plan.mutants) {
      final replacement = m.mutant.replacement.replaceAll('\n', r'\n');
      stdout.writeln('${m.mutant.file}:${m.mutant.line} '
          '[${m.mutant.operator}] -> $replacement  '
          '(${m.tests.length} test file(s))');
    }
  }

  int _usageError(String message) {
    stderr
      ..writeln('Error: $message')
      ..writeln('Usage: mutate4dart [paths...] [options] (see --help)');
    return ExitCodes.usageError;
  }
}

class _UsageError implements Exception {
  const _UsageError(this.message);

  final String message;
}
