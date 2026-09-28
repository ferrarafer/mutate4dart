import 'dart:convert';
import 'dart:io';

import 'package:crap4dart/crap4dart.dart';
import 'package:path/path.dart' as p;

import '../run/mutation_runner.dart';

/// Mutation results of one method, next to its CRAP metrics.
class MethodReport {
  /// Creates a [MethodReport].
  MethodReport({
    required this.file,
    required this.name,
    required this.line,
    this.complexity,
    this.crap,
  });

  /// Project-relative file.
  final String file;

  /// `Class.method`, or `(top-level)` for code outside methods.
  final String name;

  /// First line of the method.
  final int line;

  /// Cyclomatic complexity, when known.
  final int? complexity;

  /// CRAP score, when coverage is known.
  final double? crap;

  /// Results of the mutants inside this method, in source order.
  final List<MutantResult> results = [];

  /// Mutants the tests detected (killed or timed out).
  int get detected => results.where((r) => r.detected).length;

  /// Mutants the tests missed.
  List<MutantResult> get survivors =>
      results.where((r) => r.status == MutantStatus.survived).toList();

  /// Mutants counted in the score (invalid ones are excluded).
  int get scored =>
      results.where((r) => r.status != MutantStatus.invalid).length;

  /// Detected share of scored mutants in `0..100`, or `null` when none.
  double? get score => scored == 0 ? null : 100 * detected / scored;
}

/// Results of a mutation run, grouped per method.
class MutationReport {
  MutationReport._(this.methods);

  /// Groups [results] per method of their files under [projectRoot];
  /// methods carry CRAP metrics from [lcovPath] when given.
  factory MutationReport.build(
    List<MutantResult> results, {
    required String projectRoot,
    String? lcovPath,
  }) {
    final byFile = <String, List<MutantResult>>{};
    for (final result in results) {
      (byFile[result.mutant.file] ??= []).add(result);
    }
    final methods = <MethodReport>[];
    byFile.forEach((file, fileResults) {
      methods.addAll(_groupByMethod(file, fileResults, projectRoot, lcovPath));
    });
    return MutationReport._(methods);
  }

  /// Methods that had at least one mutant.
  final List<MethodReport> methods;

  /// Every result.
  Iterable<MutantResult> get results => methods.expand((m) => m.results);

  /// Overall detected share of scored mutants, or `null` when none.
  double? get score {
    final scored = methods.fold(0, (n, m) => n + m.scored);
    final detected = methods.fold(0, (n, m) => n + m.detected);
    return scored == 0 ? null : 100 * detected / scored;
  }

  static List<MethodReport> _groupByMethod(
    String file,
    List<MutantResult> results,
    String projectRoot,
    String? lcovPath,
  ) {
    final absolute = p.join(projectRoot, file);
    final metrics = const CrapAnalyzer().analyze(
      [absolute],
      lcovPath: lcovPath,
      projectRoot: projectRoot,
    );
    final reports = [
      for (final m in metrics)
        MethodReport(
          file: file,
          name: '${m.method.className}.${m.method.methodName}',
          line: m.method.startLine,
          complexity: m.complexity,
          crap: m.crap,
        ),
    ];
    final ranges = [for (final m in metrics) m.method];
    MethodReport? topLevel;
    for (final result in results) {
      final line = result.mutant.line;
      final index =
          ranges.indexWhere((r) => r.startLine <= line && line <= r.endLine);
      if (index >= 0) {
        reports[index].results.add(result);
      } else {
        (topLevel ??= MethodReport(file: file, name: '(top-level)', line: 1))
            .results
            .add(result);
      }
    }
    return [
      ...reports.where((r) => r.results.isNotEmpty),
      if (topLevel != null) topLevel,
    ];
  }
}

/// Renders a [MutationReport] for the terminal or as JSON.
class ReportRenderer {
  /// Creates a [ReportRenderer] reading sources from [projectRoot].
  const ReportRenderer(this.projectRoot);

  /// Project root, used to show original and mutated source lines.
  final String projectRoot;

  /// A per-method table (lowest score first) followed by the survivors.
  String console(MutationReport report) {
    final out = StringBuffer()
      ..writeln(' SCORE  DET  SURV  INV   CRAP  CC  METHOD'
          '                                   FILE:LINE');
    final methods = [...report.methods]
      ..sort((a, b) => (a.score ?? 101).compareTo(b.score ?? 101));
    for (final m in methods) {
      out.writeln('${_pct(m.score)}  ${_n(m.detected, 3)}  '
          '${_n(m.survivors.length, 4)}  ${_n(m.results.length - m.scored, 3)}'
          '  ${_crap(m.crap)}  ${_n(m.complexity, 2)}  '
          '${m.name.padRight(40)}  ${m.file}:${m.line}');
    }
    final survivors =
        report.results.where((r) => r.status == MutantStatus.survived).toList();
    if (survivors.isNotEmpty) {
      out
        ..writeln()
        ..writeln('Survivors (the tests miss these changes):');
      for (final r in survivors) {
        out.writeln(_describe(r));
      }
    }
    out
      ..writeln()
      ..writeln('Mutation score: ${_pct(report.score).trim()} '
          '(${report.results.length} mutants)');
    return out.toString();
  }

  /// The report as a JSON document.
  String json(MutationReport report) =>
      const JsonEncoder.withIndent('  ').convert({
        'score': report.score,
        'methods': [
          for (final m in report.methods)
            {
              'file': m.file,
              'method': m.name,
              'line': m.line,
              'complexity': m.complexity,
              'crap': m.crap,
              'score': m.score,
              'mutants': [
                for (final r in m.results)
                  {
                    'line': r.mutant.line,
                    'operator': r.mutant.operator,
                    'replacement': r.mutant.replacement,
                    'status': r.status.name,
                    'tests': r.tests,
                  },
              ],
            },
        ],
      });

  String _describe(MutantResult r) {
    final lines = File(p.join(projectRoot, r.mutant.file)).readAsStringSync();
    final lineText = lines.split('\n')[r.mutant.line - 1].trim();
    final mutatedText =
        r.mutant.apply(lines).split('\n')[r.mutant.line - 1].trim();
    return '  ${r.mutant.file}:${r.mutant.line} [${r.mutant.operator}]\n'
        '    - $lineText\n'
        '    + $mutatedText';
  }

  static String _pct(double? v) =>
      v == null ? '   N/A' : '${v.toStringAsFixed(1).padLeft(5)}%';

  static String _crap(double? v) =>
      v == null ? '  N/A' : v.toStringAsFixed(1).padLeft(5);

  static String _n(int? v, int width) => (v?.toString() ?? '-').padLeft(width);
}
