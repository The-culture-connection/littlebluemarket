# Little Blue Market — redesign build plan for Claude Code

*Written 2026-09-25. Visual source of truth: `Planning/full-app-redesign-mockup.html` (open in a browser; "All screens" tab). Companion files: `Planning/redesign-checkpoints.md`, `Planning/redesign-CLAUDE-additions.md`, `scripts/verify-redesign.ps1`, `scripts/deploy-check-redesign.ps1`.*

Read this whole file once before touching code. Then work from `Planning/redesign-checkpoints.md`, first unticked box only, exactly as `CLAUDE.md` already says.

---

## 0. What this is, in one paragraph

The app keeps its tokens (cornflower paper, white surfaces, orchid accent, Fraunces + Nunito, pill radii) and its data model. What changes is the *shape* of every screen: the Market feed becomes a two-column masonry grid where the photo is the card; every other kind of content (reviews, cart posts, forum threads, the open chat, announcements, shoutouts, nudges) becomes a "pin" in the same grid; the orchid accent is reserved for the cart action; product/review/cart-post details get a full-bleed image with a sheet underneath; every hashtag becomes a collection page you can follow and get notified about; the You hub gets quieter; seller "Under review" hands off to Shipturtle. The welcome screen and GIF do not change.

**A passing test is not proof.** Acceptance is what Grace sees on the phone against the running app. Tests exist to catch regressions afterwards. Section 9 lists what only a human can judge.

---

## 1. Preflight (must all be true before writing code)

| # | Check | Command / where | Expect |
|---|---|---|---|
| P1 | Toolchain | `flutter --version`, `node --version` | Flutter with Dart ≥ 3.11 (pubspec `sdk: ^3.11.0`), Node 20+ |
| P2 | Repo clean, on `main`, up to date | `git status`, `git pull` | nothing to commit |
| P3 | Existing gate is green *before* we start | `scripts\test-all.ps1` | "All green." (≈455 Flutter tests, functions tests, tsc) |
| P4 | Doctor is clean | `scripts\doctor.ps1` | no FAIL lines |
| P5 | Fixture backend runs | `scripts\run-fixtures.ps1` | app boots to the feed with demo data |
| P6 | Mockup opens | `Planning\full-app-redesign-mockup.html` in Chrome | all 34 screens listed in "All screens" |
| P7 | Branch | `git checkout -b redesign/pinterest-grid` | on the branch. **All work happens here.** Nothing merges to `main` until Grace says so (see hard gates). |
| P8 | Firebase project confirmed | `firebase use` | `little-blue-610e5` (dev). Never switch to `little-blue-cart-prod` in this plan. |

If P3 or P4 fails, stop and report; do not "fix it on the way".

---

## 2. Hard gates — stop and ask Grace

1. Merging or pushing anything to `main`. The plan ends with an open branch. (`CLAUDE.md` says "push to main at the end of each phase" — **that rule is suspended for this branch**; push the branch instead.)
2. Any change to `firebase/firestore.rules` or `firestore.indexes.json` — allowed only in Phase 6, and it must be deployed to **dev** only, after `functions/test/rules.test.mjs` passes on the emulator.
3. Anything touching Shopify, Shipturtle, `catalog.ts`, `cart.ts`, `orders.ts`, `linking.ts`, `vendors.ts`, or money (`*Cents`). This plan does not need to.
4. Deleting or rewriting data in any Firestore collection.
5. Deleting an existing test file or relaxing an assertion, except where a task below explicitly says "update this assertion".
6. Changing `lib/screens/onboarding/welcome_screen.dart`, `lib/app_assets.dart`, the welcome assets, `LbmConst.welcomeBlue/onWelcome/slate`, or `test/welcome_handoff_test.dart`. **Grace's explicit instruction: welcome screen and GIF are untouched.**
7. Anything not in the files-touched map (Section 4). If a task seems to need a file outside it, stop and say why.
8. Adding a dependency other than the two named in Phase 1 (`flutter_staggered_grid_view`, `cached_network_image` is *not* added — keep `Image.network` + `cacheWidth`).

---

## 3. Diagnosis — what is actually there today (symptom → cause → file)

This is a redesign, not a bug fix, but the "flat" feeling has concrete causes in code. Each one maps to a task.

