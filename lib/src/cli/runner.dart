import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:crap_dart/crap_dart.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../mutation/mutant.dart';
import '../mutation/mutant_finder.dart';
import '../report/junit_renderer.dart';
import '../report/markdown_renderer.dart';
import '../report/mutation_report.dart';
import '../report/stryker_renderer.dart';
import '../run/coverage_collector.dart';
import '../run/mutation_runner.dart';
import '../run/parallel_runner.dart';
import '../run/test_command.dart';
import '../selection/mutant_filters.dart';
import '../selection/mutant_sample.dart';
import '../selection/test_selector.dart';
import 'config_file.dart';
import 'mutation_plan.dart';

/// Current mutate4dart version.
const String mutate4dartVersion = '0.12.2';

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
    ..addOption(
      'config',
      defaultsTo: defaultConfigPath,
      help:
          'Config file with defaults for these options (snake_case '
          'keys); flags given here win.',
    )
    ..addOption(
      'lcov',
      defaultsTo: 'coverage/lcov.info',
      help: 'LCOV file: only covered lines are mutated.',
    )
    ..addFlag(
      'coverage',
      defaultsTo: true,
      help: 'Skip mutants on lines no test executes.',
    )
    ..addFlag(
      'collect-coverage',
      help:
          'Collect coverage by running only the tests that import the '
          'target files, into $collectedLcovPath (Flutter projects), '
          'instead of reading --lcov.',
    )
    ..addFlag('diff', help: 'Only mutate lines changed since HEAD.')
    ..addOption(
      'diff-base',
      help: 'Only mutate lines changed since this git ref.',
    )
    ..addOption(
      'test-command',
      help:
          'Test command; test files are appended '
          '(default: flutter test --no-pub, or dart test).',
    )
    ..addOption(
      'reach',
      allowed: ['direct', 'transitive'],
      defaultsTo: 'direct',
      help:
          'Run tests that import the file directly, or through any '
          'chain of imports.',
    )
    ..addMultiOption(
      'exclude',
      help:
          'Glob of project-relative files not to mutate, e.g. '
          '"lib/l10n/**" (repeatable). Generated code (*.g.dart, '
          '*.freezed.dart, *.gr.dart, *.mocks.dart) is always skipped.',
    )
    ..addOption(
      'operators',
      help: 'Comma-separated operator ids (default: all).',
    )
    ..addOption(
      'max-mutants',
      help:
          'Run only the N mutants in the riskiest (highest CRAP) '
          'methods.',
    )
    ..addOption(
      'sample',
      help:
          'Run a random sample of the mutants: a count (50) or a '
          'percentage (20%), for an unbiased score estimate.',
    )
    ..addOption(
      'seed',
      help:
          'Seed of --sample, to repeat a sample (default: random, '
          'printed).',
    )
    ..addOption(
      'threshold',
      defaultsTo: '0',
      help: 'Minimum mutation score (0-100); below it exits 2.',
    )
    ..addOption(
      'format',
      allowed: ['console', 'json', 'markdown', 'stryker', 'html', 'junit'],
      defaultsTo: 'console',
      help:
          'Report format; all but console write only the report to '
          'stdout. markdown suits a CI job summary or PR comment, stryker '
          'is the Stryker JSON schema (dashboard), html a page showing '
          'it with the mutation-testing-elements viewer, junit JUnit XML '
          '(survivors as failures) for CI test reports.',
    )
    ..addOption(
      'jobs',
      abbr: 'j',
      help:
          'Mutants run at once, each in an isolated shadow copy of '
          'the project; 1 mutates in place (default: min(4, cores/2)).',
    )
    ..addOption(
      'min-timeout',
      defaultsTo: '30',
      help:
          'Seconds a mutant\'s tests may always run before it counts '
          'as a timeout.',
    )
    ..addOption(
      'timeout-factor',
      defaultsTo: '3',
      help:
          'A mutant\'s tests may run this multiple of their unmutated '
          'duration (at least --min-timeout).',
    )
    ..addFlag(
      'dry-run',
      negatable: false,
      help: 'List the planned mutants and their tests without running.',
    );

  /// Runs mutate4dart with [args]; returns the exit code.
  Future<int> execute(List<String> args) async {
    final ArgResults options;
    try {
      options = _parser.parse(args);
    } on FormatException catch (e) {
      return _usageError(e.message);
    }
    if (options['help'] as bool) {
      stdout.writeln(
        'Usage: mutate4dart [paths...] [options]\n\n'
        '${_parser.usage}',
      );
      return ExitCodes.success;
    }
    if (options['version'] as bool) {
      stdout.writeln('mutate4dart $mutate4dartVersion');
      return ExitCodes.success;
    }
    try {
      return await _mutate(_withConfig(args, options));
    } on _UsageError catch (e) {
      return _usageError(e.message);
    }
  }

  /// Re-parses [args] after the arguments of the config file, so the
  /// command line wins.
  ArgResults _withConfig(List<String> args, ArgResults options) {
    final ConfigFile config;
    try {
      config = ConfigFile.load(
        projectRoot ?? Directory.current.path,
        options['config'] as String,
        _parser,
        required: options.wasParsed('config'),
      );
    } on ConfigFileException catch (e) {
      throw _UsageError(e.message);
    }
    try {
      return _parser.parse([
        ...config.arguments,
        ...args,
        if (options.rest.isEmpty) ...config.paths,
      ]);
    } on FormatException catch (e) {
      throw _UsageError('${options['config']}: ${e.message}');
    }
  }

  Future<int> _mutate(ArgResults options) async {
    final root = projectRoot ?? Directory.current.path;
    final runner = MutationRunner(
      projectRoot: root,
      command: _testCommand(options, root),
      run: run,
      timeout: _timeout(options),
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
    final sample = _sample(options);
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
    ).limited(maxMutants: _intOption(options, 'max-mutants'), sample: sample);
    _printPlan(plan, sample);
    if (options['dry-run'] as bool) {
      _printDryRun(plan);
      return ExitCodes.success;
    }
    final results = await _runMutants(options, plan, runner);
    if (results == null) return ExitCodes.usageError;
    final report = MutationReport.build(
      results,
      projectRoot: root,
      lcovPath: lcov,
    );
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
        : _runParallel(plan, runner, jobs);
  }

  /// The files to mutate: `paths` (default `lib`) minus `--exclude`,
  /// narrowed to changed files in diff mode. Also keeps
  /// --collect-coverage from running the tests of untouched files.
  static List<String> _targetFiles(
    ArgResults options,
    String root,
    DiffLineMap? diff,
  ) => [
    for (final f in MutationPlan.dartFiles(
      root,
      options.rest.isEmpty ? const ['lib'] : options.rest,
      exclude: _excludes(options),
    ))
      if (diff == null || diff.hasRealChanges(f)) f,
  ];

  static String _render(String format, MutationReport report, String root) =>
      switch (format) {
        'json' => '${ReportRenderer(root).json(report)}\n',
        'markdown' => MarkdownRenderer(root).render(report),
        'stryker' => '${StrykerRenderer(root).json(report)}\n',
        'html' => StrykerRenderer(root).html(report),
        'junit' => JUnitRenderer(root).render(report),
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
    MutationRunner runner,
    int jobs,
  ) async {
    final parallel = ParallelMutationRunner(
      projectRoot: runner.projectRoot,
      command: runner.command,
      jobs: jobs,
      run: run,
      timeout: runner.timeout,
    );
    final interrupt = ProcessSignal.sigint.watch().listen((_) {
      parallel.dispose();
      stderr.writeln('\nInterrupted: shadow workspaces removed.');
      exit(130);
    });
    var done = 0;
    try {
      return await parallel.runAll([
        for (final m in plan.mutants) (mutant: m.mutant, tests: m.tests),
      ], onResult: (r) => _progress(++done, plan.mutants.length, r));
    } on RedBaselineException catch (e) {
      _printRedBaseline(e);
      return null;
    } finally {
      await interrupt.cancel();
    }
  }

  void _progress(int done, int total, MutantResult r) => stderr.writeln(
    '[$done/$total] ${r.mutant.file}:${r.mutant.line} '
    '${r.mutant.operator}: ${r.status.name}',
  );

  void _printRedBaseline(RedBaselineException e) => stderr
    ..writeln('Error: $e')
    ..writeln(
      'Fix the failing tests first: every mutant would look '
      'killed.',
    )
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
    final collector = CoverageCollector(
      projectRoot: root,
      command: command,
      run: run,
    );
    if (!collector.supported) {
      throw const _UsageError(
        '--collect-coverage needs flutter test. For '
        'Dart projects run dart test --coverage and format_coverage, then '
        'pass --lcov.',
      );
    }
    stderr.writeln(
      'Collecting coverage from ${tests.toSet().length} test '
      'file(s)...',
    );
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
    throw _UsageError(
      'No coverage file at ${options['lcov']}. Run the '
      'tests with coverage first (flutter test --coverage / dart test '
      '--coverage), pass --lcov, or use --no-coverage.',
    );
  }

  Future<DiffLineMap?> _diff(ArgResults options, String root) async {
    final base =
        options['diff-base'] as String? ??
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
            (throw _UsageError(
              'Unknown operator "$id". Known: '
              '${MutationOperator.values.map((o) => o.id).join(', ')}',
            )),
    };
  }

  static List<Glob> _excludes(ArgResults options) {
    try {
      return [
        for (final pattern in options['exclude'] as List<String>)
          Glob(pattern, context: p.posix),
      ];
    } on FormatException catch (e) {
      throw _UsageError('Invalid --exclude glob: ${e.message}');
    }
  }

  MutantTimeout _timeout(ArgResults options) {
    final raw = options['timeout-factor'] as String;
    final factor = double.tryParse(raw);
    if (factor == null || factor < 1) {
      throw _UsageError('--timeout-factor must be a number >= 1, got "$raw".');
    }
    return MutantTimeout(
      min: Duration(seconds: _intOption(options, 'min-timeout')!),
      factor: factor,
    );
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

  MutantSample? _sample(ArgResults options) {
    final raw = options['sample'] as String?;
    if (raw == null) return null;
    if (options['max-mutants'] != null) {
      throw const _UsageError(
        '--sample and --max-mutants cannot be '
        'combined.',
      );
    }
    final seedRaw = options['seed'] as String?;
    final seed = seedRaw == null
        ? Random().nextInt(1 << 32)
        : int.tryParse(seedRaw);
    if (seed == null) {
      throw _UsageError('--seed must be an integer, got "$seedRaw".');
    }
    try {
      return MutantSample.parse(raw, seed: seed);
    } on FormatException catch (e) {
      throw _UsageError('--sample: ${e.message}.');
    }
  }

  void _printPlan(MutationPlan plan, MutantSample? sample) {
    final ignored = plan.ignored == 0
        ? ''
        : ', ${plan.ignored} ignored by pragma';
    final sampled = sample == null
        ? ''
        : ' Sampled ${plan.mutants.length} of ${plan.sampledFrom} with '
              '--seed ${sample.seed}.';
    stderr.writeln(
      '${plan.found} mutants found, ${plan.mutants.length} '
      'to run (${plan.withoutTests} without tests importing their file'
      '$ignored).$sampled',
    );
    for (final file in plan.unparsed) {
      stderr.writeln('Skipped $file: it does not parse.');
    }
  }

  void _printDryRun(MutationPlan plan) {
    for (final m in plan.mutants) {
      final replacement = m.mutant.replacement.replaceAll('\n', r'\n');
      stdout.writeln(
        '${m.mutant.file}:${m.mutant.line} '
        '[${m.mutant.operator}] -> $replacement  '
        '(${m.tests.length} test file(s))',
      );
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
