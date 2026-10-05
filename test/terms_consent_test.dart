import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/main.dart';
import 'package:little_blue_market/router/app_router.dart';
import 'package:little_blue_market/legal_links.dart';
import 'package:little_blue_market/screens/onboarding/eula_screen.dart';
import 'package:little_blue_market/state/providers.dart';

/// Agreeing to the terms before an account exists (Grace, 2026-09-14).
///
/// They were already on the screen and she still went through account
/// creation without seeing them: 11.5px, three quarters opacity, the last
/// thing on the page, under the button. Being present is not being
/// presented. These pin the difference.
Future<void> _openCreate(WidgetTester tester, {required bool creating}) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(retry: lbmRetry);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const LittleBlueMarketApp(),
    ),
  );
  await tester.pump();
  container.read(routerProvider).go('/signin?create=${creating ? 1 : 0}');
  await tester.pumpAndSettle();
}

Finder _createButton() =>
    find.widgetWithText(InkWell, 'Create my profile').first;

bool _enabled(WidgetTester tester) =>
    tester.widget<InkWell>(_createButton()).onTap != null;

void main() {
  testWidgets('the terms are asked for, above the button, in plain sight', (
    tester,
  ) async {
    await _openCreate(tester, creating: true);

    // Not small print at the bottom: a tick with the two policies in it.
    expect(find.textContaining('I agree to the'), findsOneWidget);
    expect(find.textContaining('Terms of Use'), findsOneWidget);
    expect(find.textContaining('Privacy Policy'), findsOneWidget);

    // And a screen reader is told it is a checkbox, not just words.
    expect(
      find.bySemanticsLabel(
        'I agree to the Terms of Use and the Privacy Policy',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a filled-in form still cannot be sent until it is ticked', (
    tester,
  ) async {
    await _openCreate(tester, creating: true);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'someone@example.test');
    await tester.enterText(fields.at(1), 'a-good-password');
    await tester.pumpAndSettle();

    // Everything typed, nothing ticked: the button is dead. This is the
    // assertion that would have caught the terms being skippable.
    expect(_enabled(tester), isFalse);

    await tester.tap(find.textContaining('I agree to the'));
    await tester.pumpAndSettle();
    expect(_enabled(tester), isTrue);

    // Unticking closes it again, rather than the first tick being a
    // one-way door.
    await tester.tap(find.textContaining('I agree to the'));
    await tester.pumpAndSettle();
    expect(_enabled(tester), isFalse);
  });

  testWidgets('signing in is not asked to agree to anything', (tester) async {
    await _openCreate(tester, creating: false);

    // No new agreement is being made, so no tick, and Sign in works on its
    // own once the form is filled.
    expect(find.textContaining('I agree to the'), findsNothing);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'someone@example.test');
    await tester.enterText(fields.at(1), 'a-good-password');
    await tester.pumpAndSettle();
    expect(
      tester.widget<InkWell>(find.widgetWithText(InkWell, 'Sign in').first).onTap,
      isNotNull,
    );
  });

  testWidgets('the terms open in the app, and carry the clause that matters', (
    tester,
  ) async {
    final container = ProviderContainer(retry: lbmRetry);
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LittleBlueMarketApp(),
      ),
    );
    await tester.pump();

    // The route the tick pushes. Tapping the link itself means hitting one
    // TextSpan inside a sentence, which tests the hit-test rather than the
    // terms; this checks the door opens and what is behind it.
    container.read(routerProvider).go(LegalLinks.termsRoute);
    await tester.pumpAndSettle();

    expect(find.text('Terms of use'), findsWidgets);
    expect(find.textContaining('version $kTermsVersion'), findsOneWidget);

    // The sentence App Review looks for in a user-generated-content app.
    // Section 4, so a lazy list has to be scrolled to build it.
    await tester.scrollUntilVisible(
      find.textContaining('no tolerance here for objectionable content'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('no tolerance here for objectionable content'),
      findsOneWidget,
    );
  });

  test('the terms say the things the app stores ask about', () {
    final all = kTermsSections
        .expand((s) => [s.heading, ...s.body])
        .join(' ')
        .toLowerCase();

    // Zero tolerance, in so many words.
    expect(all, contains('no tolerance'));
    // How to report, and how to block.
    expect(all, contains('report'));
    expect(all, contains('block'));
    // Published contact, or nobody can reach a person.
    expect(all, contains('@'));
    // Deletion, which the app now does itself.
    expect(all, contains('delete my account'));
    // Apple's own required acknowledgements.
    expect(all, contains('apple'));
    expect(all, contains('third party'));
    // An age, because an app carrying what people write needs one.
    expect(all, contains('13 years old'));
    // Every section has a heading and something under it.
    for (final section in kTermsSections) {
      expect(section.heading, isNotEmpty);
      expect(section.body, isNotEmpty);
      for (final paragraph in section.body) {
        expect(paragraph.trim(), isNotEmpty);
      }
    }
  });
}
