# Phase 9 — Chip in + round-up, Following-first feed, comments on profiles

*For Claude Code, 2026-09-29. Visual spec: `Planning/donations-mockup.html` ("Chip in page", "Checkout round-up", "Feed nudge", "You tab quiet row" moments). Rules in `CLAUDE.md` (incl. the redesign section) still apply. **This phase runs in its own worktree in parallel with another session — see §0.***

## 0. Parallel-session rules (read first)

Another Claude Code session is working in the main checkout on `redesign/pinterest-grid` right now. Do not touch that working tree.

1. From `little_blue_market/`, create your own worktree from the **last commit** of that branch: `git fetch && git worktree add ..\lbm-phase9 -b redesign/phase9-donations origin/redesign/pinterest-grid` (if the branch is local-only, use `redesign/pinterest-grid` without `origin/`). Work only inside `..\lbm-phase9`.
2. Never `git pull`, rebase, or merge during the phase. Never push to `redesign/pinterest-grid` or `main`. Push only `redesign/phase9-donations`. Grace merges later.
3. Keep changes **additive**. Prefer new files. The other session may be editing `feed_screen.dart`, `feed_items.dart`, `profile_screen.dart`, `app_shell.dart`, `lbm_toast.dart` and the pin widgets. Where you must touch those, make the smallest insertion possible (a new provider read, a new tab entry, a new `switch` case) and put the logic in a new file so the merge is one-line.
4. No deploys from this worktree. No `firebase deploy`, no emulator-backed rules tests unless the other session confirms it isn't running them (ports collide). `flutter analyze` and `flutter test` are yours.
5. When done, run `git rebase redesign/pinterest-grid` **once, at the end**, resolve conflicts in favour of keeping both changes, re-run `scripts\verify-redesign.ps1 -Phase 5`, push, and report the conflict list to Grace.

## 1. Grace's decisions

