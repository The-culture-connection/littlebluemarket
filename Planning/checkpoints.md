# Little Blue Market — the checkpoint plan (the order of work)

*Written for Grace. Plain language first, engineering detail second. Every checkpoint ends with something you can see on your phone. This file is the order of work; tick a box only when its "Pass looks like" line has actually been seen. Engineering depth for Phases 4–8 lives in `implementation-phases.md`.*

Path shorthand: `REPO` = `…\Little Blue Cart\little_blue_market` (the git repo). `PARENT` = `…\Little Blue Cart` (not git).

---

## Progress at a glance (updated 2026-09-05)

| Item | Status |
|---|---|
| Stage 0 — Unblock the repo, preflight doctor, launchers, scopes, webhooks, catalog mirror | ✅ Done, passed by Grace |
| Stage 1 — Loud failures: dev error strip, Copy for Claude, Diagnostics screen, backend health check, security pass | ✅ Done, passed by Grace |
| CP-A1 — Sign up as a buyer, email confirmed without a restart | ✅ Done, passed by Grace |
| CP-A2 — Existing Shopify customer signs in and sees past orders | ✅ Done, passed by Grace |
| CP-A3 — Seller claim code → seller mode without a restart, Products tab | ✅ Done, passed by Grace |
| CP-A4 — A seller's existing products appear on their profile | 🟡 Built and deployed, waiting for your test |
| CP-A5 — Shipturtle roster probe, automatic vendor detection by email | 🟡 Built and deployed (roster found at /api/v1/users), waiting for your test |
| Stage 3 — Buying: add to cart, checkout in-app, order lands | ⬜ Not started |
| Stage 4 — The real catalog: admin claim, collections, backfill, browse an initiative | ⬜ Not started |
| Stage 5 — A seller adds a product | ⬜ Not started |
| Stage 6 — Approval, edits, "Total sales" | ⬜ Not started |
| Stage 7 — Cart replaces like, cart posts, reviews | ⬜ Not started |
| Stage 8 — Shipturtle: payouts, approval status, fulfilment push | ⬜ Not started |
| Cutover to the real shop | ⬜ Not started |

Extras done along the way: a Sign out row, the app opens on the Market when you are already signed in, search matches any word of a title, product pages open for shops that have not joined yet, the catalog's spec subdocument rule, the first-save profile fix, Git Bash launchers.

---

## 1. Context — what is actually going on

**The good news: this is not a prototype anymore.** `REPO` is a real app with a real backend:

- All 15 original PRs (Track A and Track B) are committed and pushed.
- Phases 0 and 1 of the newer plan are committed too (`Phase 0: clear the decks`, `Phase 1: selling is a grant`).
- 311 Flutter tests pass. 39 backend tests pass. (I ran both today.)
- 11 Cloud Functions are deployed to Firebase project `little-blue-610e5`.
- All five secrets (Shopify client secret, Storefront token, webhook secret, Shipturtle key, Shipturtle webhook secret) exist in Secret Manager.
- Already built: email-based buyer linking to Shopify, seller claim codes, custom-claim seller roles, cart, checkout handoff, order attribution, catalog mirror, webhook signature checks.

**The bad news: the app cannot actually be walked through as a user today, and nobody could tell why.** These are the concrete reasons every session hits hurdles. None of them is a Firebase problem.

| # | What is wrong | Effect on you |
|---|---|---|
| 1 | `flutter analyze` fails with 207 issues: a Firebase Data Connect *movie-review sample* leaked into `REPO\lib\dataconnect_generated\` from an accidental `firebase init` in `PARENT`. Nothing imports it. | Every session's "definition of done" is red before it starts. |
| 2 | `REPO\functions\.env.little-blue-610e5` has **empty** `SHOPIFY_STORE_DOMAIN` and `SHOPIFY_CLIENT_ID`. | The deployed functions cannot reach Shopify. Every cart, checkout, or linking call fails. The right values are in `PARENT\.env.dev` (dev store `little-blue-market-devtestingshop.myshopify.com`, which is correct; production is `little-blue-cart-dev.myshopify.com` and must not be used). |
| 3 | The two Phase 1 functions, `sellerClaimVendor` and `sellerRevokeVendor`, were **never deployed** (13 exported, 11 live). | The claim-code screen fails with "not found". |
| 4 | The app **never calls `linkAccounts`**. Deployed, never invoked. | "Existing website customer signs in and sees their orders" cannot work. |
| 5 | After you click the verification email, the app never re-reads the account, so it keeps thinking you are unverified for up to an hour. | Linking and claiming say "confirm your email first" even after you did. |
| 6 | Your own profile screen has no Products tab (only Posted / Bought & received). | "Products tab appears after claiming" has nowhere to appear. |
| 7 | The seller lookup in `vendors.ts` still reads `users.shopifyVendorName`, which Phase 1 moved to `sellers/{uid}`. | A seller's products can never be matched to them. |
| 8 | Two purchase-document id schemes (`order_index` in the backfill, `order_lineId` in the webhook). | Duplicate cells and a wrong purchase count if both paths see one order. |
| 9 | `npm run webhooks:dev` cannot run: it looks for `.env.dev`, which does not exist, and needs a `--url` nobody passes. | Nobody knows whether Shopify webhooks are registered on the dev store. Likely not. |
| 10 | Every backend error becomes "Something went wrong. That is on us." (`lib/widgets/async.dart`). | You cannot see what failed, so you cannot tell Claude what to fix. |
| 11 | `PARENT` holds a second accidental Firebase scaffold (hello-world functions, movie sample, wide-open rules expiring 2026-10-04, a Shopify CLI config with `scopes = ""` from which a stray `shopify app deploy` could wipe the app's scopes). Six planning docs are uncommitted. No preflight check. No Claude Code permission allowlist. | Sessions get confused about which folder is real and stall on prompts. |

Also unverified until the doctor exists: whether Email/Password and Anonymous sign-in are switched on in the Firebase console, whether the deployed Firestore rules are the real ones, and which of the two Shipturtle tokens is the one in Secret Manager.

**Decisions you made today:** test against the real dev Firebase project + dev Shopify test shop (not emulators); cover everything through Phase 8; archive the `PARENT` clutter; Shipturtle is installed on the test shop with a vendor; **keep Flutter + Firebase**.

**Correction carried through:** the seller platform is **Shipturtle**, not ShipHero.

**Tech stack decision (made today): keep Flutter + Firebase.** The hurdles so far are tooling and wiring, not the stack, and every row in the table above would exist on any backend. The one place Firebase is weak for this app is the combined feed query (hashtag + radius + text); the existing plan already routes around it and Typesense/Algolia can be added later behind `SearchRepository` without touching screens. If a move is ever reconsidered, Supabase is the candidate and the repository seam means only `lib/data/firebase/` and `functions/` change; budget weeks, not days.

---

## 2. How the roles work (the part you asked about)

One login for everyone. Roles are decided by the backend from the **verified email**. The phone never talks to Shopify or Shipturtle directly.

```
You type email + password  →  Firebase Auth gives you an account (uid)
You click the verification link  →  the email is now "verified"
The app calls linkAccounts  →  backend asks Shopify:    "is this email a customer?"  yes → past orders copied in (buyer)
                               backend asks Shipturtle: "is this email a vendor?"    yes → vendor id stored (seller candidate)
