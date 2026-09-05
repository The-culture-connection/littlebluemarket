// `copyWithPrevious` is the only way to build "loading over data" outside a
// provider. Riverpod marks it internal but it is stable and this is a test.
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/repositories/repositories.dart';
import 'package:little_blue_market/theme/app_theme.dart';
import 'package:little_blue_market/widgets/async.dart';
import 'package:little_blue_market/widgets/skeleton.dart';

Widget _host(Widget child) => MaterialApp(
  theme: buildLbmTheme(Brightness.light),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('LbmAsync', () {
    testWidgets('shows the skeleton on a first load', (tester) async {
      await tester.pumpWidget(
        _host(
          LbmAsync<String>(
            const AsyncValue.loading(),
            skeleton: const PostCardSkeleton(count: 1),
            data: (value) => Text(value),
          ),
        ),
      );
      expect(find.byType(PostCardSkeleton), findsOneWidget);
    });

    testWidgets('keeps stale data while refreshing', (tester) async {
      // The design has no blank state, so blanking a populated screen on every
      // pull-to-refresh would look broken.
      await tester.pumpWidget(
        _host(
          LbmAsync<String>(
            const AsyncValue<String>.loading().copyWithPrevious(
              const AsyncValue.data('the feed'),
            ),
            skeleton: const PostCardSkeleton(count: 1),
            data: (value) => Text(value),
          ),
        ),
      );
      expect(find.text('the feed'), findsOneWidget);
      expect(find.byType(PostCardSkeleton), findsNothing);
    });

    testWidgets('keeps stale data when a refresh fails', (tester) async {
      await tester.pumpWidget(
        _host(
          LbmAsync<String>(
            AsyncValue<String>.error(
              const OfflineException(),
              StackTrace.empty,
            ).copyWithPrevious(const AsyncValue.data('the feed')),
            data: (value) => Text(value),
          ),
        ),
      );
      expect(find.text('the feed'), findsOneWidget);
      expect(find.byType(LbmErrorCard), findsNothing);
    });

    testWidgets('renders the empty state instead of empty content', (tester) async {
      await tester.pumpWidget(
        _host(
          LbmAsync<List<String>>(
            const AsyncValue.data([]),
            isEmpty: (items) => items.isEmpty,
            empty: const LbmEmpty(title: 'No results'),
            data: (items) => Text('${items.length} items'),
          ),
        ),
      );
      expect(find.text('No results'), findsOneWidget);
      expect(find.text('0 items'), findsNothing);
    });

    testWidgets('renders data when there is data', (tester) async {
      await tester.pumpWidget(
        _host(
          LbmAsync<List<String>>(
            const AsyncValue.data(['a']),
            isEmpty: (items) => items.isEmpty,
            empty: const LbmEmpty(title: 'No results'),
            data: (items) => Text('${items.length} items'),
          ),
        ),
      );
      expect(find.text('1 items'), findsOneWidget);
    });

    testWidgets('a hard failure offers exactly one action', (tester) async {
      var retried = 0;
      await tester.pumpWidget(
        _host(
          LbmAsync<String>(
            AsyncValue.error(const OfflineException(), StackTrace.empty),
            onRetry: () => retried++,
            data: (value) => Text(value),
          ),
        ),
      );

      expect(find.text('No connection'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retried, 1);
    });

    testWidgets('offers no retry when there is nothing to retry', (tester) async {
      await tester.pumpWidget(
        _host(
          LbmAsync<String>(
            AsyncValue.error(const OfflineException(), StackTrace.empty),
            data: (value) => Text(value),
          ),
        ),
      );
      expect(find.text('Try again'), findsNothing);
    });
  });

  group('describeError', () {
    test('never leaks an exception string to a person', () {
      final errors = <Object>[
        const OfflineException(),
        const NotFoundException('product', 'p9'),
        const UnauthenticatedException(),
        const PermissionException('nope'),
        const RateLimitException(),
        const BackendException('boom', code: '500'),
        StateError('a raw Dart error'),
      ];

      for (final error in errors) {
        final described = describeError(error);
        expect(described.title, isNotEmpty);
        expect(described.body, isNotEmpty);
        expect(described.title, isNot(contains('Exception')));
        expect(described.body, isNot(contains('Exception')));
      }
    });

    test('a validation message is shown, because the person can act on it', () {
      final described = describeError(
        const ValidationException('That handle is taken'),
      );
      expect(described.body, 'That handle is taken');
    });

    test('names what was not found', () {
      expect(
        describeError(const NotFoundException('forum', 'f9')).body,
        contains('forum'),
      );
    });
  });

  group('skeletons', () {
    testWidgets('settle, so pumpAndSettle cannot hang on them', (tester) async {
      // A repeating shimmer would hang the 23-route smoke test.
      await tester.pumpWidget(
        _host(
          const Column(
            children: [
              PostCardSkeleton(count: 2),
              IdentitySkeleton(),
              ChipRailSkeleton(),
              ListRowSkeleton(),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LbmSkeleton), findsWidgets);
    });
  });
}
