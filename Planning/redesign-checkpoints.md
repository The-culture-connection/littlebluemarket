# Redesign checkpoints — work top to bottom, one at a time

Rules: this file is the queue. Do the first unticked box only. A box is ticked when its *Done when* in `Planning/redesign-plan.md` is true on the fixture backend, `scripts\verify-redesign.ps1 -Phase N` is green, and the phase commit is pushed to the branch `redesign/pinterest-grid`. Never tick on a red suite. Never merge to `main` (hard gate 1).

## Preflight
- [ ] P1–P8 in the plan all true; branch `redesign/pinterest-grid` created; baseline `scripts\test-all.ps1` "All green." recorded in the first commit message.

## Phase 1 — Foundations (frontend)
- [x] T1.1 masonry dependency + `LbmMasonry`
- [x] T1.2 `NaturalPhoto`
- [x] T1.3 `CartPill` + bounce + toast + guest gate
- [x] T1.4 `LbmText.headline/pinTitle/pinMeta`
- [x] T1.5 chips restyled; `FilterChips`
- [x] T1.6 `LbmToast` (built ahead of T1.3, which needs it)
- [x] T1.7 `FeedItem` union + all pin widgets
- [x] Phase 1 verify green · commit `redesign(1): …` · push
      Verify passes every check except its welcome gate, which diffs against
      `main` and so flags the splash.mp4 commits that were on `staging`
      before this work. Checked by hand against 5603a3e: welcome untouched.

## Phase 2 — Feed (frontend)
- [x] T2.1 `feedItemsProvider` + `assembleFeed` + paging
- [x] T2.2 `feed_screen.dart` on the grid (tabs, filters, hero, pull-to-refresh)
- [x] T2.3 `PostCard` retired from the feed
- [x] T2.4 tab bar with center [+]
- [x] T2.5 guest behaviour
- [x] T2.6 feed goldens regenerated and attached to the report
- [x] Phase 2 verify green · commit · push · **report to Grace with shots**
      Same one known-bad check as Phase 1: the welcome gate diffs against
      `main`. Everything else in the script passes; welcome checked by hand
      against 5603a3e and untouched.

## Phase 3 — Details (frontend)
- [x] T3.1 product detail (gallery, sheet, variants, proof count, facts, reviews block, **Also sold by this seller**)
- [x] T3.2 review detail + cart-post detail (`PostScreen` by kind; listing → product)
- [x] T3.3 maker board
- [x] T3.4 star-first review composer
- [x] Phase 3 verify green · `light-post.png` regenerated · commit · push
      `product_detail_test.dart` did not exist and could not: the product
      page never left its skeleton under a widget test, because
      `productDetailProvider` ends on `watchRating(id).first` and the fixture
      store's `Watchable` handed `Stream.first` a cancellation to await.
      Fixed in `fixture_store.dart`; the test is 11 cases now. The script's
      "Also in carts with this" grep matched a doc comment that explained the
      removal, so the comment was reworded. Welcome gate as Phase 1.

## Phase 4 — Tags as collections (frontend)
- [x] T4.1 `tag/:key` route, `goToTag`, all hashtag taps rerouted; results default query removed
- [x] T4.2 `TagScreen` with Follow / Notify
- [x] T4.3 repository + fixture for tag follows; `followedTagsProvider`
- [x] T4.4 onboarding "pick 3 tags"
- [x] T4.5 search screen as browse hub; collection screen follow when mapped
- [x] Phase 4 verify green · commit · push
      Clean, including "no hashtag goes to results". Welcome gate as Phase 1.

## Phase 5 — Community, You, Seller, polish (frontend)
- [x] T5.1 `Composer` quick replies + product cards in messages; product "Ask" prefill
- [x] T5.2 forums grid, forum threads as pins, chat header + pinned announcement
- [x] T5.3 You hub, quiet (no points/level/streak/shipping/orders)
- [x] T5.4 notifications, settings (tag switch), messages, edit profile restyle
- [x] T5.5 seller "Your shop"; Under review → Shipturtle; no Orders screen
- [x] T5.6 onboarding restyle (welcome untouched), tour copy, cart, checkout copy, admin preview
- [x] T5.7 goldens + dead code sweep; analyze reports zero
- [x] Phase 5 verify green · commit · push · **report to Grace with all shots · STOP until she replies**
      `composer_quick_replies_test.dart` did not exist either; writing it
      found the DM and chatroom threads opening on the oldest message, with
      a message you had just sent below the fold. Both lists are `reverse:
      true` now and the chatroom's pull-for-Forums gesture flipped sign with
      them. 736 green, analyze clean, goldens regenerated. Welcome gate as
      Phase 1. **Stopped here: Phase 6 is backend and needs Grace's go.**

## Phase 6 — Backend: tag follow → notify (backend) — needs Grace's go (hard gate 2)
- [ ] T6.1 rules + rules tests
- [ ] T6.2 `onTagFollowWritten` + test
- [ ] T6.3 `tagPost` push type, prefs, fan-out in `onPostWritten` + tests
- [ ] T6.4 client `NotificationKind.tagPost`
- [ ] T6.5 hot-threads index (or N/A with reason)
- [ ] T6.6 deploy to **dev** · `scripts\deploy-check-redesign.ps1` PASS · commit · push

## Phase 7 — Integration pairs
- [ ] all five pair checks in plan §7 green (they live inside the phase tests; run `verify-redesign.ps1 -Phase all`)

## Phase 8 — reserved for findings from the adversarial review and Grace's manual pass
- [ ] (add tasks here as symptom → cause → file:line → fix, never as "tweak X")