Seller status is a GRANT:  a claim code today (sellerClaimVendor);
                           automatic email match against Shipturtle's roster once CP-A5's probe proves the API works.
Granted sellers get `seller: true` on their token. Rules and functions check that claim, plus sellers/{uid}
and vendorNames/{name}. A phone cannot fake any of those.
```

Guests get an anonymous account so their cart survives signing up. All of this is built; what is missing is the wiring on the phone, the ability to see failures, and the Shipturtle automatic path.

---

## 3. The rules of the road (so sessions stay autonomous)

These go into `CLAUDE.md` under a new **"Start of every session"** heading.

1. **Run `scripts\doctor.ps1` first.** Every line prints PASS / FAIL / WARN / MANUAL with the exact fix. Do not start feature work with a FAIL you have not fixed or reported.
2. **Then `scripts\test-all.ps1`** (analyze, flutter test, tsc, npm test). Zero issues, all green.
3. **Find the next unchecked checkpoint in `Planning/checkpoints.md`.** Do only that one. Do not skip ahead.
4. **Finish a checkpoint = tests green, app runs, commit, push, tick the box.** Never commit red.
5. **How Grace reports a failure:** tap "Copy for Claude" in the app, or copy the doctor output, or the last 30 lines of the terminal. Paste verbatim, say which checkpoint step and what you tapped. No paraphrasing, no screenshots of text.
6. **How Claude reports a failure:** name the file and line, quote the exact message, give one command, stop. Do not fix three other things on the way.
7. **Secrets never go in files, commits, logs, or chat.** Store domain and client ID are identifiers, not secrets; anything named "secret" or "token" is.
8. **Never run bare `firebase deploy --only functions`.** Use `scripts\deploy-dev.ps1` (it tests, compiles, deploys functions + rules + indexes + storage, registers webhooks, runs doctor).
9. **Dev-only surfaces** are off in release builds and off under `FLUTTER_TEST`, always.

---

## 4. Stages and checkpoints

Each checkpoint: **Goal** · **Claude builds** · **Grace does** · **Pass looks like** · **If it fails**. Boxes get ticked in `Planning/checkpoints.md`.

Test identities (write them in a note outside the repo): `grace-s+buyer1@the-culture-connection.com`, `grace-s+customer1@…`, `grace-s+seller1@…`. Verification mail comes from `noreply@little-blue-610e5.firebaseapp.com` and often lands in Spam.

### Stage 0 — Unblock the repo (one session, no features) — ✅ passed by Grace 2026-09-05

**Goal:** analyze, tests, doctor, and the deployed backend all agree, and the live app shows real dev-store products.

**Claude builds:**

- [x] **0.1 Archive, never delete.** Create `PARENT\_archive\2026-09-04-firebase-init-leak\` with a `README.md` explaining each item. Move there: `PARENT\functions\` (genkit hello-world), `PARENT\dataconnect\`, `PARENT\firestore.rules`, `PARENT\storage.rules`, `PARENT\firestore.indexes.json`, `PARENT\shopify.app.toml`, `PARENT\.shopify\`, `PARENT\firebase-debug.log`, `REPO\lib\dataconnect_generated\`, `REPO\functions\src\dataconnect-admin-generated\`, `REPO\firebasestuff\`. Delete the empty `PARENT\Planning\` and the two 0-byte `REPO\firestore.rules` / `REPO\firestore.indexes.json` (the real ones are in `REPO\firebase\`). Leave `.env.dev`, `.env.littlebluemarket`, `shopify_recovery_codes.txt`, `lbm-prototype\` exactly where they are; note in the README that `.env.littlebluemarket` holds production-store leftovers including a stored admin token and must never be wired in.
- [x] **0.2 Repo edits for the leak.** Remove `@dataconnect/admin-generated` from `functions/package.json`, `npm install` so the lockfile follows. Add `lib/dataconnect_generated/`, `functions/src/dataconnect-admin-generated/`, `dataconnect/`, `.dataconnect/` to `.gitignore`. `seed.mjs:30` default project → `little-blue-610e5`. Add `.gitattributes` with `* text=auto eol=lf` to stop CRLF warnings.
- [x] **0.3 Analyze clean.** Remove the three unused imports (`post_screen.dart:13`, `profile_screen.dart:17`, `sheets.dart:15`); delete the unreachable `num` arm in `mappers.dart:25`; delete the dead `_notWired` in `providers.dart:142`; fix the two `copyWithPrevious` uses in `test/async_widget_test.dart:35,54` by producing the loading-over-data value through a real `FutureProvider` + `container.refresh`, or a per-line ignore with a reason if that proves awkward.
- [x] **0.4 Fill the params and deploy everything.** `functions/.env.little-blue-610e5`: `SHOPIFY_STORE_DOMAIN` and `SHOPIFY_CLIENT_ID` copied from `PARENT\.env.dev` (identifiers, not secrets), `SHOPIFY_API_VERSION=2026-07`, `SHIPTURTLE_BASE_URL=https://api-v2.shipturtle.com` (the host the vendor panel really uses). Deploy `functions,firestore:rules,firestore:indexes,storage --project dev`. This also ships the two missing seller functions and answers "are the real rules deployed" by construction.
- [x] **0.5 Commit** the five planning docs, the `CLAUDE.md` diff, and this plan as `Planning/checkpoints.md`. Update `CLAUDE.md`: reading list points at `checkpoints.md` as the execution order; add §3 above; add the six launchers to Commands.
- [x] **0.6 Launchers** in `REPO\scripts\` (PowerShell, each prints what it will do and ends with "paste the last 30 lines to Claude if this failed"): `doctor.ps1` · `run-live.ps1` (`flutter run -d emulator-5554 --dart-define=LBM_BACKEND=live`, your default) · `run-fixtures.ps1` (`-Chrome` switch for `-d chrome`) · `run-emulators.ps1` (starts the emulator suite in a new window, waits for port 8080, seeds, runs with `LBM_EMULATORS=true`) · `test-all.ps1` (stops at the first failure with a red banner naming it) · `deploy-dev.ps1` (test-all → deploy all four targets → `npm run webhooks:dev` → doctor) · `issue-claim-code.ps1` (CP-A3) · `probe-shipturtle.ps1` (CP-A5).
- [x] **0.7 Fix and extend the webhook script.** Extract `resolveProject(alias)` (reads `.firebaserc`), `loadParams`, `mintAdminToken`, `graphql`, `listWebhookSubscriptions` from `register-webhooks.mjs` into `functions/scripts/lib/shopify-admin.mjs`. The script resolves `--project dev` to the project id, defaults `--url` from `firebase functions:list --json`, and gains `--check` (list only, exit 1 if any topic is missing). New npm scripts: `webhooks:check`, `doctor`, `doctor:emu`, `touch-products`, `probe:shipturtle`, `replay-order`.
- [x] **0.8 `npm run doctor`** — `functions/scripts/doctor.mjs`. One line per check; on FAIL the exact fix; exit non-zero only on FAIL; never prints a secret. The two values it needs in memory (client secret for the Admin mint, Storefront token for the storefront probe) come from `firebase functions:secrets:access` via a child process and are never logged.

  | # | Check | Fix printed on failure |
  |---|---|---|
  | 1 | flutter / firebase (≥14) / node (≥22) / adb on PATH | install links |
  | 2 | PowerShell execution policy not Restricted | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
  | 3 | `.firebaserc` has `dev` → `little-blue-610e5`; `firebase use` matches | `firebase use dev` |
  | 4 | `.env.little-blue-610e5` params non-empty; domain ends `.myshopify.com`; WARN if it is the production domain | which line to set |
  | 5 | each secret in `ALL_SECRETS` exists (names parsed from `config.ts`) | `firebase functions:secrets:set NAME --project dev` |
  | 6 | Admin token mints and `{ shop { name myshopifyDomain } }` answers | reinstall the app on the dev store, then re-set the client secret |
  | 7 | Storefront token answers `{ shop { name } }` | re-set the storefront token |
  | 8 | every `export const` in `index.ts` is in `firebase functions:list` | `scripts\deploy-dev.ps1`, naming the missing ones |
  | 9 | six webhook topics registered against the deployed `shopifyWebhook` URL | `npm run webhooks:dev` |
  | 10 | Email/Password and Anonymous enabled (Identity Toolkit REST with the public API key; creates and deletes a throwaway account) | console deep link to Authentication → Sign-in method |
  | 11 | backend health (calls `diagnosticsHealthCheck`, Stage 1): deployed rules sha equals `firebase/firestore.rules`, Shipturtle key + probe, counts | each sub-check carries its own fix |
  | 12 | emulator ports 8080/9099/5001/9199/4000 free (or in use for `doctor:emu`) | `netstat -ano \| findstr :8080` |
  | 13 | Android emulator booted (`adb devices` shows `emulator-5554`) | "Android Studio → Device Manager → Play" |

  Output ends with a summary line: `2 FAIL, 1 WARN, 11 PASS. Paste this whole block to Claude if anything is FAIL.`
- [x] **0.9 `npm run touch-products`** *(ran 2026-09-05: 17 products touched, product webhooks live)* — `functions/scripts/touch-products.mjs`: a no-op `productUpdate` on every dev-store product (`--vendor "Name"`, `--limit N`) so `products/update` fires through the real webhook path and fills the `catalog` mirror. Prints "touched N; catalog now has M documents". Doubles as the end-to-end webhook test.
- [x] **0.10 `.claude/settings.json`** (committed): allow the read-only and idempotent commands (`flutter analyze|test|pub get|devices`, `dart format|analyze`, `git status|diff|log|show|branch`, `npm test`, `npm run doctor|test:rules|webhooks:check`, `npx tsc --noEmit`, `firebase use|functions:list|functions:log|functions:secrets:get|projects:list`, `adb devices`, `netstat`, `node scripts/*.mjs` read-only ones); **deny** `firebase functions:secrets:access*`, `git push --force*`, and `Read(**/.env*)` / `Read(**/shopify_recovery_codes.txt)` so Claude can never display a token. Deploy, commit, push, and `secrets:set` stay prompt-gated.
- [x] **0.11 Phase 0/1 audit.** Verified by me today, done: `.firebaserc` · Node 22 everywhere · bundle id `com.littleblue.market` in Gradle, Xcode, `google-services.json` · Dynamic Links gone, email+password in (`f352d74`) · voting removed · `postCount` locked · `SHIPTURTLE_WEBHOOK_SECRET` inside `ALL_SECRETS` · API version default `2026-07` · Shipturtle webhook accepts-and-shouts (tested) · Phase 1 code, rules, claim screen, 24 rules tests. **Not done:** items 2, 3, 9 in the table in §1 (fixed by 0.4 and 0.7), `npm run verify:security` (Stage 1), and the console checks the doctor turns into MANUAL lines.

**Found on 2026-09-05 when Stage 0 ran:** the Shopify app on the dev store has **no access scopes at all**, so Shopify refuses every webhook topic and every product read. Only the app owner can fix this; the doctor's `shopify scopes` line names the exact scopes.

**Grace does first (Shopify Dev Dashboard, dev.shopify.com/dashboard):** Apps → the Little Blue Market app (client id starting `7ed01fec`) → Configuration → Access scopes → add `read_products, write_products, read_inventory, write_inventory, write_publications, read_customers, read_orders, read_fulfillments, write_fulfillments` → Save (and Release, if the dashboard asks) → open the dev store and reinstall / re-authorise the app so the new scopes take effect. Then `scriptsdoctor.ps1` must show `PASS shopify scopes`.

**Grace does second (done 2026-09-05: scopes granted, protected customer data granted, all six webhooks registered, 17 products mirrored):** the order and fulfilment webhooks carry customer names and addresses, so Shopify also wants **Protected customer data access**: the app → Configuration (or API access) → Protected customer data access → Request access → reason "App functionality" → save. No review is needed for a development store. Then `cd functions; npm run webhooks:dev` registers the last three topics (ORDERS_PAID, FULFILLMENTS_CREATE, FULFILLMENTS_UPDATE).

**Grace does next:** `scripts\doctor.ps1` (fix reds, rerun) → `scripts\run-live.ps1` → "Continue as a guest" → the Market feed says **Nothing posted yet** (expected: the feed shows *posts*, and nobody has posted on the live backend yet; browsing the shop by collection arrives in Stage 4) → tap the search icon → type **snowboard** → real products appear with photos and prices.
**Pass looks like:** doctor all PASS/WARN/MANUAL; the corner badge (Stage 1, if landed) or the debug banner says live; the product appears with its real photo and price; Firebase console → Firestore shows `catalog` documents.
**If it fails:** paste the doctor output. No search results → paste the `touch-products` output (M must be ≥ N).

### Stage 1 — Make failures loud (before any feature work) — ✅ passed by Grace 2026-09-05 (backend health all green)

**Goal:** when anything breaks on the phone, you see *what*, *where*, and *what to paste*.

**Claude builds:**

- [x] **1.1 A dev-only error surface.**
  - `lib/data/repositories/dev_error_sink.dart` (pure Dart): `DevErrorSink.enabled`, `report(error, [stack], [operation])`, a broadcast stream, `DevErrorReport{error, stack, operation, at}` with `typeName`, `code`, `message`, `details` getters. No-op unless enabled.
  - The single hook: `translateFirestoreError` in `lib/data/firebase/firestore_errors.dart` gains `{String? operation}` and reports the **raw** exception (so `FirebaseFunctionsException.code/message/details` are intact) before translating; `guardFirestore` and `.guarded()` pass `operation` through. `CommerceProxyRepository._call(name)` and `FulfillmentProxyRepository` pass `'callable $name'`; `requestSellerStatus` and the new `linkStoreAccounts` likewise; `FirebaseAuthService._translate` reports `'auth ${code}'`.
  - `lib/state/dev_errors.dart`: `devErrorsProvider` (last 20 entries stamped with route from `routerProvider` and the backend label), `devSurfaceEnabledProvider = kDebugMode && !FLUTTER_TEST` (tests override to true when they want it), `formatForClaude(entry)` producing the block below.
  - `lib/widgets/dev_error_surface.dart`: `DevErrorSurface(child)` — a red strip (`context.c.clay`) under the status bar with one line `Type · code · operation`, two lines of message, **Copy for Claude** (turns into "Copied") and **Dismiss**; tap opens an `showLbmSheet` list of recent errors. `DevBackendBadge()` — an `IgnorePointer` chip reading `DEV · fixtures`, `DEV · live · little-blue-610e5`, or `DEV · emulators · little-blue-610e5` from a new `backendLabelProvider` in `data/providers.dart`. Both return `child`/nothing under `FLUTTER_TEST`, so `screens_smoke_test.dart` and `text_scaling_test.dart` are untouched. All text has `maxLines`, so it can never overflow.
  - `lib/widgets/async.dart` `LbmErrorCard`: in debug and not under test, a third small line `Type · code: cause` under the friendly copy. `describeError` unchanged.
  - `lib/main.dart`: under `kDebugMode`, enable the sink, set `FlutterError.onError` (present, then report) and `PlatformDispatcher.instance.onError` (report, return true); wrap the `builder` child in `DevErrorSurface(child: Stack([child, DevBackendBadge()]))`.
  - The copy block:
    ```
    --- LBM dev error (paste to Claude) ---
    when:      2026-09-04 22:41:07
    backend:   live · little-blue-610e5   (app 0.3.0+1, debug)
    route:     /you/claim-shop
    operation: callable sellerClaimVendor
    type:      FirebaseFunctionsException
    code:      failed-precondition
    message:   Confirm your email address first, then try your code again.
    details:   null
    stack (top 8): …
    ---------------------------------------
    ```
  - Tests: `test/dev_error_sink_test.dart`; `test/dev_error_surface_test.dart` (banner appears after a report, Copy hits the clipboard via the mock platform channel, no overflow at 390 wide in both themes, Dismiss clears).
- [x] **1.2 Backend errors that say what to do.** `functions/src/errors.ts` with `fail(code, message, operation, hint?)` and `withLoudErrors(name, handler)` wrapping every `onCall` in `index.ts`: unexpected throws become `HttpsError('internal', '<name> failed: <message>. Run npm run doctor; if all PASS, paste this to Claude.', {operation})` and are logged with the stack. Rewrite `token.ts:63` (mint failure: status, domain, "reinstall the app, then re-set SHOPIFY_CLIENT_SECRET"), `token.ts:163` and `storefront.ts:37` (domain, version, status, "check SHOPIFY_STORE_DOMAIN" on 404/301).
- [x] **1.3 `diagnosticsHealthCheck`** callable in `functions/src/diagnostics.ts` (`runHealthCheck(probes)` with each probe isolated so one failure never hides another): `storeDomain`, `clientId`, `adminToken` (`{ shop { name myshopifyDomain } }` via `adminGraphQL`), `storefrontToken`, `webhooks` (topics present vs six expected), `shipturtleKey` (present + decoded JWT `scopes`/`exp`, never the token), `shipturtleProbe` (CP-A5), `authProviders` (Identity Toolkit admin config via the runtime's own credentials), `rulesSha` (Rules REST, sha256 of the deployed source), `counts` (`catalog`, `sellers`, `vendorNames`, unused `vendorClaims`). Requires a signed-in user; allowed when `admin: true` or the project is `little-blue-610e5` (`TODO(prod)` like `index.ts:336`). Unit tests with injected probes.
- [x] **1.4 Hidden Diagnostics screen** at `/you/diagnostics` (debug only): a facts card (backend, project, uid, email, `emailVerified`, `seller` claim, `isLinked`, app version) and, on live, "Run backend health check" rendering each check as a `ListRow` with a green/clay dot, summary, and fix; "Copy report for Claude". Entry row "Diagnostics (dev)" at the bottom of Edit Profile. `DiagnosticsRepository` interface + Firestore and fixture implementations; route added to the smoke and scaling tests.
- [x] **1.5 `npm run verify:security`** — `functions/scripts/verify-security.mjs` under `firebase emulators:exec`: signs in as a normal user and attempts S1–S8 from `implementation-phases.md`; PASS/FAIL per line.

**Grace does:** `scripts\run-live.ps1` → Profile → Edit profile → Diagnostics (dev) → Run backend health check. Then turn off Wi-Fi on the emulator (swipe down from the top of the phone screen, tap the Wi-Fi tile), search **snowboard**, open a product and tap Add to cart. (The feed itself is empty until someone posts; products live behind search until Stage 4.)
**Pass looks like:** green rows for `adminToken`, `storefrontToken`, `webhooks`, `rulesSha`; the offline tap shows the red strip; Copy for Claude puts the block above on the clipboard.

### Stage 2 — Accounts and roles, verified by you (the missing wiring + Phase 3)

- [x] **CP-A1 Sign up as a buyer and become verified without a restart.** *(passed by Grace 2026-09-05)*
  **Claude builds:** `AuthService.reloadUser()` (`user.reload()` then `getIdToken(true)`), `AuthUser.isSeller` from `getIdTokenResult().claims['seller']`; `FirebaseAuthService.authStateChanges()` becomes `idTokenChanges()` mapped with claims and `.distinct()` on `(uid, emailVerified, isSeller)` so hourly refreshes do not re-emit; `VerifyScreen` gains "I've confirmed it" (reload; "Confirmed." or "Not confirmed yet. Open the link in the email (check Spam), then tap again.") plus a 5-second poll while the screen is open; `MemberSession.emailVerified`, and an Edit Profile row "Confirm your email" until it is true.
  **Grace does:** `run-live.ps1` → Create a Profile → `+buyer1` → open the mail, click the link → back in the app tap "I've confirmed it" (or wait 5 s) → Continue → handle → Create a profile.
  **Pass:** Market with a You tab; Diagnostics shows `emailVerified: true`, `seller: false`; the account has a green tick in the Firebase console.
  **If it fails:** `auth operation-not-allowed` → doctor check 10. Never flips to confirmed → paste the Diagnostics facts card. No email → check Spam, then Authentication → Templates.
- [x] **CP-A2 An existing Shopify customer signs in and sees their orders.** *(passed by Grace 2026-09-05; needed the protected customer *fields* grant in the Dev Dashboard)*
  **Claude builds:** `linkStoreAccounts` once-only (skip when `backfilledAt` exists); purchase ids `${orderId}_${lineId}` from `lineItems.nodes.id` to match `orders.ts:230`; `vendor` passed through `resolveSellerUid({vendor, productId})` instead of `sellerId: ''`; response gains `backfilledOrders/backfilledItems`. Flutter: `ProfileRepository.linkStoreAccounts()` (fixture returns a canned result), `Person.isLinked` (`linkedAt != null`); `SessionNotifier` fires it once when it sees a verified, unlinked member (errors go to the sink); Profile opens on "Bought" after a successful link.
  **Grace does (once, dev Shopify admin):** Customers → Add customer `+customer1` → Save. Orders → Create order → add a product that `touch-products` mirrored → that customer → Collect payment → Mark as paid → Create order. In the app: sign out (add the row to Edit Profile if missing), Create a Profile with `+customer1`, confirm as in CP-A1.
  **Pass:** You tab opens on "Bought" showing that product with a "Received" badge; Diagnostics `isLinked: true`.
  **If it fails:** Firestore console → your user doc: no `linkedAt` means the callable never ran (paste the banner or `firebase functions:log --only linkAccounts`); `backfilledAt` present but no `purchases` means the emails do not match exactly. Grey boxes → `npm run touch-products`.
  **Tests:** `functions/test/linking.test.ts` (once-only, line-id keys, vendor passthrough, two matches link neither); `session_test.dart` (exactly one link call for a verified unlinked member, none for unverified).
- [x] **CP-A3 Seller claim code → seller surfaces appear without a restart.** *(passed by Grace 2026-09-05 — claim code LBM-TEST-0001 for vendor "Snowboard Vendor", bound to grace-s+seller1@; the vendorClaims document is in the "Grace does" step)*
  **Claude builds:** `MemberSession.isSeller` comes from the auth claim; the profile is emitted as `person.copyWith(isSeller: user.isSeller)` so `meProvider`, `isSellerProvider`, Edit Profile and the composer all agree without touching a screen (`Person.isSeller` stays the public display mirror for other people's profiles). Claim/document drift → one `reloadUser()`. `requestSellerStatus` already forces `getIdToken(true)`; with `idTokenChanges()` that now reaches the session (the real fix for S9). Fixture parity via `FixtureAuthService.grantSeller()`. **Products tab on the own profile:** extract the grid from `seller_feed_screen.dart:94-99` into `lib/widgets/seller_products_grid.dart` with `LbmAsync` empty/error states ("No products yet — they arrive from your store"); own profile tabs become `['Products', 'Posted', 'Bought']` for sellers (shorten labels if 2.0 scale overflows). Claim issuing with no service-account key: `functions/scripts/claim-code-hash.mjs LBM-TEST-0001 --vendor "Exact vendor string" --email …` prints the sha256 doc id and the fields to paste into Firestore console → `vendorClaims` → Add document (same hashing as `sellers.ts:46`); `scripts\issue-claim-code.ps1` wraps it. `ClaimShopScreen` navigates to `/you` on success. Fix `requireSeller()`'s stale copy in `sheets.dart:166` to point at Claim a shop.
  **Grace does:** `issue-claim-code.ps1 -Vendor "<vendor string of a dev-store product>" -Email grace-s+seller1@…` → create the document as printed. App: Create a Profile with `+seller1`, confirm. Edit profile → Start selling → type `LBM-TEST-0001` → Claim my shop.
  **Pass:** "You are now selling as <vendor>"; the Products tab appears (empty state until CP-A4); Edit profile shows Payouts & bank / Sales & shipping; Diagnostics `seller: true`; no restart. Same code again → "You have already claimed that shop."
  **If it fails:** "not found" on the callable → doctor check 8 (the seller functions are not deployed). "Confirm your email first" → CP-A1's button. "not recognised" → the console doc id must equal the printed hash exactly.
  **Tests:** `session_test.dart` (claim drives `isSellerProvider`; document alone does not); smoke/scaling with three tabs; `sellers.test.ts` (hash script output equals `hashClaimCode`).
- [ ] **CP-A4 The seller's existing products appear** (Phase 3b, tightened). *(built 2026-09-05; ready to test)*
  **Claude builds:** `mirrorProduct` persists `vendorName` and `vendorKey` (normalized) and resolves `sellerId` via `resolveSellerUid`; `vendors.ts` strategy 3 reads `vendorNames/{normalizeVendorName(vendor)}` (with `sellers/{uid}.revokedAt == null`) instead of `users`; misses are not cached (a separate 60 s negative cache); new trigger `resolveSellerForVendorName` on `sellers/{uid}` batch-updates `catalog.sellerId` for that `vendorKey` (400 per batch) and calls `forgetVendorCache()`; `seed.mjs` writes the new fields and one claim for the emulator path.
  **Grace does:** `scripts\deploy-dev.ps1` → `npm run touch-products -- --vendor "<vendor>"` → pull to refresh the Products tab. Then edit one of that vendor's products in the Shopify admin (add a tag), save, pull again.
  **Pass:** the products with photos and prices; the edited one updates within seconds.
  **If it fails:** open one of those products in Firestore: no `vendorKey` → the redeploy/touch did not happen; `vendorKey` but empty `sellerId` → `firebase functions:log --only resolveSellerForVendorName`, paste it.
  **Tests:** `catalog.test.ts` (fields persisted), `vendors.test.ts` (no miss caching; strategy 3 reads `vendorNames`), rules (`catalog` still not client-writable), `npm run test:integration` (new, emulator: writing `sellers/{uid}` backfills `sellerId`).
- [ ] **CP-A5 Shipturtle probe, then automatic vendor detection by email.** *(probe ran 2026-09-05: the roster is `GET /api/v1/users` with a Bearer token, 5 vendor users with `email` and `company_id`; wired as `SHIPTURTLE_VENDORS_PATH` and `findVendor` now matches it — a matched account gets `shipturtleVendorId`; the seller **grant** still comes from a claim code because the roster does not carry the Shopify vendor name)*
  **Claude builds:** `functions/scripts/shipturtle-probe.mjs` — token from the environment only (`probe-shipturtle.ps1` pulls it with `functions:secrets:access` into a variable; accepts `SHIPTURTLE_API_KEY_ORDER`/`_PRODUCT` too so both tokens can be compared). Decodes the JWT payload (`sub`, `aud`, `scopes`, `exp`, expired?; never the token). Tries each base (`SHIPTURTLE_BASE_URL`, `api-v2.shipturtle.com`, `api.shipturtle.com`) × path (`/api/v1/me`, `/api/v1/vendors`, `/api/v1/vendor`, `/api/v1/users`, `/api/v1/company`, `/api/v3/vendors`, `/api/v1/orders?limit=1`, `/api/v1/products?limit=1`, `/api/v3/fetch-product-data/parent`) × auth header style (`Authorization: Bearer`, `x-api-key`, `access-token`), 10 s timeout, printing status, content-type, top-level keys, array length, first 160 chars of non-2xx bodies. Ends with `ROSTER REACHABLE at … , N vendors` or `NO ROSTER ENDPOINT FOUND — token scopes […]; ask team@shipturtle.com: "Which Open API endpoint lists the merchant's vendors and their user emails?"`. Then `functions/src/shipturtle_api.ts` with `probeShipturtle()` and `listVendorUsers()` parameterised by new params `SHIPTURTLE_VENDORS_PATH` and `SHIPTURTLE_AUTH_HEADER` (set in `.env`, not code), roster cached 15 min in `_internal/shipturtleRoster`; `findVendor` in `linking.ts` prefers the roster (exact, unique, lowercase match), falls back to `vendorMappings`, logs which path answered. Auto-grant from the roster stays for Stage 8; the claim code remains the grant.
  **Grace does:** in Shipturtle on the dev store, set your test vendor's user email to `+seller1`. Run `scripts\probe-shipturtle.ps1`, paste the whole output (no secret in it). Look for a docs link under Dashboard → API integration and paste it too. After Claude wires it and you `deploy-dev.ps1`: doctor `shipturtleProbe` green; Diagnostics shows the vendor count; `users/{uid}.shipturtleVendorId` in the console equals the vendor's `company_id`.
  **If it fails:** all 401 → wrong token of the two, or expired (`exp` is printed) → `firebase functions:secrets:set SHIPTURTLE_API_KEY --project dev` with the other one. All 404 → paste the output. If no roster endpoint exists, this box gets a note and Stage 8 waits on Shipturtle's answer.
  **Tests:** `shipturtle_api.test.ts` (decoder never returns its input; roster mapper against a recorded, secret-stripped response; `findVendor` order and duplicate refusal).

### Stage 2 walkthrough, as of 2026-09-05 (do these in order)

**One-time setup you do (about 10 minutes):**

1. **A customer with an order, in the dev Shopify admin** (for CP-A2). Open the dev store admin → Customers → Add customer → email `grace-s+customer1@the-culture-connection.com`, any name → Save. Then Orders → Create order → add "The Complete Snowboard" (any product works) → Customer: pick that customer → Collect payment → Mark as paid → Create order.
2. **The claim code document, in the Firebase console** (for CP-A3). Open https://console.firebase.google.com/project/little-blue-610e5/firestore/data/~2FvendorClaims → Start collection `vendorClaims` (or Add document if it exists) → Document ID exactly `7001e4474dd563741370b90deaeb8bd76bc95309a42ac15222f0d29709276cb9` → fields: `vendorName` (string) `Snowboard Vendor`; `email` (string) `grace-s+seller1@the-culture-connection.com`; `expiresAt` (timestamp) any date next month → Save. (That ID is the SHA-256 of the code LBM-TEST-0001; `scripts/issue-claim-code.sh` prints it again if needed.)

**Then, in the app** (restart it first: `q`, then `scripts/run-live.sh`):

- **CP-A2.** Edit profile → Sign out → Create a Profile with `grace-s+customer1@…` → confirm the email → Continue → handle → Create a profile. **Pass:** within a few seconds the You tab's "Bought & received" grid shows the snowboard you ordered in the admin, with a "Received" badge; Diagnostics (dev) shows "Linked to the store: yes".
- **CP-A3.** Sign out → Create a Profile with `grace-s+seller1@…` → confirm the email → handle → Create a profile. Edit profile → Start selling → type `LBM-TEST-0001` → Claim my shop. **Pass:** "You are now selling as Snowboard Vendor", you land on your profile, and it now has three tabs (Products · Posted · Bought) — no restart. Edit profile shows Payouts & bank / Sales & shipping. Diagnostics shows "Seller claim: yes". Entering the code again says it was already used.
- **CP-A4.** Stay on the Products tab (pull down once). **Pass:** the "Snowboard Vendor" products from the dev store (The Complete Snowboard, The Archived Snowboard, The Hidden Snowboard) appear as a grid with prices. Open one: the "Sold by" card now shows *you*.
- **CP-A5.** Nothing to tap. In Shipturtle on the dev store, if a vendor user has the email `grace-s+seller1@…`, Diagnostics on that account shows it linked as a vendor. Otherwise this checkpoint is proven by the doctor's green `shipturtleProbe` row.

**If anything is red:** "Copy for Claude" and paste it. The usual suspects: the claim document ID does not match (re-run the script and compare), or the customer email in Shopify differs from the sign-up email by a character.

### Stage 3 — Buying (Phase 2)

- [ ] **CP-B1 Add to cart, live.** No new code. **Grace:** Market → product → Add to cart → Cart. **Pass:** the line with a real price. **If it fails:** the red strip names `commerceAddLine` and the code; paste it.
- [ ] **CP-B2 Checkout opens inside the app.** **Decision (deviates from the earlier `flutter_inappwebview` default, to cut hurdles):** `url_launcher` in `LaunchMode.inAppBrowserView` (a Chrome Custom Tab on Android — in-app, zero native config, no Gradle risk). Since `orders/paid` is the only truth, nothing depends on watching the thank-you URL. Swap to a web view later if the sheet look is wanted. **Claude builds:** replace the SnackBar at `sheets.dart:232` with the launcher behind a `checkoutLauncherProvider` (tests inject a fake); on failure "Could not open checkout" with a copy-link action; on app resume, `CartScreen` shows the existing "we'll confirm shortly" copy and invalidates purchases; `recordPaidOrder` clears `carts/{uid}` for orders carrying `app_uid`. Plus `functions/scripts/replay-order.mjs --order <id>` (fetches the order, signs a REST-shaped payload in-process, POSTs to `shopifyWebhook`) — the M2 replay test and the "push a missed webhook by hand" tool. **Grace:** as `+buyer1`: product → Buy → Check out → Open checkout → Bogus Gateway card `1`, any future date, CVV `111` → Pay → close. **Pass:** the checkout renders in-app; the cart says it will confirm shortly.
- [ ] **CP-B3 The order lands.** **Grace:** within ~10 s You → Bought shows the item; the seller's profile sales rose by the line amount. Then `node scripts/replay-order.mjs --order <number>` twice → second prints `duplicate`, counts unchanged. **If it fails:** doctor check 9 (webhooks), then `firebase functions:log --only shopifyWebhook`; `401 bad signature` means the client secret in Secret Manager is not the one the app was registered with.

### Stage 4 — The real catalog (Phase 4)

- [ ] **CP-C0 Admin claim without a key.** `adminClaimSelf` callable grants `admin: true` only if the caller's verified email is in `_internal/config/admins.emails`, a document only a project owner can write. **Grace:** Firestore console → create `_internal/config/admins` with `emails: ["grace-s@the-culture-connection.com"]` → Diagnostics → "Claim admin". **Pass:** Diagnostics `admin: true`.
- [ ] **CP-C1 Collections mirror.** `syncCollections` (scheduled + callable) → `collections/{handle}` with id, title, handle, image. **Grace:** Diagnostics → "Sync collections". **Pass:** count matches the dev store's Collections page.
- [ ] **CP-C2 Catalog backfill.** `backfillCatalog` via `bulkOperationRunQuery`, one shape adapter so REST webhooks and GraphQL bulk yield byte-identical documents (unit-tested), resume cursor, and the two `mirrorProduct` fixes (category from collections; keep non-`#` tags). Admin-only. **Grace:** Diagnostics → "Backfill catalog", twice. **Pass:** document count equals the store's product count both times; Market feed and search show real products.
- [ ] **CP-C3 Browse an initiative.** `Collection` model + `CollectionRepository` + fixture; initiative chips read real collections. **Grace:** tap "Ally Owned". **Pass:** real products.

