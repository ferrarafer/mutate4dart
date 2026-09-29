import 'dart:io';

import 'package:mutate4dart/src/internal/mutate4dart_internal.dart';
import 'package:test/test.dart';

import '../test_project.dart';

const _source = "String f(int a) {\n  return a > 1 ? '</script>' : '';\n}\n";

MutantResult _result(MutantStatus status, {List<String>? tests}) {
  final offset = _source.indexOf('>');
  return MutantResult(
    Mutant(
      file: 'lib/a.dart',
      line: 2,
      offset: offset,
      length: 1,
      replacement: '>=',
      operator: 'relational_boundary',
    ),
    status,
    tests ?? const ['test/a_test.dart'],
  );
}

void main() {
  late Directory root;

  setUp(() => root = createProject({'lib/a.dart': _source}));
  tearDown(() => root.deleteSync(recursive: true));

  MutationReport build(List<MutantResult> results) =>
      MutationReport.build(results, projectRoot: root.path);

  test('html embeds the report and loads the viewer', () {
    final html = StrykerRenderer(
      root.path,
    ).html(build([_result(MutantStatus.killed)]));
    expect(html, startsWith('<!DOCTYPE html>'));
    expect(html, contains('<script defer src="${StrykerRenderer.viewerUrl}">'));
    expect(html, contains('<mutation-test-report-app title-postfix='));
    expect(html, contains('app.report = {"schemaVersion":"2"'));
    expect(
      html,
      contains(
        r'\u'
        '003c/script>',
      ),
      reason: 'the source string literal is escaped',
    );
    expect(
      html.split('</script>'),
      hasLength(3),
      reason: 'only the two real script tags close a script block',
    );
  });
}
