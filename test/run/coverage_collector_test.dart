import 'dart:io';

import 'package:mutate4dart/src/internal/mutate4dart_internal.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../fake_runner.dart';
import '../test_project.dart';

void main() {
  late Directory root;

  setUp(() => root = createProject({}, flutter: true));
  tearDown(() => root.deleteSync(recursive: true));

  CoverageCollector collector(FakeRunner fake, {TestCommand? command}) =>
      CoverageCollector(
        projectRoot: root.path,
        command: command ?? TestCommand.detect(root.path),
        run: fake.call,
      );

  test('runs only the given tests with coverage into .mutate4dart', () async {
    final fake = writesCoverage();
    final lcov = await collector(fake).collect(['test/a_test.dart']);
    expect(lcov, p.join(root.path, collectedLcovPath));
    expect(
      fake.calls.single.command,
      'flutter test --no-pub --coverage --coverage-path $lcov '
      'test/a_test.dart',
    );
  });

  test('no tests: nothing runs and there is no coverage', () async {
    final fake = FakeRunner((_, _) => result(0));
    expect(await collector(fake).collect(const []), isNull);
    expect(fake.calls, isEmpty);
  });

  test('a run that writes no coverage is an error', () async {
    final fake = FakeRunner((_, _) => result(0));
    await expectLater(
      collector(fake).collect(['test/a_test.dart']),
      throwsA(
        isA<RedBaselineException>().having(
          (e) => e.output,
          'output',
          contains('No coverage'),
        ),
      ),
    );
  });

  test('failing tests are a red baseline', () async {
    final fake = FakeRunner((_, _) => result(1, output: 'boom'));
    await expectLater(
      collector(fake).collect(['test/a_test.dart']),
      throwsA(isA<RedBaselineException>()),
    );
  });

  test('only flutter test commands are supported', () {
    final fake = FakeRunner((_, _) => result(0));
    expect(collector(fake).supported, isTrue);
    expect(
      collector(fake, command: TestCommand.parse('fvm flutter test')).supported,
      isTrue,
    );
    expect(
      collector(fake, command: const TestCommand('dart', ['test'])).supported,
      isFalse,
    );
  });
}
