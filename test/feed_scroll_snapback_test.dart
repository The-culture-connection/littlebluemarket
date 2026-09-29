import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/theme/app_theme.dart';
import 'package:little_blue_market/widgets/async.dart';

/// The For you feed snapping back mid-fling (Grace, 2026-09-29, screen
/// recording; `Planning/bug-feed-scroll-snapback.md`).
///
/// The order of the pins never changed between the two positions, so nothing
/// was being inserted: the **scroll position itself** was being re-created. A
/// `ScrollController` that attaches a new `ScrollPosition` restores the offset
/// it last saved, which is exactly a fling travelling and then jumping back to
/// where it began, over and over, with no further touch.
///
/// The cause was [LbmAsync] changing the *shape* of the tree around its
/// content while a refresh was in flight: a bare child one moment, that child
/// inside a Stack the next. Same widget, different element, so everything
/// below it was built again, scroll position included.
///
/// This holds that shape still. It is not something reading the widget will
/// tell you, and the feed is not the only screen that scrolls.

/// Counts how many times the thing inside it is built from scratch.
///
/// A [State] is created once per element. If the element survives a rebuild
/// this stays at 1 however many times the tree above it changes; if the
/// element is replaced it climbs, and so does the scroll position's.
class _Mounts extends StatefulWidget {
  const _Mounts({required this.tally});

  final List<int> tally;

  @override
  State<_Mounts> createState() => _MountsState();
}

class _MountsState extends State<_Mounts> {
  @override
  void initState() {
    super.initState();
    widget.tally.add(1);
  }

  @override
  Widget build(BuildContext context) => const SizedBox(height: 40);
}

void main() {
  testWidgets('a refresh over existing data does not rebuild the content', (
    tester,
  ) async {
    final tally = <int>[];
    var pending = Completer<int>();
    final source = FutureProvider<int>((ref) => pending.future);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildLbmTheme(Brightness.light),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => LbmAsync<int>(
                ref.watch(source),
                skeleton: const SizedBox(height: 40),
                data: (_) => _Mounts(tally: tally),
              ),
            ),
          ),
        ),
      ),
    );

    // Nothing yet: the skeleton, and no content to speak of.
    expect(tally, isEmpty);

    pending.complete(1);
    await tester.pumpAndSettle();
    expect(tally.length, 1, reason: 'built once, when the data first arrived');

    // A refresh. The value is still there, and LbmAsync promises to keep it
    // on screen: it has to keep the *same* content, not an identical copy in
    // a new element.
    pending = Completer<int>();
    container.invalidate(source);
    await tester.pump();
    expect(
      tally.length,
      1,
      reason:
          'the content was thrown away and built again while refreshing; a '
          'scroll view treated this way forgets where it was, which is the '
          'fling snapping back',
    );

    // And when the refresh lands.
    pending.complete(2);
    await tester.pumpAndSettle();
    expect(tally.length, 1);
  });

  test('whenData keeps the value of a refresh, on this Riverpod', () {
    // Worth pinning because the bug note assumed the opposite, and it is a
    // reasonable thing to assume: `whenData` reads as though it only maps the
    // data case. Here it carries the previous value through, so mapping a
    // refresh does **not** drop a grid to its skeleton, and that was not what
    // re-created the scroll position.
    //
    // If this ever goes red, that becomes a second cause of the same bug and
    // anything reading state off a mapped AsyncValue has to stop.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final source = FutureProvider<int>((ref) => Completer<int>().future);

    final refreshing = container.read(source);
    expect(refreshing.isLoading, isTrue);
    expect(refreshing.whenData((v) => v).isLoading, isTrue);
  });
}
