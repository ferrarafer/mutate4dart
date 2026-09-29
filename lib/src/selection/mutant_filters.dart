import 'dart:io';

import 'package:crap_dart/crap_dart.dart';
import 'package:path/path.dart' as p;

import '../mutation/mutant.dart';

/// Line coverage of the project, keyed by project-relative file path.
class CoverageMap {
  /// Creates a [CoverageMap] from per-file hit counts.
  const CoverageMap(this.lineHits);

  /// Loads the LCOV file at [lcovPath], resolving paths against
  /// [projectRoot]. Entries outside the project (e.g. the pub cache) are
  /// ignored.
  factory CoverageMap.load(String lcovPath, String projectRoot) {
    final files = LcovParser(
      projectRoot: projectRoot,
    ).parse(File(lcovPath).readAsStringSync());
    return CoverageMap({
      for (final file in files)
        if (!p.isAbsolute(file.path) && !file.path.startsWith('..'))
          p.normalize(file.path): file.lineHits,
    });
  }

  /// Hit counts per line, per project-relative file.
  final Map<String, Map<int, int>> lineHits;

  /// Whether a test executed [line] of [file].
  bool isCovered(String file, int line) =>
      (lineHits[p.normalize(file)]?[line] ?? 0) > 0;

  /// Whether the LCOV file has an entry for [line] of [file]. The Dart VM
  /// only instruments lines with a call or an operator, so a line holding
  /// just a literal (`return true;`) never has one.
  bool isInstrumented(String file, int line) =>
      lineHits[p.normalize(file)]?.containsKey(line) ?? false;

  /// Whether a test executed any line of [file] in `start..end`.
  bool hasHitsIn(String file, int start, int end) {
    final hits = lineHits[p.normalize(file)];
    if (hits == null) return false;
    for (var line = start; line <= end; line++) {
      if ((hits[line] ?? 0) > 0) return true;
    }
    return false;
  }
}

/// Keeps the mutants a test run can say something about.
class MutantFilter {
  /// Creates a [MutantFilter]; a `null` [coverage] or [diff] disables
  /// that filter.
  const MutantFilter({this.coverage, this.diff});

  /// Only mutants on covered lines survive (a mutant no test executes
  /// always survives and says nothing new).
  final CoverageMap? coverage;

  /// Only mutants on lines added or changed in the diff survive.
  final DiffLineMap? diff;

  /// The [mutants] that pass every enabled filter. [methods] are the
  /// methods of the mutants' files: a mutant on a line the LCOV file does
  /// not list is kept when its method has an executed line, since the VM
  /// never lists lines holding only a literal (`return true;`).
  List<Mutant> apply(
    List<Mutant> mutants, {
    List<MethodInfo> methods = const [],
  }) => [
    for (final mutant in mutants)
      if (_covered(mutant, methods) && _changed(mutant)) mutant,
  ];

  bool _covered(Mutant m, List<MethodInfo> methods) {
    final coverage = this.coverage;
    if (coverage == null) return true;
    if (coverage.isCovered(m.file, m.line)) return true;
    if (coverage.isInstrumented(m.file, m.line)) return false;
    return methods.any(
      (method) =>
          method.startLine <= m.line &&
          m.line <= method.endLine &&
          coverage.hasHitsIn(m.file, method.startLine, method.endLine),
    );
  }

  bool _changed(Mutant m) => diff?.linesFor(m.file).contains(m.line) ?? true;
}