### Stage 5 — A seller adds a product (Phase 5)

- [ ] **CP-P1 Draft → Under review.** `SellerRepository` (pure Dart) + `Listing` (int cents) + fixture; composer product section (single variant); images to `listings/{uid}/{file}` (public-read Storage rule); `listings/` rules; `sellerPublishListing` with the three-fact check, server-side re-read, `submitting` guard, `app.draft_id` idempotency, one `productSet` with `inventoryQuantities`, mirror seed; the **Under review** modal. **Grace:** Products → Add → title, price, one photo → Add. **Pass:** modal; in Shopify the product is **Draft** with vendor = your vendor.
- [ ] **CP-P2 Retry is safe.** Force-close mid-spinner, reopen, retry. **Pass:** one product.
- [ ] **CP-P3 Bad input refused before Shopify.** Price 0; no photo. **Pass:** a message naming the field; nothing in Shopify.
- [ ] **CP-P4 A non-seller is refused.** As `+buyer1`: no Add button; Diagnostics "try publish" reports `permission-denied`.

### Stage 6 — Approval, edits, honest numbers (Phase 6)

- [ ] **CP-R1 Approval flips the chip.** Approval branch in `mirrorProduct` reading `app.draft_id`; `sellerRefreshListings` (batched, 60 s limit); status chips + pull-to-refresh. **Grace:** approve in Shipturtle → Live. Then with the webhook disabled (script), approve another, pull-to-refresh → Live.
- [ ] **CP-R2 Edit and restock without losing variants.** `sellerUpdateListing` via `productVariantsBulkUpdate` + `inventorySetQuantities`, never `productSet` (asserted by a test). **Grace:** edit price, restock. **Pass:** Shopify shows both; variant count unchanged.
- [ ] **CP-R3 "Total sales".** `revenueCents` → `grossSalesCents` end to end. **Pass:** the label says Total sales; no payout figure anywhere.

