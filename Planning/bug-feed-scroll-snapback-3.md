# Bug (round 3): reproduced on the production web build 0.3.9+12 (`296f720`) as a guest — replace the lazy masonry

All frontend. Supersedes rounds 1 and 2; keep their fixes (they were real bugs), but neither was *this* bug.

## What I did

Opened https://lbm-web-production.up.railway.app/market in Chrome as a **guest** (no sign-in, nothing live changing, the held-assembly code from `296f720` in place — `version.json` says build 12, `main.dart.js` built 20:33 GMT today) and drove the feed with synthetic wheel events of 150 px, screenshotting after each one.

Reproduces every time, with no touch and no data change:

1. **For you · All**: scroll down in 150 px steps. Somewhere between 2 and 6 steps in, the feed **stops accepting downward scroll**: every further wheel-down is reverted within the same frame; wheel-up still works; the web scrollbar thumb sits near the *top* of its track, so this is not `maxScrollExtent` clamping — the position is being corrected back. Earlier in the session the same feed instead did a 4-step cycle: three steps down, then a snap back ~345 px, repeat, forever. Which of the two you get depends on where the first run's rows fall relative to the viewport; both are the same defect.
2. **For you · Carts** (a single masonry run, no wide items): scrolls cleanly to "That's everything new". No snap.
3. **Post screen** (`LbmMasonry.fixed`, no `SliverMasonryGrid`): scrolls cleanly.
4. The **layout of the first run changes** when the fault fires. At the top the run is a correct masonry: `[+6 cart | Custom Art]`, `[Open chat | +5 cart]`. After the snap it is `[+6 cart | (empty)]`, `[Custom Art | +5 cart]`, `[Open chat | —]` — Custom Art has moved from column 1 to column 0, under the +6 cart, leaving a blank half-width slot beside the +6 cart. That is the signature of `RenderSliverMasonryGrid` re-laying the run from a leading child whose cached `crossAxisIndex`/`lastMainAxisExtent` it no longer has (`_previousCrossAxisIndexes.isNotEmpty ? removeLast() : 0`) — it defaults to column 0 and extent 0, the run grows by a row, and the sliver emits a `scrollOffsetCorrection` on the next layout to reconcile. Every subsequent scroll re-enters the same path, hence "stuck" or "cycle".

So: the item list is static, nothing is reindexed by us, and the package still corrupts its own leading-edge cache during ordinary scrolling of a run whose first row has one tall and one short pin. Round 2's mechanism (our reindexing) was one *trigger*; the package gets there on its own too. `findChildIndexCallback` and keyed runs do not help because the corruption is inside the render object's stack-based cache, not in element matching.

## Fix: stop using `SliverMasonryGrid` for the feed runs

Runs are short (≤ ~10 pins between wide items) and the feed is paged in twenties, so per-child laziness inside a run buys nothing. Lay each run out as **one box** with a small masonry `RenderBox` of our own, and keep laziness *per run* with a `SliverList`. Boxes never emit scroll-offset corrections and have no garbage-collection cache to corrupt.

### `lib/widgets/masonry.dart`

1. Add `MasonryRun`, a `MultiChildRenderObjectWidget` with `RenderMasonryRun extends RenderBox with ContainerRenderObjectMixin, RenderBoxContainerDefaultsMixin`:
   - `performLayout`: `columnWidth = (width - gutter) / 2`; for each child in order, `child.layout(BoxConstraints.tightFor(width: columnWidth), parentUsesSize: true)`, place it in the column with the smaller running height (ties → column 0), at `Offset(col * (columnWidth + gutter), heights[col])`, then `heights[col] += child.height + rowGap`. `size = Size(width, max(heights) - rowGap)` (0 when empty).
   - `hitTestChildren` via `defaultHitTestChildren`, `paint` via `defaultPaint`, `computeDryLayout` mirrors `performLayout` without positioning.
   - Parent data: `ContainerBoxParentData<RenderBox>`.
   This is ~90 lines; it is the shortest-column rule `SliverMasonryGrid` uses, so the grid looks identical.
2. `LbmMasonry.slivers` becomes: cut `children` into runs and wide items exactly as now, but emit a **single** `SliverList.builder` (or `SliverList` with a `SliverChildListDelegate` — the list is short) whose items are, in order: `Padding(pad, MasonryRun(children: run))` for a run, `Padding(pad, wideChild)` for a wide item, `SizedBox(height: rowGap)` between them. Give each item a stable key (`ValueKey('run:${firstChildKey}')`, the wide child's own key). Drop the per-run `SliverMasonryGrid`, `findChildIndexCallback`, and the `flutter_staggered_grid_view` import from this file.
3. `LbmMasonry.fixed` uses `MasonryRun` too, so "Also sold by this maker" / "More reviews" become a true masonry instead of alternating columns. Delete the alternate-column `column()` helper.
4. `pubspec.yaml`: remove `flutter_staggered_grid_view` if nothing else imports it (`grep -r staggered lib test`). If something else does, leave it.

### `lib/screens/market/feed_screen.dart`

No change to `_GridState`: it already passes `children` + `wide` into `LbmMasonry.slivers`. Keep the hold-while-scrolling and keep-in-place rules from round 2; they are correct and cheap.

### Tests

- Update `feed_reindex_scroll_test.dart`: its "reindexed mid-drag → jumps back 430 px" case should now **not** jump (a box list does not correct); keep the control. Rename the expectation and say why in the test.
- New `masonry_run_test.dart`: five children of heights 300, 80, 200, 120, 90 in a 400-wide run land at column/offset `(0,0) (1,0) (1,92) (1,304) (0,312)` with `rowGap = 12` (shortest column wins each time: after three children the columns stand at 312 and 304, so the 120 goes right, then the 90 goes left), and the run's height is 424. One test for an empty run (height 0) and one for a single child.
- Goldens: `flutter test --update-goldens` for the feed shots; the grid should be pixel-identical or within a row gap. Attach before/after.
- `scripts\verify-redesign.ps1 -Phase 5` green.

## Done when (I will verify these myself on the web build — no need to wait for a phone)

- On `lbm-web-production` (or staging with real data) as a guest, 30 wheel steps of 150 px on **For you · All** reach "That's everything new" with the scrollbar thumb at the bottom and no step moving the content upward.
- The first run keeps its layout (`[+6 cart | Custom Art]`, `[Open chat | +5 cart]`) at every scroll position.
- Post screen and tag/collection screens unchanged.
- Commit on `redesign/phase9-donations` as `fix(feed): masonry runs laid out as boxes; SliverMasonryGrid retired`. Push to `staging` first; tell me and I will run the wheel script against staging before anything goes to `main`.

## If you want to keep the package instead (not recommended)

The only package-side mitigation that avoids the leading-edge cache is to never let it garbage-collect: `CustomScrollView(cacheExtent: 4000)`. I could not confirm on the web build that the fault waits for garbage collection (the first run's first pin was still inside the default 250 px cache when the feed locked), so this is a guess, and the box layout above is not.
