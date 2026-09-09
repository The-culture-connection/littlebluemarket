import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/theme/app_theme.dart';
import 'package:little_blue_market/widgets/tag_entry.dart';

void main() {
  testWidgets('type a tag, tap the check: it becomes a chip above; x removes', (
    tester,
  ) async {
    var tags = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLbmTheme(Brightness.light),
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: TagEntry(
              tags: tags,
              onChanged: (next) => setState(() => tags = next),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Wrap), findsNothing);

    await tester.enterText(find.byType(TextField), 'plastic free');
    await tester.tap(find.byTooltip('Add tag'));
    await tester.pump();
    expect(tags, ['#plasticfree']);
    expect(find.text('#plasticfree'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
      reason: 'the field is ready for the next tag',
    );

    // The keyboard's done key adds too; a duplicate is ignored.
    await tester.enterText(find.byType(TextField), '#Detroit');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'detroit');
    await tester.tap(find.byTooltip('Add tag'));
    await tester.pump();
    expect(tags, ['#plasticfree', '#Detroit']);

    await tester.tap(find.text('#plasticfree'));
    await tester.pump();
    expect(tags, ['#Detroit']);
    expect(find.text('#plasticfree'), findsNothing);
  });

  test('a tag is one word with one leading #', () {
    expect(TagEntry.normalize(' #Plastic Free! '), '#PlasticFree');
    expect(TagEntry.normalize('###'), '');
    expect(TagEntry.normalize('woman-owned'), '#womanowned');
  });

  test('Shopify placeholder variant names are recognised', () {
    expect(isPlaceholderVariantName('Default Title'), isTrue);
    expect(isPlaceholderVariantName('default'), isTrue);
    expect(isPlaceholderVariantName(''), isTrue);
    expect(isPlaceholderVariantName('Cocoa Mint'), isFalse);
    expect(const Variant('Default Title', 800).isPlaceholder, isTrue);
  });
}
