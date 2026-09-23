import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:huim6_planning/main.dart';

void main() {
  test('GardeFlow root widget remains constructible', () {
    const app = HuimApp();
    expect(app, isA<StatelessWidget>());
    expect(app.key, isNull);
  });
}
