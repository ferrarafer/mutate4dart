# AGENTS.md

Guidance for AI agents and contributors working on mutate4dart.

## What this is

`mutate4dart` is a mutation-testing CLI for Dart and Flutter projects, a
sibling of [crap4dart](https://github.com/ferrarafer/crap4dart) (Uncle
Bob's `crap4java` / `mutate4java` pair). It mutates covered code with
`package:analyzer`, runs only the test files that import the mutated
library, and reports a mutation score per method next to its CRAP score.

The contract is in [spec.md](spec.md). Keep `spec.md`, `README.md`,
`CHANGELOG.md` and this file in sync with behavior changes.

## Commands

```bash
dart pub get
dart test                    # all tests must pass
dart analyze                 # must report "No issues found!"
dart format .                # apply before committing
dart test --coverage=coverage
dart pub global run coverage:format_coverage \
  --lcov --in coverage --out coverage/lcov.info --report-on lib
crap4dart check              # dogfooding: must pass (crap4dart.yaml)
crap4dart analyze            # max CRAP must stay <= 8.0
```

## Architecture

```
bin/mutate4dart.dart          # entry point -> Mutate4DartRunner
lib/src/cli/runner.dart       # flags, orchestration, exit codes
lib/src/cli/mutation_plan.dart# find -> filter -> select tests -> order by CRAP
lib/src/mutation/             # Mutant model, operators, AST MutantFinder
lib/src/selection/            # coverage/diff filters, import-graph TestSelector
lib/src/run/                  # TestCommand, ProcessRunner, MutationRunner
lib/src/report/               # per-method MutationReport, console/JSON
```

Conventions:

- Reuse crap4dart through its **public** API (`package:crap4dart/crap4dart.dart`:
  parser, method extractor, LCOV parser, diff parser, CRAP analyzer). If
  something is missing, export it from crap4dart rather than copying code.
- AST work goes through `package:analyzer`, never regex. Replacements use
  the original source text (`source.substring(node.offset, node.end)`),
  not `toSource()`.
- A new operator needs: a `MutationOperator` value with a stable id, the
  visitor case in `mutant_finder.dart`, tests, and README/spec entries.
  Avoid operators that duplicate another's program (see `_negate`).
- Source files must always be restored: every mutation goes through
  `MutationRunner.runMutant` (backup + `finally` restore).
- Exit codes: `0` success, `1` usage/config error or red baseline, `2`
  score below `--threshold`. `--format json` keeps stdout JSON-only.

## Testing

- `package:test`; fixtures are temp projects (`test/test_project.dart`).
- **Never run real test suites from unit tests.** Inject a `FakeRunner`
  (`test/fake_runner.dart`) as the `ProcessRunner`. CLI tests run in-process
  via `runCli` (`test/cli/cli_test_utils.dart`).
- crap4dart gates the test code too (`sources` includes `test/`): keep
  `main()` bodies under 80 lines by splitting files by topic.
