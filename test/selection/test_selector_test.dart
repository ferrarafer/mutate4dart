import 'dart:io';

import 'package:mutate4dart/mutate4dart.dart';
import 'package:test/test.dart';

import '../test_project.dart';

void main() {
  late Directory root;

  setUp(() {
    root = createProject({
      'lib/a.dart': 'int a() => 1;\n',
      'lib/b.dart': "import 'a.dart';\nint b() => a();\n",
      'lib/barrel.dart': "export 'src/c.dart';\n",
      'lib/src/c.dart': 'int c() => 3;\n',
      'lib/owner.dart': "part 'owned.dart';\n",
      'lib/owned.dart': "part of 'owner.dart';\nint d() => 4;\n",
      'test/a_test.dart': "import 'package:demo/a.dart';\nvoid main() {}\n",
      'test/b_test.dart': "import 'package:demo/b.dart';\nvoid main() {}\n",
      'test/barrel_test.dart':
          "import 'package:demo/barrel.dart';\nvoid main() {}\n",
      'test/owner_test.dart':
          "import 'package:demo/owner.dart';\nvoid main() {}\n",
      'test/helper.dart': "import 'package:demo/a.dart';\n",
      'test/rel/rel_test.dart': "import '../../lib/a.dart';\nvoid main() {}\n",
    });
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('direct: test files that import the library', () {
    final selector = TestSelector.build(root.path);
    expect(selector.testsFor('lib/a.dart'),
        ['test/a_test.dart', 'test/rel/rel_test.dart']);
  });

  test('transitive: also tests reaching it through other libraries', () {
    final selector = TestSelector.build(root.path);
    expect(selector.testsFor('lib/a.dart', reach: TestReach.transitive),
        ['test/a_test.dart', 'test/b_test.dart', 'test/rel/rel_test.dart']);
  });

  test('direct follows barrels that re-export the library', () {
    final selector = TestSelector.build(root.path);
    expect(selector.testsFor('lib/src/c.dart'), ['test/barrel_test.dart']);
  });

  test('a part file maps to the library that owns it', () {
    final selector = TestSelector.build(root.path);
    expect(selector.testsFor('lib/owned.dart'), ['test/owner_test.dart']);
  });

  test('files no test imports have no tests', () {
    final selector = TestSelector.build(root.path);
    expect(selector.testsFor('lib/unknown.dart'), isEmpty);
  });
}