- **Chip in page** with the transparency block (last month's bill as tiles + progress bar, "N members covered $X of $Y", one-time amounts, monthly membership) — build it.
- **Checkout round-up** — build it, off by default, shown as its own line item, money goes to Little Blue Market (see §3 for the mechanism).
- **In the feed, frequent but not annoying** — the sage note-pin with the cadence rules in §4.
- **Store-compliant**: no standalone in-app charge. Every ask resolves to the Shopify checkout the app already uses. Copy says "opens the same checkout you buy with" and "not tax-deductible".
- Not in this phase: cause/initiative pages, maker tips, pass-the-hat. Leave hooks (a `kind` field) but no UI.
- **Following before For you** in the feed's top tabs.
- **Comments on profiles**: forum/thread comments (and threads started) appear on a person's profile; the person chooses what their profile shows via toggles in Edit profile.

## 2. Hard gates

- Shopify: creating the donation products (§3) is done by Grace in Shopify admin, not by code. Stop and ask if the product handles are not in config.
- Shipturtle: a donation line must never be routed to a vendor for fulfilment. Verify how Shipturtle treats a line whose vendor is the store itself **before** enabling round-up in prod; stop and report what you find.
- No change to `cart.ts` beyond adding the donation line-item helper described in C1. No change to money math elsewhere.
- Rules change (C3 only) — write it, test it on the emulator only when the other session is idle, do not deploy.

## 3. Where the money goes (backend design, decided)

Two hidden Shopify products, vendor = **Little Blue Market**, no shipping required, not in any collection:
- `lbm-chip-in` with variants $2 / $5 / $10 / $20 and a "Monthly · $3" variant (Shopify subscriptions are out of scope; monthly is a plain $3 line until a subscriptions app exists — say so in the UI as "$3 today; monthly coming").
- `lbm-round-up` with one variant at **$0.01**; the app adds it with `quantity = cents to the next dollar` (1–99). One line, one price, Shopify does the math. Handles live in `config.ts` (`DONATION_CHIP_IN_HANDLE`, `DONATION_ROUND_UP_HANDLE`) and are exposed by `appConfig` so the app can hide the features when unset.

Money flow: both are ordinary order lines paid through the same checkout, settled to the store's Shopify account — which is Little Blue Market's. Because vendor = the store, Shipturtle's vendor split leaves them with the store (verify: hard gate). The order webhook (`orders.ts`) recognises the two handles and (a) excludes them from vendor `grossSalesCents`, (b) increments `funding/{yyyy-mm}.raisedCents` and `.donors` (once per uid per month), (c) sets `users/{uid}.chippedInAt`. Nothing else in the money path changes.

## 4. Feed cadence for the nudge ("frequent but not annoying")

Pure function `donationNudgeSlot(ctx) → int | null` in `lib/state/donation_nudge.dart`, unit-tested:
- Never in the first screen: earliest position 7, latest 10 (after the first ad-free scroll).
- At most **one per feed session** (a session = app foreground; stored in memory, not disk).
- Never on a screen that also has an announcement hero (the hero wins); never adjacent to another nudge.
- Copy rotates through 4 lines (in `LbmCopy.donationNudges`) keyed by day-of-year, all using the live number from `funding/{month}` (`"212 people chipped in this month"`), never a made-up one; if the doc is missing, use the line without a number.
- Dismiss (✕) → hidden **7 days**; gift this month (`chippedInAt` in current month) → hidden **30 days** and the You-tab row shows the thank-you instead; dismissed 3 times in 90 days → hidden 90 days.
- Guests: never (they can't check out).
- Result: a regular user sees it roughly every other day, in the middle of the feed, and it disappears the moment they give.

---

## 5. Tasks — frontend first, backend last

### Part A — Chip in + round-up (frontend)

**A1 `ChipInScreen`** — new `lib/screens/you/chip_in_screen.dart`, route `/you/chip-in` (member-only), `goToChipIn()` in `nav.dart`. Layout = mockup "Chip in page": header "Chip in · Little Blue Market is member-run"; **Last month's bill** card: three `skyWash` tiles (hosting & push / directory sync / town halls — amounts from `funding/{lastMonth}.costs` map; if absent show the tiles with "—" and a `// no data` comment, never invented numbers), sage progress bar `raisedCents / budgetCents`, line "**N members** covered **$X of $Y**. No ads, no investors."; **One-time** card: $2/$5/$10/$20 chips (ink when selected), sage "Chip in $N" button → `commerceRepository.buyNow(productId: chipIn, variantId: <amount variant>)` → existing `showCheckoutHandoff`; small copy "Opens the same in-app checkout you buy with. Not tax-deductible."; **Monthly member** card ($3 variant, copy per §3); **Or, at checkout** card explaining the round-up. After a completed checkout that contained a donation line (detected the same way `checkoutPendingProvider` detects an order), `LbmToast('Thank you 💙', '$N to Little Blue Market')` + confetti (`ConfettiBurst` widget, 18 particles, 1.1 s, colours from tokens).
- Done when: on fixtures the page renders with fixture funding data; tapping $5 → Chip in opens the checkout handoff with the chip-in variant.
- Test: `test/chip_in_test.dart` — bill tiles read from a fixture `funding` doc; amount chip selection changes the button label; Chip in calls `buyNow` with the $5 variant; missing funding doc → tiles show "—" and no crash. *Proves the transparency block is data-driven and the purchase path is the store one.*

**A2 Checkout round-up + line item** — `lib/screens/market/cart_screen.dart` + `sheets.dart` (`showBuySheet`/checkout sheet): a "Round up for Little Blue Market" card with a sage toggle (**off by default**, `Switch`-styled per mockup), subtitle showing the computed cents ("$0.60 keeps the app member-run") when on; a "Round-up 🌱 $0.60" line in the totals; `Total` updates. On Pay: pass `roundUpCents` to `commerceRepository.beginCheckout(...)` (new optional param; fixture mirror) which adds the `lbm-round-up` line with `quantity = cents` (C1). If `appConfig.donationRoundUpHandle` is empty, the card is hidden entirely.
- Done when: toggling shows the line and changes the total; the checkout handoff URL's cart contains the round-up line with the right quantity (fixture commerce repo records it).
- Test: `test/round_up_test.dart` — subtotal $63.40 → toggle → line "$0.60", total $64.00; $63.00 → toggle → line "$1.00" (round to the *next* dollar, never $0); off by default; `beginCheckout` called with `roundUpCents: 60`; hidden when handle unset. *Proves the round-up math and that it is opt-in.*

**A3 Feed nudge + You row** — new `lib/widgets/pins/donation_nudge_pin.dart` (sage `note` pin: 🌱, Fraunces title, one-line body with the live number, "Chip in →" sage pill, ✕ top-right) and `lib/state/donation_nudge.dart` (§4 logic + `fundingProvider`). Insert into `feed_items.dart` as a new `NudgeKind.chipIn` handled by `assembleFeed` via the slot function (one `case` line in the other session's file; logic stays in yours). You tab: one quiet row under the stats (mockup "You tab quiet row"): "Chip in to Little Blue Market · From $2 →", becomes "You chipped in this month — thank you · See the bill →" when `chippedInAt` is this month; a 🌱 "Chipped in" chip next to the profile tags when `chippedInAt` is within 12 months.
- Done when: fixtures with a regular user show the nudge once around position 7–10, ✕ hides it, and after a fixture "gift" the You row flips to the thank-you.
- Test: `test/donation_nudge_test.dart` — slot in [7,10]; null for guests; null when hero present; null within 7 days of dismiss; null within 30 days of a gift; copy contains the fixture number; second call in the same session → null. `test/you_hub_test.dart` add: row copy flips with `chippedInAt`. *Proves "frequent but not annoying" as rules, not vibes.*

### Part B — Following first, comments on profiles (frontend)

**B1 Following before For you** — `feed_screen.dart` top tabs order becomes **Following · For you · Near me** (one array change; the tab widget is the other session's — change only the order and default). Default tab: `Following` when the user follows ≥ 1 person **or** ≥ 1 tag (`followingProvider` / `followedTagsProvider`), else `For you`. Following's empty state: "Nothing yet — follow a maker or a #tag and it lands here" with 4 trending-tag chips that follow on tap. Remember the last tab per session.
- Test: `feed_screen_test.dart` add: tab labels in order; new user with no follows lands on For you; user following `#handmade` lands on Following and sees a post tagged `#handmade`. *Proves Grace's ordering and that Following isn't an empty landing.*

**B2 Comments and threads on the profile** — new `lib/screens/you/profile_activity.dart` with two tabs' content: **Threads** (threads where `authorId == uid`, as `ThreadPin`s) and **Comments** (collection-group `comments` where `authorId == uid` order by `createdAt desc`, limit 30; each row: the comment text, "in {thread title}" or "on {post title}" resolved via `threadProvider`/`postProvider`, age; tap → the thread or post). New repository methods `SocialRepository.threadsBy(uid)`, `commentsBy(uid)` + Firestore + fixture. Profile tabs become the *enabled* subset of: Bought · Reviews · Posts · Carts · Threads · Comments (see B3); order fixed as listed. Viewing someone else's profile shows only the tabs they enabled; your own profile shows all enabled ones plus a small "Edit what shows" link. Index: collection-group `comments` (`authorId asc, createdAt desc`) added to `firestore.indexes.json` (file only; deploy is C).
- Test: `test/profile_activity_test.dart` — Comments tab lists the fixture user's thread comment with "in {thread}" and taps to `/community/thread/<id>`; Threads tab lists their thread. *Proves the profile shows community activity.*

**B3 Edit profile toggles** — `edit_profile_screen.dart`: a "What shows on your profile" card with six switches (Bought, Reviews, Posts, Carts, Threads, Comments; defaults: all on except Bought for other viewers — Bought defaults **on** since it exists today, keep it). Stored as `users/{uid}.profileSections: {bought:bool, reviews:bool, posts:bool, carts:bool, threads:bool, comments:bool}` via `ProfileEdit` (+ mapper, fixture). `Person.profileSections` read by `profile_screen.dart` and by `seller_feed_screen.dart` (the public view).
- Test: `profile_activity_test.dart` add: switch Comments off → own profile keeps the tab with an "(hidden from others)" hint; another viewer's profile of that user has no Comments tab. *Proves the toggle governs the public view.*

### Part C — Backend (do not deploy from this worktree)

**C1 Donation lines** — `functions/src/cart.ts` `commerceBeginCheckout`: accept `roundUpCents?: number` (1–99, validated) and add the `lbm-round-up` variant with `quantity = roundUpCents`; `commerceBuyNow` already takes any variant, so Chip in needs no change. `config.ts`: the two handles + `appConfig` exposure. Unit test in `functions/test/cart.test.ts`: `roundUpCents: 60` → line `{variantId: roundUp, quantity: 60}`; `0`/`100`/negative → rejected.

**C2 Order webhook** — `functions/src/orders.ts`: on paid order, lines whose product handle ∈ {chip-in, round-up} are (a) excluded from vendor `grossSalesCents`, (b) summed into `funding/{yyyy-mm}.raisedCents` (+ `donors` set-once per uid via `funding/{m}/donors/{uid}`), (c) `users/{uid}.chippedInAt = now`. Test: `orders.test.ts` — an order with a $25 jam + $0.60 round-up → vendor gets 2500, funding gets 60, donor recorded once across two orders.

**C3 Rules + index** — `funding/{m}` read by members, write server-only; `funding/{m}/donors` server-only; `users/{uid}.profileSections` writable by self (add to the existing self-write allow-list); `users/{uid}.chippedInAt` server-only. Collection-group `comments` index from B2. Rules tests for each. **File changes only; deploy happens after merge, by the main session.**

---

## 6. Manual checklist (Grace) — frontend first

| # | Side | Do | Expect | Wrong if |
|---|---|---|---|---|
| 1 | FE | Open the feed as a member who follows a tag | tabs read Following · For you · Near me, and you land on Following | For you first; empty Following |
| 2 | FE | New account, no follows | lands on For you; Following shows the "follow a maker or a #tag" empty state with chips | blank screen |
| 3 | FE | Scroll the feed | the sage 🌱 nudge appears once, around the 7th–10th item, never on the first screen | first screen; twice in one session |
| 4 | FE | Tap ✕ on it, reopen the app tomorrow | gone today, back within a week | back immediately |
| 5 | FE | Cart two things → checkout | "Round up for Little Blue Market" card, toggle off; turn it on → a "Round-up 🌱 $0.xx" line and the total rounds to the next dollar | on by default; total wrong |
| 6 | FE | You → Chip in | last month's bill tiles + bar, amounts, Chip in opens the same checkout; copy says not tax-deductible | a card form inside the app |
| 7 | FE | After a chip-in order completes | thank-you toast + confetti; You row says "You chipped in this month"; 🌱 chip by your tags; the feed nudge stops | nudge keeps showing |
| 8 | FE | Your profile | Threads and Comments tabs list your forum activity; "in {thread}" taps through | missing; wrong thread |
| 9 | FE | Edit profile → turn Comments off → view your profile as someone else | no Comments tab for them; you still see it with "(hidden from others)" | hidden for you too; still visible to them |
| 10 | BE | (after merge + deploy) place a real $1 test order with round-up on dev | vendor total excludes the round-up; `funding/{month}` raised increments; Shipturtle shows no shipment for the round-up line | round-up routed to a vendor |

---

## Addendum (2026-09-29, evening) — decisions since kickoff

1. **Monthly membership will be an in-app purchase (Phase 10), not a Shopify variant.** A $3/month member with digital perks (🌱 badge, first look at drops) is a digital subscription, so Apple/Google billing is required and correct. Phase 9: **hide the Monthly card on the Chip in page entirely** (no "coming soon"), keep the four one-time amounts. The `Monthly · $3` variant may exist on the Shopify product; ignore it. Transparency tiles will later sum two sources (Shopify donation lines + store subscription payouts); leave `funding/{month}.raisedCents` as the Shopify-side number with a `sources` map so a second source can be added without a migration.
2. **Gate 1 handling confirmed**: hidden-when-unset was the design; carry on. Products are being created in the **dev store** (`little_blue_market_devtestingshop`) first: `lbm-chip-in` ($2/$5/$10/$20, plus an unused Monthly variant) and `lbm-round-up` ($0.01), vendor "Little Blue Market", not a physical product, tax off.
3. **Gate 2 workaround**: verify from the Shopify side (requires_shipping = false; test order on dev shows "No shipping required" and no Shipturtle activity on the line). Round-up stays defaulted off until that's observed. Treat `requires_shipping == false` + handle match as the donation-line signal in the webhook.
4. **Sales channels**: do **not** unpublish the donation products from any channel until it is confirmed which channel the app's checkout uses (`commerceBuyNow` / `commerceBeginCheckout` — Admin API draft/checkout vs Storefront/Headless). If it is the Headless channel, the products must stay published there. Report which it is.
