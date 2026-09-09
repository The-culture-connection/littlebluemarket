import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/theme/app_theme.dart';
import 'package:little_blue_market/widgets/hashtag_chips.dart';

void main() {
  Widget host(TextEditingController controller) => MaterialApp(
    theme: buildLbmTheme(Brightness.light),
    home: Scaffold(
      body: Column(
        children: [
          HashtagChips(controller: controller),
          TextField(controller: controller),
        ],
      ),
    ),
  );

  testWidgets(
    'a typed hashtag becomes a chip; its x takes it out of the text',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(host(controller));

      expect(find.byType(Wrap), findsNothing);

      await tester.enterText(
        find.byType(TextField),
        'Fresh #PlasticFree soap #Detroit',
      );
      await tester.pump();
      expect(find.text('#PlasticFree'), findsOneWidget);
      expect(find.text('#Detroit'), findsOneWidget);

      await tester.tap(find.text('#PlasticFree'));
      await tester.pump();
      expect(controller.text, 'Fresh soap #Detroit');
      expect(find.text('#PlasticFree'), findsNothing);
      expect(find.text('#Detroit'), findsOneWidget);
    },
  );

  test('Shopify placeholder variant names are recognised', () {
    expect(isPlaceholderVariantName('Default Title'), isTrue);
    expect(isPlaceholderVariantName('default'), isTrue);
    expect(isPlaceholderVariantName(''), isTrue);
    expect(isPlaceholderVariantName('Cocoa Mint'), isFalse);
    expect(const Variant('Default Title', 800).isPlaceholder, isTrue);
  });
}