### Stage 7 — The journey changes (Phase 7)

- [ ] **CP-J1 The heart becomes the cart.** `PostActionBar` drops like; "N added · M comments"; `catalog/{id}/carted/{uid}` + `saveCount` (monotonic) + `inCartsCount` (live), written only by the commerce functions; the tutorial card. **Grace:** add from a feed card, remove, add again. **Pass:** "added" climbs and never drops; the seller's listing shows "in carts right now" dropping on remove.
- [ ] **CP-J2 Cart posts and reviews.** `CartPost` (≤24 frozen items, rules), Cart tab on the profile, `commerceAddManyLines`, `onReviewWritten`, delivered → "How was it?". **Grace:** post your cart; "Add all" from another account; mark a purchase delivered (Claude replays a fulfilment webhook) and review it. **Pass:** the cart post renders; 30 items refused at 24; the review appears on the product and in the feed.

### Stage 8 — Shipturtle, the rest (Phase 8)

Depends on CP-A5's verdict. Roster auto-grant in `sellerClaimVendor` + scheduled `sellerSyncVendorRoster`; payout figures from Shipturtle as separate fields, never computed locally; approval status with merchant remarks; the real fulfilment push replacing the placeholder in `fulfillment.ts` (`/v1/fulfillments` is a guess); the `TODO(prod)` gate so unverified Shipturtle webhooks are accepted only on `little-blue-610e5`. **Grace:** ship an order from the vendor panel. **Pass:** the buyer's Receiving tab shows the tracking number.

