# Changelog

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
