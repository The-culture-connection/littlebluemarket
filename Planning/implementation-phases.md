# Implementing `backend-architecture.md` — frontend-first phases

## Context

`Planning/backend-architecture.md` (636 lines) and `Planning/user-journeys.md` (313 lines) specify
PRs 16–21 as **backend-shaped** units: a PR is "the join key", "the write path", "Shipturtle". That
sequencing is correct about dependencies but it means nothing is visible or testable until a Cloud
Function exists, and it leaves PR 18's client half entirely unnamed even though `CLAUDE.md` makes a
repository interface plus a fixture twin non-negotiable.

This plan re-cuts the same work into **phases by user-visible capability**, each built in two halves:

- **(a) Frontend against fixtures** — screens, models, repository *interfaces*, fixture
  implementations. Verified by `flutter analyze` + `flutter test`, which is real automated coverage:
  `screens_smoke_test.dart` renders 27 routes × 2 themes and fails on overflow,
  `text_scaling_test.dart` re-renders 19 at 2.0 scale, `no_fixture_imports_test.dart` enforces the
  seam. 291 tests today.
- **(b) Backend behind that interface** — Cloud Functions, rules, indexes, the live repository
  implementation. Verified manually against the emulator and a Shopify dev store, plus
  `npm test` (30) and `npm run test:rules` (18).

This works because the seam already exists — Track A built the entire client on `FixtureStore` with
zero Firebase dependency, and `Backend.fixtures` / `Backend.live` still switches cleanly. We are
repeating a discipline the codebase already proved, not inventing one.

**The one real risk of frontend-first**, stated so it gets managed: you can build a screen against a
fixture the backend cannot actually satisfy. Mitigation — in every phase, half (a) starts by writing
the **repository interface and the model**, and that signature is the contract half (b) must meet. If
(b) cannot meet it, the interface changes and (a)'s tests fail loudly rather than the two halves
quietly diverging.

### Verification findings that change the plan

I verified both planning docs against the code. The architecture is sound and §8's
privilege-escalation claim is **real** — confirmed at `firestore_profile_repository.dart:149-154`
(client writes `isSeller: true` directly), `firestore.rules:63-69` (lock list omits `isSeller` and
`shopifyVendorName`), `vendors.ts:85-100` (credits sales to the single account claiming a vendor
name), reachable in one tap from `edit_profile_screen.dart:266-275`. That sets Phase 1.

Six things the docs get wrong or leave undefined, folded into the phases below rather than listed
separately: §4 still credits `linkAccounts` with `isSeller` (and `linking.ts:47` really does write
it — deleting `becomeSeller()` alone does **not** close the hole); §6 still gates on
`users/{uid}.isSeller` and reads `users/{uid}.shopifyLocationId`, both moved by §8; §6 keeps two
`publishablePublish` references that step 7 removed; §6a writes "a notification document" that no
collection defines; `saveCount`/`inCartsCount`/`carted/{uid}` and `CartPost` are specified in
`user-journeys.md` but absent from §3's data model.

---

---

# What I need to do

You are standing up your own Shopify test store and your own Shipturtle, which removes four of the six
blockers outright — you become the merchant, so you can issue your own claim codes, approve your own
listings, and read your own Locations page. What is left is setup, in this order. Roughly half a day,
most of it waiting for things to install.

**Do it in this order.** Each step produces a value the next one needs.

### 1. A Shopify development store — free, and safe to write to

1. Sign up at **partners.shopify.com** (free; no store or plan required).
2. **Stores → Add store → Development store**, purpose "test and build an app". Give it a name — the
   `xxx.myshopify.com` domain it generates is your `SHOPIFY_STORE_DOMAIN`.
3. When offered, **start with test data** — it seeds products, customers and orders, which saves you
   inventing them. If you skip it, import a CSV later; you need products with **several distinct
   `vendor` values** or Phase 3 has nothing to attribute.
4. Development stores have payments in test mode by default (Bogus Gateway), so **M1** can run a real
   checkout with a fake card and no money moves.

> Shopify moves its dashboards around. If a path below does not match what you see, the value you are
> looking for is still the one named — search the admin for it rather than assuming it is gone.

### 2. An app on that store, and the credentials it issues

The backend mints its Admin token from a **client-credentials grant** (`token.ts:50-58`), so you need
an app, not a legacy private-app password.

1. In the Partners dashboard (or the newer Shopify Dev Dashboard, if your account has it):
   **Apps → Create app**.
2. Set the Admin API scopes. Phase 5 fails without all of these:
   `write_products`, `write_inventory`, `write_publications`, `read_customers`, `read_orders`,
   `read_fulfillments`, `write_fulfillments`.
3. **Install the app on your development store.** The client-credentials grant only works against a
   store the app is installed on.
4. Collect, from the app's overview / API credentials page:
   - **Client ID** → `SHOPIFY_CLIENT_ID`
   - **Client secret** → `SHOPIFY_CLIENT_SECRET` *(secret)*
   - **Storefront API private token** (sometimes "delegate" or "headless" access token) →
     `SHOPIFY_STOREFRONT_PRIVATE_TOKEN` *(secret)*
5. **Shop ID** — visit `https://<your-store>.myshopify.com/account/login` and read the number out of
   the URL it redirects to (`shopify.com/authentication/<SHOP_ID>/login`). Only needed if you later
   turn on buyer OAuth; grab it while you are here.
6. **Do not** copy any credential from the production store into the dev environment, or vice versa.

### 3. Webhooks — one command, no secret to hunt for

There are two ways Shopify signs a webhook, and **the code already handles both**:
`shopifyWebhook` (`index.ts:154-159`) passes the client secret *and* the webhook secret to
`verifyShopifyHmac` (`webhooks.ts:39-57`), which tries each in turn. Only one has to be right.

So take the simple route: **register the webhooks from the app**, and the signing secret is the app's
**client secret** — the value you are already setting in step 2. There is no separate secret to find.
Set `SHOPIFY_WEBHOOK_SECRET` to that same value; it must exist in Secret Manager either way, because
`index.ts:151` declares it.

Registration happens with **`npm run webhooks:dev`** — a script this plan adds in Phase 0 (below). It
needs the deployed function URL, so **step 5 happens first**, then you come back and run it.

> If you ever add a webhook by hand in **Settings → Notifications**, that page shows its own signing
> secret and you would put *that* in `SHOPIFY_WEBHOOK_SECRET` instead. Two notes if you go looking:
> the secret does not appear until at least one webhook exists there, and newer admin versions have
> moved webhooks out of Notifications. You do not need any of this for the app-registered route.

### 4. Firebase — you already have the project, it just is not wired up