### Cutover (later, its own checklist)

Unchanged from `answers-to-open-questions.md` Part 2: add a `prod` alias, confirm the app on the real shop, repoint the store domain, deploy, register webhooks, backfill, issue claim codes to the top five vendors. Nothing in this plan touches the real shop.

### Sequencing

Stage 0 → Stage 1 → CP-A1 → (CP-A2 and CP-A3 independent) → CP-A4 needs CP-A3 → CP-A5 independent of A2–A4 → Stage 3 needs Stage 0 and CP-A1 (CP-A4 for seller sales) → Stages 4–8 in order. One commit and push per checkpoint.

---

## 5. Things only you can do (collect these up front)

- Firebase console: Email/Password + Anonymous ON (doctor check 10 tells you if not); Blaze confirmed.
- Dev Shopify admin: one test customer + one paid order (CP-A2); confirm the app scopes `write_products, write_inventory, write_publications, read_customers, read_orders, read_fulfillments, write_fulfillments`.
- Shipturtle on the dev store: your test vendor's user email = `+seller1`; the docs link from Dashboard → API integration (CP-A5).
- Firestore console: the `vendorClaims` document the script prints (CP-A3); the `_internal/config/admins` document (CP-C0).
- Approving listings in Shipturtle (CP-R1).

---

