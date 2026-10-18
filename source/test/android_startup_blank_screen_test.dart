import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';
import '../lib/state/app_state.dart';

void main() {
  testWidgets('GardeFlow paints a visible loader before initialization completes', (tester) async {
    final pending = Completer<AppState>();
    await tester.pumpWidget(GardeFlowBootstrap(bootstrap: () => pending.future));
    await tester.pump();
    expect(find.text('GardeFlow'), findsOneWidget);
    expect(find.text('Chargement de votre espace…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(StateError('test startup failure'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.textContaining('données enregistrées'), findsOneWidget);
  });

  testWidgets('A retry can complete after an initialization failure', (tester) async {
    var calls = 0;
    final pending = Completer<AppState>();
    await tester.pumpWidget(GardeFlowBootstrap(bootstrap: () {
      calls++;
      if (calls == 1) return Future<AppState>.error(StateError('offline'));
      return pending.future;
    }));
    await tester.pump();
    await tester.pump();
    expect(find.text('Réessayer'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    await tester.pump();
    expect(calls, 2);
    expect(find.text('Chargement de votre espace…'), findsOneWidget);
    // Let the element be disposed rather than opening the real app.
  });
}
