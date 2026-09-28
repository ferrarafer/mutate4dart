import 'dart:io';

import 'package:mutate4dart/mutate4dart.dart';

/// Runs the mutate4dart command line.
Future<void> main(List<String> args) async {
  exitCode = await Mutate4DartRunner().execute(args);
}
