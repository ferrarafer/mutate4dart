# Changelog

## 0.12.1

- crap_dart 0.13.1: sources parse at their package's language version.
  With 0.13.0 (analyzer 14 parsing at the newest version), a file using
  `final` on a function parameter, valid in a Dart 3.9 project, was
  skipped as "does not parse".
- The finder and the method extraction get the file's absolute path, so
  the language version comes from the target project's `pubspec.yaml`
  whatever the working directory.

## 0.12.0

- Depends on [crap_dart](https://github.com/ferrarafer/crap_dart) 0.13.0,
  the renamed continuation of crap4dart, instead of the crap4dart fork.
  The dogfooding config is `crap_dart.yaml`.
- `analyzer` 7.3 -> 14.4, SDK `^3.11.0`, `lints` 6.1, `test` 1.32;
  sources use the Dart 3.7+ "tall" formatter style.
- The public library `package:mutate4dart/mutate4dart.dart` exports only
  `Mutate4DartRunner`, `ExitCodes`, `defaultJobs`, `mutate4dartVersion`,
  `ProcessRunner`, `CommandResult` and `runProcess`. The rest is internal;
  the CLI and its JSON, Stryker and JUnit reports are the contract.
- pubspec topics and issue tracker for pub.dev. `publish_to: none` stays
  until crap_dart is published and replaces the git dependency.

## 0.11.0

- `--sample N` / `--sample P%` runs a random subset of the planned
  mutants (still riskiest first), for an unbiased score estimate on
  large projects. `--seed S` repeats a sample; without it the seed is
  random and printed in the plan summary. Cannot be combined with
  `--max-mutants`.
- `MutationPlan.build` no longer takes `maxMutants`; use
  `MutationPlan.limited(maxMutants:, sample:)`.

## 0.10.0

- `--format junit`: JUnit XML for CI test report views (GitLab, Jenkins,
  Azure DevOps). One test suite per mutated file, one test case per
  mutant under its method; survivors are failures carrying the diff, the
  test files run and the operator's hint, invalid mutants are skipped.

## 0.9.0

- Config file: `mutate4dart.yaml` at the project root, or `--config
  <file>`, holds option defaults with snake_case keys (`max_mutants: 200`,
  `exclude: [...]`, `paths: [...]`). The command line wins; `exclude`
  globs from both add up; `paths` applies when the command line has
  none. Unknown keys and bad values exit 1.
- `--collect-coverage` and `--diff` are negatable (`--no-collect-coverage`,
  `--no-diff`), so the command line can turn off a config file's `true`.

## 0.8.0

- `--exclude <glob>` (repeatable) skips files whose project-relative path
  matches the glob, such as `lib/l10n/**`, on top of the generated code
  that is always skipped.
- `--min-timeout S` (default 30) and `--timeout-factor F` (default 3) set
  the mutant timeout, `max(S, F × baseline)`, for slow widget tests or
  tight CI budgets. Both apply in place and in parallel shadows.
- `MutationRunner` and `ParallelMutationRunner` take a `MutantTimeout`
  instead of `minTimeout` / `timeoutFactor`.

## 0.7.1

- `boolean_literal` no longer flips `growable: true/false`
  (`toList(growable: false)`, `List.filled(..., growable: true)`). The
  flag only tunes performance, so those mutants always survived; a run
  on a Flutter service produced two of them.
- README: example output and limitations refreshed from a 0.7.1 run.

## 0.7.0

- Ignore pragma: `// mutate4dart: ignore` silences the mutants of its
  line (trailing) or of the next line (alone on a line); operator ids
  after `ignore` narrow it. Ignored mutants are not run or scored, and
  the plan summary counts them. Meant for equivalent mutants.

## 0.6.0

- New operator `collection`: `isEmpty` ↔ `isNotEmpty`, `first` ↔ `last`
  and `xs.any(p)` ↔ `xs.every(p)`. Each pair has the same type, so the
  mutants always compile.
- `assignment` also turns `a ??= b` into `a = b`.
- Markdown report: each survivor now lists the test files that ran and a
  hint on what a test must check to detect that operator, and the
  survivors are repeated as a `file:line` block at the end.
- `MutationOperator` carries a `hint` and has a `byId` lookup.

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
