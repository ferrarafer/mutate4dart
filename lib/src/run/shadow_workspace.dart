import 'dart:io';

import 'package:path/path.dart' as p;

/// Package-resolution files copied into a shadow's `.dart_tool/`.
const List<String> _resolutionFiles = [
  'package_config.json',
  'package_graph.json',
];

/// Build output that must not be shared between concurrent test runs.
const Set<String> _perWorkerDirs = {'.dart_tool', 'build', '.mutate4dart'};

/// An isolated view of a project for one parallel worker.
///
/// It mirrors the *resolution root* (the nearest directory with
/// `.dart_tool/package_config.json`, e.g. a pub workspace root above the
/// project) with symlinks. Only the directories leading to the mutated
/// files are real, and the files themselves are real copies. So a worker
/// can rewrite them while the original project stays untouched.
/// `package_config.json` keeps its relative paths, so they resolve inside
/// the shadow. `.dart_tool`, `build` and `.git` are not shared: each
/// worker's test runs get their own build cache.
class ShadowWorkspace {
  ShadowWorkspace._(this.root, this.projectRoot);

  /// Creates a shadow of [projectRoot] under a new temporary directory in
  /// which [files] (project-relative) are real, writable copies.
  factory ShadowWorkspace.create({
    required String projectRoot,
    required Iterable<String> files,
  }) {
    final source = p.canonicalize(projectRoot);
    final resolutionRoot = findResolutionRoot(source);
    final copied = {for (final f in files) p.join(source, f)};
    final realDirs = <String>{
      for (final path in [source, ...copied])
        ..._ancestors(path, upTo: resolutionRoot),
    };
    final root = Directory.systemTemp.createTempSync('mutate4dart_w').path;
    _mirror(resolutionRoot, root, realDirs, copied);
    return ShadowWorkspace._(
      root,
      p.join(root, p.relative(source, from: resolutionRoot)),
    );
  }

  /// Root of the shadow (mirror of the resolution root).
  final String root;

  /// The project root inside the shadow.
  final String projectRoot;

  /// Deletes the shadow. Symlinks are removed, not followed.
  void delete() {
    final dir = Directory(root);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  /// The nearest directory at or above [projectRoot] that holds
  /// `.dart_tool/package_config.json`, or [projectRoot] when none does.
  static String findResolutionRoot(String projectRoot) {
    var dir = p.canonicalize(projectRoot);
    while (true) {
      if (File(p.join(dir, '.dart_tool', 'package_config.json')).existsSync()) {
        return dir;
      }
      final parent = p.dirname(dir);
      if (parent == dir) return p.canonicalize(projectRoot);
      dir = parent;
    }
  }

  /// [path]'s directory and its ancestors down from [upTo] (inclusive).
  static Iterable<String> _ancestors(String path,
      {required String upTo}) sync* {
    var dir = FileSystemEntity.isDirectorySync(path) ? path : p.dirname(path);
    while (dir == upTo || p.isWithin(upTo, dir)) {
      yield dir;
      if (dir == upTo) return;
      dir = p.dirname(dir);
    }
  }

  static void _mirror(
    String from,
    String to,
    Set<String> realDirs,
    Set<String> copied,
  ) {
    Directory(to).createSync(recursive: true);
    for (final entity in Directory(from).listSync(followLinks: false)) {
      final name = p.basename(entity.path);
      final target = p.join(to, name);
      if (name == '.git') continue;
      if (_perWorkerDirs.contains(name) && realDirs.contains(from)) {
        if (name == '.dart_tool') _copyResolution(entity.path, target);
      } else if (realDirs.contains(entity.path)) {
        _mirror(entity.path, target, realDirs, copied);
      } else if (copied.contains(entity.path)) {
        File(entity.path).copySync(target);
      } else {
        Link(target).createSync(entity.path);
      }
    }
  }

  static void _copyResolution(String dartTool, String target) {
    Directory(target).createSync();
    for (final name in _resolutionFiles) {
      final file = File(p.join(dartTool, name));
      if (file.existsSync()) file.copySync(p.join(target, name));
    }
  }
}
