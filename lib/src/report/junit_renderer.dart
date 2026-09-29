import 'dart:io';

import 'package:path/path.dart' as p;

import '../mutation/mutant.dart';
import '../run/mutation_runner.dart';
import 'mutation_report.dart';

/// Renders a [MutationReport] as JUnit XML, the test report format CI
/// systems (GitLab, Jenkins, Azure DevOps, ...) show natively.
///
/// Each mutated file is a `<testsuite>` and each mutant a `<testcase>`
/// whose `classname` is its method. A survivor is a `<failure>` carrying
/// the original and mutated line, the test files that ran and the
/// operator's hint; an invalid mutant is `<skipped>`; killed and timed
/// out mutants pass.
class JUnitRenderer {
  /// Creates a [JUnitRenderer] reading sources from [projectRoot].
  const JUnitRenderer(this.projectRoot);

  /// Project root, used to show original and mutated source.
  final String projectRoot;

  /// The report as a JUnit XML document.
  String render(MutationReport report) {
    final byFile = <String, List<(MethodReport, MutantResult)>>{};
    for (final m in report.methods) {
      for (final r in m.results) {
        (byFile[m.file] ??= []).add((m, r));
      }
    }
    final all = report.results.toList();
    final out = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<testsuites name="mutate4dart"${_counts(all)}>');
    byFile.forEach((file, cases) => _suite(out, file, cases));
    out.writeln('</testsuites>');
    return out.toString();
  }

  void _suite(
    StringBuffer out,
    String file,
    List<(MethodReport, MutantResult)> cases,
  ) {
    final source = File(p.join(projectRoot, file)).readAsStringSync();
    out.writeln(
      '  <testsuite name="${_escape(file)}"'
      '${_counts([for (final (_, r) in cases) r])}>',
    );
    for (final (method, r) in cases) {
      out.writeln(
        '    <testcase classname="${_escape(method.name)}" '
        'name="${_escape(_name(r.mutant, source))}" '
        'file="${_escape(file)}" line="${r.mutant.line}">',
      );
      _outcome(out, r, source);
      out.writeln('    </testcase>');
    }
    out.writeln('  </testsuite>');
  }

  static void _outcome(StringBuffer out, MutantResult r, String source) {
    switch (r.status) {
      case MutantStatus.survived:
        out
          ..writeln(
            '      <failure type="survived" message="Survived: no '
            'test detected this change">',
          )
          ..writeln(_escape(_details(r, source)))
          ..writeln('      </failure>');
      case MutantStatus.invalid:
        out.writeln(
          '      <skipped message="Invalid: the mutant does not '
          'compile"/>',
        );
      case MutantStatus.killed || MutantStatus.timeout:
        break;
    }
  }

  /// `line 2 arithmetic: + -> -`, with newlines shown as `\n` and a
  /// removed statement as `(removed)`.
  static String _name(Mutant m, String source) {
    String flat(String s) => s.replaceAll('\n', r'\n');
    final to = m.replacement.trim().isEmpty ? '(removed)' : flat(m.replacement);
    return 'line ${m.line} ${m.operator}: ${flat(m.original(source))} -> $to';
  }

  static String _details(MutantResult r, String source) {
    final index = r.mutant.line - 1;
    final before = source.split('\n')[index].trim();
    final after = r.mutant.apply(source).split('\n')[index].trim();
    final hint = MutationOperator.byId(r.mutant.operator)?.hint;
    return '${r.mutant.file}:${r.mutant.line} ${r.mutant.operator}\n'
        '- $before\n+ $after\n'
        'Tests run: ${r.tests.isEmpty ? 'none' : r.tests.join(', ')}'
        '${hint == null ? '' : '\nHint: $hint'}';
  }

  /// `tests`, `failures` and `skipped` attributes for [results].
  static String _counts(List<MutantResult> results) {
    int count(MutantStatus s) => results.where((r) => r.status == s).length;
    return ' tests="${results.length}" '
        'failures="${count(MutantStatus.survived)}" '
        'errors="0" skipped="${count(MutantStatus.invalid)}"';
  }

  /// Escapes XML special characters and drops characters XML 1.0 does
  /// not allow.
  static String _escape(String s) => s
      .replaceAll(RegExp('[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
