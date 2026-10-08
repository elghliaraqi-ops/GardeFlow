import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GitHub Pages workflow deploys the same version as the source', () {
    final workflow =
        File('../.github/workflows/build-web-v12.yml').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final screen =
        File('lib/screens/official_planning_screen.dart').readAsStringSync();

    // Resolve the canonical version from the pubspec. The release contract
    // must remain valid when preparing the next maintenance version.
    final match = RegExp(r'^version: (\d+\.\d+\.\d+)\+(\d+)$',
            multiLine: true)
        .firstMatch(pubspec);
    expect(match, isNotNull);
    final appVersion = match!.group(1)!;
    final buildNumber = match.group(2)!;

    expect(workflow, contains('APP_VERSION: $appVersion'));
    expect(workflow, contains('BUILD_NUMBER: "$buildNumber"'));
    expect(workflow, contains('version: $appVersion+$buildNumber'));
    expect(RegExp(r'^  deploy-pages:', multiLine: true)
        .allMatches(workflow).length, 1);
    expect(RegExp(r'^  build-web:', multiLine: true)
        .allMatches(workflow).length, 1);
    expect(workflow, contains('actions/deploy-pages@v4'));
    expect(workflow, isNot(contains('GardeFlow-v12.0.2-web')));
    expect(screen, contains("label: const Text('Relire avec pdfrx')"));
    expect(screen, contains("label: const Text('Relire avec Groq')"));
  });
}
