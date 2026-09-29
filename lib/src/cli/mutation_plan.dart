import 'dart:io';

import 'package:crap4dart/crap4dart.dart';
import 'package:path/path.dart' as p;

import '../mutation/mutant.dart';
import '../mutation/mutant_finder.dart';
import '../selection/mutant_filters.dart';
import '../selection/test_selector.dart';

/// Generated code is never mutated.
const List<String> _generatedSuffixes = [
  '.g.dart',
  '.freezed.dart',
  '.gr.dart',
  '.mocks.dart',
];

/// A mutant scheduled to run together with the test files that cover it.
typedef PlannedMutant = ({Mutant mutant, List<String> tests, double risk});

/// The mutants to run, riskiest first, and why others were skipped.
class MutationPlan {
  MutationPlan._(this.mutants, this.found, this.withoutTests, this.unparsed);

  /// Plans mutants for the Dart [files] (project-relative) of the project
  /// at [projectRoot]. [lcovPath] enables the coverage filter and CRAP
  /// ordering; [maxMutants] keeps only the riskiest ones.
  factory MutationPlan.build({
    required String projectRoot,
    required List<String> files,
    required MutantFinder finder,
    required MutantFilter filter,
    required TestSelector selector,
    TestReach reach = TestReach.direct,
    String? lcovPath,
    int? maxMutants,
  }) {
    final planned = <PlannedMutant>[];
    var found = 0;
    var withoutTests = 0;
    final unparsed = <String>[];
    for (final file in files) {
      final List<Mutant> mutants;
      final List<MethodInfo> methods;
      try {
        final source = File(p.join(projectRoot, file)).readAsStringSync();
        mutants = finder.find(source, file: file);
        methods = _methods(source, file);
      } on DartParseException {
        unparsed.add(file);
        continue;
      }
      found += mutants.length;
      final kept = filter.apply(mutants, methods: methods);
      final tests = selector.testsFor(file, reach: reach);
      if (tests.isEmpty) {
        withoutTests += kept.length;
        continue;
      }
      final risk = _riskByLine(projectRoot, file, lcovPath);
      for (final mutant in kept) {
        planned.add((mutant: mutant, tests: tests, risk: risk(mutant.line)));
      }
    }
    // Stable sort: riskiest methods first, source order within a method.
    final ordered = _stableSortByRisk(planned);
    return MutationPlan._(
      maxMutants == null ? ordered : ordered.take(maxMutants).toList(),
      found,
      withoutTests,
      unparsed,
    );
  }

  /// Mutants to run.
  final List<PlannedMutant> mutants;

  /// Mutants generated before filtering.
  final int found;

  /// Mutants that passed the filters but have no test file importing
  /// their library.
  final int withoutTests;

  /// Files that could not be parsed.
  final List<String> unparsed;

  /// The Dart files under [paths] (files or directories, relative to
  /// [projectRoot]), excluding generated code, sorted.
  static List<String> dartFiles(String projectRoot, List<String> paths) {
    final files = <String>{};
    for (final path in paths) {
      final absolute = p.join(projectRoot, path);
      if (File(absolute).existsSync()) {
        files.add(p.normalize(path));
      } else if (Directory(absolute).existsSync()) {
        for (final entity in Directory(absolute).listSync(recursive: true)) {
          if (entity is File && entity.path.endsWith('.dart')) {
            files.add(p.relative(entity.path, from: projectRoot));
          }
        }
      }
    }
    return files.where((f) => !_generatedSuffixes.any(f.endsWith)).toList()
      ..sort();
  }

  /// The methods of [source], for the coverage filter's fallback on
  /// lines the LCOV file does not list.
  static List<MethodInfo> _methods(String source, String file) {
    final parsed = DartParser().parse(content: source, path: file);
    return const MethodExtractor(countConstructors: true)
        .extract(parsed.unit, parsed.lineInfo, filePath: file);
  }

  /// CRAP of the method containing each line (0 outside methods or
  /// without coverage).
  static double Function(int) _riskByLine(
    String projectRoot,
    String file,
    String? lcovPath,
  ) {
    if (lcovPath == null) return (_) => 0;
    final metrics = const CrapAnalyzer().analyze(
      [p.join(projectRoot, file)],
      lcovPath: lcovPath,
      projectRoot: projectRoot,
    );
    return (line) {
      for (final m in metrics) {
        if (m.method.startLine <= line && line <= m.method.endLine) {
          return m.crap ?? 0;
        }
      }
      return 0;
    };
  }

  static List<PlannedMutant> _stableSortByRisk(List<PlannedMutant> list) {
    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
    indexed.sort((a, b) {
      final byRisk = b.$2.risk.compareTo(a.$2.risk);
      return byRisk != 0 ? byRisk : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }
}
