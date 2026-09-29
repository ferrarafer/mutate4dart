# mutate4dart specification (0.2)

## 1. Scope

`mutate4dart [paths...] [options]` mutates Dart source files of the project
in the current directory (the *project root*), runs the test files that can
detect each mutant, and reports which mutants survived.

## 2. File selection

`paths` are files or directories relative to the project root (default
`lib`). Directories are searched recursively for `.dart` files. Files
ending in `.g.dart`, `.freezed.dart`, `.gr.dart` or `.mocks.dart` shall
never be mutated. `--exclude <glob>` (repeatable) shall drop the files
whose project-relative path, with `/` separators, matches the glob, given
paths included. An invalid glob is a usage error (exit 1). Files that do not parse shall be skipped with a message
on stderr.

## 3. Mutants

Mutants shall be generated from the unresolved `package:analyzer` AST. Each
mutant replaces one source range, and replacements shall reuse the original
source text of sub-expressions. The operators are listed in the README.
The following shall not be mutated: annotations, `assert` statements and
initializers, `if (x case ...)` conditions, and `+` with a string-literal
operand. `negate_condition` shall be skipped when the condition (ignoring
parentheses) is an `==`/`!=` comparison or a `!` expression.

A comment whose text, after the `/` characters, is `mutate4dart: ignore`
optionally followed by operator ids (separated by commas or spaces) is an
*ignore pragma*. A pragma with code before it on its line covers that
line; a pragma alone on its line covers the next line. A mutant whose
start line is covered, by a pragma without ids or by one naming its
operator, is *ignored*: it shall not be run, not be listed by `--dry-run`
and not be scored. The plan summary shall report the number of ignored
mutants when it is not zero. Unknown ids match nothing.

`boolean_literal` shall not flip a literal that is the value of a
`growable:` named argument.

`collection` swaps the member names `isEmpty` ↔ `isNotEmpty` and
`first` ↔ `last` in any property access, and `any` ↔ `every` in method
invocations that have a target. `assignment` also turns `??=` into `=`.
Every operator carries a one-sentence hint for reports.

`remove_call` removes an expression statement that is a method or
function invocation, or an `await` of one, and whose parent is a block or
a `switch` member. Calls on `super` and calls named `print` or
`debugPrint` shall not be removed. The replacement keeps only the
newlines of the removed statement, so line numbers do not change.

Mutants that break type promotion shall not be generated. A *promoting
test* is an `is` expression or an `==`/`!=` comparison with a `null`
literal operand, possibly combined through `&&`, `||`, `!` and
parentheses. `equality` shall not flip a null comparison. `logical` shall
not swap an `&&`/`||` expression that contains a promoting test.
`negate_condition` shall not negate a condition that contains one.

## 4. Filters

- **Coverage** (default on): with `--lcov` (default `coverage/lcov.info`),
  a mutant is kept when its line has a hit count > 0. A line the LCOV file
  does not list (the Dart VM instruments only lines with a call or an
  operator, never a line holding just a literal) counts as covered when
  it lies inside a method (crap4dart method extraction, constructors
  included) that has at least one line with a hit count > 0; outside
  methods it counts as uncovered. LCOV entries that are not
  project-relative are ignored. A missing LCOV file is a usage error
  unless `--no-coverage` is given.
- **Collected coverage**: with `--collect-coverage`, the test files
  selected (section 5) for all target files shall first run once with
  `--coverage --coverage-path .mutate4dart/lcov.info`, and that file is
  used instead of `--lcov`. Only test commands running `flutter test` are
  supported (usage error otherwise). Failing tests, or a run that writes
  no coverage file, shall be a usage error (exit 1). Without selected
  tests nothing runs.
- **Diff**: with `--diff` (base `HEAD`) or `--diff-base <ref>`, only files
  changed in `git diff <ref>` are targeted (before coverage is collected),
  and a mutant is kept only when its line is added or changed.

## 5. Test selection

The import graph is built from `import`, `export` and `part` directives of
all `.dart` files under `lib/` and `test/`. `package:<name>/` URIs of the
project itself resolve to `lib/`, relative URIs against the importing file,
and other URIs are ignored. A `part` file maps to its owning library.
Test files are files under `test/` named `*_test.dart`.

- `--reach direct` (default): test files importing the library, or a file
  that re-exports it (transitively through `export`).
- `--reach transitive`: test files reaching the library through any chain
  of project imports.

Mutants of a file without selected tests shall not run. Their count is
reported.

## 6. Order

