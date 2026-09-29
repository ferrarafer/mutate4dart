import 'dart:io';

import 'package:mutate4dart/src/internal/mutate4dart_internal.dart';
import 'package:test/test.dart';

import '../test_project.dart';

const _source =
    'int f(int a) {\n  return a + 1;\n}\n'
    'int g(int b) {\n  return b * 2;\n}\n';

void main() {
  late Directory root;

  setUp(() => root = createProject({'lib/a.dart': _source}));
  tearDown(() => root.deleteSync(recursive: true));

  String render(List<MutantResult> results) => MarkdownRenderer(
    root.path,
  ).render(MutationReport.build(results, projectRoot: root.path));

  test('counts test files past the first five and skips unknown hints', () {
    final tests = [for (var i = 1; i <= 7; i++) 'test/t${i}_test.dart'];
    final result = MutantResult(
      Mutant(
        file: 'lib/a.dart',
        line: 2,
        offset: _source.indexOf('+'),
        length: 1,
        replacement: '-',
        operator: 'custom',
      ),
      MutantStatus.survived,
      tests,
    );
    final md = render([result]);
    expect(md, contains('`test/t5_test.dart` and 2 more\n'));
    expect(md, isNot(contains('Hint:')));
  });
}