`firebase projects:list` shows one Little Blue project, **`little-blue-610e5`** ("little blue
market"), already the active one, with nothing live in it yet. So there is no second project to
create: **`little-blue-610e5` is your dev project.** A separate `prod` comes later, before launch —
the aliasing below is set up so adding it is one line.

1. **Create `.firebaserc` in the repo root.** It does not exist today, which is why
   `--project dev` failed with a 403 — Firebase resolved `dev` as a literal project id and found
   someone else's project:
   ```json
   {
     "projects": {
       "default": "little-blue-610e5",
       "dev": "little-blue-610e5"
     }
   }
   ```
   Add `"prod": "<new-id>"` when you create it. Commit this file — the names are shared, the ids are
   not secret.
   *(`firebase use --add` does the same thing interactively, if you prefer prompts.)*
2. In the console for `little-blue-610e5`: enable Authentication (Email link or Email/password, plus
   Anonymous for guests), Firestore, Storage and Functions. Functions needs the **Blaze** plan — free
   tier, but it wants a card on file.
3. Register the iOS and Android apps against **`com.littleblue.market`**. The Phase 0 rename has to
   land *first*, or the generated config files will not match the built app:
   ```
   flutterfire configure --project=little-blue-610e5 \
     --ios-bundle-id=com.littleblue.market \
     --android-package-name=com.littleblue.market
   ```
   One project for now means one `firebase_options.dart` and no `LBM_ENV` plumbing yet — that work
   moves to whenever `prod` is created, and Phase 0 only needs to leave room for it.
4. Sanity check before moving on:
   ```
   firebase use            # → dev (little-blue-610e5)
   ```

### 5. Wire the credentials in, and deploy once

Two mechanisms, and mixing them up is the usual mistake:

- **Params** (not secret — store domain, client id, API version) live in a **gitignored `.env` file**
  named for the **project id, not the alias**: `functions/.env.little-blue-610e5`. Firebase Functions
  reads it automatically at deploy for that project. There is no such file in the repo today, which is
  why `SHOPIFY_STORE_DOMAIN` has no deploy-time source.
- **Secrets** (client secret, storefront private token, webhook secret, Shipturtle keys) **never go in
  a file.** They go to Secret Manager:
  ```
  firebase functions:secrets:set SHOPIFY_CLIENT_SECRET --project dev
  ```
  It prompts for the value and does not echo it. Repeat per secret. `CLAUDE.md` makes this a hard
  rule: never write a token value into a file in this repo, a commit, a log, or a chat message.

  **`--project dev` only works once `.firebaserc` exists** (step 4.1). Without it you get a 403
  about `roles/serviceusage.serviceUsageConsumer` on a project called "dev" — which reads like a
  permissions problem and is actually a typo problem. Either create the alias first, or pass
  `--project little-blue-610e5` verbatim.

Then deploy so you have a webhook URL for step 3:
```
firebase deploy --only functions --project dev
```
The `shopifyWebhook` URL is printed at the end. Go back and finish step 3 with it.

### 6. Shipturtle on the dev store

1. Install **Shipturtle** on the development store from the Shopify App Store.
   *Unknown worth checking early:* dev stores sometimes cannot install paid apps, or install them in a
   restricted mode. If it refuses, that is worth finding out now rather than at Phase 6 — tell me and
   we will route Phases 1–5 around it, which the architecture already allows.
2. Create a vendor, and invite a vendor user at **an email you control** — this becomes your test
   seller for **A1** and **P1**.
3. Note the vendor's `company_id` (visible in the vendor panel, or via `/api/v1/me` while signed in as
   that vendor) and the exact Shopify `vendor` string it writes.
4. Set a commission so payout figures are non-zero when Phase 8 arrives.
5. **The API Integration add-on is optional and only Phase 8 needs it.** Buy it when you get to
   Phase 8, not now.

### 7. Issue yourself a claim code

Once Phase 1 ships, write one `vendorClaims/{sha256(code)}` document by hand with your test vendor's
name and `company_id`, redeem it in the app, and you have walked the whole grant path as both merchant
and seller. That is **S5** and **A1** in one pass.

### What this leaves blocked

Only **Phase 8** (the Shipturtle add-on), and only when you get there. Everything in Phases 0–7
becomes runnable by you alone.

---

# Secrets and decisions — fill this in

**Nothing is configured today.** Verified: there is no `.firebaserc` (no project is linked to this
repo at all), no `functions/.env*`, and therefore no secrets in Secret Manager. You are starting from
zero, not from a partial setup — so this list is complete, and nothing here is already done.

There is also **no `firebase functions:secrets:list`** — the CLI (v15.12.0) offers only `access`,
`get`/`describe`, `set`, `destroy` and `prune`, all of which require you to already know the name.
Listing them all needs `gcloud secrets list`, and gcloud is not installed. **This table is the source
of truth; there is nowhere to look it up.**

| Name | Kind | From | First needed |
|---|---|---|---|
| `SHOPIFY_STORE_DOMAIN` | param → `.env` | Step 1 | Phase 2 |
| `SHOPIFY_CLIENT_ID` | param → `.env` | Step 2 | Phase 3 |
| `SHOPIFY_API_VERSION` | param → `.env` | You choose — `2026-07` | Phase 2 |
| `SHIPTURTLE_BASE_URL` | param → `.env` | Default is fine | Phase 8 |
| `SHOPIFY_CLIENT_SECRET` | **secret** | Step 2 | Phase 3 |
| `SHOPIFY_STOREFRONT_PRIVATE_TOKEN` | **secret** | Step 2 | Phase 2 |
| `SHOPIFY_WEBHOOK_SECRET` | **secret** | = the client secret (step 3) | Phase 3 |
| `SHIPTURTLE_API_KEY` | **secret** | Step 6 | Phase 8 |
| `SHIPTURTLE_WEBHOOK_SECRET` | **secret** | Step 6 | Phase 8 |

**Five of the nine get you to Phase 5.** The two Shipturtle secrets wait for Phase 8 and
`SHIPTURTLE_BASE_URL` has a working default. Confirm one landed with
`firebase functions:secrets:get <NAME> --project dev`.

### Nothing from Firebase goes in the `.env`

Worth stating because it is the obvious assumption and it is wrong. `initializeApp()` at
`index.ts:32` takes **no arguments** — the runtime injects the project and credentials
(Application Default Credentials, `FIREBASE_CONFIG`, `GCLOUD_PROJECT`). That is also why `CLAUDE.md`
forbids creating a service-account key: there is nothing for one to do. There are exactly nine
`defineSecret`/`defineString` declarations in `config.ts` and none of them is a Firebase value.

Three config surfaces, and Firebase appears only in the third:

| | What | Where | Secret? |
|---|---|---|---|
| **1** | 4 Shopify/Shipturtle params | `functions/.env.<project-id>` | No, but gitignored |
| **2** | 5 Shopify/Shipturtle secrets | Secret Manager, via CLI | Yes — never a file |
| **3** | Firebase client config | `firebase_options*.dart`, `google-services.json`, `GoogleService-Info.plist` | **No — public by design**, committed. Security is in rules and App Check |

The `.env` exists only because Shopify and Shipturtle sit outside Google's world and have no ambient
credentials. An app talking only to Firebase would need no `.env` at all — which is why `--project`
is passed explicitly on every write command in this plan: it is the one place the project id appears.

*One prerequisite for Phase 2's checkout test:* it needs a product in the mirror carrying a real
Shopify variant id, and a fresh dev store will not have fired `products/create` for its seeded
products. Create one product by hand in the Shopify admin after registering webhooks — it mirrors
itself, and it exercises the webhook path before anything depends on it.

Save as **`functions/.env.little-blue-610e5`** — named for the project id, not the alias, because that
is how Firebase Functions finds it. **Confirm `functions/.env*` is in `.gitignore` before you put a
single value in it.** Lines marked *secret* must be **deleted from this file** and set with
`firebase functions:secrets:set` instead — they are listed here only so you have one checklist.

