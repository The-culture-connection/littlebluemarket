# Bug (round 2): For you feed snaps back mid-drag — it is the masonry sliver, not a remount

All frontend. Supersedes the "remount" theory in `bug-feed-scroll-snapback.md` — the LbmAsync and paging fixes from that brief are right and stay, but they were not the cause. Two recordings now (iPhone, and the web app in Chrome), both after commit `aaa8773`.

## What the recordings show, frame by frame

- iPhone, 30 fps: the grid creeps down a few px per frame (finger dragging), then in **one frame** (≤33 ms) jumps back ~350 px, then keeps creeping from there, then jumps again. Instantaneous, and the drag survives it — so the `ScrollableState` and its `ScrollPosition` are the same objects throughout. A remount would have killed the drag. This is a **scroll offset correction** applied by a sliver during layout.
- Every position it jumps back to is the **start of a masonry run**: the row right under the FoundHouse business card (phone), the row under Sticker Punks, the row under the hero (web). Wide items break the grid into separate `SliverMasonryGrid` runs (`LbmMasonry.slivers`), and the jump lands at run offset 0 each time.
- The pin order never changes across a jump. Nothing visible is inserted; the run just resets to its top.
- Same behaviour on iOS and web, live backend only. The fixture backend never re-assembles the feed mid-scroll, which is why every widget test is green and the phone is not.

## The mechanism, in the package's own code

`flutter_staggered_grid_view` `RenderSliverMasonryGrid.performLayout` (`lib/src/rendering/sliver_masonry_grid.dart`, same in 0.7.x and master):

```dart
// A firstChild with null layout offset is likely a result of children reordering.
if (childScrollOffset(firstChild!) == null) {
  ... collectGarbage(leadingChildrenWithoutLayoutOffset, 0);
  if (firstChild == null) { addInitialChild(); }        // index 0, offset 0
}
...
while (scrollOffsets.any((x) => x > scrollOffset)) {
  earliestUsefulChild = insertAndLayoutLeadingChild(...);
  if (earliestUsefulChild == null) {
    ...
    } else {
      // We ran out of children before reaching the scroll offset.
      geometry = SliverGeometry(scrollOffsetCorrection: -scrollOffset);   // <-- the snap
      return;
    }
```

So: if the run's **leading laid-out child loses its `layoutOffset`**, the sliver throws away its leading children, restarts from index 0, cannot climb back to the current scroll offset (there is nothing before index 0), and corrects the viewport by `-scrollOffset` — straight to the run's start. That is the jump.

A child loses its `layoutOffset` when its render object is dropped and re-adopted (`RenderObject.dropChild` nulls `parentData`). That happens whenever the sliver's child at that **index** gets a widget with a **different key** — i.e. whenever an item is inserted or removed *above the viewport within the same run*, or the runs are re-cut so this sliver now holds a different slice of the list. Keys are stable per item (`grow:<item.key>`), so it is the indexes that shift, not the keys that change.

The package also caches gc'd children's extents as a plain stack (`_previousMainAxisExtents.removeLast()`), so it is only ever correct if children re-enter in exact reverse order. Any reindexing above the viewport breaks that too.

## What reindexes items above the viewport during a drag (live only)

`feedItemsProvider` re-runs `assembleFeed` on every emission of anything it watches: `chatMomentProvider` (live chatroom — every message), `hotThreadsProvider`, `nearbySellersProvider`, `announcementsProvider`, `allPromosProvider`, `purchasesProvider`, `directoryListingProvider(listingId)` for each directory post (via `_localListingIds`), `feedPagingProvider` (loadMore, which on this short feed fires mid-scroll), and `feedProvider` itself. `stableOrder` keeps the *relative* order of items that survive, but:

- an item that is **dropped** (assembly no longer includes it — a thread that fell out of "hot", a chat moment while its provider has no value, a directory card that a placement rule no longer selects once more posts are loaded) shifts every index after it;
- a run is **re-cut** when a wide item (`isFullWidth`: directory cards, makers rail, announcement, nudges) appears, disappears or moves, so a `SliverMasonryGrid` at sliver position *n* suddenly receives a different run.

