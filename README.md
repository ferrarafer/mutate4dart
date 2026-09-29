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
$ mutate4dart lib/services/wager_service.dart --collect-coverage   # a Flutter app, 228 mutants, 7.8 min
 SCORE  DET  SURV  INV   CRAP  CC  METHOD                                   FILE:LINE
 65.0%   13     7    1   11.0  11  WagerService._sumStrokesForPlayer         lib/services/wager_service.dart:904
 71.1%   27    11    0   19.0  19  WagerService._calculatePressOpportunity   lib/services/wager_service.dart:462
 ...
Survivors (the tests miss these changes):
  lib/services/wager_service.dart:916 [relational_boundary]
    - if (index < 0 || index >= round.holes.length) continue;
    + if (index <= 0 || index >= round.holes.length) continue;
  ...
Mutation score: 85.8% (228 mutants)
```

## How it works

1. **Parse** each file under `lib/` (or the given paths) with
   `package:analyzer`, the SDK's own parser, and generate mutants. Generated
   code (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.mocks.dart`),
   files matching an `--exclude` glob, annotations and `assert`s are
   skipped.
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
   limited budget where it matters most. `--sample` instead runs a random
   subset, for an unbiased estimate of the whole score.

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
| `--exclude <glob>` | | Skip project-relative files matching the glob, e.g. `'lib/l10n/**'` (repeatable) |
| `--lcov` | `coverage/lcov.info` | Coverage used to skip lines no test executes |
| `--[no-]coverage` | on | Turn the coverage filter off |
| `--[no-]collect-coverage` | off | Flutter: run only the tests that import the target files, with coverage, into `.mutate4dart/lcov.info` (no full-suite coverage needed) |
| `--[no-]diff` / `--diff-base <ref>` | | Only mutate lines changed since `HEAD` / `<ref>` |
| `--test-command` | detected | Test command; test files are appended |
| `--reach` | `direct` | `transitive` also runs tests that reach the file through other libraries |
| `--operators` | all | Comma-separated operator ids (see below) |
| `--max-mutants N` | | Only the N mutants in the riskiest methods |
| `--sample N` / `--sample P%` | | A random sample of N mutants or P% of them; the score estimates the full run's |
| `--seed S` | random | Seed of `--sample`; the seed used is printed, so a sample can be repeated |
| `--threshold` | `0` | Minimum mutation score; below it exits `2` |
| `--format` | `console` | `json`, `markdown`, `stryker`, `html` or `junit` write only the report to stdout (Markdown suits `$GITHUB_STEP_SUMMARY` or a PR comment; see [Reports](#reports)) |
| `--jobs N` | `min(4, cores/2)` | Parallel workers in shadow workspaces; `1` mutates in place |
| `--min-timeout S` | `30` | Seconds a mutant's tests may always run before it counts as a timeout |
| `--timeout-factor F` | `3` | A mutant's tests may run F× their unmutated duration (at least `--min-timeout`) |
| `--dry-run` | | Plan only, nothing is run |
| `--config <file>` | `mutate4dart.yaml` | Config file with defaults for these options |

Exit codes: `0` success, `1` usage/configuration error or tests failing on
unmutated code, `2` mutation score below `--threshold`.

### Configuration file

`mutate4dart.yaml` at the project root (or `--config <file>`) holds
defaults for the options above, one snake_case key per option, so CI and
local runs share them:

```yaml
paths: [lib/services]
exclude:
  - 'lib/l10n/**'
  - 'lib/**/*_view.dart'
operators: [arithmetic, relational_boundary, negate_condition]
threshold: 80
max_mutants: 200
timeout_factor: 2
collect_coverage: true
```

Options given on the command line win over the file (`--no-<flag>` turns
a flag off). `exclude` globs
from both add up, and `paths` applies only when the command line names
none. Unknown keys and wrong value types are configuration errors
(exit `1`).

## Operators

| Id | Mutation |
|---|---|
| `relational_boundary` | `<` ↔ `<=`, `>` ↔ `>=` |
| `equality` | `==` ↔ `!=` |
| `logical` | `&&` ↔ `\|\|` |
| `arithmetic` | `+` ↔ `-`, `*` ↔ `/`, `%` / `~/` → `*` (not string `+`) |
| `assignment` | `+=` ↔ `-=`, `*=` ↔ `/=`, `??=` → `=` |
| `increment` | `++` ↔ `--` |
| `boolean_literal` | `true` ↔ `false` (not a `growable:` argument, which only tunes performance) |
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

## Ignoring mutants

Some survivors are *equivalent*: the mutant behaves exactly like the
original, so no test can kill it (`i >= n` → `i == n` in a loop that
counts up by one). Silence them with a pragma comment:

```dart
if (i >= n) break; // mutate4dart: ignore
// mutate4dart: ignore relational_boundary, equality
final done = index >= items.length;
```

A trailing pragma covers its own line; a pragma alone on a line covers the
next line. Without operator ids every operator on that line is ignored.
Ignored mutants are not run and not scored; the plan summary counts them.

## Results

- **killed**: a selected test failed. The suite detects the change.
- **timeout**: the tests ran longer than 3× their baseline duration (at
  least 30 s; see `--timeout-factor` and `--min-timeout`), usually an
  infinite loop. Counted as detected.
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
mutate4dart --format junit > mutation-junit.xml           # CI test report
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
- `junit`: JUnit XML for the test report view of GitLab
  (`artifacts:reports:junit`), Jenkins, Azure DevOps and others. Each
  mutated file is a test suite and each mutant a test case named after
  its line, operator and change, under its method. Survivors are
  failures whose body has the diff, the test files run and the hint;
  invalid mutants are skipped; detected mutants pass.

## Limitations

- Each worker's first `flutter test` run compiles from a cold cache
  (about 10 s on a Flutter app); later runs take about 3–4 s per mutant.
  On an 11-core machine, 4 workers were fastest (2.5× over sequential):
  228 mutants of a 1,100-line Flutter service, coverage collection
  included, took under 8 minutes. More workers contend for CPU and
  memory.
- Some surviving mutants are *equivalent*: they change the code without
  changing its behaviour. Review survivors before writing tests, and
  silence the equivalent ones with a pragma (see [Ignoring
  mutants](#ignoring-mutants)).
- Without type information, a few mutants still don't compile (e.g. `*` →
  `/` on `int`s yields a `double`). They are reported as `invalid` and
  excluded from the score.
- No config file or baseline yet: options are CLI flags only.

## License

MIT, see [LICENSE](LICENSE).
