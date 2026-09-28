import 'dart:io';

import 'package:crap4dart/crap4dart.dart';
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
    final files = LcovParser(projectRoot: projectRoot)
        .parse(File(lcovPath).readAsStringSync());
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

  /// The [mutants] that pass every enabled filter.
  List<Mutant> apply(List<Mutant> mutants) => [
        for (final mutant in mutants)
          if (_covered(mutant) && _changed(mutant)) mutant,
      ];

  bool _covered(Mutant m) => coverage?.isCovered(m.file, m.line) ?? true;

  bool _changed(Mutant m) => diff?.linesFor(m.file).contains(m.line) ?? true;
}
