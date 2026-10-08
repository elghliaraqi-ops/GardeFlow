import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GitHub Pages workflow deploys the same version as the source', () {
    final workflow =
        File('../.github/workflows/build-web-v12.yml').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final screen =
        File('lib/screens/official_planning_screen.dart').readAsStringSync();

    expect(pubspec, contains('version: 12.0.6+306'));
    expect(workflow, contains('APP_VERSION: 12.0.6'));
    expect(workflow, contains('BUILD_NUMBER: "306"'));
    expect(workflow,
        contains(r"grep -q '^version: 12.0.6+306$' pubspec.yaml"));
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