```dotenv
# ─── Params: safe in this file (gitignored, but not secret) ──────────────────

SHOPIFY_STORE_DOMAIN=
# From step 1. Format: your-dev-store.myshopify.com — no https://, no trailing slash.

SHOPIFY_CLIENT_ID=
# From step 2. The app's Client ID.

SHOPIFY_API_VERSION=2026-07
# config.ts currently defaults to 2025-07, which is a year stale. Phase 0 bumps the default;
# set it explicitly here too.

SHIPTURTLE_BASE_URL=https://api.shipturtle.com
# Default is fine. The vendor panel talks to api-v2.shipturtle.com — if the merchant API
# turns out to live there too, correct this when you get the token in Phase 8.


# ─── Secrets: DELETE these lines; use functions:secrets:set ──────────────────
#
#   firebase functions:secrets:set SHOPIFY_CLIENT_SECRET --project dev
#   firebase functions:secrets:set SHOPIFY_STOREFRONT_PRIVATE_TOKEN --project dev
#   firebase functions:secrets:set SHOPIFY_WEBHOOK_SECRET --project dev
#
# SHOPIFY_CLIENT_SECRET             step 2 — the app's Client secret
# SHOPIFY_STOREFRONT_PRIVATE_TOKEN  step 2 — Storefront private/delegate token
# SHOPIFY_WEBHOOK_SECRET            step 3 — set this to THE SAME VALUE as the client
#                                   secret. Not a mistake: webhooks the app registers are
#                                   signed with the client secret, and index.ts:151
#                                   requires this secret to exist regardless. The
#                                   verifier tries both, so the duplicate costs nothing
#                                   and keeps the second path live if you ever add a
#                                   webhook by hand in the Shopify admin.
#
# Phase 8 only, leave unset until then — fulfillment.ts self-disables cleanly without them:
# SHIPTURTLE_API_KEY                step 6 — merchant token, API Integration add-on
# SHIPTURTLE_WEBHOOK_SECRET         step 6 — Shipturtle's webhook signing secret


# ─── Not wired into config.ts today ──────────────────────────────────────────
# Contrary to the plan's "Credentials — status" section, these three are in your .env
# but have no param in config.ts and are read by nothing. Keep them somewhere safe;
# they are only needed if a later phase turns on buyer OAuth (defaulted to: no).
#
# SHOPIFY_STOREFRONT_PUBLIC_TOKEN
# SHOPIFY_SHOP_ID                     step 2.5
# SHOPIFY_CUSTOMER_ACCOUNT_CLIENT_ID
```

### Decisions — answer inline, or leave them and I take the default

```dotenv
# Q1. Checkout surface.
#     DEFAULT: flutter_inappwebview on checkoutUrl.
#     Alternative: native Checkout Sheet Kit via a platform channel — better UX, ~1 week more.
# ANSWER: Default

# Q2. Variants in Phase 5.
#     DEFAULT: single variant; variants arrive in Phase 6.
# ANSWER:Default

# Q3. Per-vendor Shopify location.
#     DEFAULT: shop default. You can now settle this yourself — after step 6, look at
#     Settings → Locations and tell me whether Shipturtle created one per vendor.
# ANSWER:Default

# Q4. Admin authorization (backfillCatalog, sellerRevokeVendor).
#     DEFAULT: an admin:true custom claim, reusing Phase 1's machinery.
# ANSWER:Default

# Q5. Notification surface in Phase 6.
#     DEFAULT: the listing's own status chip. No notifications collection yet.
# ANSWER:Default

# Q6. Revoked-seller token window (up to 1h).
#     DEFAULT: add a sellers/{uid} check to the seller() rules helper and close it.Default
# ANSWER:Default

# Q7. Image moderation on seller uploads.
#     DEFAULT: none beyond image-type and 10MB; merchant approval is the human gate.
# ANSWER:Default

# Q8. Buyer sign-in.
#     DEFAULT: Firebase Auth only, matched to Shopify by verified email.
#     Changing this later is a full OAuth build — the most expensive answer on this list.
# ANSWER:Default

# Q9. Tutorial-card copy (user-journeys.md L84-87).
#     DEFAULT: ship as written.
# ANSWER:Default
```

---

## Immediate — let the Shipturtle webhook run without a secret, and shout if it needs one

**Why now:** you are registering webhooks in Shipturtle today, and `SHIPTURTLE_WEBHOOK_SECRET` has no
known source — their Register-webhook dialog offers only Topic and URL, with no secret to paste or
reveal. Today `verifyShipTurtleSignature` (`shipturtle.ts:44`) returns `false` when the secret is
empty, so `shipturtleWebhook` rejects **100%** of traffic with a 401. The endpoint is unusable until
either the secret is found or this changes.

**The trick that makes it self-resolving:** if Shipturtle *does* sign, the signature arrives in a
header. A signature header present while we hold no secret is proof a secret exists somewhere — and
that is exactly the moment to log loudly. No guessing required; real traffic answers the question.

### The change

**1. Extract the decision into a pure function** in `functions/src/shipturtle.ts`, matching how
`webhooks.ts` keeps `verifyShopifyHmac` / `webhookTopic` pure and testable. Today the logic is inline
in `index.ts:264-284` and cannot be unit-tested.

```ts
export type ShipTurtleAuth =
  | { ok: true;  verified: boolean; alarm?: string; sawHeaders: string[] }
  | { ok: false; reason: string };

export function authenticateShipTurtleWebhook(
  rawBody: Buffer | string,
  headers: Record<string, string | string[] | undefined>,
  secret: string | undefined,
): ShipTurtleAuth
```

Behaviour, in order:

| Secret | Signature header | Result |
|---|---|---|
| set | valid | `{ok: true, verified: true}` |
| set | invalid or absent | `{ok: false}` → 401, unchanged from today |
| **empty** | **present** | `{ok: true, verified: false, alarm: …}` → **accept + `logger.error`** |
| empty | absent | `{ok: true, verified: false}` → accept + one `logger.warn` |

**2. Detect the header generically.** The code currently reads only `x-shipturtle-signature`
(`index.ts:267`), which is a guess. Collect every request header matching
`/^x-.*(sign|hmac|digest|secret|token)/i` plus any `x-shipturtle-*`, and report the **names** in
`sawHeaders`. Log names only, never values — a signature value is a credential-adjacent secret and
`CLAUDE.md` forbids writing those to logs. This is what tells us the real header name from live
traffic.

**3. The loud message.** It has to say what is wrong, what it costs, and the exact fix:

```
SHIPTURTLE SIGNS ITS WEBHOOKS AND WE ARE NOT VERIFYING THEM.
A signature header (x-…) arrived but SHIPTURTLE_WEBHOOK_SECRET is empty, so this
endpoint is accepting unverified writes to order documents. Anyone who guesses this
URL can mark any order shipped. Find the secret in Shipturtle → Settings → API
Integration, then:
  firebase functions:secrets:set SHIPTURTLE_WEBHOOK_SECRET --project dev
```

`logger.error`, so it surfaces in Cloud Logging error reporting rather than scrolling past in info.

**4. Say so in the data, not just the logs.** Pass `verified: false` through to `recordFulfillment`
and stamp it on the shipment. A shipment recorded from an unverified webhook should be *marked* as
such — otherwise the moment you find the secret you have no way to tell which existing rows were
trustworthy.

### What this trades away, stated plainly

This deliberately opens an unauthenticated write path to order documents, which is the precise thing
`shipturtle.ts:34-36` warns against: *"a public URL that writes to order documents, so an unverified
endpoint lets anyone mark anything shipped."* The blast radius is a forged shipment — a wrong tracking
number on an order, and a buyer's Receiving tab showing a parcel that does not exist. It cannot move
money, create products, or grant seller status.

That is acceptable on a dev project with no real users. **It is not acceptable in production**, so:

- Add a `TODO(prod)` at the accept-unverified branch.
- When the `prod` alias is created, gate the branch on project id — unverified accept in dev, hard
  401 in prod. Cheaper to write that guard now than to remember it later.
- The durable fix, better than a signature: treat the webhook as *notification only* — ignore the body
  and re-read the order from Shipturtle's API with your own token. A forged POST then costs one wasted
  API call instead of a fabricated shipment. Needs the Order API key, so it lands in Phase 8.

### Tests

Extend `functions/test/shipturtle.test.ts` (5 cases today) with four:

1. secret set + valid signature → `ok: true, verified: true`
2. secret set + wrong signature → `ok: false` *(existing behaviour must not regress)*
3. **empty secret + a signature header present → `ok: true, verified: false`, and `alarm` is set**
4. empty secret + no signature header → `ok: true, verified: false`, no `alarm`

Case 3 is the one that matters — it is the alarm working. Because the logic is now a pure function,
none of these needs the emulator.

### Files

