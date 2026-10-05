import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/models/feed_item.dart';
import 'package:little_blue_market/state/feed_items.dart';

/// The rule the For you feed lives by, after two screen recordings:
/// **never reindex a grid somebody is holding.**
///
/// `feed_reindex_scroll_test.dart` measures why — a masonry run whose
/// children are reindexed corrects the scroll offset back to its own start,
/// several hundred pixels, in the frame it happens. This is about the half
/// that is ours: what the grid is allowed to do with a new assembly while a
/// finger is down.

FeedItem _pin(String id) =>
    NudgeItem(NudgeKind.values[id.hashCode.abs() % NudgeKind.values.length]);

void main() {
  group('stableOrder', () {
    // Distinct items, since the point is what happens to the running order.
    final a = const NudgeItem(NudgeKind.chipIn);
    final b = const NudgeItem(NudgeKind.reviewDelivered);
    final c = const NudgeItem(NudgeKind.sayHi);

    test('the first assembly is composed exactly as it likes', () {
      expect(stableOrder(const [], [a, b, c]), [a, b, c]);
    });

    test('what is already shown keeps its place', () {
      // Assembly would like them the other way round; it does not get to
      // reorder a grid that is on screen.
      expect(stableOrder([a, b], [b, a]), [a, b]);
    });

    test('new items go after what is already shown', () {
      expect(stableOrder([a], [c, a, b]), [a, c, b]);
    });

    test('an item assembly stops including is kept in place', () {
      // The rule this bug changed. Dropping it shifts the index of everything
      // after it, and a masonry run responds to that by jerking the scroll
      // back to its start. A thread that stopped being one of the hot ones is
      // still a thread; refreshing is when the list is really replaced.
      expect(stableOrder([a, b, c], [a, c]), [a, b, c]);
      expect(stableOrder([a, b], const []), [a, b]);
    });

    test('a kept item takes the newer copy when assembly still has one', () {
      // Keeping the place is not the same as freezing the contents: a pin
      // whose counts changed should show the new ones, at the old index.
      final older = _pin('x');
      final newer = _pin('x');
      expect(identical(stableOrder([older], [newer]).single, newer), isTrue);
    });
  });

  group('the paging generation', () {
    test('only a refresh bumps it, and it survives a page load', () {
      const first = FeedPaging();
      expect(first.generation, 0);

      // Loading another page is not a refresh: the grid must not forget.
      expect(first.copyWith(loading: true).generation, 0);

      // This is what pull to refresh does, and it is how the grid hears that
      // it may drop what it was holding.
      const refreshed = FeedPaging(generation: 1);
      expect(refreshed.generation, 1);
      expect(refreshed.copyWith(done: true).generation, 1);
    });
  });
}
