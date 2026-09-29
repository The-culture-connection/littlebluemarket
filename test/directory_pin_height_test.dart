import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/models/feed_item.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/state/providers.dart';
import 'package:little_blue_market/theme/app_theme.dart';
import 'package:little_blue_market/widgets/pins/directory_card.dart';
import 'package:little_blue_market/widgets/pins/directory_pin.dart';

/// A pin that changes height after it is drawn breaks a fling.
///
/// A fling is simulated against the scroll view's *estimated* height, because
/// the tiles below the fold have not been built. If the real total turns out
/// shorter, the scroll clamps back to a bottom that moved, which reads as the
/// page jumping and as never being able to reach the end. Dragging slowly
/// hides it, because each tile is built before you get to it and the
/// correction is a pixel at a time (Grace, 2026-09-29: "slowly dragging does
/// work").
///
/// Each directory pin fetches its own listing, so it is the one in the feed
/// that spends time not knowing its contents. It must not spend that time at
/// the wrong height.

final _post = DirectoryPost(
  id: 'directory_9001',
  authorId: 'dee',
  createdAt: DateTime(2026, 9, 29),
  tags: const [],
  likeCount: 0,
  commentCount: 0,
  likedByMe: false,
  listingId: '9001',
  title: 'Sticker Punks Print Shop',
);

/// The width a pin gets in the feed: a 390 phone less the gutters.
const _width = 370.0;

/// A listing that arrives when the test says so, rather than whenever the
/// fixtures feel like it: the whole point is to look at the pin *while* it is
/// waiting.
final _controller = StreamController<DirectoryListing?>.broadcast();

const _listing = DirectoryListing(
  id: '9001',
  ownerUid: 'dee',
  title: 'Sticker Punks Print Shop',
  status: 'publish',
  link: 'https://example.com/listing/sticker-punks/',
  website: 'stickerpunks.example.com',
  city: 'Ellington',
  state: 'CT',
  locationLabel: 'Ellington, CT',
  categories: ['Print shop'],
  tags: ['Stickers', 'BIPOC-Owned'],
  imageUrl: 'asset://assets/images/product-lipbalm.jpg',
  description: 'Custom stickers, posters, bookmarks and keychains.',
);

Widget _host(Widget child) => ProviderScope(
  overrides: [
    directoryListingProvider.overrideWith((ref, id) => _controller.stream),
  ],
  child: MaterialApp(
    theme: buildLbmTheme(Brightness.light),
    home: Scaffold(
      body: Center(child: SizedBox(width: _width, child: child)),
    ),
  ),
);

void main() {
  testWidgets('a directory pin is the same height before and after its '
      'listing arrives', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(DirectoryPin(item: DirectoryItem(_post))));

    // Nothing has come down the stream yet, so this is the placeholder: the
    // state the pin is in while you are flinging towards it.
    await tester.pump();
    final whileLoading = tester.getSize(find.byType(DirectoryPin)).height;

    // And now the listing arrives, exactly as it does mid-fling.
    _controller.add(_listing);
    await tester.pumpAndSettle();
    final whenLoaded = tester.getSize(find.byType(DirectoryPin)).height;
    expect(find.text('Sticker Punks Print Shop'), findsOneWidget);

    // Not exact, and the helper says why: the card is a minimum height round
    // intrinsic content, so a longer name is a taller card. What matters is
    // that the error is small enough that the sum of them across a feed does
    // not move the bottom out from under a fling. A generic placeholder was
    // out by about 140 pixels a card.
    expect(
      (whenLoaded - whileLoading).abs(),
      lessThan(20),
      reason:
          'the pin moved the page by ${(whenLoaded - whileLoading).abs()} '
          'pixels when its listing arrived; four of these in one feed is what '
          'makes a fling snap back',
    );
    // And it reserves a business card's shape, rather than any old height
    // that happens to be close.
    expect(whileLoading, closeTo(directoryCardHeightFor(_width), 0.5));
  });
}
