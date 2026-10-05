import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/theme/app_theme.dart';
import 'package:little_blue_market/widgets/named_text.dart';
import 'package:little_blue_market/widgets/primitives.dart';

/// What the app picks out of a run of words and makes tappable: `@handles`
/// and `#hashtags`, in a post, an announcement or an advert.
///
/// The rule these all turn on: **what is highlighted has to be the same
/// thing that gets looked up.** They drifted once, over a full stop, and the
/// symptom was a mention at the end of a sentence that did nothing when
/// tapped (2026-09-24).
Future<void> _pump(
  WidgetTester tester,
  String text, {
  Map<String, String> mentions = const {},
  ValueChanged<String>? onProfile,
  ValueChanged<String>? onTag,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: buildLbmTheme(Brightness.light),
        home: Scaffold(
          body: NamedText(
            text,
            mentions: mentions,
            onOpenProfile: onProfile ?? (_) {},
            onOpenTag: onTag ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the highlighter and the parser agree', () {
    test('a full stop that ends a sentence is not part of the handle', () {
      // The parser has always known this; the highlighter did not, and the
      // two have to name the same person or the tap looks up a handle
      // nobody has.
      expect(parseMentionHandles('ask @foundhouse.'), ['foundhouse']);
      expect(HashtagText.has('ask @foundhouse.'), isTrue);
    });

    test('a dot inside a handle is part of it', () {
      expect(parseMentionHandles('@found.house makes bowls'), [
        'found.house',
      ]);
    });

    test('plain prose has nothing to pick out', () {
      expect(HashtagText.has('Forty makers, one room, all day.'), isFalse);
      expect(HashtagText.has('Meet @kali'), isTrue);
      expect(HashtagText.has('The #HolidayMarket'), isTrue);
    });
  });

  group('tapping', () {
    testWidgets('a mention at the end of a sentence still opens the shop', (
      tester,
    ) async {
      String? opened;
      await _pump(
        tester,
        'Forty makers, including @foundhouse.',
        mentions: const {'foundhouse': 'kali'},
        onProfile: (uid) => opened = uid,
      );
      await tester.tapOnText(find.textRange.ofSubstring('@foundhouse'));
      await tester.pumpAndSettle();
      expect(opened, 'kali');
    });

    testWidgets('a hashtag comes back with its hash on it', (tester) async {
      String? tag;
      await _pump(
        tester,
        'On now: #HolidayMarket',
        onTag: (t) => tag = t,
      );
      await tester.tapOnText(find.textRange.ofSubstring('#HolidayMarket'));
      await tester.pumpAndSettle();
      expect(tag, '#HolidayMarket');
    });

    testWidgets('the stored uid wins over the handle as written', (
      tester,
    ) async {
      // The point of storing it: @foundhouse has since been renamed, and
      // the advert still has to open the same shop.
      String? opened;
      await _pump(
        tester,
        'New from @foundhouse',
        mentions: const {'foundhouse': 'whoever-that-is-now'},
        onProfile: (uid) => opened = uid,
      );
      await tester.tapOnText(find.textRange.ofSubstring('@foundhouse'));
      await tester.pumpAndSettle();
      expect(opened, 'whoever-that-is-now');
    });

    testWidgets('an email address is not a mention', (tester) async {
      var opened = false;
      await _pump(
        tester,
        'write to grace@example.com',
        onProfile: (_) => opened = true,
      );
      await tester.tapOnText(find.textRange.ofSubstring('grace@example.com'));
      await tester.pumpAndSettle();
      expect(opened, isFalse);
    });
  });
}
