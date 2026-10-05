import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/theme/app_theme.dart';
import 'package:little_blue_market/widgets/remote_image.dart';

/// Grace, 2026-09-14: 227 directory businesses, every photo blank, each one
/// still reserving a 16:9 hole above the name. Two causes, two fixes.
void main() {
  group('a browser loads a no-CORS picture through this origin', () {
    test('littlebluecart.com uploads are routed through /img on the web', () {
      const url =
          'https://littlebluecart.com/wp-content/uploads/2024/12/Josie-300x300.webp';
      final web = resolveImageUrl(url, onWeb: true);
      expect(web, startsWith('/img?u='));
      // The original address survives the round trip exactly.
      expect(Uri.parse(web).queryParameters['u'], url);
      expect(web, isNot(contains(' ')));
    });

    test('www is the same host as far as this is concerned', () {
      expect(
        resolveImageUrl('https://www.littlebluecart.com/a.jpg', onWeb: true),
        startsWith('/img?u='),
      );
    });

    test('a phone loads it directly; there is no cross-origin on a phone', () {
      const url = 'https://littlebluecart.com/wp-content/uploads/a.webp';
      expect(resolveImageUrl(url, onWeb: false), url);
    });

    test('our own Storage needs it too', () {
      // I assumed Firebase Storage sent the header. It does not, unless the
      // bucket is given a CORS configuration, and neither of ours has one:
      // an advert's photo was as blank as a directory listing's
      // (Grace, 2026-09-14). The server narrows this to our two buckets.
      const storage =
          'https://firebasestorage.googleapis.com/v0/b/little-blue-610e5.firebasestorage.app/o/promos%2Fa.png?alt=media&token=x';
      final web = resolveImageUrl(storage, onWeb: true);
      expect(web, startsWith('/img?u='));
      expect(Uri.parse(web).queryParameters['u'], storage);
      expect(resolveImageUrl(storage, onWeb: false), storage);
    });

    test('everything else is left alone, even on the web', () {
      expect(resolveImageUrl('', onWeb: true), '');
      expect(resolveImageUrl('asset://assets/images/a.jpg', onWeb: true),
          'asset://assets/images/a.jpg');
      // Not a url at all: handed back untouched rather than mangled.
      expect(resolveImageUrl('not a url', onWeb: true), 'not a url');
    });

    test('a query string in the original is not lost or re-read', () {
      const url = 'https://littlebluecart.com/a.jpg?w=300&h=200';
      final web = resolveImageUrl(url, onWeb: true);
      expect(Uri.parse(web).queryParameters['u'], url);
      // The inner ? and & must not become part of our own query.
      expect(Uri.parse(web).queryParameters.keys, ['u']);
    });
  });

  group('a picture that cannot be shown takes up no room', () {
    Future<void> pump(WidgetTester tester, String url) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLbmTheme(Brightness.light),
          home: Scaffold(
            body: Column(
              children: [
                RemoteImage(url: url),
                const Text('the name underneath'),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('an empty address renders nothing at all', (tester) async {
      await pump(tester, '');
      expect(find.byType(AspectRatio), findsNothing);
      expect(tester.getSize(find.byType(RemoteImage)), Size.zero);
    });

    testWidgets('a failed load collapses instead of leaving a hole', (
      tester,
    ) async {
      // In a widget test every network image fails, which is exactly the
      // case this is about.
      await pump(tester, 'https://littlebluecart.com/gone.webp');
      expect(find.byType(AspectRatio), findsOneWidget);

      // The error arrives, then the box goes.
      await tester.pumpAndSettle();
      expect(find.byType(AspectRatio), findsNothing);
      expect(tester.getSize(find.byType(RemoteImage)), Size.zero);
      expect(find.text('the name underneath'), findsOneWidget);
    });
  });
}
