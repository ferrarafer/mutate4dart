import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// How far [TestSelector] follows imports from a test file.
enum TestReach {
  /// Test files that import the mutated library themselves.
  direct,

  /// Test files that reach it through any chain of project imports
  /// (can select most of the suite when shared helpers import services).
  transitive,
}

/// Picks the test files that can detect a mutation in a library, from
/// the import graph of `lib/` and `test/`.
///
/// `package:<name>/...` URIs of the project itself resolve to `lib/`,
/// relative URIs to the importing file's directory. A `part` file maps to
/// the library that owns it.
class TestSelector {
  TestSelector._(this._imports, this._exports, this._partOwner, this._tests);

  /// Builds the import graph of the project at [projectRoot].
  factory TestSelector.build(String projectRoot) {
    final package = _packageName(projectRoot);
    final imports = <String, Set<String>>{};
    final exports = <String, Set<String>>{};
    final partOwner = <String, String>{};
    for (final file in _dartFiles(projectRoot)) {
      final unit = _parseDirectives(p.join(projectRoot, file));
      if (unit == null) continue;
      final targets = imports[file] = <String>{};
      for (final directive in unit.directives) {
        final uri = _uriOf(directive);
        final target = uri == null ? null : _resolve(uri, file, package);
        if (target == null) continue;
        if (directive is PartDirective) {
          partOwner[target] = file;
          continue;
        }
        targets.add(target);
        if (directive is ExportDirective) {
          (exports[target] ??= <String>{}).add(file);
        }
      }
    }
    final tests = imports.keys
        .where((f) => p.isWithin('test', f) && f.endsWith('_test.dart'))
        .toList()
      ..sort();
    return TestSelector._(imports, exports, partOwner, tests);
  }

  /// Library → the files it imports or exports.
  final Map<String, Set<String>> _imports;

  /// Library → the files that re-export it (barrels).
  final Map<String, Set<String>> _exports;
  final Map<String, String> _partOwner;
  final List<String> _tests;

  /// Test files (project-relative, sorted) that import [file] according
  /// to [reach]. [file] may be a `part` of another library; in direct
  /// mode, importing a barrel that re-exports it counts too.
  List<String> testsFor(String file, {TestReach reach = TestReach.direct}) {
    final library = _partOwner[p.normalize(file)] ?? p.normalize(file);
    final exposers = _exposers(library);
    return [
      for (final test in _tests)
        if (reach == TestReach.direct
            ? (_imports[test] ?? const <String>{}).any(exposers.contains)
            : _reaches(test, library))
          test,
    ];
  }

  /// [library] plus every file that re-exports it, transitively.
  Set<String> _exposers(String library) {
    final result = <String>{library};
    final queue = [library];
    while (queue.isNotEmpty) {
      for (final barrel in _exports[queue.removeLast()] ?? const <String>{}) {
        if (result.add(barrel)) queue.add(barrel);
      }
    }
    return result;
  }

  bool _reaches(String from, String library) {
    final seen = <String>{from};
    final queue = [from];
    while (queue.isNotEmpty) {
      for (final next in _imports[queue.removeLast()] ?? const <String>{}) {
        if (next == library) return true;
        if (seen.add(next)) queue.add(next);
      }
    }
    return false;
  }

  static String? _uriOf(Directive directive) => switch (directive) {
        UriBasedDirective(:final uri) => uri.stringValue,
        _ => null,
      };

  static String? _resolve(String uri, String from, String? package) {
    if (package != null && uri.startsWith('package:$package/')) {
      return p.join('lib', uri.substring('package:$package/'.length));
    }
    if (uri.contains(':')) return null; // dart:, other packages
    return p.normalize(p.join(p.dirname(from), uri));
  }

  static CompilationUnit? _parseDirectives(String path) {
    final result = parseString(
      content: File(path).readAsStringSync(),
      path: path,
      throwIfDiagnostics: false,
    );
    return result.unit;
  }

  static Iterable<String> _dartFiles(String root) sync* {
    for (final dir in const ['lib', 'test']) {
      final directory = Directory(p.join(root, dir));
      if (!directory.existsSync()) continue;
      for (final entity in directory.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          yield p.relative(entity.path, from: root);
        }
      }
    }
  }

  static String? _packageName(String root) {
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return null;
    final yaml = loadYaml(pubspec.readAsStringSync());
    return yaml is YamlMap ? yaml['name'] as String? : null;
  }
}