| Symptom (Grace's words) | Root cause in code | Where | Fixed by |
|---|---|---|---|
| "Stale and flat" | Feed is one card type on repeat: `ListView(children:[... for post in posts PostCard(post)])`, every card a white `LbmCard` with identical padding/shadow | `feed_screen.dart:93-147`; `post_card.dart:35-39` | T2.1–T2.4 |
| Product photos look like placeholders | `_Tile` pastel art is the fallback, but real `Image.network` is used when `imageUrls` non-empty; cards frame the photo in a white card at 4:3 | `product_art.dart:47-78, 150-197` | T1.2 (natural aspect, no frame) |
| Nothing is a headline | Display font used only at 22–23px; product title sizes equal everywhere | `post_card.dart:212-238`; `product_screen.dart:108-114` | T1.4 tokens, T3.1 |
| Accent means nothing | `accentDeep`/`accentMist` used on chips, tabs, buttons and the cart icon alike | `primitives.dart:373-449` (`ChipStyle.initiative`), `post_card.dart:735-808` | T1.3 (`CartPill`), T1.5 (chip restyle) |
| No motion | No animation anywhere in the feed; no toast on add-to-cart (a snackbar at most) | `post_card.dart:598-625` | T1.3, T1.6 |
| Community and Market feel like two apps | Feed reads only `posts`; threads/chat/announcements never appear in it; hashtag taps go to a search-results screen | `providers.dart:295-303`; `nav.dart:51-63` | T2.2, T4.x |
| Tags aren't a place | `#tag` tap → `ResultsScreen` (a search UI defaulting to `#PlasticFree`); no follow, no notify | `app_router.dart:94-98`; `results_screen.dart` | T4.1–T4.4, T6.1–T6.4 |
| You hub is busy | `ProfileIdentity` + directory card + 3 tabs + drafts panel stacked | `profile_screen.dart:112-180` | T5.3 |
| Under review goes nowhere useful | `showUnderReviewDialog` just says "sent for approval"; drafts panel has no link | `add_product_screen.dart:849-886`; `widgets/seller_drafts.dart` | T5.5 |

Things that are **already right** and must be preserved: cart-is-the-like (`post_card.dart:62-67`, `firestore_social_repository.dart:98`), `saveCount` on `Product` (`models.dart:229`), natural-aspect image decoding (`product_art.dart:361-426`), the reviews histogram (`product_screen.dart:581-673`), `Message.attachedProductId` (`message.dart:27`), person-follow → push (`index.ts:1234-1246`, `push.ts:329-338`), `watchFeed(tags:)` with its index (`firestore_social_repository.dart:53-56`, `firestore.indexes.json:3-17`).

---

## 4. Files touched map

**New (frontend)**
- `lib/models/feed_item.dart` — sealed `FeedItem` union (product/review/cart/thread/chat/announcement/shoutout/nudge/makers/directory).
- `lib/widgets/masonry.dart` — `LbmMasonry` (two-column, wide-span support).
- `lib/widgets/pins/` — `product_pin.dart`, `review_pin.dart`, `cart_pin.dart`, `thread_pin.dart`, `chat_pin.dart`, `announcement_pin.dart`, `shoutout_pin.dart`, `nudge_pin.dart`, `makers_rail.dart`, `pin_caption.dart`.
- `lib/widgets/cart_pill.dart` — the orchid pill on every image, with bounce.
- `lib/widgets/lbm_toast.dart` — top toast with thumbnail.
- `lib/widgets/detail_sheet.dart` — `DetailGallery` + `DetailSheet` (full-bleed image, sheet with 26px radius pulled up over it).
- `lib/widgets/filter_chips.dart` — horizontal filter row (ink pill when on).
- `lib/screens/market/tag_screen.dart` — the tag/collection page.
- `lib/state/feed_items.dart` — `feedItemsProvider`, mix rules, paging.
- `test/masonry_test.dart`, `test/feed_items_test.dart`, `test/pins_test.dart`, `test/tag_screen_test.dart`, `test/product_detail_test.dart`, `test/composer_quick_replies_test.dart`, `test/you_hub_test.dart`.

**Modified (frontend)**
- `pubspec.yaml` (+ `flutter_staggered_grid_view: ^0.7.0`)
- `lib/theme/app_theme.dart` (add `LbmText.headline`, `LbmText.pinTitle`, `LbmText.pinMeta`)
- `lib/widgets/primitives.dart` (`ChipStyle` colours; `LbmChip` unchanged API), `lib/widgets/screen.dart` (`Composer` gains `quickReplies`, `attachedProduct`), `lib/widgets/product_art.dart` (expose `NaturalPhoto`), `lib/widgets/post_card.dart` (keep exports; `PostCard` becomes a thin adapter used only by `post_screen`), `lib/widgets/tips.dart`, `lib/widgets/first_tour.dart` (copy), `lib/widgets/seller_drafts.dart`, `lib/widgets/composers.dart` (review composer star-first)
- `lib/screens/market/feed_screen.dart`, `product_screen.dart`, `post_screen.dart`, `seller_feed_screen.dart`, `search_screen.dart`, `results_screen.dart`, `collection_screen.dart`, `reviews_screen.dart`, `cart_screen.dart`
- `lib/screens/community/chatroom_screen.dart`, `forums_screen.dart`, `forum_screen.dart`, `thread_screen.dart`
- `lib/screens/you/profile_screen.dart`, `dm_screen.dart`, `messages_screen.dart`, `notifications_screen.dart`, `notification_settings_screen.dart`, `sell_screen.dart`, `add_product_screen.dart`, `edit_profile_screen.dart`
- `lib/screens/onboarding/auth_screens.dart` (ProfileSetupScreen only — add the tags step)
- `lib/router/app_router.dart` (+ `tag/:key` shared route), `lib/router/nav.dart` (+ `goToTag`)
- `lib/state/providers.dart` (+ `followedTagsProvider`, `tagFeedProvider`, `hotThreadsProvider`, `chatMomentProvider`, `nearbySellersProvider`)
- `lib/data/repositories/repositories.dart` (+ methods below), `lib/data/firebase/firestore_social_repository.dart`, `firestore_profile_repository.dart`, `firestore_catalog_repository.dart`, `lib/data/firebase/mappers.dart`, **`lib/data/fixtures/fixture_repositories.dart`, `fixture_store.dart`** (mirror every interface change)
- `lib/models/notification.dart` (+ `NotificationKind.tagPost`, `NotificationPrefs.tagPosts`), `lib/models/models.dart` (`TagCount` unchanged)
- `test/screens_smoke_test.dart` (+ `tag/:key`), `test/visual_check.dart` (+ shots), `test/shots/*.png` regenerated, `test/guest_gating_test.dart` (assertion update noted in T2.5)

**Modified (backend — Phase 6 only)**
- `firebase/firestore.rules` (+ `users/{uid}/followedTags/{key}`, `hashtags/{key}/subscribers/{uid}`)
- `firebase/firestore.indexes.json` (+ collection-group `threads` by `commentCount desc, createdAt desc` if `threads` is top-level; verify first)
- `functions/src/push.ts` (`PushType` + `'tagPost'`, `NotificationPrefs.tagPosts`, `shouldPush`, `titleFor`), `functions/src/index.ts` (`onTagFollowWritten`, tag fan-out in `onPostWritten`), `functions/src/notifications.ts` (no change expected), `functions/test/rules.test.mjs`, `functions/test/push.test.ts`, new `functions/test/tag_follow.test.ts`

**Never touched**: `welcome_screen.dart`, `app_assets.dart`, assets, `catalog.ts`, `cart.ts`, `orders.ts`, `shipturtle*.ts`, `linking.ts`, `vendors.ts`, `admin-web/`, anything under `_archive/`.

---

## 5. Repository interface additions (so the fixture mirror is written once)

Add to `lib/data/repositories/repositories.dart` and implement in **both** Firestore and fixture repositories in the same task:

```dart
// SocialRepository
Stream<List<Post>> watchTagFeed(String tag, {int limit = 30});         // wraps watchFeed(tags:[tag])
Stream<Set<String>> watchFollowedTags();                                // users/{me}/followedTags keys
Future<void> setFollowingTag(String tag, {required bool on, bool notify = false});
Future<void> setTagNotify(String tag, {required bool on});             // notify implies follow
Stream<List<ForumThread>> watchHotThreads({int limit = 6});             // across forums, by commentCount then createdAt
Stream<ChatMoment> watchChatMoment();                                   // last 2 messages + count in last hour
Stream<List<Post>> watchThreadPostsFor(...)  // NOT needed — threads are their own FeedItem

// ProfileRepository
Future<List<Person>> nearbySellers({int limit = 8});                    // isSeller == true, ordered by handleLower for now (index exists)

// MessagingRepository
Future<void> sendToChatroom(String text, {String? attachedProductId});  // add the optional param
```

`ChatMoment` is a new small model in `lib/models/message.dart`: `{ List<Message> latest; int lastHourCount; int hereNow /* 0 until presence exists */ }`.

Rules for the fixture: same behaviour as Firestore in spirit — `setFollowingTag` mutates an in-memory set and re-emits; `watchHotThreads` sorts the fixture threads by `commentCount`.

---

## 6. Phases and tasks

Ordering: **frontend phases first (1–5), backend last (6)**, per Grace's checklist convention. Phase 6 depends on nothing in 1–5 except the pref key name, so it can also be run first if a backend session is what's available.

Every task has *Done when* (observable) and *Test* (which test, and the requirement it proves). A task is not done because its test passes; it is done when *Done when* is true on the fixture backend.

---

### Phase 1 — Foundations (frontend)

**T1.1 Add the masonry dependency and primitive**
- Missing: no masonry layout exists (`pubspec.yaml:9-32` has no grid package).
- Change: add `flutter_staggered_grid_view: ^0.7.0`. Create `lib/widgets/masonry.dart` exporting `LbmMasonry({required List<Widget> children, List<bool>? wide})` built on `SliverMasonryGrid.count(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 10)` inside a `CustomScrollView`, where a `wide` child renders as a full-width sliver *between* masonry runs (split the children list at each wide item). Padding 10 horizontal, 110 bottom (tab bar clearance).
- Done when: a debug page (behind `kDebugMode`, not routed) shows 10 tiles of random heights in two balanced columns with one full-width tile in the middle, at 390 wide and at text scale 2.0 without overflow.
- Test: `test/masonry_test.dart` — pumps `LbmMasonry` with 7 tiles + 1 wide; asserts two columns exist (x-offsets of tiles fall in exactly two buckets), the wide tile's width equals the viewport minus padding, and no `FlutterError` overflow at `textScaleFactor: 2.0`. *Proves: masonry layout renders mixed heights and wide spans at the mockup's width.*

**T1.2 `NaturalPhoto` — photo with its own aspect, no frame**
- Missing: `_NaturalFrame` (`product_art.dart:361-426`) is private and only used by `ProductGallery`; pins need it.
- Change: export `NaturalPhoto({required String url, double minAspect = 3/4, double maxAspect = 5/4, BorderRadius radius = LbmRadius.imageR, Widget? fallback})` from `product_art.dart`, reusing `_NaturalFrame`'s decode listener and `resolveImageUrl` + `cacheWidth: 600`. Fallback (no photo / error) = the existing pastel `_Tile` at 4:5. Do **not** change `ProductArt`'s signature (importers listed in grounding §13.2).
- Done when: the debug page shows 6 real photos from fixture products at differing heights with 18px corners directly on the paper, and a product with no photo shows the pastel tile.
- Test: `test/pins_test.dart` group "NaturalPhoto" — pumps with a 100×150 and a 150×100 `MemoryImage`; asserts rendered aspect is clamped within [3/4, 5/4] and that an `asset://` missing path renders the fallback. *Proves: photo-is-the-card sizing and graceful fallback.*

**T1.3 `CartPill` with bounce, and the "cart = like" contract**
- Missing: cart affordance is an icon in an action row (`post_card.dart:735-808`); no animation.
- Change: `lib/widgets/cart_pill.dart`: `CartPill({required String productId, String? variantId, CartPillSize size = .small})`. Reads `cartProvider` for `inCart` (same lookup as `_Actions`, `post_card.dart:577-583`). Visual: 34px pill, `accentDeep` fill + `accentInk` label "Cart" with the cart icon; when in cart: `ink` fill, white check, label "Carted". On tap: `requireProfile` → `showCartTipOnce` (first time) → `addToCart(...)` (reuse `post_card.dart:158-173`), then `AnimatedScale` 1 → 1.25 → 1 over 450ms with `Curves.elasticOut`, and fire `LbmToast.show(context, title: 'In your little blue cart', subtitle: product.name, thumbnailUrl: ..., action: ('View', goToCart))`. Guests: tap opens the existing guest gate sheet.
- Done when: on the fixture backend, tapping the pill on any product photo in the feed bounces, flips to "Carted", shows the toast with the product photo, and the header cart badge count increments — without leaving the feed. Tapping again removes the line and flips back.
- Test: `test/pins_test.dart` group "CartPill" — with `FixtureBackend`, tap → asserts `cartProvider` has the line, pill text reads "Carted", toast is found; tap again → line gone. Guest → asserts gate sheet shown, no line added. *Proves: cart-from-the-grid works and guests are gated (Grace's product decision, `CLAUDE.md:14`).*

**T1.4 Type scale for pins and headlines**
- Missing: `LbmText` (`app_theme.dart:18-55`) has no headline size above `display` 22–23.
- Change: add `LbmText.headline` (Fraunces 30, height 1.02, weight 800, letterSpacing −0.3) for announcement pins and detail titles at 24; `LbmText.pinTitle` (Nunito 13, w800, height 1.3); `LbmText.pinMeta` (Nunito 11.5, w700, `ink2`). Add to `design_tokens_test.dart` only if it asserts the enumeration of styles (check first).
- Done when: styles compile and `flutter analyze` is clean.
- Test: existing `test/design_tokens_test.dart` stays green (run it). *Proves: no contrast/ token rule broken.*

**T1.5 Restyle chips so orchid means "act now" only**
- Wrong: `ChipStyle.initiative` uses `accentMist/accentText` for hashtags (`primitives.dart:373-449`), competing with the cart pill.
- Change: `ChipStyle.initiative` → `skyMist` fill + `skyDeep` text; `ChipStyle.on` → `ink` fill + `surface` text (dark: `surface` fill + `ink` text); keep `accentMist` **only** for `ChipStyle.plain`-with-`accent: true` used by "Ask" and "Rate" affordances (add a `bool accent = false` param). Add `lib/widgets/filter_chips.dart`: `FilterChips({required List<(String key, String label)> items, required String selected, required ValueChanged<String> onSelect})` rendering `LbmChip(style: on/quiet)` in a horizontal `ListView`.
- Done when: in the feed only cart pills and the FAB are orchid; hashtag chips are sky.
- Test: `test/pins_test.dart` group "chips" — asserts `LbmChip('#x', style: initiative)` background == `c.skyMist`. *Proves: accent reserved for the cart action.*

**T1.6 `LbmToast`**
- Missing: no in-app toast component; snackbars are used.
- Change: `lib/widgets/lbm_toast.dart` — `OverlayEntry` inserted at top (`top: 58`), `surface` card radius 18, `shadowLift`, optional 40px thumbnail, title/subtitle, optional action; slides in 400ms `Curves.easeOutBack`, auto-dismisses 2400ms, swipe-up to dismiss. Only for the user's own actions (cart, repost, review posted, follow) — never for other people's events (Grace's rule: pop-ups triggered by the user's own actions + foreground push only).
- Done when: visible on cart tap (T1.3), review posted (T3.4), follow tag (T4.3).
- Test: `test/pins_test.dart` "toast" — pumps, calls `LbmToast.show`, `pump(500ms)` finds title, `pump(3s)` finds nothing. *Proves: transient, non-blocking feedback.*

**T1.7 `FeedItem` union and pin widgets (rendering only)**
- Missing: `Post` is sealed (`post.dart:14-17`) and the feed needs non-post items.
- Change: `lib/models/feed_item.dart`:
  ```dart
  sealed class FeedItem { String get key; }
  class ProductItem extends FeedItem { final ListingPost post; bool proof; }
  class ReviewItem extends FeedItem { final ReviewPost post; }
  class CartItem  extends FeedItem { final CartPost post; }
  class ShoutoutItem extends FeedItem { final ShoutoutPost post; }
  class DirectoryItem extends FeedItem { final DirectoryPost post; }
  class ThreadItem extends FeedItem { final ForumThread thread; final ThreadComment? topReply; final List<Person> repliers; }
  class ChatItem extends FeedItem { final ChatMoment moment; }
  class AnnouncementItem extends FeedItem { final Announcement a; final Promo? promo; bool hero; }
  class NudgeItem extends FeedItem { final NudgeKind kind; /* reviewDelivered, sayHi, forumActivity */ final Object? payload; }
  class MakersRailItem extends FeedItem { final List<Person> sellers; }
  ```
  Build `lib/widgets/pins/*` one widget per item, matching the mockup exactly: `ProductPin` (NaturalPhoto + CartPill + optional "N carted" badge top-left + caption: title 2 lines, avatar 22px + first word of shop, price Fraunces 14 right); `ReviewPin` (square photo + star strip pill bottom-left + quoted text + "Name · bought it"); `CartPin` (2×2 collage, "+N" ink tile, caption + "Add all" orchid text which calls `addManyLines` like `_CartBody`, `post_card.dart:824-850`); `ThreadPin` (white, "FORUM · name" sage kicker, question Fraunces 17, top reply quoted with sage left border, replier avatars, "N replies", "Join in"/"Joined ✓" pill); `ChatPin` (ink background, pulsing sage dot, "Open chat · N here now", last two messages as translucent bubbles, "N messages in the last hour", white "Jump in" pill); `AnnouncementPin` (hero: wide, gradient `accentDeep→#5E2A8F→skyDeep` **via tokens** — add `LbmColors.heroGradient` rather than raw colours; kicker, `LbmText.headline`, body, white CTA pill; non-hero: same at 150px min height with the 🛒 glyph drawn as an icon at 14% opacity); `ShoutoutPin` (sky gradient, kicker, quote Fraunces 17, "by" row); `NudgePin` (white or tinted `accentMist`/`skyMist`/`sageMist`, emoji icon in a 44px rounded box, Fraunces 16 title, 12px body, small CTA pill); `MakersRail` (wide; "Makers near you" + horizontal 96px cards with gradient ring avatars and a reason line).
  Every pin is tappable as a whole (`InkWell` → route), and every pin must survive 390 width at text scale 2.0 (`Wrap`/`FittedBox` idiom from `_CartBody`).
- Done when: the debug page renders one of each pin from fixture data, light and dark.
- Test: `test/pins_test.dart` — one `testWidgets` per pin asserting key texts and no overflow at 2.0 scale in both themes. *Proves: every card kind in the mockup exists and is safe at the app's size constraints.*

**Phase 1 verify**: `scripts\verify-redesign.ps1 -Phase 1` → analyze clean, `flutter test test/masonry_test.dart test/pins_test.dart test/design_tokens_test.dart` green. Commit `redesign(1): masonry, pins, cart pill, toast, feed item model`. Push branch.

---

### Phase 2 — The feed (frontend)

**T2.1 `feedItemsProvider` — merge sources and apply the mix rules**
- Missing: `feedProvider` is a single `posts` stream of 20 (`providers.dart:295-303`); nothing merges other sources; `feedPage` unused.
- Change: `lib/state/feed_items.dart`. Inputs (all existing or from §5): `feedProvider` (posts, blocked filtered), `hotThreadsProvider` (new, `watchHotThreads`), `chatMomentProvider` (new), `announcementsProvider` (`providers.dart:154`, member-only; guests get none) + `promoRepository.live()` for a hero image if a promo exists, `purchasesProvider` (for the review nudge: `p.delivered && p.canReview`, same predicate as `tips.dart:106-162`), `nearbySellersProvider` (new), `isGuestProvider`, `tipsProvider`, a `feedFilterProvider` (`all|product|review|cart|forum|chat|community`).
  Assembly (pure function `assembleFeed(FeedInputs) → List<FeedItem>` in the same file, no Riverpod inside so it is unit-testable):
  1. Slot 1: newest un-retired announcement as `hero: true` if user has not seen it (`announcementsSeenAt` from prefs), else compact; guests: the cart-tip hero (`Tips.cartIsTheLike` not yet seen) — this replaces `CartTipCard`.
  2. Posts in `createdAt` order, mapped to Product/Review/Cart/Shoutout/Directory items. `proof: true` on a ProductItem when `product.saveCount >= 50`.
  3. Interleave: after every 3rd post insert the next item from the queue `[nudge?, thread, chat, makersRail, thread, ...]` where nudge is `reviewDelivered` if applicable (regular users) or `sayHi` (new users: profile created < 7 days, from `sessionProvider`), threads come from `hotThreadsProvider` (max 3 per page), chat once per 12 items, makers rail once per page.
  4. Rules: never two of the same `FeedItem` type adjacent except ProductItem; at most 1 nudge per 8 items; dismissed nudge (stored in `shared_preferences` under `nudge_dismissed_<kind>_<id>` with a 7-day TTL) is skipped.
  5. Filter: `product` → Product+Directory; `review`; `cart`; `forum` → Thread; `chat` → Chat; `community` → Thread+Chat+Shoutout; `all` → everything. The announcement stays in every filter.
  Paging: `FeedItemsNotifier` holds the assembled list and a `cursor`; `loadMore()` calls `socialRepository.feedPage(cursor)` (`repositories.dart:207`) and re-assembles the tail. Trigger at 80% scroll.
- Done when: fixture feed shows, top to bottom: hero, product, product, nudge/thread, product, review, thread, chat pin, cart post, makers rail… with no two non-product kinds adjacent; scrolling past 20 posts loads more.
- Test: `test/feed_items_test.dart` — feeds `assembleFeed` fixed inputs and asserts: (a) first item is `AnnouncementItem(hero:true)` for a member who hasn't seen it; (b) no adjacent equal types except Product; (c) `filter: 'community'` yields only Thread/Chat/Shoutout/Announcement; (d) a nudge with `dismissed` set is absent; (e) guest input yields the cart-tip hero and no Thread/Chat items (see T2.5). *Proves: the feed recipe from `Planning/ux-map.md`, deterministically.*

**T2.2 Rebuild `feed_screen.dart` on the grid**
- Wrong: `ListView` of `PostCard` (`feed_screen.dart:93-147`).
- Change: header = `SearchPill` (existing) + cart `CircleIconButton` with count badge (from `cartCountProvider`); a `SegmentedTabs`-style row "For you · Near me · Following" (ink underline, not pills — new small widget `TopTabs` in `primitives.dart`); `FilterChips` row; body = `LbmMasonry` of `feedItemsProvider` items rendered through a `switch (item)` → pin widgets; wide items: AnnouncementItem(hero), MakersRailItem. Keep `RefreshIndicator` (invalidate `feedProvider`, `hotThreadsProvider`, `chatMomentProvider`). Keep `UnverifiedBanner` as the first (wide) item when applicable. Remove `CollectionRail`, `DirectoryRail`, `CartTipCard`, `ReviewPromptCard` from this screen (they move: rail → search screen T5.1; tip → hero; review prompt → nudge). "Near me" tab = existing `filters.nearMe` toggle + `NearMeShelf` replaced by the same masonry over `nearbyProductsProvider`. "Following" = `watchFeed` filtered to authors in `following` ∪ posts whose tags ∈ `followedTags` (client-side filter of the same stream for now).
  Bottom of feed: `'That's everything new'` + a "Go see Community" ghost pill.
  FAB: the existing `showNewPostSheet` moves into the tab bar center (T5.6) — until then keep it as a `FloatingActionButton` with `accentDeep`.
- Done when: matches mockup "Feed" screen on the fixture backend in light and dark; pull-to-refresh works; filter chips narrow the grid without a full reload; the hero tap opens the announcement route; cart pill works from the grid.
- Test: update `test/screens_smoke_test.dart` route `/market` expectations (it should still find the search pill); add `test/feed_screen_test.dart`: pumps `/market` on `FixtureBackend`, asserts a `ProductPin`, a `ThreadPin` and a `ChatPin` are present; taps "Forums" chip → only `ThreadPin`s remain. *Proves: community content is in the Market feed and the filter works.*

**T2.3 Retire `PostCard` from the feed, keep it for `PostScreen`**
- Change: `post_card.dart` keeps exporting `PostActionBar`, `openMention`, `addToCart`, `openBuyUrl`, `ReviewRow`; `PostCard` itself remains for `post_screen.dart:71` until T3.3 replaces it. Delete `_ListingBody` etc. only after T3.3. Do not delete `PostCardSkeleton` yet.
- Done when: `flutter analyze` clean, no dead-code warnings.
- Test: existing suite. *Proves: no importer broke.*

**T2.4 Tab bar with center compose button**
- Wrong: FAB floats over content; tab bar is 3 items (`app_shell.dart:120-128`).
- Change: tab bar = Market · Community · **[+]** · Cart · You, where [+] is a 54px `accentDeep` circle calling `showNewPostSheet` (add "Ask the community" option that opens `NewThreadComposer` for the user's most active forum, and "Post my cart"). Cart tab routes to `goToCart` (it is a shared route, not a branch — push it). Guests: Community and You hidden as today; [+] opens the guest gate. Keep the `dot` for unread community.
- Done when: matches the mockup tab bar; `guest_gating_test.dart` still passes (update its expectation of tab count from 3 → 4 with [+] excluded; state that in the commit).
- Test: `test/guest_gating_test.dart` (updated assertion, explicitly). *Proves: guests still can't reach Community/You.*

**T2.5 Guests and community pins**
- Risk (grounding §13.4): guests are bounced off `/community*`.
- Change: `assembleFeed` omits Thread/Chat items for guests (their "join" affordance would dead-end). Guests keep Product/Review/Cart/Shoutout/Announcement + the cart-tip hero; the guest banner becomes the wide dark join bar pinned above the tab bar (mockup "Guest feed").
- Done when: continue-as-guest → feed shows the join bar, no thread/chat pins; tapping a cart pill shows the gate sheet.
- Test: covered in `feed_items_test` (e) and `guest_gating_test`. *Proves: guest gating survives the redesign.*

**T2.6 Feed golden shots**
- Change: `flutter test test/visual_check.dart --update-goldens`; commit the new `test/shots/light-feed.png`, `dark-feed.png`. Attach both PNGs to the phase report so Grace can compare to the mockup without running anything.
- Done when: shots exist and visibly match the mockup's feed.

**Phase 2 verify**: `verify-redesign.ps1 -Phase 2`. Commit `redesign(2): masonry feed with community pins, filters, tab bar`. Push branch. **Report to Grace with the two shots.**

---

### Phase 3 — Detail screens (frontend)

**T3.1 Product detail**
- Wrong: card-in-card layout (`product_screen.dart:67-327`).
- Change (order is the spec): (1) `DetailGallery` — `ProductGallery(natural:true)` edge-to-edge, no radius, floating back/share/cart circles at top 50 (`floatbar`), dots over the image; (2) `DetailSheet` pulled up 26px over the image, `surface`, radius 26 top: maker row (`Avatar md`, name, `'${loc} · replies in ~1h'` — the reply-time string is **static copy** until data exists; say so in a doc comment) with an `Ask` accent chip → `goToDm(seller.id)`; title `LbmText.display 24`; price Fraunces 26 + stars + `InlineLink('${total} reviews')` that scrolls to the reviews block; **variant pills** (`_VariantRow` → chips, `ink` when selected; keep passing `variant?.name` as today, grounding §13.8); **proof line** `'${saveCount} carted'` with three overlapping avatars of… nothing yet: render avatars only if `product.cartedBy` exists (it does not) — so proof line is count only, no avatars, no "people you've bought from" (that claim would be invented data); big row: `PillButton` full-width `accentDeep` "Add to cart" (bounce on tap like CartPill) + ghost "Buy now" → `showBuySheet` (unchanged contract); **facts** row of three `skyWash` tiles: Shipping (`spec.shipping` first line), Pickup (from spec if present else "Ask the maker"), Returns (`spec.returns` first line); description; (3) below the sheet, on paper: `Reviews` block = existing `_RatingBreakdown` restyled into a white block with "Write one" link (opens `ReviewComposer` if the user has a reviewable purchase, else the purchase-required copy), filter chips "Verified · With photos · 5★" (client-side over `reviewsProvider`), `_LatestReviews` rows with maker replies shown if `review.reply` exists (check model; if absent, omit); **"Also sold by {shop}"** = `LbmMasonry` of `ProductPin`s from `sellerProductsProvider(sellerId)` excluding this product, capped 6, with a "Their shop" link → `goToSeller`. **No** "Also in carts with this" (Grace removed it). **No** product comments block (there is no product comments source; do not invent one).
- Done when: matches mockup "Product detail" for a product with 4 photos (fixture jam-equivalent) and one with 1 photo; variant tap updates price; Add to cart bounces + toast; Ask opens the DM; "Also sold by" shows the maker's other products.
- Test: `test/product_detail_test.dart` — on `FixtureBackend` pumps `/market/product/<id>`; asserts title, price, "N carted", the Add to cart button, the "Also sold by" section contains ≥1 other product from the same seller and not the current one; tapping a variant chip changes the displayed price. *Proves: the product page contract (variants → price, proof count, seller cross-sell) as Grace specified.*

**T3.2 Review detail and cart-post detail (replace `PostScreen` body by kind)**
- Wrong: `post_screen.dart:71` renders the feed card at the top of the detail.
- Change: `PostScreen` switches on kind: `ReviewPost` → gallery (photo or product photo) + sheet: reviewer row with "bought <date> · ✓ verified" when `purchaseId != null`, stars, quote in `LbmText.display 21`, body, **product card row** with a `CartPill`, "Helpful · N" chip (wire to existing comment-like plumbing? No — helpful does not exist; render as a static "Helpful" chip that opens the comment composer, and note it), maker reply row if present, comments (existing `_CommentComposer`), then "More reviews of {shop}" masonry of `ReviewPin`s from `reviewsProvider(productId)`. `CartPost` → header (avatar, "posted their cart · age · snapshot, won't change"), caption in a `quote` card, full-width "Add all N · $total" button (existing `addManyLines` path), `LbmMasonry` of the snapshot items as `ProductPin`s (**from the snapshot**, not live products — `CartPostItem`), comments. `ListingPost` → redirect to `goToProduct` (a listing post's detail *is* the product). `ShoutoutPost` and `DirectoryPost` → current layout restyled with the sheet.
- Done when: tapping a review pin, a cart pin and a product pin in the feed open the three distinct layouts.
- Test: extend `test/product_detail_test.dart` with two cases: `/market/post/<reviewId>` finds the quote and a `CartPill`; `/market/post/<cartId>` finds "Add all" and N `ProductPin`s equal to `itemCount`. *Proves: snapshot semantics (cart post shows its frozen items) and review → cart path.*

**T3.3 Maker board (`seller_feed_screen.dart`)**
- Change: centered header (`Avatar lg`, name Fraunces 24, `'${loc} · joined ${month year}'`), buttons "Get drop alerts" (= existing `_NotifyMeButton` logic, `seller_feed_screen.dart:127-180`, relabelled) + ghost "Message"; stats row (sales → `Fmt.money(grossSalesCents)` labelled "Total sales" per product decision, rating, carted = sum of `saveCount` over their products, "~1h" replies static); filter row Shop · Reviews · Posts · About; body masonry (Shop = `ProductPin`s from `sellerProductsProvider`; Reviews = `ReviewPin`s via `reviewsTagged`? no — use `postsByProvider(sellerId)` filtered to reviews *about* their products if that exists, else omit the tab; Posts = their posts as pins).
- Done when: matches mockup "Maker board".
- Test: smoke route `/market/seller/<id>` in `screens_smoke_test.dart` (already listed) plus one assertion in `product_detail_test.dart` that "Their shop" from T3.1 lands here. *Proves: seller cross-sell loop.*

**T3.4 Review composer, star-first**
- Wrong: `ReviewComposer` (`composers.dart:127-254`) is text-first.
- Change: sheet opens with the product thumbnail + "How was the {product}?", five 40px stars, "Tap a star · that alone counts" (a stars-only review is valid: `body` optional — check `createReview` validation and relax to allow empty body when rating ≥ 1; update the fixture and the rules if rules require a body — **if rules need changing, that is Phase 6, so until then keep body required and prefill it with the tapped chip text**), quick chips ("Would buy again", "Great gift", …) that append to the body, optional photo, orchid "Post review". On success: `LbmToast('Review posted', '{shop} will see it')`.
- Done when: from the review nudge or a "Write one" link, a review posts in three taps on the fixture backend.
- Test: `test/composer_quick_replies_test.dart` "review sheet" — tap 5th star, tap a chip, tap Post → `FixtureSocialRepository` has a new review with rating 5 and body containing the chip text. *Proves: the low-friction review path that feeds the review-pin loop.*

**Phase 3 verify**: `verify-redesign.ps1 -Phase 3`; `--update-goldens` for `light-post.png`; commit `redesign(3): product, review and cart-post details, maker board, star-first reviews`. Push.

---

### Phase 4 — Tags as collections (frontend)

**T4.1 `tag/:key` route and `goToTag`**
- Wrong: hashtags route to `ResultsScreen` (`app_router.dart:94-98`, `nav.dart:51-63`).
- Change: add shared route `tag/:key` → `TagScreen(tag)` in `_sharedRoutes()`; add `goToTag(String tag)` in `nav.dart` (push; **not** the replace semantics of `goToResults`). Change every `goToResults(tag)` call whose argument starts with `#` to `goToTag` (list in grounding §10: `post_card.dart:208,424,472,497,865,912,1079`, `product_screen.dart:168`, `chatroom_screen.dart:205`, `thread_screen.dart:136`, `feed_screen.dart:83`, `search_screen.dart:218`, `results_screen.dart:501`, `notifications_screen.dart:118`). Keyword searches keep `goToResults`. `ResultsScreen` default query `#PlasticFree` → `''` (empty state).
- Done when: tapping any `#tag` anywhere opens the tag page; back returns to where you were.
- Test: `test/tag_screen_test.dart` — `HashtagText('#Handmade')` tap → router location is `/market/tag/handmade`. Add `tag/:key` to `screens_smoke_test.dart` routes (count becomes 24). *Proves: tags are a place, consistently.*

**T4.2 `TagScreen`**
- Change: `DetailGallery`-style hero: photo = first product with a photo from the tag feed (fallback: sky gradient), kicker "Collection", `#Tag` in `LbmText.headline`, `'${postCount} posts · ${makers} makers'` (postCount from `hashtags/{key}`, makers = distinct `authorId`s in the loaded page — say "in this page" semantics in a comment), two pills: **Follow / ✓ Following** and **🔔 Notify me / Notifying you** (notify implies follow; unfollow clears notify). Filter row All · Products · Reviews · Posts · Makers · 📍 Near me. Body: `LbmMasonry` over `watchTagFeed(tag)` mapped to pins (Products = listing posts; Reviews = `reviewsTagged(tag)` as `ReviewPin`s; Makers = `MakersRail` of distinct authors). "Near me" applies `searchFiltersProvider.nearMe` as the feed does.
- Done when: matches mockup "Tag = collection page"; Follow toggles and persists across app restart on the fixture backend (fixture store keeps state for the process).
- Test: `tag_screen_test.dart` — pumps `/market/tag/handmade` on fixtures: finds ≥1 `ProductPin`; tap Follow → `watchFollowedTags()` emits the set containing `handmade`; tap Notify → `setTagNotify` called with `on: true` and Follow reads "✓ Following". *Proves: follow/notify state machine as Grace described ("follow a collection, get notified when there's a new post about a tag").*

**T4.3 Repository + fixture for tag follows (client side)**
- Change: implement §5 `watchFollowedTags`, `setFollowingTag`, `setTagNotify`, `watchTagFeed` in `firestore_social_repository.dart` against `users/{me}/followedTags/{key}` docs `{ tag, notify: bool, createdAt }` (key = `tag.replace('#','').toLowerCase()`, same as `index.ts:1136`), and in `fixture_repositories.dart`. `followedTagsProvider` (stream) in `providers.dart`. Until Phase 6 deploys the rules, the Firestore write will be **denied on the live backend** — the UI must surface that via the existing `translateFirestoreError` path, not swallow it. The fixture backend works immediately.
- Done when: fixture: works. Live dev: Follow shows the permission error toast until Phase 6 lands (expected; note in the report).
- Test: `tag_screen_test.dart` covers it on fixtures. *Proves: the client contract is complete before the backend.*

**T4.4 Onboarding — "pick 3 tags you care about"**
- Missing: `ProfileSetupScreen` (`auth_screens.dart:771-1016`) has name/handle/bio only.
- Change: after Bio, a section "Pick 3 things you care about" of `LbmChip`s from `popularTagsProvider` (fallback: a static list of the 8 initiative tags if the provider is empty), multi-select, minimum 1, `ChipStyle.on` when selected. On `_finish`: `ProfileEdit(..., tags: selected)` (field exists, `repositories.dart:630`) and then `setFollowingTag(tag, on: true)` for each (best-effort; failures don't block signup). Do **not** touch the welcome screen; `/setup` only.
- Done when: new signup → chips visible → profile shows the tags → tag pages show "✓ Following".
- Test: `test/auth_screens_test.dart` (exists per grounding — extend): select two chips, finish → fixture profile `tags` has both and `watchFollowedTags()` contains both. *Proves: onboarding seeds the personal feed.*

**T4.5 Search screen becomes the browse hub**
- Change: `search_screen.dart` → mockup "Search": category photo tiles (from `kMarketCategoryHandles` → `goToCollection`, photo = collection `imageUrl`), "Trending this week" (`popularTagsProvider` → `goToTag`), "Tags you follow" (`followedTagsProvider`), `MakersRail`, "Recent" (existing recent searches). `CollectionScreen` (Shopify collections) gets the same hero + Follow/Notify treatment as tags **only if** a collection maps to a hashtag key (it does per manual-test J8 "store tags become hashtags"); otherwise Follow is hidden.
- Done when: matches mockup "Search"; tapping a category tile opens the collection.
- Test: smoke route; `tag_screen_test.dart` adds: from `/market/search` tapping a trending tag chip lands on `/market/tag/...`. *Proves: discovery routes into tag pages.*

**Phase 4 verify**: commit `redesign(4): tags as collections — tag page, follow/notify (client), onboarding tags, browse hub`. Push.

---

### Phase 5 — Community, You, Seller, polish (frontend)

**T5.1 `Composer` quick replies and product cards in messages**
- Missing: `Composer` (`screen.dart:117-133`) has no chip slot; bubbles ignore `attachedProductId` (`chatroom_screen.dart:198-207`, `dm_screen.dart:190-260`).
- Change: `Composer({..., List<String> quickReplies = const [], Product? attachedProduct, VoidCallback? onAttach})` renders a chip row above the field; tapping a chip fills the field (does not send). Bubbles render a `ProductCard` mini row (40px photo, name, price, tap → product; a `CartPill(size: .small)` inside) when `message.attachedProductId != null` (hydrate via `productProvider`). `sendToChatroom` gains `attachedProductId` (§5). Quick replies per screen: DM → `["Is this still available?", "Do you do pickup?", "🛒 Add to cart" (only when the thread has an attached product)]`; chatroom → new users `["👋 Say hi — I'm new", "Where's everyone based?"]`, others `["I'm in", "🛒 Claimed one!"]`; thread → `["Mine's in too", "What qualifies?"]`; product-page "Ask" opens the DM with `attachedProductId = product.id` and a prefilled "Hi! Is the {name} still available?".
- Done when: mockup "DM with a maker", "Open chat", "Thread" match; sending from the product page shows the product card in the DM.
- Test: `test/composer_quick_replies_test.dart` — tap a chip → field text equals chip; send with `attachedProductId` → the bubble contains the product name and a `CartPill`. *Proves: community feeds commerce (the bridge Grace asked for).*

**T5.2 Forums grid, forum threads as pins, chat header**
- Change: `forums_screen.dart` → `LbmMasonry` of gradient tiles (gradients from a small token list in `LbmColors`, keyed by `forum.id.hashCode % n`), member count + activity line, badges "🔥 active" (≥5 comments in 24h — compute from `threads` loaded for the card, or omit the badge if not cheaply available and say so), "📍 near you", "new"; Join → existing `setForumMembership`. `forum_screen.dart` → masonry of `ThreadPin`s + a "Start a thread" `NudgePin`. `chatroom_screen.dart` → header "Open chat" + "N here now" is **omitted** (no presence data) — use "Everyone in the market"; pinned announcement row at top from `announcementsProvider.first`; bubbles restyled (18/18/18/5 radii). Keep `_PullTab`.
- Done when: matches mockup "Forums", "Forum (threads)", "Open chat".
- Test: smoke routes; `feed_screen_test.dart` adds: tapping a `ThreadPin` in the feed lands on `/community/thread/<id>`. *Proves: feed → community deep link.*

**T5.3 You hub, quiet**
- Wrong: busy stack (`profile_screen.dart:112-180`).
- Change, exactly and only this (Grace: "make it quieter"): header "You" + bell (badge) + mail + gear (→ `/you/edit`); identity row: `Avatar lg` (no ring, **no points, no level, no streak**), name Fraunces 22, `@handle · city`, the person's `tags` as sky chips; stats row bought · in cart · reviews · posts (`purchases`, `cartCountProvider`, review count from `postsByProvider` filtered, `posts`) — **"Total sales" appears only for sellers**, in place of "in cart"; **one** quiet banner (translucent white, 36px thumbnail, "N things you bought are waiting for a review · Rate →") when `purchases.any(delivered && canReview)` — no shipping status, no order info anywhere; one quiet "Got something to sell? · Apply →" row for non-sellers; filter row Bought · Reviews · Posts · Carts; masonry of pins. Sellers: the Products tab content (`SellerProductsGrid`, drafts) moves to `/you/sell` (T5.5); the You hub for a seller shows a "Your shop →" row instead of "Got something to sell?". Remove `_DirectoryCard` from here (it lives in edit profile, `edit_profile_screen.dart:378-407`). No first-week checklist on this screen (it lives in the feed as a nudge for new users, T2.1).
- Done when: matches mockup "You hub (new)" and "(regular)"; nothing on the screen mentions shipping, orders, points or levels.
- Test: `test/you_hub_test.dart` — pumps `/you` on fixtures as a buyer with a delivered unreviewed purchase: finds the review banner text, finds no text matching `/points|level|streak|shipping|order/i`; as a seller: finds "Total sales". *Proves: Grace's "quieter, no points, no shipping" instruction, literally.*

**T5.4 Notifications, settings, messages, edit profile restyle**
- Change: `notifications_screen.dart` → white block "New" with 40px thumbnails (post/product image when `postId`/`productId` resolves) and "Earlier" dimmed; `notification_settings_screen.dart` → add the **"New posts under tags you follow"** switch bound to `NotificationPrefs.tagPosts` (model + mapper + `toMap`, `mappers.dart:111-124`) and a "Quiet hours" row **only if** a prefs field exists (it does not — omit, do not invent); `messages_screen.dart` → rows with "· about {product}" when the last message has `attachedProductId`; `edit_profile_screen.dart` → same fields, restyled with `LbmField`, keep `_SellerRows` including `_ShipturtleRow`.
- Done when: matches mockup screens; the tag switch persists on fixtures.
- Test: extend `you_hub_test.dart`: toggling the tag switch updates `notificationPrefsProvider.tagPosts`. *Proves: the notify preference the backend will honour exists client-side.*

**T5.5 Seller: "Your shop" and Under review → Shipturtle; no Orders**
- Wrong: under-review dialog goes nowhere (`add_product_screen.dart:849-886`); drafts panel has no link.
- Change: new route `/you/sell` content for sellers = mockup "Your shop": stats (Total sales, carted, drop alerts = subscriber count if `Person.subscribers` exists else omit, rating), the "N people carted it this week" prompt (**only if** a weekly delta exists — it does not; use `'${saveCount} people carted {top product}'` all-time and say so), **Under review** block listing listings with status `submitting`/pending from `listingsProvider` where each row and the block's "Open in Shipturtle ↗" link call `launchUrl(appConfig.shipturtleUrl, mode: externalApplication)` (same as `_ShipturtleRow`, `edit_profile_screen.dart:409-437`), a one-line note "Orders and shipping are managed in Shipturtle, not here.", "Live in your shop" masonry of `ProductPin`s + an "Add photos" nudge for products with < 3 photos. `showUnderReviewDialog` → title "Sent for review", primary button "Track it in Shipturtle ↗" (launchUrl), secondary "Back to your shop". Non-sellers keep the existing apply flow (`SellWithUsScreen`) restyled. **No Orders screen, no orders list anywhere in the app** (`directoryOrdersProvider` remains only where it is today).
- Done when: as a seller on fixtures, submitting a product shows the dialog whose primary button opens `https://app.shipturtle.com/` (verify via `url_launcher` mock); the shop screen lists it under review with the ↗ link; searching the app for "Orders" as a screen title finds nothing.
- Test: `test/you_hub_test.dart` "seller shop" — mock `url_launcher`; tap "Track it in Shipturtle" → launched URL equals `appConfig.shipturtleUrl`; assert no route contains `orders`. *Proves: Grace's Shipturtle hand-off and "no orders screen".*

**T5.6 Onboarding restyle (not welcome), first tour copy, cart & checkout, admin preview**
- Change: `EmailScreen`/`VerifyScreen`/`ProfileSetupScreen` restyled to mockup (fields as `LbmField`, orchid primary, white secondary) — keep `_OnboardingScaffold` and every behaviour (verify polling, intent routing); **welcome untouched**. `first_tour.dart` copy: page 1 mentions the grid and the cart pill; page 2 "Tap any hashtag to see its collection — follow it to get new posts"; page 4 no mention of points/shipping. `cart_screen.dart` → masonry of carted `ProductPin`s + full-width "Check out · N items" + "Post this cart to the feed →" (existing cart composer). `showCheckoutHandoff` copy "Secured by Shopify · you're still in the app". Admin screen (`/you/admin`): add a live `AnnouncementPin` preview of the announcement being composed (pure widget reuse).
- Done when: mockup "Sign in", "Verify", "Profile setup", "Cart", "Checkout", "Admin" match; `welcome_handoff_test.dart` untouched and green.
- Test: existing `auth_screens_test.dart`, `welcome_handoff_test.dart`, `checkout_sheet_test.dart` green; `screens_smoke_test.dart` 24 routes × 2 themes green; `text_scaling_test.dart` green. *Proves: nothing behavioural regressed in onboarding/checkout.*

**T5.7 Goldens and the final frontend sweep**
- Change: `--update-goldens`; regenerate all `test/shots/`; delete dead code (`_ListingBody`… in `post_card.dart` once nothing imports them; `CollectionRail`/`DirectoryRail` if unused; `NearMeShelf`); `flutter analyze` must report zero, including unused-element infos.
- Done when: `verify-redesign.ps1 -Phase 5` green; all shots attached to the report.

**Phase 5 verify**: commit `redesign(5): community, you hub, seller shop, onboarding restyle, goldens`. Push. **Report to Grace with all shots. Stop here until she has looked** — Phase 6 changes rules.

---

### Phase 6 — Backend: tag follow → notify (backend)

**T6.1 Rules**
- Change in `firebase/firestore.rules`: under the `users/{uid}` block (near `:309-312`):
  ```
  match /followedTags/{tag} {
    allow read, write: if isSelf(uid) && member()
      && tag == tag.lower() && tag.size() > 0 && tag.size() <= 40
      && (request.method == 'delete' || (request.resource.data.keys().hasOnly(['tag','notify','createdAt']) && request.resource.data.notify is bool));
  }
  ```
  and under `hashtags/{tag}` (`:568-571`): `match /subscribers/{uid} { allow read, write: if false; }`.
- Done when: `functions/test/rules.test.mjs` gains three tests: owner can create/update/delete their followedTags doc; another user cannot read it; nobody can write `hashtags/x/subscribers`. Emulator run green.
- Test: those rules tests. *Proves: follow state is private and the fan-out list is server-only, mirroring the person-follow design (`rules.test.mjs:411`).*

**T6.2 `onTagFollowWritten` mirror**
- Change in `functions/src/index.ts`: modelled on `onFollowWritten` (`:1234-1246`): on write to `users/{uid}/followedTags/{tag}` → if deleted or `notify === false`, delete `hashtags/{tag}/subscribers/{uid}`; else set it `{ createdAt }`. Ensure `hashtags/{tag}` exists (`set({tag}, {merge:true})`) so the doc isn't orphaned.
- Test: `functions/test/tag_follow.test.ts` with the firestore mock pattern used by `push.test.ts`: create with notify:true → subscriber doc exists; update notify:false → gone. *Proves: only "notify" followers are fanned out (follow-without-notify stays quiet).*

**T6.3 Fan-out in `onPostWritten` + push type**
- Change: `push.ts`: `PushType` + `'tagPost'`; `NotificationPrefs.tagPosts?: boolean` (default on); `shouldPush` case → `prefs.tagPosts !== false`; `titleFor('tagPost', …)` → `New under #${tag}`. `index.ts onPostWritten` (`:1122-1227`), **create only**, after the follower block: for each tag in `afterAll.tags` (max 5 tags), page `hashtags/{key}/subscribers` (cap 500 like `postSubscribers`), dedupe against people already notified in this run (mentions, shoutout seller, author's followers) and the author, then `notify(uid, { type:'tagPost', fromUid: authorId, postId, text: '${authorName} posted under #tag: ${snippet}', route: '/market/tag/${key}', title })`. Batch `notify` calls with `Promise.all` in chunks of 25 (the sequential-await tail-drop risk from the earlier audit).
- Done when: on the dev project with the emulator: user A follows `#handmade` with notify, user B posts with `#handmade` → A gets a bell row with `type: 'tagPost'` and route `/market/tag/handmade`; A with `tagPosts:false` gets the bell row but no push; A who only follows (notify false) gets nothing.
- Test: `functions/test/push.test.ts` add `shouldPush` cases for `tagPost`; `tag_follow.test.ts` add the fan-out case asserting `notify` called once per subscriber and not for the author. *Proves: the notification Grace asked for, with the preference respected.*

**T6.4 Client wiring of the new kind**
- Change (small frontend inside the backend phase because it depends on the type name): `NotificationKind.tagPost` + mapper (`mappers.dart:87-97`), icon 🏷️ in `notifications_screen.dart`, route from `n.route`. `NotificationPrefs.tagPosts` was added in T5.4.
- Test: `you_hub_test.dart` adds: a fixture notification of kind `tagPost` renders and taps to `/market/tag/...`. *Proves: end-to-end from push to tag page.*

**T6.5 Hot threads query and index (if needed)**
- Check first: is `threads` a top-level collection with `commentCount` (grounding says `threads/{id}` exists with `commentCount` maintained by `onThreadCommentWritten`)? If yes, `watchHotThreads` = `threads.orderBy('commentCount', desc).orderBy('createdAt', desc).limit(6)` and needs a composite index → add to `firestore.indexes.json`; deploy indexes to dev. If `commentCount` is missing on old docs, treat null as 0 client-side.
- Done when: the feed's `ThreadPin`s on the live dev backend show the most-commented threads.
- Test: none automatable beyond the index existing in the file; manual check M12.

**T6.6 Deploy to dev and check**
- `firebase deploy --only firestore:rules,firestore:indexes,functions:onTagFollowWritten,functions:onPostWritten --project little-blue-610e5` (**dev only**, hard gate 2). Then `scripts\deploy-check-redesign.ps1` must print PASS for: rules contain `followedTags`; functions list includes `onTagFollowWritten`; index for `threads` present or marked N/A; `appConfig` callable returns a `shipturtleUrl`.
- Commit `redesign(6): tag follow → notify (rules, mirror, fan-out, client kind)`. Push. Report.

---

### Phase 7 — Integration checks (both)

Pairs of tasks that touch the same path and need a combined check:

| Pair | Collision | Check |
|---|---|---|
| T1.3 CartPill × T3.1 big Add-to-cart | both write the same cart line; double-tap across surfaces | `product_detail_test`: tap pill in "Also sold by" then the big button on that product → exactly one line each, no duplicate |
| T2.1 nudge × T5.3 You banner | same predicate (`delivered && canReview`) must agree | `you_hub_test`: when the feed shows the review nudge, the You banner shows too, and both vanish after posting a review (T3.4) |
| T4.1 goToTag × T4.5 search × T2.2 "Following" tab | followed tags must appear in Following | `feed_screen_test`: follow `#handmade` → Following tab contains a post tagged `#handmade` |
| T5.1 attachedProductId × T2.1 ChatPin | chat pin renders a message with a product card | `pins_test` ChatPin with an attached product → product name present |
| T6.3 fan-out × existing follower fan-out | a user who follows both the author and the tag must be notified once | `tag_follow.test.ts` dedupe case |

---

## 7. Criteria matrix (Grace's acceptance criteria as checks)

Frontend first, backend at the bottom. Driven by `scripts/verify-redesign.ps1 -Phase all`, which runs each test named here and prints one line per row.

| ID | Side | Grace said | Assertion | Test |
|---|---|---|---|---|
| C1 | FE | "I love the grid" | Feed renders `LbmMasonry` with two columns of mixed heights | `masonry_test`, `feed_screen_test` |
| C2 | FE | Community in the feed | `/market` contains ThreadPin and ChatPin for a member | `feed_screen_test` |
| C3 | FE | Reviews, products, carts in the feed | ProductPin, ReviewPin, CartPin present | `feed_screen_test` |
| C4 | FE | Filter chips | "Forums" chip leaves only ThreadPins | `feed_screen_test` |
| C5 | FE | Cart from the grid, cart is the like | Pill tap adds line, toast, badge; no like button anywhere | `pins_test`, grep `favorite` in lib/widgets/pins → 0 |
| C6 | FE | Product detail | gallery, variants→price, "N carted", big cart button, facts, reviews block | `product_detail_test` |
| C7 | FE | "Also sold by this seller" (not "also in carts") | section present with seller's other products; text "in carts with" absent | `product_detail_test` |
| C8 | FE | Every tag is a collection with its page | `#tag` tap → `/market/tag/<key>`; page shows hero + masonry | `tag_screen_test` |
| C9 | FE | Follow a collection | Follow toggles `watchFollowedTags()` | `tag_screen_test` |
| C10 | FE | Notified on new post under a tag (pref) | Notify pill sets notify; settings switch exists | `tag_screen_test`, `you_hub_test` |
| C11 | FE | Tags in profile creation | setup shows chips; finish stores `tags` and follows them | `auth_screens_test` |
| C12 | FE | You hub quieter, no points, no shipping | no text matching `/points|level|streak|shipping|order/i` on `/you` | `you_hub_test` |
| C13 | FE | Keep review banner, quieter | banner present when a delivered purchase is unreviewed | `you_hub_test` |
| C14 | FE | Under review → Shipturtle | dialog primary and shop rows launch `appConfig.shipturtleUrl` | `you_hub_test` |
| C15 | FE | No orders screen | no route containing `orders`; no screen title "Orders" | `you_hub_test` |
| C16 | FE | Welcome GIF/screen unchanged | `git diff main -- lib/screens/onboarding/welcome_screen.dart lib/app_assets.dart assets/` is empty | `verify-redesign.ps1` |
| C17 | FE | Guests still gated | guest feed has no Thread/Chat pins; Community/You hidden | `guest_gating_test`, `feed_items_test` |
| C18 | FE | Works at 390 and text scale 2.0, light+dark | no overflow across 24 routes | `screens_smoke_test`, `text_scaling_test` |
| C19 | BE | Follow state private, fan-out server-only | rules tests | `rules.test.mjs` |
| C20 | BE | Notify only when notify=true | mirror + fan-out tests | `tag_follow.test.ts` |
| C21 | BE | Preference respected | `shouldPush('tagPost')` false when `tagPosts:false` | `push.test.ts` |
| C22 | BE | Deployed to dev | deploy-check prints PASS | `deploy-check-redesign.ps1` |

---

## 8. What cannot be proven automatically (name it)

- That the grid *feels* punchy: rhythm of heights, how the orchid pill reads against real photos, the bounce timing.
- Photo quality from the live catalog (aspect clamps chosen from Shopify CDN photos; some vendor photos are tiny or portrait).
- Push delivery on a physical phone (emulator tests stop at `sendPushToUid`).
- Shipturtle opening in the external browser on iOS/Android.
- "N here now" and "replies in ~1h" — **static copy** in this plan; must be visibly labelled as such in code comments so nobody mistakes them for data.
- That announcement hero images look right (they come from promos, which the admin site sets).

---

## 9. Manual checklist for Grace (do / expect / wrong if)

Frontend first, backend last. Run on the fixture backend first (`run-fixtures.ps1`), then live dev.

| # | Side | Do this | Expect | Something is wrong if |
|---|---|---|---|---|
| M1 | FE | Open the app as a new member | Welcome screen exactly as before, GIF plays, three buttons | anything on the welcome screen looks different |
| M2 | FE | Finish profile setup | a "Pick 3 things you care about" chip row; Into the market | no chips, or you can finish with zero selected |
| M3 | FE | Land on the feed | popup once, then a hero announcement on top of a two-column photo grid | white framed cards; single column; hero missing |
| M4 | FE | Scroll one screen | products, a review pin, a forum pin, the dark chat pin, a cart post, makers rail — never two non-product kinds in a row | the same kind twice in a row; empty white gaps |
| M5 | FE | Tap the pink pill on a photo | bounce, "Carted", toast with the photo, badge on the bag icon; you stay on the feed | navigates away; no toast; two lines in cart after one tap |
| M6 | FE | Tap "Forums" chip | only forum pins remain | products still show |
| M7 | FE | Tap a product | full-bleed photo, sheet slides up: maker + Ask, price, variant pills, "N carted", big pink Add to cart, ship/pickup/returns tiles, reviews with bars, **Also sold by {shop}** | "Also in carts with this" appears; white card-in-card |
| M8 | FE | Tap Ask | DM opens about that product with a prefilled question and quick-reply chips | plain empty DM |
| M9 | FE | Tap any #tag anywhere | tag page with hero, Follow and 🔔 Notify me | search results screen |
| M10 | FE | Follow, close app, reopen, revisit | still "✓ Following" | reset |
| M11 | FE | You tab | avatar, name, tags, four stats, one quiet review banner (if you have a delivered unreviewed item), tabs, grid | points, level, streak, shipping, orders, a ring around the avatar |
| M12 | FE | As a seller: submit a product | "Sent for review" with **Track it in Shipturtle ↗** opening app.shipturtle.com; shop screen lists it under review with ↗ | "Back to your shop" is the only button; an Orders screen exists |
| M13 | FE | Dark mode | everything readable, pill still pink, chat pin darker than paper | white text on pink; invisible chips |
| M14 | FE | Guest: continue as guest | grid, join bar at bottom, no forum/chat pins; pill → join sheet | forum pins visible; pill adds to cart |
| M15 | BE | Live dev: A follows #tag with Notify; B posts with that tag | A's bell shows "New under #tag"; phone push if enabled | nothing; or A gets it with Notify off |
| M16 | BE | Settings: turn off "New posts under tags you follow"; repeat M15 | bell row only, no push | push still arrives |

---

## 10. After the plan (the loop)

1. **Execute** — Claude Code runs Phases 1–5 without checking in (one commit per phase, verify script green, push the branch), reports once with the golden shots. Stops before Phase 6.
2. **Adversarial review** — a *fresh* session reads this plan and the diff with one job: find a test that asserts something the product doesn't do, and find where two phases collide (Section 7 pairs). It reports; fixes come back as a Phase 8 diagnosed symptom → cause before any code.
3. **End-to-end** — `scripts/verify-redesign.ps1 -Phase all` plus M1–M14 on fixtures, then Phase 6 and M15–M16 on dev.
4. **Grace's eyes** — Section 9 on a real phone. Bugs found become new tasks with file:line causes, not tweaks in place.
