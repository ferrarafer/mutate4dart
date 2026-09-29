# Changelog

## 0.5.1

- The coverage filter no longer drops mutants on lines the LCOV file
  does not list. The Dart VM instruments only lines with a call or an
  operator, so `return true;` / `return false;` never appear and their
  `boolean_literal` mutants were skipped as uncovered. Such a line now
  counts as covered when its enclosing method has an executed line.

## 0.5.0

- New operator `remove_call`: a call statement whose result is discarded
  (`repo.save(x);`, `callback();`, `await sync();`) is removed, exposing
  side effects no test checks. Calls on `super`, `print` and `debugPrint`
  are left alone, as are single-statement `if` and loop bodies. The
  replacement keeps the statement's newlines so line numbers stay stable.
- `--format stryker`: the Stryker mutation-testing report schema
  (version 2) for the Stryker dashboard and compatible tools. Each mutant
  lists the test files that ran as `coveredBy`, and as `killedBy` when a
  single file detected it.
- `--format html`: a self-contained page that embeds the Stryker report
  and shows it with the `mutation-testing-elements` viewer.
- `--dry-run` escapes newlines in replacements.

## 0.4.2

- Internal: `Mutate4DartRunner._mutate` back under the project's own
  CRAP limit (8.0). 0.4.1 was released at 9.0.

## 0.4.1

- `--diff` / `--diff-base` now narrow the target files to changed ones
  before anything else, so `--collect-coverage` only runs the tests of
  changed files, not the tests of every file under `lib/`.
- `--collect-coverage` reports an error when the test run writes no
  coverage file, instead of crashing.

## 0.4.0

- `--collect-coverage` (Flutter): runs only the test files that import the
  target files, with coverage, into `.mutate4dart/lcov.info`, so
  mutating one service no longer requires coverage from the whole suite.
  The user's `coverage/` is left untouched.

## 0.3.0

- `--format markdown`: a report for CI job summaries
  (`$GITHUB_STEP_SUMMARY`) and PR comments. It has the score line, a
  table of methods with survivors (with CRAP and CC), and each survivor
  as a collapsible `diff` of the original and mutated line.

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
