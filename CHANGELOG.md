# Changelog

## 0.2.0

- Parallel runs: `--jobs N` (default `min(4, cores/2)`) runs mutants
  concurrently, each worker in a *shadow workspace* (a symlink mirror of
  the project or its pub workspace root, with real copies of the mutated
  files and private build caches). The original project is never touched.
  `--jobs 1` keeps the in-place mode. On a Flutter app, 4 workers were
  2.5× faster than sequential.
- Mutants that break type promotion are no longer generated: null
  comparisons are not flipped, and conditions or `&&`/`||` chains
  containing a null check or an `is` test are not negated or swapped. On
  a Flutter service this removed 31 of 184 mutants, most of which did not
  compile.

## 0.1.0

First version.

- AST mutants (`package:analyzer`) with 10 operators: relational boundary,
  equality, logical, arithmetic, compound assignment, increment, boolean
  literal, remove `!`, negate condition, `??` fallback.
- Coverage filter (LCOV) and diff filter (`--diff`, `--diff-base`).
- Test selection from the import graph (`--reach direct|transitive`),
  following barrels and `part` files.
- Flutter / Dart test command detection, `--test-command` override.
- Baseline check, per-mutant timeout, compile failures reported as
  `invalid`, crash-safe backups with automatic recovery.
- Per-method report next to crap4dart's CRAP score, riskiest methods
  first, `--max-mutants`, `--threshold`, console and JSON output.