`functions/src/shipturtle.ts` (new function, `verifyShipTurtleSignature` unchanged),
`functions/src/index.ts:264-284` (call it, do the logging), `functions/src/orders.ts`
(`recordFulfillment` takes `verified`), `functions/test/shipturtle.test.ts`.

**Verify:** `npx tsc --noEmit`, `npm test` (30 → 34). Then POST an unsigned body to the deployed
endpoint with `curl` — expect 200 and a warn; POST one with a junk `x-shipturtle-signature` header —
expect 200 and the loud error. Registering the real webhook then tells you which case you are in.

---

## Phase 0 — Reconcile and clear the decks

No new capability. Everything here is deletion or a one-line fix, and every later phase is cheaper
for it.

**Frontend**
- **Remove voting entirely** (`user-journeys.md` §2.4). `upvotes` from both models in
  `lib/models/models.dart`; `voteThread`/`voteThreadComment`/`voteForum` from
  `lib/data/repositories/repositories.dart` and both implementations
  (`firestore_social_repository.dart:508,594`, the fixture repo); arrows, score and tap handlers in
  `thread_screen.dart` and `forum_screen.dart`; `upvotes` in `mappers.dart`.
- Tests: delete the vote assertions. This is the sanctioned exception to "fix the cause, never the
  assertion" — `user-journeys.md` L310-313 pre-authorises it; say so in the commit.

**Backend**
- `match /votes/{uid}` under `threads` and its `comments`, plus `upvotes` from two `untouched` lists,
  out of `firebase/firestore.rules`.
- `config.ts`: bump `SHOPIFY_API_VERSION`'s default off `'2025-07'`; move `SHIPTURTLE_WEBHOOK_SECRET`
  (declared at :72) above `ALL_SECRETS` (:64-69), which silently omits it today.
- Add `postCount` to the `users/{uid}` update lock list — `firestore.rules:59` asserts `== 0` on
  create but `:63-69` never locks it, so a client can inflate its own post count.

**Rename the bundle ID to `com.littleblue.market`** — before anything is registered with Firebase,
because `GoogleService-Info.plist` and `google-services.json` are keyed to it and a mismatch fails at
runtime with errors that never mention the bundle ID. Five places, all found:

- `ios/Runner.xcodeproj/project.pbxproj` — `PRODUCT_BUNDLE_IDENTIFIER` at :375, :554, :576, plus the
  three `…app.RunnerTests` variants at :391, :408, :423.
- `android/app/build.gradle` — `namespace` (:9) and `applicationId` (:24).
- `android/app/src/main/kotlin/com/littlebluemarket/app/MainActivity.kt` — the `package` declaration
  on line 1, and the directory path itself.
- `lib/data/firebase/firebase_auth_service.dart:60,62` — `androidPackageName` and `iOSBundleId` are
  **hardcoded** in the email-link `ActionCodeSettings`. Easy to miss; breaks sign-in silently.
- Any Firebase app already registered under the old id becomes orphaned — register fresh.

One bundle ID for both environments, per your call: the app switches Firebase project at launch via
`LBM_ENV`, so only one build is installed at a time. Worth knowing the tradeoff you accepted — the app
on your phone gives no visual clue which backend it is talking to. If that bites, an in-app debug
banner is cheaper than retrofitting flavors later.

**Check email-link sign-in still works before Phase 1 depends on it.**
`firebase_auth_service.dart:58` points at `https://littlebluemarket.page.link/signin` — a **Firebase
Dynamic Links** URL, and Dynamic Links was shut down in August 2025. Phase 1's entire grant path rests
on `email_verified` being true, so if email-link sign-in is broken, Phase 1 cannot ship regardless of
what else works. Test this first; if it is dead, migrate to a Hosting-based action URL. **This is the
one thing in Phase 0 that could turn out to be real work rather than housekeeping.**

**Environment switching** — the tooling that makes a dev project cheap to use. Without it, "which
project am I pointed at" is answered by remembering, and someone eventually deploys dev secrets over
production.

- **Create `.firebaserc`** — it does not exist, and its absence is what makes `--project dev` fail
  with a misleading 403. Commit it; project ids are not secret:
  ```json
  { "projects": { "default": "little-blue-610e5", "dev": "little-blue-610e5" } }
  ```
  `prod` gets added before launch. Until then dev and default are the same project, deliberately.
- Confirm `.gitignore` covers `functions/.env*` **before** any value is written to one, alongside the
  entries `CLAUDE.md` already requires (`functions/lib/`, `functions/node_modules/`,
  `*-service-account*.json`, `firebase-debug.log`, `.firebase/`).
- `functions/.env.little-blue-610e5` for params — named for the project **id**, not the alias.
- `npm run` shortcuts in `functions/package.json` so the project is never implicit: `deploy:dev`,
  `secrets:dev`, each passing `--project` explicitly. Build the scripts to take the project as a
  variable now, so adding `prod` later is one line rather than a rewrite.
- **Defer the `LBM_ENV` dart-define and the second `firebase_options` file** until `prod` exists.
  One project means one config, and building a switch with one position is how you get a switch
  nobody trusts.

**`functions/scripts/register-webhooks.mjs`** — the other piece of setup tooling, and the one that
stops a whole class of silent failure. Registering six webhook subscriptions by hand is fine once and
error-prone every time after, and a webhook that quietly stops existing looks exactly like "nothing is
selling."

- Creates `products/create`, `products/update`, `products/delete`, `orders/paid` and the
  `fulfillments/*` subscriptions against the deployed `shopifyWebhook` URL, via
  `webhookSubscriptionCreate` through the existing `adminGraphQL` helper (`token.ts:137`) — no new
  credential path.
- **Idempotent**: reads `webhookSubscriptions` first, creates only what is missing, and prints a table
  of already-present / created / failed. Safe to run on every deploy.
- Run as `npm run webhooks:dev` / `webhooks:prod`, with the target URL and project explicit.
- It replaces the vaguest item on the pre-deploy checklist. "Confirm the webhook subscriptions still
  point at the deployed function" becomes "run the script and read the table."

**The commands, in one place:**

```bash
firebase projects:list                 # what you have access to, and which is current
firebase use --add                     # alias a project interactively (or write .firebaserc by hand)
firebase use dev                       # switch the default target
firebase use                           # ← print the active alias. Run before every deploy

firebase functions:secrets:set NAME --project dev     # prompts; never echoes; never a file
firebase functions:secrets:get NAME --project dev     # confirm it exists (metadata only)
firebase functions:secrets:access NAME --project dev  # prints the value — careful where
npm run deploy                                        # tsc FIRST, then deploy — see note below
firebase deploy --only firestore:rules,storage --project dev
firebase emulators:start                              # local, no project needed
npm run seed                                          # fixture content into the running emulator
```

```bash
flutter run --dart-define=LBM_BACKEND=fixtures        # no backend at all
flutter run --dart-define=LBM_BACKEND=live            # little-blue-610e5 + your dev Shopify store
```

Always pass `--project` on anything that writes. `firebase use` sets a default that persists across
terminal sessions, which is convenient right up until it is not.

**Never run bare `firebase deploy --only functions`.** It does not compile TypeScript, and
`package.json` points `main` at `lib/index.js` — so it fails with *"functions\lib\index.js does not
exist"*, which reads like a missing file and is actually a missing build. `npm run deploy` runs `tsc`
first. Same trap with the emulator: `npm run serve`, not `firebase emulators:start --only functions`.

**Every secret named in a `secrets: [...]` array must exist before deploy** — even one the function
never reads. `SHIPTURTLE_API_KEY` and `SHIPTURTLE_WEBHOOK_SECRET` are declared in `index.ts` but not
needed until Phase 8, so set them **empty** now. `fulfillment.ts:76` guards on `if (!key)` and returns
early, which is exactly how that code expects to be told Shipturtle is unconfigured:
```
printf '' | firebase functions:secrets:set SHIPTURTLE_API_KEY --project dev --data-file -
```

