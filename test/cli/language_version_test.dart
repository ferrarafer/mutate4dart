import 'dart:io';

import 'package:mutate4dart/src/internal/mutate4dart_internal.dart';
import 'package:test/test.dart';

import '../test_project.dart';

/// Valid up to Dart 3.12; the latest language version rejects `final` on
/// a function parameter.
const _source = 'int f({final int a = 0}) => a + 1;\n';

void main() {
  late Directory root;

  tearDown(() => root.deleteSync(recursive: true));

  MutationPlan plan() => MutationPlan.build(
    projectRoot: root.path,
    files: ['lib/a.dart'],
    finder: const MutantFinder(),
    filter: const MutantFilter(),
    selector: TestSelector.build(root.path),
  );

  test('files parse at their package language version', () {
    root = createProject({
      'lib/a.dart': _source,
      'test/a_test.dart': "import 'package:demo/a.dart';\nvoid main() {}\n",
    });
    writeFiles(root, {
      'pubspec.yaml': 'name: demo\nenvironment:\n  sdk: ^3.9.0\n',
    });
    final planned = plan();
    expect(planned.unparsed, isEmpty);
    expect(planned.mutants.map((m) => m.mutant.operator), ['arithmetic']);
  });
}