Either one, while the viewport is inside that run, trips the path above. The oscillation (snap every ~0.5 s) is the assembly re-running on each live emission while the finger keeps dragging.

## Confirm in one run (before changing anything)

In `_GridState.build`, after `_shown = stableOrder(_shown, next)`, diff the old and new key lists and print insertions/removals with their index, guarded by `kLbmDev`:

```dart
final before = _shown.map((i) => i.key).toList();
_shown = stableOrder(_shown, next);
final after = _shown.map((i) => i.key).toList();
if (!listEquals(before, after)) debugPrint('feed reindex: -${before.where((k) => !after.contains(k))} +${after.where((k) => !before.contains(k))}');
```

and in `_FeedScreenState._maybeLoadMore` (already runs per tick): `debugPrint('px=${_controller.position.pixels.toStringAsFixed(0)} act=${_controller.position.activity.runtimeType}')`.

Run `flutter run -d chrome` against the **live** backend, drag slowly on For you. Expected: a `feed reindex` line, then `px` going backwards to a run boundary in the next frame while `act` is still `DragScrollActivity`. That is the confirmation. If `px` never goes backwards on its own, stop and report — the theory is wrong.

## Fix — two layers, both in `lib/`, no backend

### 1. Do not reindex a run that is on screen while it is scrolling (the cause)

In `_GridState`, hold assembly changes while the position is moving and apply them when it stops:

- keep `_shown` as is; add `List<FeedItem>? _pending`;
- in `build`: if `controller.hasClients && controller.position.isScrollingNotifier.value` → `_pending = next` and build with the current `_shown`; otherwise apply `stableOrder` as today;
- `initState`: listen to `controller.position.isScrollingNotifier` (attach in a post-frame callback; controller may not have clients on first build) and when it flips to `false` with `_pending != null`, `setState` applying `stableOrder(_shown, _pending)`;
- **never drop an item mid-session**: change `stableOrder` so an item that vanished from `next` is kept in place (it is still valid content — a thread that stopped being "hot" is still a thread). Drop only on pull-to-refresh (`reset()`), where the whole list is replaced anyway. Update the `stableOrder` test accordingly: "kept items keep their index; new items append; nothing is removed."
- appended items land at the end, below the viewport, which the masonry handles without correction.

With this, nothing above the viewport ever changes index while the finger is down, and the correction path is never entered.

### 2. Make the runs resilient anyway (belt to the braces)

In `LbmMasonry.slivers`:

- give each run's `SliverPadding`/`SliverMasonryGrid` a `key: ValueKey('run:${firstChildKey}')` (pass the item keys in alongside `children`, or read `children[i].key`), so a re-cut run maps to the sliver that already holds it instead of the sliver at the same position;
- build the grid with `SliverMasonryGrid(delegate: SliverChildBuilderDelegate(..., findChildIndexCallback: (key) => index of that key in this run))` rather than `.count`, so a child whose index shifts is moved, not recreated. Its `layoutOffset` still resets on the move, so this alone does not cure it — layer 1 does — but it stops the "recreate every child after the shift" churn that makes the jump land at a run start instead of a few pixels off.

Do not upgrade or fork the package for this; the path above exists in master too.

## Done when

- The instrumentation shows `feed reindex` lines arriving during a drag **and** `px` never going backwards on its own; then remove the prints.
- Fling For you five times from the top on the phone, and drag slowly through the FoundHouse / Sticker Punks cards on web: no snap. (Grace's manual row — the only evidence that counts.)
- Send a chat message from a second device while dragging For you on the first: the feed does not move; the chat pin updates once the drag ends.
- Pull-to-refresh still replaces the list (items dropped upstream disappear then).
- `stableOrder` tests updated to the keep-in-place rule; a new widget test that pumps a `_Grid` with a fake `feedItemsProvider`, starts a drag (`tester.startGesture` + `moveBy`), emits an assembly that removes an item above the viewport, and asserts `controller.offset` did not decrease.
- `scripts\verify-redesign.ps1 -Phase 5` green. Commit on `redesign/phase9-donations` as `fix(feed): hold feed changes while scrolling; masonry runs keyed`. No rebase, no merge, no deploy.
