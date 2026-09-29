import 'dart:io';

import 'package:mutate4dart/src/internal/mutate4dart_internal.dart';
import 'package:test/test.dart';

import '../test_project.dart';

/// A project whose `lib/a.dart` has literal-only `return` lines (3 and
/// 5), which the Dart VM never lists in LCOV, inside a method that ran,
/// and the same shape in a method that never ran (lines 9 and 11).
Directory _project() => createProject({
  'lib/a.dart':
      'bool ran(int a) {\n'
      '  if (a > 1) {\n'
      '    return true;\n'
      '  }\n'
      '  return false;\n'
      '}\n'
      'bool never(int a) {\n'
      '  if (a > 1) {\n'
      '    return true;\n'
      '  }\n'
      '  return false;\n'
      '}\n'
      'bool flag = true;\n',
  'test/a_test.dart': "import 'package:demo/a.dart';\nvoid main() {}\n",
  'coverage/lcov.info': 'SF:lib/a.dart\nDA:2,1\nDA:8,0\nend_of_record\n',
});

void main() {
  late Directory root;

  setUp(() => root = _project());
  tearDown(() => root.deleteSync(recursive: true));

  test('keeps unlisted literal lines of methods that ran', () {
    final lcov = '${root.path}/coverage/lcov.info';
    final plan = MutationPlan.build(
      projectRoot: root.path,
      files: ['lib/a.dart'],
      finder: const MutantFinder(),
      filter: MutantFilter(coverage: CoverageMap.load(lcov, root.path)),
      selector: TestSelector.build(root.path),
      lcovPath: lcov,
    );
    final lines = plan.mutants.map((m) => m.mutant.line).toList()..sort();
    expect(
      lines,
      [2, 2, 3, 5],
      reason:
          'the condition and both returns of ran(); nothing of '
          'never() nor the top-level flag',
    );
    expect(plan.found, 9);
    expect(plan.ignored, 0);
  });

  test('drops and counts mutants under an ignore pragma', () {
    writeFiles(root, {
      'lib/a.dart':
          'bool ran(int a) {\n'
          '  if (a > 1) { // mutate4dart: ignore relational_boundary\n'
          '    return true;\n'
          '  }\n'
          '  // mutate4dart: ignore\n'
          '  return false;\n'
          '}\n',
    });
    final plan = MutationPlan.build(
      projectRoot: root.path,
      files: ['lib/a.dart'],
      finder: const MutantFinder(),
      filter: const MutantFilter(),
      selector: TestSelector.build(root.path),
    );
    expect(plan.ignored, 2);
    expect(plan.found, 4);
    expect(
      [for (final m in plan.mutants) m.mutant.operator],
      ['negate_condition', 'boolean_literal'],
    );
  });
}
