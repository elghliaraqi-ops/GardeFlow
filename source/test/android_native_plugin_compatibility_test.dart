import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android release uses stable pre-JNI SharedPreferences native plugin', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      pubspec.contains('dependency_overrides:\n  shared_preferences_android: 2.4.28'),
      isTrue,
      reason: 'Do not reintroduce the 2.5.0 JNI getAll ABI crash on Android.',
    );
    final lock = File('pubspec.lock').readAsStringSync();
    final native = RegExp(
      r'  shared_preferences_android:\s*(?:.|\n)*?    version: "([^"]+)"',
    ).firstMatch(lock);
    expect(native?.group(1), '2.4.28');
  });
}
