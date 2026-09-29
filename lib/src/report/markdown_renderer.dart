import 'dart:io';

import 'package:path/path.dart' as p;

import '../mutation/mutant.dart';
import '../run/mutation_runner.dart';
import 'mutation_report.dart';

/// Renders a [MutationReport] as GitHub-flavoured Markdown, for a CI job
/// summary (`$GITHUB_STEP_SUMMARY`) or a pull request comment.
///
/// Methods without survivors are only counted, so the table stays short
/// on large diffs. Survivors are listed as collapsible `diff` blocks with
/// the original and mutated line.
class MarkdownRenderer {
  /// Creates a [MarkdownRenderer] reading sources from [projectRoot].
  const MarkdownRenderer(this.projectRoot);

  /// Project root, used to show original and mutated source lines.
  final String projectRoot;

  /// The report as Markdown under a `## Mutation testing` heading.
  String render(MutationReport report) {
    final out = StringBuffer()..writeln('## Mutation testing (mutate4dart)\n');
    final results = report.results.toList();
    if (results.isEmpty) {
      out.writeln('No mutants to run: no covered, mutable code in scope.');
      return out.toString();
    }
    out
      ..writeln(_summary(report, results))
      ..writeln();
    final weak = report.methods.where((m) => m.survivors.isNotEmpty).toList()
      ..sort((a, b) => (a.score ?? 101).compareTo(b.score ?? 101));
    if (weak.isEmpty) {
      out.writeln('Every mutant was detected by the tests. ✅');
      return out.toString();
    }
    out
      ..writeln('| Score | Survived | CRAP | CC | Method | Location |')
      ..writeln('|---:|---:|---:|---:|---|---|');
    for (final m in weak) {
      out.writeln(
        '| ${_pct(m.score)} | ${m.survivors.length} | '
        '${m.crap?.toStringAsFixed(1) ?? 'N/A'} | ${m.complexity ?? '-'} | '
        '`${m.name}` | `${m.file}:${m.line}` |',
      );
    }
    final fullyTested = report.methods.length - weak.length;
    if (fullyTested > 0) {
      out.writeln('\n$fullyTested more method(s) had every mutant detected.');
    }
    out
      ..writeln()
      ..writeln(
        '<details><summary>Survivors: changes no test detects '
        '(${weak.fold(0, (n, m) => n + m.survivors.length)})</summary>\n',
      );
    final survivors = [for (final m in weak) ...m.survivors];
    for (final r in survivors) {
      out.writeln(_survivor(r));
    }
    out
      ..writeln('Survivors as `file:line`:\n')
      ..writeln('```');
    for (final r in survivors) {
      out.writeln('${r.mutant.file}:${r.mutant.line}  ${r.mutant.operator}');
    }
    out
      ..writeln('```')
      ..writeln('</details>');
    return out.toString();
  }

  String _summary(MutationReport report, List<MutantResult> results) {
    int count(MutantStatus s) => results.where((r) => r.status == s).length;
    final detected = count(MutantStatus.killed) + count(MutantStatus.timeout);
    return '**Score: ${_pct(report.score)}**, ${results.length} mutants: '
        '$detected detected, ${count(MutantStatus.survived)} survived, '
        '${count(MutantStatus.invalid)} invalid.';
  }

  /// Where a test file is listed after this many, the rest are counted.
  static const int _maxTestsListed = 5;

  /// The survivor's diff, the test files that ran and did not notice, and
  /// the operator's hint on what a test needs to check.
  String _survivor(MutantResult r) {
    final source = File(p.join(projectRoot, r.mutant.file)).readAsStringSync();
    final index = r.mutant.line - 1;
    final before = source.split('\n')[index].trim();
    final after = r.mutant.apply(source).split('\n')[index].trim();
    final hint = MutationOperator.byId(r.mutant.operator)?.hint;
    return '`${r.mutant.file}:${r.mutant.line}` ${r.mutant.operator}\n'
        '```diff\n- $before\n+ $after\n```\n'
        'Tests run: ${_tests(r.tests)}${hint == null ? '' : '\nHint: $hint'}\n';
  }

  static String _tests(List<String> tests) {
    if (tests.isEmpty) return 'none';
    final listed = tests.take(_maxTestsListed).map((t) => '`$t`').join(', ');
    final more = tests.length - _maxTestsListed;
    return more > 0 ? '$listed and $more more' : listed;
  }

  static String _pct(double? v) =>
      v == null ? 'N/A' : '${v.toStringAsFixed(1)}%';
}