## 6. Critical files (for Claude)

**Flutter:** `lib/main.dart` · `lib/widgets/async.dart` · `lib/data/firebase/firestore_errors.dart` (the one error hook) · `lib/data/shopify/{commerce,fulfillment}_proxy_repository.dart` · `lib/data/firebase/firestore_profile_repository.dart` · `lib/data/firebase/firebase_auth_service.dart` · `lib/data/auth/auth_service.dart` · `lib/state/session.dart` · `lib/router/app_router.dart` · `lib/screens/onboarding/auth_screens.dart` · `lib/screens/you/{profile,edit_profile,claim_shop}_screen.dart` · `lib/screens/market/seller_feed_screen.dart` (grid to extract) · `lib/widgets/sheets.dart` (checkout at :232, `requireSeller` copy at :166) · `lib/data/repositories/{repositories,exceptions}.dart` · `lib/data/providers.dart` · `lib/data/fixtures/fixture_repositories.dart`.

**Functions:** `functions/src/{index,config,linking,sellers,vendors,catalog,orders,cart,fulfillment,shipturtle}.ts` · `functions/src/shopify/{token,storefront}.ts` · `functions/scripts/{register-webhooks,seed}.mjs` · `functions/test/*` · `firebase/{firestore.rules,storage.rules,firestore.indexes.json}` · `.firebaserc` · `functions/.env.little-blue-610e5`.