**Node 20 is deprecated** (2026-04-30) and decommissioned **2026-10-30** — about eight weeks out. Bump
`functions/package.json` `engines.node` and `firebase.json` `runtime` to 22 during Phase 0, rather
than being forced mid-phase in October. `firebase-functions` is also a major version behind, with
breaking changes; do that one deliberately and on its own.

**There is no `firebase functions:secrets:list`.** Confirmed against CLI v15.12.0 — you get `access`,
`get`/`describe`, `set`, `destroy` and `prune`, every one of which needs the name up front. The nine
names in the table above are the only record of what should exist.

**Done when** `flutter analyze` clean, `flutter test` green with a lower count, `npm run test:rules`
green, and `firebase use dev` / `firebase use prod` both round-trip.

---

## Phase 1 — Selling is a grant, not a checkbox

**Ships:** a person becomes a seller by redeeming a claim code, and cannot become one any other way.
**This closes a live privilege-escalation hole and goes before everything else.**

### 1a — Frontend (fixtures)

- **Contract first.** In `lib/data/repositories/repositories.dart`: delete `becomeSeller()` (:182);
  add `Future<SellerGrant> requestSellerStatus(String claimCode)` and a `SellerGrant` /
  `SellerGrantFailure` result type in `lib/models/` — invalid code, already used, expired, vendor name
  already claimed, email not verified. Each needs its own copy; a generic failure here reads as "the
  app is broken."
- **Claim screen.** A new route replacing the "Start selling" row in `edit_profile_screen.dart:294-305`
  and `_startSelling()` (:266-275) with its "Selling is on. Your storefront is live." message. Build it
  from `LbmField` + `PillButton` (`widgets/primitives.dart`) inside `LbmScreen`; explain where a code
  comes from, since a seller who does not have one needs to know who to ask.
- **Fixture implementation** in `fixture_repositories.dart` (replacing :979-985): a canned valid code,
  one already-used, one expired, one whose vendor name is taken — so all four failure paths are
  reachable in the fixtures backend and in tests.
- **Tests:** replace `fixture_repositories_test.dart:434-436`; add the claim route to
  `screens_smoke_test.dart` and `text_scaling_test.dart`; a widget test per failure state.
- `isSellerProvider` (`session.dart:128-131`) and `requireSeller()` (`sheets.dart:158-173`) keep their
  signatures — only their *source* changes in 1b, so nothing downstream is touched.

### 1b — Backend

- Collections and rules per §3/§8: `sellers/{uid}`, `vendorNames/{normalizedName}`,
  `vendorClaims/{sha256(code)}` — all `allow write: if false`, `vendorClaims` also `read: if false`.
  Add the `seller()` helper beside `member()`.
- `sellerClaimVendor` callable: verify `email_verified`, consume the claim code, reserve the vendor
  name, write `sellers/{uid}`, `setCustomUserClaims(uid, {seller: true, vendor})`, write
  `_internal/sellerAudit/{id}` — **one transaction, or none of it**.
- **Delete `linking.ts:47`'s `isSeller: true` write.** §4's table still credits `linkAccounts` with
  granting seller status; if this write survives, the hole survives with it.
- Client-side: `getIdToken(true)` after a successful grant, or the Products tab waits up to an hour.
- **Close the revocation gap the doc leaves open:** `seller()` reads only the custom claim, so a
  revoked seller keeps `listings/` write access until their token refreshes. Either add a
  `sellers/{uid}` existence check to the helper or accept it explicitly — do not leave it undecided.
- Rules tests in `functions/test/rules.test.mjs`: a client cannot write `sellers/`, `vendorNames/`,
  `vendorClaims/`, `isSeller`, or `postCount`.

**Manual test** (emulator, `npm run seed`): sign in; try `users/{uid}.set({isSeller:true})` from the
client → denied; redeem a seeded code → `sellers/{uid}` appears, token carries `seller: true`,
Products tab appears without a restart; redeem the same code twice → second fails; two accounts race
the same vendor name → exactly one wins.

---

## Phase 2 — Checkout actually opens

**Ships:** tapping Buy reaches Shopify's checkout. Small, almost entirely frontend, and it unblocks
manual verification of every commerce phase after this one.

### 2a — Frontend

- Add `flutter_inappwebview` (or a platform channel around Shopify's native Checkout Sheet Kit — a
  decision, see "Things I need from you"). Replace the SnackBar at `sheets.dart:236` with a webview on
  `checkoutUrl`, watching for the thank-you URL.
- The post-checkout screen says **"we'll confirm shortly"** and never asserts success — `orders/paid`
  is the only truth that money moved (`CLAUDE.md`, §7).
- Tests: the webview cannot render in a widget test; test the URL-matching logic as pure Dart and keep
  the screen behind a thin wrapper so the smoke test still passes.

### 2b — Backend

Nothing new. `commerceBeginCheckout` (`cart.ts:209`) and `orders/paid` → `recordPaidOrder`
(`orders.ts:165`) already exist and are tested.

**Manual test:** add to cart, check out on the dev store, pay with a Shopify test card; within seconds
the buyer's purchase count increments and the item appears under "Bought & received". Then replay the
same `orders/paid` payload with `curl` and confirm the counters do **not** double.

---

## Phase 3 — Your shop is already there (Journey A)

**Ships:** an existing vendor signs in and her products are on her profile. She never tells the app
she is a seller.

### 3a — Frontend

- The Products tab on the profile reads `CatalogRepository.productsBySeller`
  (`repositories.dart:43`) — it exists and is already wired through `sellerProductsProvider`
  (`providers.dart:45-52`). What is missing is honest **empty / loading / error** states via
  `LbmAsync`, and the fixture data to drive them.
- Fixtures gain a seller with products, a seller with none, and a buyer — so "no products yet" is a
  designed state rather than a blank grid.
- `ListingComposer` (`composers.dart:424-542`) needs no rewrite. Contrary to §6 step 12, it is already
  reachable — `showNewPostSheet` (:21,43) is gated on `isSellerProvider` and wired to
  `profile_screen.dart:90`. It is *empty*, not unreachable, and this phase is what fills it.

### 3b — Backend

- **`mirrorProduct` must persist the raw `payload.vendor` string** on the catalog document
  (`catalog.ts:47-73` writes only the resolved uid today). One field, and the prerequisite for
  everything else in this phase.
- `resolveSellerForVendorName`: a Firestore trigger on `sellers/{uid}` that backfills
  `catalog.sellerId` for that vendor's products and calls `forgetVendorCache()` (`vendors.ts:127`,
  which has zero callers today).
- Stop caching misses in `resolveSellerUid` (`vendors.ts:62-66` caches `''` forever on a warm
  instance).
- `backfillOrders`: pass `lineItems.vendor` through. It is already queried at `linking.ts:114` and
  thrown away at `:164` (`sellerId: ''`), so a buyer's history dead-ends.
- Indexes: `listings: sellerUid + updatedAt DESC` and `catalog: collectionHandles CONTAINS +
  createdAt DESC`. **Skip the doc's `catalog: vendorName ASC`** — Firestore auto-indexes single
  fields.

**Manual test:** seed `catalog` with products carrying a known vendor string; grant that vendor via a
claim code; watch `sellerId` populate; confirm the Products tab fills without a restart. Then place a
website order under a known app user's email and confirm it attributes — that is the regression that
would hurt real users.

---

## Phase 4 — The real catalog and the real taxonomy

**Ships:** all ~2,500 products in the mirror, and initiatives (`Ally Owned`, `BIPOC Owned`) backed by
the store's 92 real collections.

### 4a — Frontend

- A `Collection` model and `CollectionRepository`, plus the collection picker the composer will need
  in Phase 5 and the initiative browse surface in the market.
- Fixture collections matching the real taxonomy shape, so the picker is exercised by smoke tests
  before `syncCollections` exists.
