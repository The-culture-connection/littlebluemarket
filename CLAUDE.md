# Little Blue Market — working agreement

A Flutter marketplace app being taken from **high-fidelity prototype** to **functional product**.
The backend is hybrid: **Firebase** owns identity and social data, **Shopify + ShipTurtle** own money
and fulfilment, behind an interface designed so Shopify can be removed later without touching a screen.

Read first, in this order:
1. `README.md` — the design system, the welcome handoff, the accent contrast split, the glyph rules. Still accurate; do not contradict it.
2. `Planning/i-have-a-prototype-vivid-dongarra.md` — the approved implementation plan. **It is the source of truth for scope, sequence, and architecture.** If this file and the plan disagree, the plan wins.

---

## Commands

```bash
flutter pub get
flutter analyze                 # must be clean — zero issues, not "only warnings"
flutter test                    # 138 tests at baseline; the count only goes up
flutter run                     # fixtures backend (default)
flutter run --dart-define=LBM_BACKEND=live             # once Track B lands
flutter test test/visual_check.dart --update-goldens   # regenerate test/shots/ after intentional UI changes
```

`visual_check.dart` is deliberately not `_test`-suffixed, so `flutter test` skips it. It renders
screenshots for human eyeballing, not assertions.

## Definition of done — every task, no exceptions

1. `flutter analyze` clean.
2. `flutter test` green. If a test fails, **fix the cause, never the assertion** — unless the
   assertion encodes behaviour the plan explicitly changes, in which case update it and say so.
3. The app still runs.
4. Commit, and push to `main` at the end of each PR/phase (the user asked for this explicitly).

Never commit with failing tests or a dirty analyze. Never `--no-verify`.

Commit messages end with:

