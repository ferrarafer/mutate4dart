import 'dart:io';

import 'package:path/path.dart' as p;

/// Creates a temp project named `demo` with [files] (relative path →
/// content); deleted by the caller.
Directory createProject(Map<String, String> files, {bool flutter = false}) {
  final root = Directory.systemTemp.createTempSync('mutate4dart_test');
  final pubspec = flutter
      ? 'name: demo\ndependencies:\n  flutter:\n    sdk: flutter\n'
      : 'name: demo\n';
  writeFiles(root, {'pubspec.yaml': pubspec, ...files});
  return root;
}

/// Writes [files] (relative path → content) under [root].
void writeFiles(Directory root, Map<String, String> files) {
  files.forEach((path, content) {
    final file = File(p.join(root.path, path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  });
}
