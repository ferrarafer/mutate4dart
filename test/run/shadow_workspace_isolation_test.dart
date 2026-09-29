import 'dart:io';

import 'package:mutate4dart/src/internal/mutate4dart_internal.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_project.dart';

void main() {
  late Directory workspace;

  // A pub workspace: package config at the root, the project in app/.
  setUp(() {
    workspace = createProject({
      '.dart_tool/package_config.json': '{"packages": []}',
      '.dart_tool/flutter_build/cache': 'x',
      '.git/HEAD': 'ref',
      'core/lib/core.dart': '',
      'app/pubspec.yaml': 'name: app\n',
      'app/lib/a.dart': 'int a = 1;\n',
      'app/lib/b.dart': 'int b = 2;\n',
      'app/lib/src/c.dart': 'int c = 3;\n',
      'app/test/a_test.dart': '',
      'app/build/out': 'x',
      'app/.dart_tool/cache': 'x',
    });
  });
  tearDown(() => workspace.deleteSync(recursive: true));

  String app() => p.join(workspace.path, 'app');

  test('writing a copied file leaves the original untouched', () {
    final shadow = ShadowWorkspace.create(
      projectRoot: app(),
      files: ['lib/src/c.dart'],
    );
    File(p.join(shadow.projectRoot, 'lib/src/c.dart')).writeAsStringSync('!');
    expect(
      File(p.join(app(), 'lib/src/c.dart')).readAsStringSync(),
      'int c = 3;\n',
    );
    shadow.delete();
    expect(Directory(shadow.root).existsSync(), isFalse);
    expect(
      File(p.join(app(), 'lib/b.dart')).existsSync(),
      isTrue,
      reason: 'deleting the shadow must not follow symlinks',
    );
    shadow.delete(); // idempotent
  });
}
