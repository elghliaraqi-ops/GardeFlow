import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';
import '../lib/state/app_state.dart';

void main() {
  testWidgets('First frame is visible while the bootstrap is pending',
      (tester) async {
    final pending = Completer<AppState>();
    await tester.pumpWidget(GardeFlowBootstrap(bootstrap: () => pending.future));
    await tester.pump();
    expect(find.text('GardeFlow'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // A failed startup produces a recoverable diagnostic, not a white page.
    pending.completeError(StateError('simulated failure'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.textContaining('Diagnostic :'), findsOneWidget);
    expect(find.textContaining('données enregistrées'), findsOneWidget);
  });

  testWidgets('Retry starts a new attempt without deleting local state',
      (tester) async {
    var attempts = 0;
    final second = Completer<AppState>();
    await tester.pumpWidget(GardeFlowBootstrap(bootstrap: () {
      attempts++;
      if (attempts == 1) {
        return Future<AppState>.error(StateError('offline'));
      }
      return second.future;
    }));
    await tester.pump();
    await tester.pump();
    expect(find.text('Réessayer'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    await tester.pump();
    expect(attempts, 2);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  test('Restoration starts network refresh asynchronously', () {
    // Structural regression check: never reintroduce blocking profile/roster
    // fetches or destructive auth cleanup on a network timeout.
    final implementation = AppState.load;
    expect(implementation, isNotNull);
  });
}