- `typeSlug`-based filtering comes out of the search UI — `product_type` is `"physical"` across the
  entire store, so it buckets everything into one meaningless slug.

### 4b — Backend

- `syncCollections` (scheduled + callable) → `collections/{handle}`, storing **id** as well as handle:
  `ProductSetInput.collections` takes GIDs, not handles, and Phase 5 needs to resolve one to the other.
- `backfillCatalog`: `bulkOperationRunQuery` for the ~2,500 products. Two things the doc omits and
  this will fail without — **a shape adapter** (`mirrorProduct` parses REST payloads: `body_html`,
  `images[].src`, `tags` as a comma-separated string, while the bulk operation returns GraphQL
  shapes; one mapper, or half the catalog gets a different field set), and **batching with a resume
  cursor** for ~5,000 document writes across `catalog` + `spec/detail`.
- Fix `mirrorProduct` to categorise from collections rather than `product_type`, and to stop
  discarding every tag lacking a `#` (`catalog.ts:34-38` keeps only `#`-prefixed tags, so real tags
  like `"feminist gift"` vanish and every mirrored product gets `tags: []`).
- Admin authorization for `backfillCatalog` — reuse Phase 1's custom-claim machinery with
  `admin: true` rather than inventing a second mechanism.

**Manual test:** run the backfill against the dev store; compare the document count to
`products.json`; spot-check a product with variants, one with several collections, one with non-`#`
tags; re-run it and confirm it is idempotent.

---

## Phase 5 — Adding a product (Journey B)

**Ships:** a seller adds a product from the composer and it goes to the merchant's approval queue.

### 5a — Frontend

- **Contract first:** `SellerRepository` in `lib/data/repositories/` (pure Dart — no `firebase_*`, no
  Shopify), with `saveDraft`, `publishListing`, `watchDrafts`; a `Listing` draft model with money as
  `int` cents from the first keystroke.
- The composer's product section, built from existing primitives — photos, title, description, price,
  quantity, SKU, weight, dimensions, collections, tags. **Single variant for this phase**; the
  `listings` schema in §3 is flat while the UI list and the `productSet` call both assume variants,
  and that contradiction has to resolve one way. Variants land in Phase 6 with `sellerUpdateListing`.
- The **Under review modal** (§6 step 7) — a modal, not a snackbar, because this is the one moment the
  seller's mental model diverges from what happened.
- An image-upload helper generalised from the avatar path
  (`firestore_profile_repository.dart:125-129`, `putData` → `getDownloadURL`).
- Fixture implementation covering draft → submitting → submitted → failed, so the retry button and
  every status chip are testable before a function exists.
- Tests: new composer routes in `screens_smoke_test.dart` and `text_scaling_test.dart`; the product
  form must survive 2.0 text scale and 390-wide without overflow.

### 5b — Backend

- `listings/{listingId}` rules per §8, and the `listings/{uid}/{file}` Storage rule reusing
  `isImage()` / `underSize()` (`storage.rules:14,18`). **Public read is required** — Shopify fetches
  `files[].originalSource` server-side and a signed URL will not work.
- `sellerPublishListing`: the three-fact seller check (custom claim, live `sellers/{uid}`,
  `vendorNames` ownership), server-side re-read of every value, transactional `submitting` guard,
  `app.draft_id` metafield adoption for idempotency, one `productSet` with `inventoryQuantities`
  inline, then the mirror seed.
- **The vendor name goes to Shopify from `sellers/{uid}`, never from the request** — that string
  assigns every future sale.
- Two doc errors to not implement: §6 step 6 reads `users/{uid}.shopifyLocationId` (§3 moved it to
  `sellers/{uid}`), and §6 step 9 plus the failure table still reference `publishablePublish`, which
  step 7 removed from this function entirely.

**Manual test** (dev store): publish a draft → product appears as `DRAFT`, unpublished, carrying the
right `vendor` and `draft_id`; kill the function mid-call and retry → one product, not two; publish
with a bad price → `status: 'failed'` with a readable error; confirm Shopify fetched the Storage image.

---

## Phase 6 — Approval, edits, and honest numbers

**Ships:** the seller learns her listing went live, can edit and restock it, and sees a number that is
actually true.

### 6a — Frontend

- Status chips on the Products tab (Under review / Live / Rejected), pull-to-refresh, merchant remarks
  when there are any, and the 14-day "still with the merchant" note with its Nudge action.
- An edit-listing screen reusing the Phase 5 form.
- **`revenueCents` → `grossSalesCents`, labelled "Total sales"** across `mappers.dart`,
  `models.dart`, `profile_screen.dart`, `edit_profile_screen.dart` and the fixtures. Show no payable
  figure at all until Shipturtle's payout API exists — "revenue" and "earnings" both promise money;
  "Total sales" is exactly what the number is.

### 6b — Backend

- The approval branch in `mirrorProduct` (read `app.draft_id`, flip `submitted` → `live` / `rejected`)
  and `sellerRefreshListings` as the pull-side fallback, batched to one Admin query per 50 ids and
  rate-limited to one refresh per listing per 60s.
- **Decide the notification surface.** §6a says "write a notification document" and no collection,
  rules or function defines one. Recommend: the listing's own status chip *is* the notification for
  this phase; defer a notifications collection until there is a second thing to notify about.
- `sellerUpdateListing` via `productVariantsBulkUpdate` + `inventorySetQuantities` — **never
  `productSet`**, which deletes any variant or option you omit. `sellerArchiveListing`.
- `grossSalesCents` in `orders.ts` and the rules lock list.

**Manual test:** approve a listing in the Shipturtle panel → the chip flips without a restart; approve
one with the webhook disabled → pull-to-refresh catches it; edit a product with two variants and
confirm neither is deleted; restock and confirm the quantity lands at the right location.

---

## Phase 7 — The journey changes

**Ships:** `user-journeys.md`'s remaining product decisions — the cart replaces the like, cart posts,
and review prompts.

### 7a — Frontend

- `PostActionBar` drops `liked`/`onLike`; three actions become **Add to cart · Comment · Repost**;
  the count line becomes "*N* added · *M* comments".
- The tutorial card ("♡ is now 🛒"), marked required rather than optional in `user-journeys.md`
  L81-88 — in first-run onboarding *and* as a one-time tip on first card tap.
- `CartPost` as a sealed-class variant, the Cart tab on the profile, and the delivered → review
  prompt.

### 7b — Backend

- `catalog/{id}/carted/{uid}` plus `inCartsCount` (live, decrements) and `saveCount` (monotonic),
  written **only** by `commerceAddLine`/`commerceRemoveLine` via the Admin SDK — the count is now a
  public signal sellers read. Name it `inCartsCount`, never `cartCount`: `cartCountProvider` already
  means "items in *my* cart".
- `commerceAddManyLines`, `onReviewWritten`.
- **Rules for `posts` where `kind == 'cart'`** — the ≤24-item frozen array is fully specified in
  `user-journeys.md` L154-163 and has no rules drafted anywhere. `carts/{uid}` stays private; a cart
  *post* is a copy.

**Manual test:** add to cart from a feed card → the public count moves and the marker appears; remove
→ `inCartsCount` drops, `saveCount` does not; check out → the marker converts; post a cart of 30 items
→ rejected at 24.

---

## Phase 8 — Shipturtle

Blocked on the paid API Integration add-on. Automatic `findVendor` (replacing claim codes as the
primary path), payout figures, approval status with remarks, and the real fulfilment endpoint in place
of the placeholder at `fulfillment.ts:64-108` — which posts to an unconfirmed URL today and
self-disables when the key is unset. Nothing before this phase depends on it.

---

## What remains blocked

Owning the test store and the Shipturtle instance dissolves most of the original blocker list — you
become the merchant, so you issue your own claim codes, approve your own listings, register your own
webhooks and read your own Locations page. What is left:

1. **The setup walkthrough above must be finished before Phase 5.** Phases 0–2 need only the Firebase
   dev project (step 4); Phase 3 onward needs the Shopify store and app.
2. **Shipturtle's API Integration add-on** — *blocks Phase 8 only, and only when you reach it.*
3. **One unknown to test early:** whether Shipturtle installs on a Shopify development store, and in
   what mode. Check it at setup step 6, not at Phase 6. If it will not install, Phases 1–5 route
   around it and Phase 6's approval flow needs rethinking — better to know in week one.
4. **The nine decisions** in the block above. All have defaults; none blocks work starting.

One thing worth saying plainly: **your dev store will not have the production store's 2,500 products
or 92 collections.** Phase 4's backfill will run correctly against a smaller catalog, which proves the
code but not the scale. Before that code touches production, re-run **C1** and **C4** there — a
resume cursor that works over 40 products and one that works over 2,500 are not the same claim.

---

## Critical files

**Frontend:** `lib/data/repositories/repositories.dart` (interfaces, pure Dart),
`lib/data/fixtures/fixture_repositories.dart`, `lib/data/firebase/firestore_*_repository.dart` +
`mappers.dart`, `lib/state/{providers,session}.dart`, `lib/widgets/{composers,sheets,primitives,
post_card}.dart`, `lib/screens/you/{edit_profile,profile,shipping}_screen.dart`,
`lib/models/{models,post,formatting}.dart`.

**Backend:** `functions/src/{config,catalog,vendors,linking,orders,cart,fulfillment}.ts`,
`functions/src/shopify/token.ts` (`adminGraphQL` at :137 — the only door to Admin),
`firebase/{firestore.rules,storage.rules,firestore.indexes.json}`.

**Reuse rather than rebuild:** `LbmAsync` and the skeletons; `widgets/primitives.dart`'s vocabulary;
`requireSeller()` at `sheets.dart:158-173`; the avatar upload at
`firestore_profile_repository.dart:125-129`; `forgetVendorCache()` at `vendors.ts:127`;
`functions/scripts/seed.mjs` for emulator content.

## Verification — the automated half

### The four layers, and what each is for

Each layer catches something the one below it cannot. The rule for deciding where a test belongs:
**if it can be tested without Shopify, it must be** — leaving it to the manual pass means it only runs
when someone remembers.

| Layer | Command | Runs against | Catches |
|---|---|---|---|
| **1. Unit** | `npm test` (`functions/`) | Nothing — mocked Admin API | Logic: money math, normalisation, HMAC, input construction, state transitions |
| **2. Rules** | `npm run test:rules` | Firestore emulator | The security boundary. Every "a client cannot…" claim |
| **3. Integration** | `npm run test:integration` *(new)* | Firestore + Auth emulators, recorded Shopify responses | Wiring — does the trigger fire, does the transaction hold, is the retry idempotent |
| **4. Manual** | the checklist below | Shopify dev store | Only what Shopify's real behaviour decides |

30 unit tests and 18 rules tests exist today. Layer 3 does not exist yet and is the one this plan adds.

**Match the existing toolchain, do not introduce a runner.** `functions/` is TypeScript compiled by
`tsc` to CommonJS in `lib/` (Node 20, `strict`, `noUncheckedIndexedAccess`), and it uses **Node's
built-in test runner** — `node --test --experimental-strip-types "test/*.test.ts"` for units, and
`firebase emulators:exec --only firestore "node --test test/rules.test.mjs"` for rules. No Jest, no
Vitest. So layer 3 is:

```json
"test:integration": "firebase emulators:exec --only firestore,auth \"node --test --experimental-strip-types test/integration/*.test.ts\""
```

Note the source imports carry `.ts` extensions (`from './cart.ts'`) because `tsconfig.json` sets
`allowImportingTsExtensions` + `rewriteRelativeImportExtensions`. Deliberate — write new imports the
same way.

**One unknown to resolve before Phase 4:** `functions/package.json` depends on a local
`@dataconnect/admin-generated` — **Firebase Data Connect** is wired into this codebase and neither
planning document mentions it. If it is live in production it is a fifth system with opinions about
who owns what, and Phase 4 writes ~5,000 documents. Find out what it is doing before then.

### What to write, by phase

**Phase 0**
- Rules: `postCount` rejected on update (it is only zero-checked on create today).
- Rules: the deleted vote rules no longer grant anything.

**Phase 1 — the security phase, and the most test-worthy in the plan**
- Rules, one case each: a client cannot write `sellers/`, `vendorNames/`, `vendorClaims/`; cannot
  *read* `vendorClaims/`; cannot set `isSeller` or `shopifyVendorName` on its own user doc; cannot
  create a user doc that already carries `isSeller: true`; cannot write a `listings/` document it does
  not own, nor set `status` or `shopifyProductId` on one it does.
- Unit: claim code is hashed before lookup (the raw code is never stored or logged); an unverified
  email is rejected; a used code is rejected; an expired code is rejected; a taken vendor name is
  rejected; the audit record is written on both grant and revoke.
- Integration: **two concurrent claims on the same vendor name — exactly one wins.** This is the test
  that justifies the transaction, and a unit test cannot express it.
- Integration: after a grant, the ID token carries `seller: true` and `sellers/{uid}` exists — or
  neither does. No partial grant.

**Phase 3**
- Unit: `mirrorProduct` persists the raw `vendor` string; `resolveSellerUid` does **not** cache a miss
  (the current `Map` at `vendors.ts:62-66` caches `''` forever on a warm instance); `backfillOrders`
  passes `lineItems.vendor` through instead of hardcoding `sellerId: ''`.
- Integration: writing `sellers/{uid}` fires `resolveSellerForVendorName`, which backfills
  `catalog.sellerId` for that vendor and calls `forgetVendorCache()`.

**Phase 4**
- Unit, and the highest-value test in this phase: **the REST payload and the GraphQL bulk payload for
  the same product produce byte-identical `catalog` documents.** Two code paths writing one collection
  is exactly how half a catalog ends up with a different field set.
- Unit: non-`#` tags survive; category comes from collections, not `product_type`.
- Integration: the backfill is idempotent — run it twice, document count and content unchanged; and it
  resumes correctly from a cursor after being interrupted mid-run.

**Phase 5**
- Unit: the three-fact seller check fails when *each* fact fails independently — claim missing,
  `sellers/{uid}` revoked, `vendorNames` owned by someone else. Three separate tests, not one.
- Unit: **a client-supplied price in the request is ignored**; every value comes from the draft.
- Unit: the `vendor` sent to Shopify is read from `sellers/{uid}` and never from the request.
- Unit: `productSet` input is well-formed — `inventoryQuantities` present on create, `draft_id`
  metafield set, collection handles resolved to GIDs.
- Integration: a second call with the same `listingId` adopts by `draft_id` rather than creating a
  second product; a `productSet` userError leaves `status: 'failed'` with a readable message and no
  orphaned Shopify product.

**Phase 6**
- Unit: `sellerUpdateListing` never calls `productSet` — assert on the mutation name. This is a
  one-line test guarding a mistake that silently deletes a seller's variants.
- Unit: every approval transition is a no-op when already applied.
- Unit: the refresh rate limit returns early rather than erroring, so pull-to-refresh always feels
  like it worked.

**Phase 7**
- Rules: `catalog/{id}/carted/{uid}` is not client-writable; a cart post with 25 items is rejected.
- Unit: `saveCount` never decrements; `inCartsCount` does; checkout converts the marker rather than
  clearing it.

**Owed regardless of phase** — `CLAUDE.md` names the Admin token broker as a single point of failure
for every seller feature, and it currently has no tests: cache hit, refresh at expiry, 401-retry-once,
and concurrent cold-start hitting the transaction. If minting breaks, product listing, product
creation and order lookup all break at once and it looks like "the seller tab is broken."

