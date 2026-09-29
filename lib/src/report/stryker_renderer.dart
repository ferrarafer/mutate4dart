import 'dart:convert';
import 'dart:io';

import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;

import '../run/mutation_runner.dart';
import 'mutation_report.dart';

/// Renders a [MutationReport] in the Stryker mutation-testing report
/// format (schema version 2), the interchange format of Stryker's
/// dashboard and of the `mutation-testing-elements` viewer.
///
/// Because mutate4dart knows which test files ran for each mutant, every
/// mutant carries `coveredBy`; `killedBy` is set when a single test file
/// ran, since then it is the one that detected the change.
class StrykerRenderer {
  /// Creates a [StrykerRenderer] reading sources from [projectRoot].
  const StrykerRenderer(this.projectRoot);

  /// Project root, used to embed the source files.
  final String projectRoot;

  /// CDN URL of the viewer used by [html].
  static const String viewerUrl = 'https://cdn.jsdelivr.net/npm/'
      'mutation-testing-elements@3/dist/mutation-test-elements.js';

  static const Map<MutantStatus, String> _status = {
    MutantStatus.killed: 'Killed',
    MutantStatus.survived: 'Survived',
    MutantStatus.timeout: 'Timeout',
    MutantStatus.invalid: 'CompileError',
  };

  /// The report as a Stryker JSON document.
  String json(MutationReport report) =>
      const JsonEncoder.withIndent('  ').convert(toMap(report));

  /// A self-contained HTML page: the report JSON embedded in a page that
  /// loads the `mutation-testing-elements` viewer from [viewerUrl].
  String html(MutationReport report) {
    // `<` is written as its JSON escape (backslash, `u003c`) so that a
    // `</script>` inside a source file cannot end the script block.
    final data = jsonEncode(toMap(report)).replaceAll('<', r'\u' '003c');
    return '<!DOCTYPE html>\n'
        '<html lang="en">\n'
        '<head>\n'
        '  <meta charset="utf-8">\n'
        '  <meta name="viewport" content="width=device-width, '
        'initial-scale=1">\n'
        '  <title>Mutation testing report</title>\n'
        '  <script defer src="$viewerUrl"></script>\n'
        '</head>\n'
        '<body>\n'
        '  <mutation-test-report-app title-postfix="mutate4dart">\n'
        '    This report needs a browser with custom elements support.\n'
        '  </mutation-test-report-app>\n'
        '  <script>\n'
        "    const app = document.querySelector('mutation-test-report-app');\n"
        '    const updateTheme = () => {\n'
        '      document.body.style.backgroundColor = app.themeBackgroundColor;\n'
        '    };\n'
        "    app.addEventListener('theme-changed', updateTheme);\n"
        '    updateTheme();\n'
        '    app.report = $data;\n'
        '  </script>\n'
        '</body>\n'
        '</html>\n';
  }

  /// The report as the JSON object of the Stryker schema.
  Map<String, Object?> toMap(MutationReport report) {
    final byFile = <String, List<MutantResult>>{};
    for (final result in report.results) {
      (byFile[result.mutant.file] ??= []).add(result);
    }
    final testFiles = {for (final r in report.results) ...r.tests}.toList()
      ..sort();
    var id = 0;
    return {
      'schemaVersion': '2',
      'thresholds': {'high': 80, 'low': 60},
      'projectRoot': projectRoot,
      'files': {
        for (final MapEntry(key: file, value: results) in byFile.entries)
          file: _file(file, results, () => '${++id}'),
      },
      'testFiles': {
        for (final test in testFiles)
          test: {
            'tests': [
              {'id': test, 'name': test},
            ],
          },
      },
    };
  }

  Map<String, Object?> _file(
    String file,
    List<MutantResult> results,
    String Function() nextId,
  ) {
    final source = File(p.join(projectRoot, file)).readAsStringSync();
    final lines = LineInfo.fromContent(source);
    return {
      'language': 'dart',
      'source': source,
      'mutants': [for (final r in results) _mutant(r, lines, nextId())],
    };
  }

  static Map<String, Object?> _mutant(
    MutantResult r,
    LineInfo lines,
    String id,
  ) =>
      {
        'id': id,
        'mutatorName': r.mutant.operator,
        'replacement': r.mutant.replacement,
        'location': {
          'start': _position(lines, r.mutant.offset),
          'end': _position(lines, r.mutant.offset + r.mutant.length),
        },
        'status': _status[r.status],
        'coveredBy': r.tests,
        if (r.detected && r.tests.length == 1) 'killedBy': r.tests,
      };

  static Map<String, int> _position(LineInfo lines, int offset) {
    final location = lines.getLocation(offset);
    return {'line': location.lineNumber, 'column': location.columnNumber};
  }
}
