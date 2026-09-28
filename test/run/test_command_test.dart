import 'package:mutate4dart/mutate4dart.dart';
import 'package:test/test.dart';

import '../test_project.dart';

void main() {
  test('detects Flutter projects from the pubspec', () {
    final flutter = createProject({}, flutter: true);
    final dart = createProject({});
    addTearDown(() {
      flutter.deleteSync(recursive: true);
      dart.deleteSync(recursive: true);
    });
    expect(
        TestCommand.detect(flutter.path).toString(), 'flutter test --no-pub');
    expect(TestCommand.detect(dart.path).toString(), 'dart test');
  });

  test('parses a custom command and appends test files', () {
    final command = TestCommand.parse('  fvm flutter  test ');
    expect(command.executable, 'fvm');
    expect(command.argumentsFor(['test/a_test.dart']),
        ['flutter', 'test', 'test/a_test.dart']);
  });

  test('recognizes compile failures', () {
    expect(isCompileFailure('Error: Compilation failed.'), isTrue);
    expect(
        isCompileFailure('Failed to load "test/a_test.dart":\n'
            "lib/a.dart:3:5: Error: The operator '-' isn't defined"),
        isTrue);
    expect(isCompileFailure('Expected: <1>\n  Actual: <2>'), isFalse);
  });
}