### One deliverable that makes the manual pass runnable

Phase 1 should ship **`npm run verify:security`** — a script in `functions/scripts/` that signs in as
an ordinary test user, attempts each forbidden write in turn, and prints PASS/FAIL per line. The
security tests are the highest-stakes ones and the least practical to do by hand; this turns tests
S1–S6 below into one command.

---

## Manual tests — the list you run

Automated tests cover everything that does not need Shopify. These are the ones that do, plus the
few where a human has to look at the screen. Run each group after the phase that ships it.

**Setup:** the emulator (`firebase emulators:start`, then `npm run seed`) for anything marked
*emulator*; the Shopify dev store for anything marked *dev store*. Where both are listed, run the
emulator first — it is faster and failures there are cheaper.

### Group S — Security (after Phase 1)

*Most of these are `npm run verify:security`. Run them by hand once anyway, so you have seen it.*

| # | Test | Expect |
|---|---|---|
| **S1** | *emulator* — Signed in as a normal user, try to set `isSeller: true` on your own user document from the client | **Denied.** Before Phase 1 this succeeds — worth doing once on the old code so you can see the hole close |
| **S2** | *emulator* — Try to set `shopifyVendorName: "Gwynstone"` on your own user document | **Denied** |
| **S3** | *emulator* — Try to write to `sellers/{yourUid}`, `vendorNames/gwynstone`, `vendorClaims/anything` | **Denied**, all three |
| **S4** | *emulator* — Try to *read* `vendorClaims/` | **Denied.** Readable claim codes are the same as no claim codes |
| **S5** | *emulator* — Redeem a valid claim code, then redeem the same code again | First succeeds; second fails with "already used". Check `_internal/sellerAudit` has exactly one record |
| **S6** | *emulator* — Two accounts redeem two different codes naming the same vendor | Exactly one gets the vendor name; the other gets a clear "already claimed" message |
| **S7** | *emulator* — Sign in with an **unverified** email and try to claim | Rejected with `failed-precondition` |
| **S8** | *emulator* — Call `sellerClaimVendor` passing **someone else's email** as a parameter | Ignored entirely in favour of the verified token claim. *This is the spoofing regression; it is the single most important test in this list* |
| **S9** | *emulator* — Grant seller status, then confirm the Products tab appears **without restarting the app** | Appears within a second or two. If it takes an hour, `getIdToken(true)` is not being called |

### Group A — Attribution (after Phase 3)

| # | Test | Expect |
|---|---|---|
| **A1** | *dev store* — Grant a vendor whose products already exist in the mirror | Her Products tab fills. Before this phase it is empty forever |
| **A2** | *dev store* — Check a mirrored product document | It carries the raw `vendor` string, not just a resolved uid |
| **A3** | *dev store* — Place an order **on the website** using a known app user's email | It lands on their app profile under "Bought & received". *This is the regression that would hurt real users* |
| **A4** | *dev store* — Sign in as a real existing website customer who has never used the app | No signup form; name and addresses prefilled; past orders visible immediately |
| **A5** | *dev store* — Place an order, then check the seller's profile | Their sales figure rises by the correct **line** amount — not the order total |

### Group C — Catalog (after Phase 4)

| # | Test | Expect |
|---|---|---|
| **C1** | *dev store* — Run the backfill, then compare the document count against `products.json` | Matches. Investigate any shortfall rather than accepting it |
| **C2** | *dev store* — Spot-check three products: one with variants, one in several collections, one with only non-`#` tags | All three complete. The third is the one that currently loses every tag |
| **C3** | *dev store* — Run the backfill a second time | Idempotent — no duplicates, no changed content |
| **C4** | *dev store* — Interrupt the backfill mid-run, then restart it | Resumes from where it stopped; does not start over and does not skip |
| **C5** | *app* — Browse an initiative (`Ally Owned`, `BIPOC Owned`) | Real products, from real collections |

### Group P — Publishing a product (after Phase 5)

| # | Test | Expect |
|---|---|---|
| **P1** | *dev store* — Publish a draft from the app | Product appears in Shopify as **DRAFT, unpublished**, with the right `vendor` and a `draft_id` metafield. It must **not** be live |
| **P2** | *dev store* — Confirm Shopify actually fetched the photo | The image shows on the Shopify product. If it does not, the Storage rule is not public-read |
| **P3** | *dev store* — Publish, kill the app mid-call, reopen and retry | **One product, not two.** Run this twice; it is the failure real sellers will hit on bad hotel wifi |
| **P4** | *app* — Publish with a price of 0, and again with no photo | Rejected before Shopify is touched, with a message that says what to fix |
| **P5** | *dev store* — Check the opening stock | Set correctly, at the expected location, in one call |
| **P6** | *app* — Read the Under review modal as if you were a seller | Does it explain why the thing you just added is not in your shop? If it does not, you will get support tickets |
| **P7** | *dev store* — Have a non-seller account attempt to publish | **Denied.** Try it with a revoked seller too |

### Group R — Review and edits (after Phase 6)

| # | Test | Expect |
|---|---|---|
| **R1** | *dev store* — Approve a listing in the Shipturtle panel | The chip flips to Live in the app within seconds, no restart |
| **R2** | *dev store* — Approve one with the webhook temporarily disabled, then pull-to-refresh | Caught by the pull path. *This is the fallback that stops a seller losing trust in the app* |
| **R3** | *dev store* — Reject a listing with a remark | The app shows `rejected` **and the merchant's reason**. A rejection with no reason is worse than no rejection |
| **R4** | *dev store* — Edit a product that has two variants | **Neither variant is deleted.** This is the `productSet`-on-edit trap; check it every time the edit path changes |
| **R5** | *dev store* — Restock a live listing | Quantity lands at the right location |
| **R6** | *app* — Look at the seller profile figure | Reads "Total sales", not "Revenue" or "Earnings", and no payable amount is shown anywhere |

### Group M — Money and counters (after Phases 2 and 7)

| # | Test | Expect |
|---|---|---|
| **M1** | *dev store* — Buy something end to end with a Shopify test card | Purchase count increments, item appears under "Bought & received", seller's sales rise. The post-checkout screen says "we'll confirm shortly" and does not claim success |
| **M2** | *dev store* — Replay the same `orders/paid` webhook payload twice with `curl` | **Counters do not double.** Run this after any change to `orders.ts` |
| **M3** | *dev store* — Send a webhook with a deliberately wrong HMAC signature | Rejected |
| **M4** | *app* — Add a feed item to your cart | The public "added" count moves; the marker appears |
| **M5** | *app* — Remove it again | `inCartsCount` drops; the "added" count does **not** — that one only ever climbs |
| **M6** | *app* — Buy it | The marker converts rather than disappearing |
| **M7** | *app* — Post a cart of 30 items | Rejected at 24 |

### Before every deploy — the five-minute pass

1. `flutter analyze` clean, `flutter test` green, `npm test` and `npm run test:rules` green.
2. `npm run verify:security` — all PASS.
3. **S8** (email spoofing) and **M2** (webhook replay) by hand.
4. Open the app on `LBM_BACKEND=fixtures` and walk one screen from the newest phase.
5. `npm run webhooks:dev` — it is idempotent, so on a healthy deploy it creates nothing and prints six
   already-present rows. Anything else means a subscription went missing, which looks exactly like
   "nothing is selling."

### Per-phase gate

- **(a)** `flutter analyze` clean, `flutter test` green, new routes in `screens_smoke_test.dart` and
  `text_scaling_test.dart`, app runnable on `LBM_BACKEND=fixtures`. The point of the split is that
  the phase is demoable before any backend exists.
- **(b)** `npx tsc --noEmit`, `npm test`, `npm run test:rules`, `npm run test:integration`, then that
  phase's manual group — emulator first, dev store second.

Then commit and push to `main`, per `CLAUDE.md`.
