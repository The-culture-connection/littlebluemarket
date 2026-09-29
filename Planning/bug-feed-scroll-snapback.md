# Bug: For you feed snaps back while flinging (Grace, 2026-09-29, screen recording)

All frontend. No rules, functions or Shopify/Shipturtle paths involved.

## What the recording shows (6 s, 60 fps, iPhone, Phase 9 build — tabs read Following · For you · Near me)

- One vertical fling on **For you**. The grid scrolls down for ~0.4 s, then the scroll offset **jumps back to where the fling started**, then scrolls down again, jumps back again — roughly every half second, for the whole clip, with no further touch.
- The **order of pins never changes** between the two positions (chat pin → "8 things" cart → FoundHouse business card → "+4" cart → Dolly hat → shoutout → "+6" cart → tee). So this is **not** the "content spliced in above the thumb" bug that `stableOrder` in `_GridState` fixed earlier today. Nothing is being inserted; the *scroll position itself* is being reset.
- The rest position it snaps back to is exactly the offset the feed was sitting at before the swipe. That is the signature of a `ScrollPosition` being **re-created** (a new position restores the last saved offset from `PageStorage`), or of a sliver applying a **scroll-offset correction** back to a cached geometry.

## Where to look (feed_screen.dart in `..\lbm-phase9`, branch `redesign/phase9-donations`)

Three things in the current tree can produce exactly this. Confirm which one before touching anything — the instrumentation below takes five minutes and tells you.

### Candidate 1 — the CustomScrollView is being unmounted and remounted (most likely)

`_GridState.build`:
```dart
final items = ref.watch(feedItemsProvider).whenData((next) => _shown = stableOrder(_shown, next));
```
`AsyncValue.whenData` on an `AsyncLoading` that *carries a previous value* returns a bare `AsyncLoading<R>()` with **no value**. `LbmAsync` then falls through `hasValue == false` and renders the **skeleton**, unmounting the `CustomScrollView`. When the data lands again it is remounted, the `ScrollController` attaches a brand-new `ScrollPosition`, and that position restores the offset saved at the end of the last scroll — the snap-back. If `feedProvider` (or anything `feedItemsProvider` reads through `posts.whenData`) flickers loading ↔ data while the user is flinging, you get exactly the recording: fling, snap, fling, snap.

This also silently violates LbmAsync rule 1 ("stale data stays on screen while refreshing"): today a pull-to-refresh on For you drops the whole grid to the skeleton.

**Fix (frontend, small):** do not route the stable-order bookkeeping through `whenData`. Keep the AsyncValue as-is and derive `_shown` from `valueOrNull`:
```dart
final items = ref.watch(feedItemsProvider);
final next = items.valueOrNull;
if (next != null) _shown = stableOrder(_shown, next);
return LbmAsync<List<FeedItem>>(items, ..., data: (_) => _grid(_shown));
```
and give the scroll view a stable identity so `_RefreshingOverlay` wrapping/unwrapping cannot remount it: in `LbmAsync`, always return the `Stack` (with the hairline `Positioned` present but transparent when not loading) instead of switching between `Stack` and bare `body`. Same tree shape → same Element → same ScrollPosition.

### Candidate 2 — `_maybeLoadMore` firing on every scroll tick and rebuilding the grid mid-fling

`_maybeLoadMore` runs on every pixel of scroll once past 80 % of `maxScrollExtent`. On a short feed (this market today) that threshold is met almost immediately, so `loadMore()` runs on the first tick of every fling. The guard `state.loading || state.done` stops duplicates, but each call still flips `loading` true → false and rebuilds the whole grid twice while the fling is in progress. Worse, the first call is `feedPage(cursor: null)`, which re-fetches the **same first 20 posts** the live stream already shows (all deduped by `seen`), so the first page load is pure churn: a rebuild that changes nothing but `paging`.

On its own this should not move the offset, but combined with Candidate 3 it can.

**Fix (frontend, small):** seed the cursor from the live page — `feedPage(cursor: state.cursor ?? live.last.id)` (pass the live tail id into `loadMore`) — and debounce the listener so it fires once per gesture, not per pixel (e.g. only when `pixels` crossed the threshold since the last check).

### Candidate 3 — `SliverMasonryGrid` scroll-offset correction on rebuild

`LbmMasonry.slivers` builds a fresh `SliverMasonryGrid.count(itemBuilder: (_, i) => items[i])` every `_Grid` rebuild. `flutter_staggered_grid_view`'s masonry sliver caches each child's column and offset by index; when the child list is rebuilt while the viewport is inside the sliver and it has to re-derive geometry for an index it no longer has, it applies a `scrollOffsetCorrection` back to the last geometry it trusts — a jump toward the run's start. The first run after the FoundHouse card (a wide item breaks the grid into a new masonry run) is right where the recording snaps to, which is consistent with this.

**Fix (frontend):** only matters if Candidates 1–2 are ruled out. Then: stop rebuilding the masonry slivers on paging state changes by watching `feedItemsProvider.select(...)` for the item list only, and hand `SliverMasonryGrid` a `SliverChildBuilderDelegate` with `findChildIndexCallback` keyed on `item.key` so it can keep geometry across rebuilds.

## Confirm before fixing — five minutes, on the phone build that shows it

In `_FeedScreenState`, log in `_maybeLoadMore` (it already runs on every tick):
```dart
debugPrint('feed pos=${_controller.position.hashCode} px=${_controller.position.pixels.toStringAsFixed(0)} '
           'act=${_controller.position.activity.runtimeType}');
```
and in `_GridState.build`: `debugPrint('grid build items=${_shown.length} loading=${items.isLoading} hasValue=${items.hasValue}');`

Then fling once and read the log:
- `pos=` **changes** hash mid-fling → Candidate 1 (position re-created). Fix 1.
- `pos=` constant, but `grid build` lines with `loading=true hasValue=false` → also Candidate 1 (the `whenData` value loss). Fix 1.
- `pos=` constant, `hasValue` always true, `grid build` firing 2–4× per fling with `px` jumping backwards between two builds → Candidates 2 + 3. Fix 2 first, retest; then 3.

Wrap the debugPrints in `if (kLbmDev)` and remove them in the commit.

## Done when

- One fling on For you scrolls and settles once; the log shows one ScrollPosition hash for the life of the screen.
- Pull-to-refresh on For you keeps the grid on screen with the hairline (LbmAsync rule 1), no skeleton flash.
- `loadMore()` never re-fetches the live first page (assert in the paging test that the first `feedPage` call carries a non-null cursor when the live page is non-empty).
- `scripts\verify-redesign.ps1 -Phase 5` green. Commit on `redesign/phase9-donations` as `fix(feed): scroll position survives refresh and paging` — do not rebase or merge; this rides along with the Phase 9 merge.

Manual checklist (Grace, on the phone): fling For you three times from the top — no snap-back; pull to refresh — grid stays, hairline shows; scroll to the bottom — "The end" appears once and the grid does not jump.