Mutants shall be ordered by the CRAP score of their enclosing method,
descending (0 outside methods or without coverage), stable within equal
scores. `--max-mutants N` keeps the first N.

## 7. Execution

The test command is `flutter test --no-pub` when the pubspec's
`dependencies` contain `flutter`, `dart test` otherwise, or the
whitespace-split `--test-command`. Test files are appended as arguments.

`--jobs N` (default `min(4, cores ÷ 2)`, at least 1) sets the number of
concurrent workers. With N = 1, mutants run in place in the project as
described below. With N > 1, each worker runs in its own *shadow
workspace*, and the original project shall not be modified:

- The shadow mirrors the *resolution root*: the nearest directory at or
  above the project root containing `.dart_tool/package_config.json`
  (the project root if none).
- Directories on the path to the project root and to each mutated file are
  real directories. The mutated files are real copies. Every other entry
  is a symlink to the original.
- `.git` is omitted. `build`, `.mutate4dart` and `.dart_tool` of real
  directories are not shared. Their `.dart_tool` holds only copies of
  `package_config.json` and `package_graph.json`.
- Workers take mutants from the shared plan order. Results are reported
  in plan order.
- Before its first mutant for a set of test files, a worker runs that set
  unmutated. A failure aborts the run with exit code 1 after in-flight
  mutants finish.
- Shadows are deleted at the end, on failure and on SIGINT.

In place, before any mutant runs, each distinct set of test files shall
run once on the unmutated code. A failure or timeout shall abort with exit code 1.
Its duration *d* sets the mutant timeout `max(m, f·d)`, where *m* is
`--min-timeout` (seconds, default 30, a positive integer) and *f* is
`--timeout-factor` (default 3, a number ≥ 1). Other values are usage
errors (exit 1). Parallel workers use the same timeout.

Each mutant shall be applied to its file. The original shall first be
written to `.mutate4dart/backup/<path>` and shall be restored after the run
even if it throws. On start, leftover backups shall be restored and
reported. On SIGINT, backups shall be restored before exiting with 130.

Outcome: timeout → `timeout`; exit 0 → `survived`; otherwise `invalid`
when the output shows a compilation failure, else `killed`.

## 8. Report

Results are grouped per method (crap4dart method extraction), and mutants
outside methods are grouped under `(top-level)`. Per method: detected
(killed + timeout), survived, invalid, CRAP and cyclomatic complexity.
Score = detected / (detected + survived), N/A when that is zero.

- Console: the per-method table (lowest score first), the survivors with
  their original and mutated line, and the overall score.
- JSON (`--format json`): `{score, methods: [{file, method, line,
  complexity, crap, score, mutants: [{line, operator, replacement, status,
  tests}]}]}`; stdout carries only JSON.
- Markdown (`--format markdown`): a `## Mutation testing (mutate4dart)`
  heading, then a summary line with the score and the detected, survived
  and invalid counts. Then a table of the methods with survivors (lowest
  score first), the number of other methods, and the survivors inside a
  `<details>` element: each as a `diff` block, then `Tests run:` with the
  test files that ran (at most 5 listed, the rest counted) and `Hint:`
  with the operator's hint (omitted for an unknown operator id), and
  finally a code block of `<file>:<line>  <operator>` lines. Without
  mutants it states there was nothing to mutate. Stdout carries only
  Markdown.
- Stryker (`--format stryker`): a document of the Stryker mutation-testing
  report schema, `schemaVersion` `2`, `thresholds` `{high: 80, low: 60}`,
  `projectRoot`, `files` keyed by project-relative path with `language`
  `dart`, the full `source` and `mutants` (`id` sequential from `1`,
  `mutatorName` = operator id, `replacement`, `location` with 1-based
  `start`/`end` line and column, `status` mapped killed → `Killed`,
  survived → `Survived`, timeout → `Timeout`, invalid → `CompileError`,
  `coveredBy` = the test files run, `killedBy` = the same when the mutant
  was detected by exactly one test file), and `testFiles` with one test
  per test file (`id` = `name` = path). Stdout carries only JSON.
- HTML (`--format html`): one page loading `mutation-testing-elements` from
  a CDN and assigning the Stryker document to its `report` property, with
  `<` in the JSON written as its JSON unicode escape (backslash `u003c`). Stdout carries only HTML.

## 9. Exit codes

- `0`: success (including `--dry-run`, `--help`, `--version`).
- `1`: usage or configuration error, git failure, red baseline.
- `2`: overall score below `--threshold` (a run without scored mutants
  counts as 100).
