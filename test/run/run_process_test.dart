import 'dart:io';

import 'package:mutate4dart/mutate4dart.dart';
import 'package:test/test.dart';

void main() {
  test('captures exit code and output', () async {
    final r = await runProcess('dart', ['--version'],
        workingDirectory: Directory.current.path,
        timeout: const Duration(seconds: 60));
    expect(r.exitCode, 0);
    expect(r.timedOut, isFalse);
    expect(r.output, contains('Dart SDK version'));
  });

  test('kills a run that exceeds its timeout', () async {
    final r = await runProcess('sleep', ['10'],
        workingDirectory: Directory.current.path,
        timeout: const Duration(milliseconds: 200));
    expect(r.timedOut, isTrue);
    expect(r.elapsed, lessThan(const Duration(seconds: 5)));
  }, testOn: '!windows');
}
