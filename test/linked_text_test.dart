import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/widgets/linked_text.dart';

void main() {
  test('addresses are found as typed, without trailing punctuation', () {
    expect(
      LinkedText.linksIn(
        'Shop at www.foundhouse.com, or book on https://cal.com/found-house/30min. '
        'Email is not a link.',
      ),
      ['www.foundhouse.com', 'https://cal.com/found-house/30min'],
    );
    expect(LinkedText.linksIn('No links here'), isEmpty);
    expect(LinkedText.linksIn('(https://a.test/x)'), ['https://a.test/x']);
  });

  testWidgets('the link is a tappable span and the rest is plain', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LinkedText('Find us at www.foundhouse.com today.'),
        ),
      ),
    );
    final rich = tester.widget<Text>(find.byType(Text));
    final span = rich.textSpan! as TextSpan;
    final children = span.children!.cast<TextSpan>();
    expect(children.map((s) => s.text), [
      'Find us at ',
      'www.foundhouse.com',
      ' today.',
    ]);
    expect(children[1].recognizer, isA<TapGestureRecognizer>());
    expect(children[0].recognizer, isNull);
    expect(children[1].style?.decoration, TextDecoration.underline);
  });

  testWidgets('a bio with no address renders as a single plain Text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LinkedText('Just words.'))),
    );
    expect(find.text('Just words.'), findsOneWidget);
  });
}
