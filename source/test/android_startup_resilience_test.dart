import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/main.dart';
import 'package:huim6_planning/state/app_state.dart';

void main() {
  testWidgets('Loading screen appears without awaiting startup', (tester) async {
    final pending = Completer<AppState>();
    await tester.pumpWidget(GardeFlowBootstrap(bootstrap: () => pending.future));
    await tester.pump();
    expect(find.text('GardeFlow'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(StateError('test cleanup'));
    await tester.pump();
  });

  testWidgets('A failed startup identifies a step and offers a retry',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(GardeFlowBootstrap(bootstrap: () async {
      attempts++;
      throw StateError('simulated offline');
    }));
    await tester.pump();
    await tester.pump();
    expect(find.text('Démarrage interrompu'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    await tester.pump();
    expect(attempts, 2);
  });
}