**Reuse, do not rebuild:** `guardFirestore`/`translateFirestoreError`; `LbmAsync`/`LbmErrorCard`/`showLbmSheet`/`ListRow`/`PillButton`; `requireSeller()` in `sheets.dart`; `requireSeller` (three-fact check) and `hashClaimCode`/`normalizeVendorName` in `sellers.ts`; the token minting and GraphQL helpers in `register-webhooks.mjs`; `forgetVendorCache()`; the avatar upload path in `firestore_profile_repository.dart`; `Planning/implementation-phases.md` for the deep engineering detail of Phases 4–8 (this document is the order and the test; that one is the how).

---

## 7. Verification

**Automated, every checkpoint:** `scripts\test-all.ps1` (analyze 0 issues, flutter test, `tsc --noEmit`, `npm test`); `npm run test:rules` when rules changed; `npm run test:integration` from CP-A4 on; `npm run verify:security` after Stage 1 and after any rules change.

**Preflight, every session and after every deploy:** `scripts\doctor.ps1` all PASS/WARN/MANUAL; `npm run webhooks:check` prints six "present" rows.

**Manual, per checkpoint:** the "Grace does / Pass looks like" lines above, on the Android emulator against the real dev project via `scripts\run-live.ps1`. The groups S, A, C, P, R, M in `implementation-phases.md` map onto Stages 1–7 and stay the detailed reference.

**Risks worth naming:** `idTokenChanges()` fires on every refresh — the `distinct()` and `_SessionListenable`'s type dedupe keep the router quiet (the existing "profile edit reaches the session" test guards it). Three own-profile tabs may overflow at 2.0 text scale — the scaling test decides; shorter labels are the fix. `diagnosticsHealthCheck` is open to any signed-in user on the dev project only — resolve the `TODO(prod)` before a `prod` alias exists. The Shipturtle endpoint shape is unknown until the probe runs — everything after it lands in `.env`, not code.