```
Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

---

## Non-negotiable architecture rules

These exist so Shopify stays removable. Breaking one is a design regression even if it compiles.

- **No Shopify type ever reaches a widget.** Screens and widgets speak only in app models
  (`lib/models/`). Shopify JSON is converted in `lib/data/shopify/shopify_mappers.dart` and nowhere else.
- **The Flutter app never holds a Shopify credential and never calls Shopify directly.**
  All commerce goes through Cloud Functions via `cloud_functions` `httpsCallable` — not `http`, not `dio`.
- **Screens never import `data/fixtures`.** They depend on repository interfaces resolved through
  Riverpod providers. `test/no_fixture_imports_test.dart` enforces this once PR 10 lands.
- **`lib/data/repositories/` is pure Dart.** No `firebase_*`, no Shopify, no Flutter imports there.
- **Counters use `FieldValue.increment`, never read-modify-write** — likes, upvotes, revenue, member counts.
- **Money is `int` cents everywhere.** Never a double, never a pre-formatted string in a model.
  Formatting lives in `lib/models/formatting.dart` (`Fmt`) and extension getters.

## Design system rules

- Colours come from `context.c` (`LbmColors` in `theme/tokens.dart`). **Never a raw `Color(0x…)`
  in a screen or widget.**
- Reuse the vocabulary in `widgets/primitives.dart` (`LbmCard`, `PillButton`, `LbmChip`, `Avatar`,
  `Stars`, `ListRow`, `RowStack`, `SectionHead`, `LbmField`, `SegmentedTabs`) and
  `widgets/screen.dart` (`LbmScreen`, `LbmAppBar`, `Composer`). Do not hand-roll a new card or button.
- **The accent contrast split is structural.** `accentDeep` exists only to carry `accentInk` text.
  White on `accent` is ~3:1 and fails. `test/design_tokens_test.dart` will catch you.
- Fraunces and Nunito do not carry `★ ◆ → ⋯`. Draw them as icons; never typeset them.
- This design came from a fixed 390-wide mockup. Overflow throws in tests. Any new row of text must
  survive `screens_smoke_test.dart` (23 routes × 2 themes) and `text_scaling_test.dart` (2.0 scale).
- Match the surrounding code: doc comments that explain *why* rather than *what*, the existing
  spacing idiom, `const` wherever possible.

---

## Sequence — keep this checklist current

Track A refactors the client on fixtures; the app stays runnable and demoable at every step, with
zero Firebase dependency until PR 11. Do not start Track B early.

- [x] **PR 1** — UI removals: drop the share/arrow icon, Save → Add to cart, unify `_PostActions`
      and `_PostActionRow` into one public `PostActionBar`, remove points entirely, remove the (i)
      icon, remove Hot/New/Top from `forum_screen.dart`.
- [x] **PR 2** — Typed models + `lib/models/formatting.dart`. Display strings become real types.
- [x] **PR 3** — New models: sealed `Post`, `Cart`/`CartLine`, `Order`, `Comment`, `Message`,
      `Address`, `SearchFilters`/`SearchResults`.
- [x] **PR 4** — Repository seam + mutable `FixtureStore` + `Backend` flag.
- [ ] **PR 5** — `LbmAsync` + skeletons.
- [ ] **PR 6** — Real session (sealed `Session`, anonymous-auth guests, `themeMode` split out).
- [ ] **PR 7** — Market screens async.
- [ ] **PR 8** — Profile / seller feed / edit profile (seller vs buyer split) / shipping.
- [ ] **PR 9** — Community: chatroom, forums, threads.
- [ ] **PR 10** — Messaging + commerce cart. Un-skip the fixture-import guard.
- [ ] **PR 11** — Firebase bootstrap.
- [ ] **PR 12** — Live social/profile/messaging + emulator seed script.
- [ ] **PR 13** — Shopify proxy, catalog mirror, order attribution. **← Milestone 1 ends here.**
- [ ] **PR 14** — ShipTurtle fulfilment.
- [ ] **PR 15** — Cleanup, rules hardening, offline persistence.

**Do not skip ahead.** Each PR assumes the previous one's seam exists.

---

## Traps in this codebase — verified, deliberate, load-bearing until their PR

The prototype fakes data in ways that look like features. Do not "tidy" these early, and do not
leave them once their PR arrives.

| Where | What it fakes | Fix in |
|---|---|---|
| `fixtures.dart:912` | `Fx.search` falls back to `['p1','p4']` — **search can never return empty**, so no screen has an empty state | PR 4 |
| `seller_feed_screen.dart:40,43` | Falls back to `['p1','p4','p5']`, so **buyer `dee` displays Kali's products as her own**; then pads the grid by duplicating the list | PR 8 |
| `fixtures.dart:134,247,579` | `Fx.person`/`product`/`spec` silently return `maya`/`p1` on a miss — **a bad deep link shows someone else's profile.** A privacy bug the moment profiles are real | PR 4 |
| `seller_feed_screen.dart:93`, `profile_screen.dart:105` | "Review" badges chosen by **grid position**, not data | PR 8 |
| `sheets.dart` buy sheet | Total ignores the selected variant — **ships wrong prices** with real variant data | PR 10 |
| `dm_screen.dart:24,144` | One global DM thread for every contact; `Fx.product('p1')` pinned as "the order" in every conversation | PR 10 |
| `thread_screen.dart:137` | `Fx.comments` is one global list rendered under **every** thread | PR 9 |
| `feed_screen.dart:59` | `itemCount: 6` hardcoded against an 8-entry `Fx.tags` — `RangeError` with real data | PR 7 |

Two more, cheap and worth doing when you are next in the file: `session.dart` carries `themeMode`,
so toggling the theme re-runs the router redirect; and `_SessionListenable` does not dedupe, so
every counter increment on `users/{uid}` will re-run it. Both belong to PR 6.

## Known constraint: Shopify checkout on Flutter

Shopify's Checkout Sheet Kit ships for Swift and Kotlin, **not Flutter**. Checkout needs either a
platform channel around the native kit or an in-app web view on the cart's `checkoutUrl`. Decide
before PR 13 — it affects the plugin list. Either way, **`orders/paid` is the only source of truth
that a purchase happened**; the app cannot reliably observe checkout completing, so the
post-checkout screen says "we'll confirm shortly" rather than asserting success.

---

## Secrets — hard rules

- **Never write a token value into a file in this repo, a commit, a log, or a chat message.**
  Secrets are set with `firebase functions:secrets:set NAME` and referenced by name only.
- The Admin token comes from Shopify's **client-credentials grant and expires in ~24h**. There is
  no stored admin token. `functions/src/shopify/token.ts` is the only place that mints one.
- `.env` and `shopify_recovery_codes.txt` live in the **parent** directory, outside this repo.
  Keep it that way.
- Before the first `functions/` commit, `.gitignore` must cover: `functions/.env*`,
  `functions/lib/`, `functions/node_modules/`, `*-service-account*.json`, `firebase-debug.log`, `.firebase/`.
- Firebase client config (`firebase_options.dart`, `google-services.json`,
  `GoogleService-Info.plist`) is **public by design** and safe to commit. Security lives in
  Firestore rules and App Check.
- **Never create a Firebase service account key** for Cloud Functions — they use Application
  Default Credentials.

## Blocked on the user — do not invent answers

- ShipTurtle API credentials.
- **The ShipTurtle vendor → app-user mapping rule.** Launch blocker: without it no existing seller
  can log in as a seller, and revenue cannot be attributed. If you reach PR 13 and this is still
  open, stop and ask.
