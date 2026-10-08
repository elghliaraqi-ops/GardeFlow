import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android and iOS release workflows use the canonical app version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version: ([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(version, isNotNull);
    final appVersion = version!.group(1)!;
    final buildNumber = version.group(2)!;
    final android =
        File('../.github/workflows/build-android-apk.yml').readAsStringSync();
    final ios =
        File('../.github/workflows/build-ios.yml').readAsStringSync();
    final signed =
        File('../.github/workflows/build-ios-signed.yml').readAsStringSync();

    expect(android, contains('--build-name $appVersion'));
    expect(android, contains('--build-number $buildNumber'));
    for (final content in [ios, signed]) {
      expect(content, contains('APP_VERSION: $appVersion'));
      expect(content, contains('BUILD_NUMBER: "$buildNumber"'));
    }
  });
}
