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

  test('finds the resolution root above the project', () {
    expect(
      ShadowWorkspace.findResolutionRoot(app()),
      p.canonicalize(workspace.path),
    );
    final lone = createProject({});
    addTearDown(() => lone.deleteSync(recursive: true));
    expect(
      ShadowWorkspace.findResolutionRoot(lone.path),
      p.canonicalize(lone.path),
    );
  });

  test('mirrors the workspace, copying only the mutated files', () {
    final shadow = ShadowWorkspace.create(
      projectRoot: app(),
      files: ['lib/a.dart'],
    );
    addTearDown(shadow.delete);
    bool isLink(String path) =>
        FileSystemEntity.isLinkSync(p.join(shadow.root, path));
    expect(shadow.projectRoot, p.join(shadow.root, 'app'));
    expect(isLink('core'), isTrue);
    expect(isLink('app'), isFalse);
    expect(isLink('app/lib'), isFalse);
    expect(isLink('app/lib/a.dart'), isFalse, reason: 'real copy');
    expect(isLink('app/lib/b.dart'), isTrue);
    expect(isLink('app/lib/src'), isTrue);
    expect(isLink('app/test'), isTrue);
    // Per-worker build state is not shared; resolution files are copied.
    expect(
      File(
        p.join(shadow.root, '.dart_tool/package_config.json'),
      ).readAsStringSync(),
      '{"packages": []}',
    );
    for (final absent in [
      '.dart_tool/flutter_build',
      '.git',
      'app/build',
      'app/.dart_tool/cache',
    ]) {
      expect(
        FileSystemEntity.typeSync(p.join(shadow.root, absent)),
        FileSystemEntityType.notFound,
        reason: absent,
      );
    }
  });
}
