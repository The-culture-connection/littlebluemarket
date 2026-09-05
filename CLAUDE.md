# Little Blue Market — working agreement

A Flutter marketplace app being taken from **high-fidelity prototype** to **functional product**.
The backend is hybrid: **Firebase** owns identity and social data, **Shopify + ShipTurtle** own money
and fulfilment, behind an interface designed so Shopify can be removed later without touching a screen.

Read first, in this order:
1. **`Planning/checkpoints.md` — the order of work.** Stages 0–9, each cut into checkpoints Grace verifies by tapping through the app. Find the first unticked box; do only that. **`Planning/manual-test.md`** is the tap-through of every user journey (J1–J11) against the live dev backend; when Grace reports "J5 step 2", that is where it lives.
2. `README.md` — the design system, the welcome handoff, the accent contrast split, the glyph rules. Still accurate; do not contradict it.
3. `Planning/i-have-a-prototype-vivid-dongarra.md` — the approved implementation plan for PRs 1–15 (all done). Source of truth for the architecture.
4. `Planning/identity-and-catalog.md` — how buyers and sellers actually authenticate, verified against the live systems, and how products map to sellers. Read before touching `linking.ts`, `vendors.ts` or `catalog.ts`.
5. `Planning/backend-architecture.md` — which box owns what, the seller journeys traced end to end, the app→Shopify product write path, and the seller-authorization guard.
6. `Planning/implementation-phases.md` — the engineering depth behind Stages 4–8 of `checkpoints.md`.
7. `Planning/user-journeys.md` — buyer and unified journeys. **Two product decisions live here and contradict the current code: the like is gone (adding to cart is the affinity signal) and upvoting is gone.** They land in Stage 7.

---

## Start of every session

