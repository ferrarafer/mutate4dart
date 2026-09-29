import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Default config file, relative to the project root.
const String defaultConfigPath = 'mutate4dart.yaml';

/// Options that only make sense on the command line.
const Set<String> _cliOnly = {'help', 'version', 'config'};

/// A config file that cannot be read or has invalid entries.
class ConfigFileException implements Exception {
  /// Creates a [ConfigFileException].
  const ConfigFileException(this.message);

  /// What is wrong, naming the file and key.
  final String message;

  @override
  String toString() => message;
}

/// Defaults read from `mutate4dart.yaml`: one snake_case key per long
/// option of [parser] (`max_mutants: 50` is `--max-mutants 50`), plus
/// `paths`.
///
/// The entries become arguments placed before the command line's, so a
/// flag given there wins; `exclude` globs from both add up.
class ConfigFile {
  ConfigFile._(this.arguments, this.paths);

  /// No config file.
  static final ConfigFile none = ConfigFile._(const [], const []);

  /// Loads [path] (relative to [root]). A missing file is fine unless
  /// [required]. Throws a [ConfigFileException] on invalid content.
  factory ConfigFile.load(
    String root,
    String path,
    ArgParser parser, {
    bool required = false,
  }) {
    final file = File(p.join(root, path));
    if (!file.existsSync()) {
      if (required) throw ConfigFileException('No config file at $path.');
      return none;
    }
    final Object? yaml;
    try {
      yaml = loadYaml(file.readAsStringSync());
    } on YamlException catch (e) {
      throw ConfigFileException('$path: ${e.message}');
    }
    if (yaml == null) return none;
    if (yaml is! YamlMap) throw ConfigFileException('$path: expected a map.');
    return _parse(path, yaml, parser);
  }

  static ConfigFile _parse(String path, YamlMap yaml, ArgParser parser) {
    final arguments = <String>[];
    var paths = const <String>[];
    for (final MapEntry(:key, :value) in yaml.entries) {
      final name = '$key'.replaceAll('_', '-');
      final option = parser.options[name];
      if (key == 'paths') {
        paths = _strings(path, 'paths', value);
      } else if (option == null || _cliOnly.contains(name)) {
        throw ConfigFileException('$path: unknown key "$key".');
      } else {
        arguments.addAll(_arguments(path, '$key', option, value));
      }
    }
    return ConfigFile._(arguments, paths);
  }

  /// Arguments equivalent to the config entries.
  final List<String> arguments;

  /// Files or directories to mutate when the command line names none.
  final List<String> paths;

  static List<String> _arguments(
    String path,
    String key,
    Option option,
    Object? value,
  ) {
    final flag = '--${option.name}';
    if (option.isFlag) {
      if (value is! bool) {
        throw ConfigFileException('$path: $key must be a bool.');
      }
      if (value) return [flag];
      return option.negatable! ? ['--no-${option.name}'] : const [];
    }
    final values = _strings(path, key, value);
    if (option.isMultiple) return [for (final v in values) '$flag=$v'];
    return ['$flag=${values.join(',')}'];
  }

  /// A scalar or a list of scalars, as strings.
  static List<String> _strings(String path, String key, Object? value) {
    final items = value is YamlList ? value.toList() : [value];
    if (items.isEmpty || items.any((v) => v == null || v is Map || v is List)) {
      throw ConfigFileException(
        '$path: $key must be a value or a list of '
        'values.',
      );
    }
    return [for (final v in items) '$v'];
  }
}
