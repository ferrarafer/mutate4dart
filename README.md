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
 SCORE  DET  SURV  INV   CRAP  CC  METHOD                                    FILE:LINE
 60.0%    6     4    0   26.0  26  WagerService._calculateWolfTotals         lib/services/wager_service.dart:781
 ...
Survivors (the tests miss these changes):
  lib/services/wager_service.dart:828 [logical]
    - if (winningIndex == -1 && !settings.carryOverWhenTied) continue;
    + if (winningIndex == -1 || !settings.carryOverWhenTied) continue;
```

## How it works

1. **Parse** each file under `lib/` (or the given paths) with
   `package:analyzer`, the SDK's own parser, and generate mutants. Generated
   code (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.mocks.dart`),
   annotations and `assert`s are skipped.
2. **Filter.** Only mutants on lines the tests executed are kept, using an
   LCOV file. A mutant no test runs can only survive. With `--diff` /
   `--diff-base`, only mutants on changed lines are kept.
3. **Select tests** from the import graph. Only the `*_test.dart` files that
   import the mutated library are run: directly, through a barrel that
   re-exports it, or via its owning library for `part` files. The whole
   suite never runs per mutant, which is what makes this practical on a
   large app.
4. **Check the baseline.** The selected tests must pass on the unmutated
   code first. Otherwise every mutant would look killed.
5. **Run** one mutant at a time. The file is backed up to
   `.mutate4dart/backup/` and always restored, including on Ctrl-C and on
   the next run after a crash.
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
| `--diff` / `--diff-base <ref>` | | Only mutate lines changed since `HEAD` / `<ref>` |
| `--test-command` | detected | Test command; test files are appended |
| `--reach` | `direct` | `transitive` also runs tests that reach the file through other libraries |
| `--operators` | all | Comma-separated operator ids (see below) |
| `--max-mutants N` | | Only the N mutants in the riskiest methods |
| `--threshold` | `0` | Minimum mutation score; below it exits `2` |
| `--format` | `console` | `json` writes only JSON to stdout |
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
| `assignment` | `+=` ↔ `-=`, `*=` ↔ `/=` |
| `increment` | `++` ↔ `--` |
| `boolean_literal` | `true` ↔ `false` |
| `remove_not` | `!x` → `x` |
| `negate_condition` | `if` / `while` / `?:` condition `c` → `!(c)` (skipped when `equality` or `remove_not` already yield the same program) |
| `null_coalescing` | `a ?? b` → `b` |

## Results

- **killed**: a selected test failed. The suite detects the change.
- **timeout**: the tests ran longer than 3× their baseline duration (at
  least 30 s), usually an infinite loop. Counted as detected.
- **survived**: every selected test passed. This is a gap.
- **invalid**: the mutant did not compile. Excluded from the score.

Score = detected / (detected + survived).

## Limitations (0.1)

- Mutants run one at a time, taking about 3–4 s each on a Flutter test
  file (Flutter reuses its build between runs). Parallel runs in isolated
  copies are planned.
- Some surviving mutants are *equivalent*: they change the code without
  changing its behaviour, e.g. `i >= n` → `i == n` in a loop that counts
  up by one. Review survivors before writing tests.
- No config file or baseline yet: options are CLI flags only.
- Mutating a null check that Dart relies on to treat a variable as
  non-null afterwards (`if (x == null || x.isEmpty)`) produces code that
  doesn't compile. Such mutants are reported as `invalid` and excluded
  from the score, but each still costs a test run.