1. `scripts\doctor.ps1` — one line per check with the exact fix. Do not start feature work with a FAIL you have not fixed or reported.
2. `scripts\test-all.ps1` — analyze (zero issues), flutter test, tsc, npm test. All green.
3. Open `Planning/checkpoints.md`, find the first unticked checkpoint, do only that one. Do not skip ahead.
4. Say which backend you are about to run (`run-live.ps1` is Grace's default; `run-fixtures.ps1` needs no backend; `run-emulators.ps1` is local).
5. Finishing a checkpoint = tests green, app runs, commit, push, tick the box. Never commit red.

**How Grace reports a failure:** the app's "Copy for Claude" block, the doctor output, or the last 30 lines of the terminal, pasted verbatim, plus which checkpoint step and what was tapped. No paraphrasing, no screenshots of text.

**How Claude reports a failure:** name the file and line, quote the exact message, give one command to run, stop. Do not fix three other things on the way.

**Dev-only surfaces** (error strip, backend badge, Diagnostics screen) are off in release builds and off under `bool.fromEnvironment('FLUTTER_TEST')`, always.

## Commands

```bash
scripts\doctor.ps1              # preflight: tools, project, params, secrets, Shopify, functions, webhooks, auth providers
scripts\test-all.ps1            # flutter analyze + flutter test + tsc + npm test, stops at the first failure
scripts\run-live.ps1            # Android emulator against the REAL dev project + dev Shopify shop (Grace's default)
scripts\run-fixtures.ps1        # no backend, demo data (-Chrome to run in the browser)
scripts\run-emulators.ps1       # local Firebase emulators, seeded
scripts\deploy-dev.ps1          # test-all -> deploy functions+rules+indexes+storage -> register webhooks -> doctor

# In Git Bash (MINGW64) backslashes do not work: use the .sh twins, e.g. scripts/doctor.sh, scripts/run-live.sh

flutter analyze                 # must be clean — zero issues, not "only warnings"
flutter test                    # 401 Flutter tests; 100 more in functions/, 41 rules tests
flutter test test/visual_check.dart --update-goldens   # regenerate test/shots/ after intentional UI changes
```

Never run bare `firebase deploy --only functions`: it does not compile TypeScript. `npm run deploy:dev` (or `deploy-dev.ps1`) builds first and also ships rules, indexes and Storage rules, so "are the real rules deployed" is answered by construction.

The parent folder holds `.env.dev`, `.env.littlebluemarket` and `shopify_recovery_codes.txt` (outside git, on purpose) and `_archive/` (an accidental `firebase init` scaffold moved out of the way on 2026-09-04; see its README). Nothing else up there is real.

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
- **Selling is a grant, never a client write.** `sellers/{uid}`, `vendorNames/` and `vendorClaims/`
  are `allow write: if false`; `isSeller` is a Firebase **custom claim**, not a document field. Any
  new seller-only capability checks `request.auth.token.seller`, plus `sellers/{uid}` and
  `vendorNames/` server-side. Never add a seller field to `users/{uid}` and never re-introduce
  `becomeSeller()` — see `Planning/backend-architecture.md` §8 for the escalation it enabled.
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
- [x] **PR 5** — `LbmAsync` + skeletons.
- [x] **PR 6** — Real session (sealed `Session`, anonymous-auth guests, `themeMode` split out).
- [x] **PR 7** — Market screens async.
- [x] **PR 8** — Profile / seller feed / edit profile (seller vs buyer split) / shipping.
- [x] **PR 9** — Community: chatroom, forums, threads.
- [x] **PR 10** — Messaging + commerce cart. Un-skip the fixture-import guard.
- [x] **PR 11** — Firebase bootstrap.
- [x] **PR 12** — Live social/profile/messaging + emulator seed script.
- [x] **PR 13** — Shopify proxy, catalog mirror, order attribution. **← Milestone 1 ends here.**
- [x] **PR 14** — ShipTurtle fulfilment.
- [x] **PR 15** — Cleanup, rules hardening, offline persistence.

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

- **Shipturtle's API Integration add-on and a merchant-level token.** Paid add-on; without it
  vendor linking stays manual via `vendorMappings`, and payouts, approval status and the fulfilment
  push in `fulfillment.ts` cannot be wired. Everything else routes around it — see
  `Planning/backend-architecture.md` §10.
- **Who issues vendor claim codes, and how.** The mechanism is specified in
  `Planning/backend-architecture.md` §8; the operational side (bulk-issue to all 79 vendors, or on
  request) is not. Needed before PR 16 ships.

**Resolved** — the Shipturtle vendor → app-user mapping rule is no longer open. A vendor is a
Shipturtle *user* whose `company_id` is the vendor id; the rule is verified email ↔ that user's
email → `shipturtleVendorId = company_id`. That is strategy 4 in `vendors.ts`. See
`Planning/identity-and-catalog.md` §2.

---

## Functions

```bash
cd functions
npm install
npm test              # HMAC, money parsing, order normalisation, ShipTurtle
npm run test:rules    # security rules, needs the Firestore emulator
npx tsc --noEmit      # typecheck
npm run seed          # fixture content into a running emulator
npm run doctor        # preflight against the dev project (never prints a secret)
npm run verify:security                 # S1-S8 + money rules, under the emulator
npm run touch-products [-- --vendor X]  # re-mirror every product through the real webhook path
npm run replay-order -- --order 1002 [--deliver|--ship]   # replay a paid order, or mark it shipped/delivered
npm run peek -- --reviews | --doc <path> | --collection <path>   # read public docs as the phone would
npm run inspect:product -- --id <id>    # one product's store record (vendor, status, channels, stock)
npm run shipturtle:vendors              # Shipturtle users + the vendor string each company's products carry
npm run move-stock -- --vendor cc --to <locationId>   # move a vendor's stock to the online-fulfilment location
```

The three places a bug there costs real money, and so the three with the most
tests: webhook signature verification, order normalisation and the per-seller
revenue split, and the Admin token broker.
