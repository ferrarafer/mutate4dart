# mutate4dart

Mutation testing for Dart and Flutter projects. It is a sibling of
[crap4dart](https://github.com/ferrarafer/crap4dart), in the spirit of Uncle
Bob's `crap4java` / `mutate4java`.

Line coverage shows that a line *ran*. It doesn't show that a test would
*notice* if that line were wrong. mutate4dart makes small changes
(*mutants*) to covered code, such as `<` → `<=`, `&&` → `||` or `+` → `-`,
and runs the tests after each one. A mutant that no test catches
(*survived*) points at logic that is executed but not really tested.

```
$ mutate4dart lib/services/wager_service.dart     # a Flutter app, 184 mutants, 11.5 min
 SCORE  DET  SURV  INV   CRAP  CC  METHOD                                   FILE:LINE
 47.1%    8     9    1   11.1  11  WagerService._sumStrokesForPlayer        lib/services/wager_service.dart:899
 53.1%   17    15    6   26.0  26  WagerService._calculateWolfTotals        lib/services/wager_service.dart:781
 ...
Survivors (the tests miss these changes):
  lib/services/wager_service.dart:928 [arithmetic]
    - total += (entry.score - allocation);
    + total += (entry.score + allocation);
  ...
Mutation score: 69.9% (184 mutants)
```

## How it works

1. **Parse** each file under `lib/` (or the given paths) with
   `package:analyzer`, the SDK's own parser, and generate mutants. Generated
   code (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.mocks.dart`),
   annotations and `assert`s are skipped.
2. **Filter.** Only mutants on lines the tests executed are kept, using an
   LCOV file. A mutant no test runs can only survive. The Dart VM never
   lists a line that holds only a literal, such as `return true;`, so
   such a line counts as executed when its method has any executed line.
   With `--diff` / `--diff-base`, only mutants on changed lines are kept.
3. **Select tests** from the import graph. Only the `*_test.dart` files that
   import the mutated library are run: directly, through a barrel that
   re-exports it, or via its owning library for `part` files. The whole
   suite never runs per mutant, which is what makes this practical on a
   large app.
4. **Check the baseline.** The selected tests must pass on the unmutated
   code first. Otherwise every mutant would look killed.
5. **Run** mutants in parallel (`--jobs`, default `min(4, cores/2)`). Each
   worker gets a *shadow workspace*: a temporary mirror of the project, or
   of its pub workspace root, made of symlinks, where only the mutated
   files are real copies and build caches are private. The original
   project is never modified. With `--jobs 1`, mutants run in place
   instead, one at a time: the file is backed up to `.mutate4dart/backup/`
   and always restored, including on Ctrl-C and on the next run after a
   crash.
6. **Report** per method, next to the method's CRAP score. The riskiest
   (highest-CRAP) methods are mutated first, so `--max-mutants` spends a
   limited budget where it matters most.

Flutter projects (a pubspec that depends on `flutter`) run
`flutter test --no-pub <files>`. Pure Dart projects run
`dart test <files>`. Use `--test-command` to override, e.g.
`--test-command "fvm flutter test --no-pub"`.

## Install

```sh
dart pub global activate -sgit https://github.com/ferrarafer/mutate4dart.git
```

## Usage

```sh
mutate4dart lib/services/wager_service.dart --collect-coverage  # Flutter: one step
flutter test --coverage              # or: dart test --coverage + format_coverage
mutate4dart lib/services/wager_service.dart
mutate4dart --diff-base origin/next  # only lines changed on this branch
mutate4dart --dry-run                # list the planned mutants and tests
```

| Option | Default | Meaning |
|---|---|---|
| `paths...` | `lib` | Files or directories to mutate |
| `--lcov` | `coverage/lcov.info` | Coverage used to skip lines no test executes |
| `--[no-]coverage` | on | Turn the coverage filter off |
| `--collect-coverage` | | Flutter: run only the tests that import the target files, with coverage, into `.mutate4dart/lcov.info` (no full-suite coverage needed) |
| `--diff` / `--diff-base <ref>` | | Only mutate lines changed since `HEAD` / `<ref>` |
| `--test-command` | detected | Test command; test files are appended |
| `--reach` | `direct` | `transitive` also runs tests that reach the file through other libraries |
| `--operators` | all | Comma-separated operator ids (see below) |
| `--max-mutants N` | | Only the N mutants in the riskiest methods |
| `--threshold` | `0` | Minimum mutation score; below it exits `2` |
| `--format` | `console` | `json`, `markdown`, `stryker` or `html` write only the report to stdout (Markdown suits `$GITHUB_STEP_SUMMARY` or a PR comment; see [Reports](#reports)) |
| `--jobs N` | `min(4, cores/2)` | Parallel workers in shadow workspaces; `1` mutates in place |
| `--dry-run` | | Plan only, nothing is run |

Exit codes: `0` success, `1` usage/configuration error or tests failing on
unmutated code, `2` mutation score below `--threshold`.

## Operators

| Id | Mutation |
|---|---|
| `relational_boundary` | `<` ↔ `<=`, `>` ↔ `>=` |
| `equality` | `==` ↔ `!=` |
| `logical` | `&&` ↔ `\|\|` |
| `arithmetic` | `+` ↔ `-`, `*` ↔ `/`, `%` / `~/` → `*` (not string `+`) |
| `assignment` | `+=` ↔ `-=`, `*=` ↔ `/=`, `??=` → `=` |
| `increment` | `++` ↔ `--` |
| `boolean_literal` | `true` ↔ `false` |
| `remove_not` | `!x` → `x` |
| `negate_condition` | `if` / `while` / `?:` condition `c` → `!(c)` (skipped when `equality` or `remove_not` already yield the same program) |
| `null_coalescing` | `a ?? b` → `b` |
| `remove_call` | a call statement whose result is discarded is removed: `repo.save(x);`, `callback();`, `await sync();` → nothing (not `super.…()`, `print`, `debugPrint`, nor the body of an `if` or a loop) |

| `collection` | `isEmpty` ↔ `isNotEmpty`, `first` ↔ `last`, `xs.any(p)` ↔ `xs.every(p)` |

`remove_call` finds side effects no test checks, e.g. a `notifyListeners()`
or a repository write that the tests never observe. Removing the statement
always compiles, so it never adds `invalid` mutants.

Mutations that would break *type promotion* are skipped, because the
result would not compile. Promotion is how Dart treats `x` as non-null
(or as type `T`) after a check. The skipped cases are flipping `x == null`
/ `x != null`, and negating a condition or swapping its `&&`/`||` when it
contains a null check or an `is` test (`x == null || x.isEmpty`,
`o is Foo && o.bar`).

## Results

- **killed**: a selected test failed. The suite detects the change.
- **timeout**: the tests ran longer than 3× their baseline duration (at
  least 30 s), usually an infinite loop. Counted as detected.
- **survived**: every selected test passed. This is a gap.
- **invalid**: the mutant did not compile. Excluded from the score.

Score = detected / (detected + survived).

## Reports

All formats other than `console` write only the report to stdout, so
redirect it to a file:

```sh
mutate4dart --format markdown >> "$GITHUB_STEP_SUMMARY"   # CI job summary
mutate4dart --format stryker > mutation-report.json       # Stryker schema
mutate4dart --format html > mutation-report.html          # open in a browser
```

- `json`: mutate4dart's own per-method document, with CRAP and the test
  files run for each mutant.
- `markdown`: a score line, a table of the methods with survivors and each
  survivor as a collapsible `diff`, followed by the test files that ran
  without noticing and a one-line hint on what a test must check to
  detect that operator. A closing `file:line` block lists the survivors
  for grepping or for handing to an agent.
- `stryker`: the [Stryker mutation-testing report
  schema](https://github.com/stryker-mutator/mutation-testing-elements/tree/master/packages/report-schema)
  (version 2), accepted by the [Stryker
  dashboard](https://dashboard.stryker-mutator.io/) and by any tool that
  reads Stryker reports. Statuses map to `Killed`, `Survived`, `Timeout`
  and `CompileError`. Every mutant lists the test files that ran as
  `coveredBy`; when a single test file ran, it is also the `killedBy`.
- `html`: one self-contained page that embeds the Stryker JSON and shows
  it with the [mutation-testing-elements](https://github.com/stryker-mutator/mutation-testing-elements)
  viewer (loaded from jsDelivr, so viewing needs network access): per-file
  source with the mutants inline, filters by status and operator.

## Limitations (0.2)

- Each worker's first `flutter test` run compiles from a cold cache
  (about 10 s on a Flutter app); later runs take about 3–4 s per mutant.
  On an 11-core machine, 4 workers were fastest (2.5× over sequential).
  More workers contend for CPU and memory.
- Some surviving mutants are *equivalent*: they change the code without
  changing its behaviour, e.g. `i >= n` → `i == n` in a loop that counts
  up by one. Review survivors before writing tests.
- Without type information, a few mutants still don't compile (e.g. `*` →
  `/` on `int`s yields a `double`). They are reported as `invalid` and
  excluded from the score.
- No config file or baseline yet: options are CLI flags only.

## License

MIT, see [LICENSE](LICENSE).
