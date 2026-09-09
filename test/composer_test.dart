import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/repositories/repositories.dart';
import 'package:little_blue_market/theme/app_theme.dart';
import 'package:little_blue_market/widgets/screen.dart';

/// The shared send bar behind DMs, the chatroom, thread replies and post
/// comments. What it promises: a failed send keeps the text and says why; a
/// send in flight cannot be sent twice; a successful send clears the field.
void main() {
  Widget host(Future<void> Function(String) onSend) => MaterialApp(
    theme: buildLbmTheme(Brightness.light),
    home: Scaffold(
      body: const SizedBox.expand(),
      bottomNavigationBar: Composer(hintText: 'Message…', onSend: onSend),
    ),
  );

  testWidgets('a rejected send keeps the text and shows the reason', (
    tester,
  ) async {
    await tester.pumpWidget(
      host((_) async {
        throw const ValidationException('Make a profile to message people.');
      }),
    );

    await tester.enterText(find.byType(TextField), 'are these in stock?');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(find.text('are these in stock?'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('profile'), findsWidgets);
  });

  testWidgets('a send in flight blocks the button; success clears the field', (
    tester,
  ) async {
    final gate = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      host((_) {
        calls++;
        return gate.future;
      }),
    );

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(calls, 1);
    // A second tap, and the keyboard's send key, while the first is pending.
    await tester.tap(find.byTooltip('Sending'));
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(calls, 1, reason: 'one message, however many taps');
    expect(find.text('hello'), findsOneWidget, reason: 'not cleared yet');

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('hello'), findsNothing);
    expect(find.byTooltip('Send'), findsOneWidget);
  });
}
