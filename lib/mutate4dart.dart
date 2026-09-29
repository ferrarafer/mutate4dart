/// Mutation testing for Dart and Flutter projects.
///
/// Mutates covered code, runs only the test files that import it, and
/// reports a mutation score per method next to its CRAP score.
library;

export 'src/cli/config_file.dart';
export 'src/cli/mutation_plan.dart';
export 'src/cli/runner.dart';
export 'src/mutation/mutant.dart';
export 'src/mutation/mutant_finder.dart';
export 'src/report/junit_renderer.dart';
export 'src/report/markdown_renderer.dart';
export 'src/report/mutation_report.dart';
export 'src/report/stryker_renderer.dart';
export 'src/run/coverage_collector.dart';
export 'src/run/mutation_runner.dart';
export 'src/run/parallel_runner.dart';
export 'src/run/shadow_workspace.dart';
export 'src/run/test_command.dart';
export 'src/selection/mutant_filters.dart';
export 'src/selection/test_selector.dart';
