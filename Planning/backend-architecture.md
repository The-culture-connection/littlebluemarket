# Backend architecture — Firebase as the seam between the app, Shopify and Shipturtle

Companion to `Planning/i-have-a-prototype-vivid-dongarra.md` (scope and sequence),
`Planning/identity-and-catalog.md` (who authenticates how, and how products map to sellers) and
`Planning/user-journeys.md` (what a person does, screen by screen).
This one answers a narrower question: **when the app writes something, which box does what, in what
order, and who is allowed to be wrong.**

Everything asserted about the live systems was read off them on 2026-09-04 — the Shopify storefront,
the Shipturtle vendor panel at `vendors.littlebluemarket.com`, and Shipturtle's own documentation.

---

## 0. Environments — test shop first, real shop at cutover

**Decided.** All development and testing runs against a **Shopify development store** created in the
Dev Dashboard, with the real catalogue imported by CSV, and a **separate Firebase project**
(`little-blue-test`). The real shop — `little-blue-cart-dev.myshopify.com`, which *is*
littlebluemarket.com despite the name — and the real Firebase project `little-blue-610e5` are not
touched until cutover.

Grace is the admin for Shopify, Firebase and Shipturtle. **The click-by-click list of everything she
needs to get, in order, is Part 0 of `Planning/answers-to-open-questions.md`.** Read that before
asking her for anything; most of what §11 asks for is already routed there.

Cutover is a checklist, not a migration: repoint `SHOPIFY_STORE_DOMAIN`, deploy to `little-blue-610e5`,
register the webhooks on the real shop, run `backfillCatalog`, issue the first claim codes. Nothing
from the test Firebase project is carried across, and a dev store cannot become a production store, so
nothing is expected to.

## 1. Four systems, and exactly one job each

The whole design rests on refusing to let two systems own the same fact.

| System | Owns | Never owns |
|---|---|---|
| **Firebase (Auth + Firestore + Functions + Storage)** | App identity, the social graph, posts, reviews, forums, messages, the cart's *lines*, the catalog *mirror*, seller drafts, and every credential | Price at the moment of sale, stock, money, payouts |
| **Shopify** | The product catalog of record, variants, prices, inventory, the checkout, the order, the payment | Who a user is in the app; anything social |
| **Shipturtle** | The vendor roster, the commission split, payout accounting, per-vendor fulfilment | Product content (it writes through to Shopify), identity |
| **The Flutter app** | Rendering, and optimistic local state | Any credential. Any price. Any write to `catalog/` |

Two consequences worth stating plainly, because they decide the shape of every function below:

- **Firebase is never the source of truth for money or stock.** It is a fast, offline-capable,
  socially-aware *cache* of things Shopify decided, plus a home for everything Shopify has no concept
  of. This is what makes `CLAUDE.md`'s "Shopify stays removable" rule actually hold.
- **The app holds no Shopify or Shipturtle credential and never calls either directly.** Cloud
  Functions are the only door. Existing code already enforces this (`CommerceProxyRepository` calls
  `httpsCallable` and nothing else); the seller-side write path must not be the exception.

### Credentials — status

All Shopify credentials are in hand and already wired to named config in `functions/src/config.ts`:
client ID, client secret, Storefront public token, Storefront **private** token, Customer Account API
client ID, shop ID, store domain, Admin token path, API version. Nothing in this plan needs a Shopify
credential you do not have.

Two notes on them:

- The Admin token is **not** stored. `functions/src/shopify/token.ts` mints one from the
  client-credentials grant on demand, caches it in `_internal/shopifyAdminToken` under a transaction
  so a cold-start burst does not stampede, and refreshes at 80% of lifetime. Keep it that way — the
  raw admin token in `.env.littlebluemarket` is for local `curl`, not for deploys.
- `config.ts` defaults `SHOPIFY_API_VERSION` to `'2025-07'` while your `.env` says `2026-07`. The
  default is a year stale and will silently apply on any environment where the param is unset. Bump it.

The one credential genuinely missing is **Shipturtle's Open API token**, which requires their paid API
Integration add-on (Settings → Subscription and Billing → API Integration, then Dashboard → API
integration → generate a token with Order and Product API access). Everything below is written so that
nothing is blocked on it: the write path goes through Shopify, and Shipturtle picks the change up
through its own Shopify sync.

---

## 2. Money and inventory — who is actually the source of truth

Verified against Shipturtle's payout documentation, because the app's seller screens currently imply
something that is not true.

**Money never touches Firebase, and never touches Shipturtle either.** The buyer pays Shopify
checkout; funds land in the marketplace owner's own gateway account (Stripe/PayPal/Shopify Payments).
Shipturtle *calculates* the split from its commission settings and generates payout documents; the
merchant then pays vendors out, through Shipturtle's Stripe/PayPal integration or by their own method,
and records it. Shipturtle explicitly "does not handle any of the customer payment directly."

Your live commission on the vendor plan we inspected is **9.50%** (plan 397, "Existing Little Blue
Market Vendors", `merchant_id` 1066319).

That produces a concrete correctness bug in what exists today: `recordPaidOrder` increments
`users/{sellerUid}.revenueCents` by the **gross** line total. A seller reading their profile will see
a number ~9.5% larger than anything they will ever be paid, plus whatever shipping and refunds do to
it. Fix it one of two ways, and say which in the UI:

1. **Cheap and honest now — do this.** Rename `revenueCents` to **`grossSalesCents`** and label it
   **"Total sales"** everywhere it appears, and show no payable figure at all until Shipturtle's
   payout API is available. "Revenue" and "earnings" both promise money; "Total sales" is exactly
   what the number is. Touch points: `functions/src/orders.ts`, `firebase/firestore.rules`,
   `lib/data/firebase/mappers.dart`, `lib/models/models.dart`, `profile_screen.dart`,
   `edit_profile_screen.dart`, the fixtures, and the tests asserting on it.
2. **Right later** — once the Shipturtle token exists, pull payout records and keep
   `payoutsPaidCents` / `payoutsPendingCents` as separate fields sourced from Shipturtle, never
   computed locally. Do not re-implement their commission engine; product-level and category-level
   commission overrides exist and you will drift.

**Inventory is Shopify's, absolutely.** The mirror in `catalog/` carries a stock number for rendering
only, and `commerceLiveVariants` already re-reads Admin for the real one before a buy. Nothing in the
app may decrement stock; the only inventory *write* in this whole design is the initial quantity when
a seller creates a listing.

---

## 3. Firestore data model

Existing collections, unchanged: `users` (+ `purchases`, `addresses`, `conversations`), `catalog`
(+ `spec/detail`, `reviews`, `rating`), `posts`, `forums`, `threads`, `chatroom`, `conversations`,
`orders`, `carts`, `hashtags`, `vendorMappings`, `_internal`.

Four additions this plan needs:

### `listings/{listingId}` — the seller's draft, and the write-ahead log
Client-writable by its owner. This is the only place a seller's product content is client-writable,
and it is deliberately **not** `catalog/`.

```
listings/{listingId}
  sellerUid            string   == request.auth.uid, immutable
  status               string   draft | submitting | submitted | live | rejected | failed
  title, description   string
  priceCents           int      cents, per CLAUDE.md
  compareAtCents       int?
  costCents            int?
  sku, barcode         string?
  quantity             int
  trackQuantity        bool
  continueSellingOOS   bool
  productType          string
  collectionHandles    [string] the initiative/category collections it belongs to
  tags                 [string] free tags; hashtags live on the post, not here
  weightGrams          int
  lengthIn/widthIn/heightIn  num?
  imagePaths           [string] Firebase Storage paths, seller-owned
  imageUrls            [string] public download URLs, written by the function
  shopifyProductId     string?  stamped by the push function
  idempotencyKey       string   == listingId, sent to Shopify as a metafield
  error                string?  human-readable, shown on the retry button
  createdAt/updatedAt  ts
```

Why a separate collection rather than writing `catalog/` directly: `catalog/` is a mirror of Shopify
and must stay `allow write: if false` for clients, or the "a client cannot invent a listing or move a
price" guarantee in `firestore.rules` is gone. The draft is the seller's; the mirror is Shopify's.

### `sellers/{uid}` — function-written, and the reason the breach closes

**Not fields on `users/{uid}`.** A separate document whose rule is one line:

```
match /sellers/{uid} { allow read: if true; allow write: if false; }
```

```
sellers/{uid}
  shopifyVendorName    string   the exact Shopify `vendor` string — the join key for everything
  shipturtleVendorId   string   Shipturtle company_id
  shipturtleUserId     string
  shopifyLocationId    string   the vendor's Shopify location, for the opening inventory write
  canUploadProducts    bool     mirrors Shipturtle's vendor-product-upload-permission
  verifiedAt           ts
  verifiedBy           string   'claim-code' | 'shipturtle-roster' | 'manual'
  grantVersion         int
  revokedAt            ts?
```

Deny-by-default beats a lock list. `users/{uid}`'s `untouched([...])` clause has to be *remembered*
every time a field is added, and it already was not: `isSeller` and `shopifyVendorName` are missing
from it today. A document nothing client-side may write cannot develop that hole.

### `sellerApplications/{uid}` — the pending-role document, and the app's wake-up signal
```
sellerApplications/{uid}
  status         'started' | 'applied' | 'approved' | 'declined' | 'revoked' | 'stale'
  appliedEmail   string   the verified address the application was filed under
  vendorName     string?  filled in on approval
  startedAt, appliedAt, decidedAt, lastCheckedAt   ts
  note           string?  the merchant's reason, when there is one
```
She may create it in `started` and nothing more; every later transition is function-written. It is
readable by her, which is the whole point — it is the realtime channel that tells the app to refresh
its ID token when the role changes (§5a step 6).

### `vendorNames/{normalizedName}` — one vendor, one owner
```
vendorNames/{normalizedName}   { uid, claimedAt }     allow read: if true; allow write: if false;
```
Claimed in a transaction, so two accounts racing for "Gwynstone" cannot both win. This is what makes
`resolveSellerUid`'s "exactly one match or give up" check safe rather than dependent on the real
seller not having signed up yet.

### `vendorClaims/{codeHash}` — how seller status is proven before the Shipturtle API exists
```
vendorClaims/{sha256(code)}    { vendorId, vendorName, email?, expiresAt, usedBy?, usedAt? }
```
Written by the merchant (or by a support tool), never by a client, never readable by one. Codes are
single-use, hashed at rest and expiring. This is the launch mechanism, and it needs nothing from
Shipturtle.

### `collections/{handle}` — the initiative and category mirror
The store has 92 collections and they are the real taxonomy (`Adult Apparel`, `Bath, Beauty &
Wellness`, `Ally Owned`, `BIPOC Owned`). The identity ones are not decoration: they are the
**Vendor Identity** field on the live application form (§5a), so a seller declares them once at
application time and they flow to the storefront and to the app's initiative hashtags. Mirror id, title, handle, image, and each product's
membership. Shipturtle's own vendor form exposes Collections as a metafield dropdown, so this is also
how a vendor-created product gets categorised on the website — the app must offer the same list.

### Indexes these additions need
`firebase/firestore.indexes.json` already covers `catalog` by `sellerId + createdAt`. Add:

- `catalog`: `vendorName ASC` — the backfill in `resolveSellerForVendorName` scans by vendor name.
- `catalog`: `collectionHandles CONTAINS` + `createdAt DESC` — browsing an initiative.
- `listings`: `sellerUid ASC` + `updatedAt DESC` — her drafts, newest first.

Note `typeSlug + geohash` becomes near-useless once PR 17 lands, since `product_type` is `"physical"`
across the store. The equivalent index on `collectionHandles` replaces it.

### `_internal/shipturtle*`
Cache for the vendor roster once the Shipturtle token exists. Denied to all clients, like the token cache.

---

## 4. Which part of the backend does what

Existing functions, and what each is responsible for. **Nothing in the write path below replaces
these; it slots between them.**

| Function | Trigger | Responsible for | Explicitly not responsible for |
|---|---|---|---|
| `linkAccounts` | callable | Turning a verified email into `shopifyCustomerId`, `shipturtleVendorId`, `isSeller`, and backfilling order history | Deciding the vendor rule (that is data, in `vendorMappings`) |
| `commerceAddLine` / `UpdateLine` / `RemoveLine` / `ClearCart` | callable | Server-priced cart lines in `carts/{uid}` | Stock truth |
| `commerceLiveVariants` | callable | The one authoritative stock read, straight from Admin | Caching it |
| `commerceBeginCheckout` | callable | `cartCreate` on Storefront, stamping `app_uid` and per-line `app_seller_uid`, returning `checkoutUrl` | Asserting a purchase happened |
| `shopifyWebhook` | HTTPS | HMAC verification, then routing by topic | Any business logic of its own |
| `mirrorProduct` / `removeMirroredProduct` | via webhook | The `catalog/` mirror and its `spec/detail` | Being the source of truth |
| `normalizeOrder` → `recordPaidOrder` | via webhook | Idempotent order recording, per-seller revenue split, buyer purchase docs | Payouts |
| `recordFulfillment` | via webhook / callable | Shipment state on the order, `delivered` on purchases | Creating labels |
| `fulfillmentAddTracking` | callable | Seller marks shipped; upstream first, then local | Working without the Shipturtle key (it degrades, loudly) |
| `shipturtleWebhook` | HTTPS | Vendor-side shipments the app never saw | Anything unsigned |
| `onPostWritten` | Firestore | Hashtag counters | Product tags |
| `adminToken` / `adminGraphQL` | library | Minting, caching, single 401 retry | Being called from anywhere but a function |

### New functions this plan adds

| Function | Trigger | Responsible for |
|---|---|---|
| `sellerPublishListing` | callable | The whole app→Shopify product write. Validates the draft server-side, hands Shopify the Storage image URLs rather than staging uploads, calls `productSet` (opening stock inline), optionally publishes, seeds the mirror, stamps `shopifyProductId` back onto the draft |
| `sellerUpdateListing` | callable | Edits and restocks on a live listing, via `productVariantsBulkUpdate` and `inventorySetQuantities` — **never `productSet`**, which deletes any variant or option you omit |
| `sellerArchiveListing` | callable | `status: ARCHIVED` on Shopify; the mirror deactivates via the `products/delete`/`update` webhook |
| `syncCollections` | scheduled + callable | Mirrors the store's 92 collections into `collections/` so the composer's picker is real |
| `backfillCatalog` | callable (admin) | The one-time `bulkOperationRunQuery` import of the ~2,500 existing products |
| `resolveSellerForVendorName` | Firestore trigger on `sellers/{uid}` | When `shopifyVendorName` appears, backfills `catalog.sellerId` for that vendor's existing products and calls `forgetVendorCache()` |
| `sellerClaimVendor` | callable | The **only** way to become a seller. Verifies the email claim, consumes a claim code or matches the Shipturtle roster, reserves the vendor name, writes `sellers/{uid}`, sets the custom claim, writes an audit record |
| `sellerRevokeVendor` | callable (admin) | Clears the claim and stamps `revokedAt`. Existing products stay; further writes are refused |
| `sellerStartApplication` / `sellerMarkApplied` | callable | Moves `sellerApplications/{uid}` through `started` → `applied`. Status is never a client write |
| `sellerSyncVendorRoster` | scheduled, 15 min | Diffs Shipturtle's vendor roster against pending applications; grants and revokes (§5a step 5b) |
| `sellerRefreshStatus` | callable | One-user, on-demand version of the above, rate-limited to 5 min |
| `sellerRefreshListings` | callable | Pull-side approval check for the caller's submitted listings (§6a) |
| `onReviewWritten` | Firestore trigger | Verifies the review names a real delivered purchase, moves the rating histogram, flips `purchases/{id}.reviewed`, creates the feed post |
| `commerceAddManyLines` | callable | Adds every item of a posted cart, server-priced, skipping what is out of stock |

---

## 5. Journey A — the seller who already has a shop, signing in for the first time

She has been selling on littlebluemarket.com for a year. She has a Shipturtle vendor account
(`company_id`), a Shopify `vendor` name, and products already live. She opens the app and signs in.

1. **App → Firebase Auth.** She signs in with her email. Firebase Auth issues the uid. This is the
   app's identity and the only one the client ever holds.
   *Why not Shopify's login:* she is a vendor, and vendors are not Shopify customers. Sellers and
   buyers must land on the same account type or the social graph splits in two.
2. **App → `linkAccounts` (callable).** No arguments that matter — the function reads
   `request.auth.token.email` and `email_verified` from the **verified token**, never from the request
   body. An unverified email is rejected with `failed-precondition`.
3. **`linkAccounts` → Shopify Admin.** `customers(query: "email:…")`. Exactly one match or none;
   two matches logs an error and links neither. On a match: `users/{uid}.shopifyCustomerId`, then
   `backfillOrders` pulls her last 50 orders into `users/{uid}/purchases` so her Bought grid is not
   empty on first paint.
4. **The seller grant — `sellerClaimVendor`, not `linkAccounts`.** Linking a *buyer* record is
   automatic; becoming a *seller* is a grant, and it goes through its own callable (§8). She either
   enters the claim code the merchant issued her, or — once the Shipturtle token exists — the roster
   match happens silently during linking and she is never asked. Either way one transaction verifies
   her email claim, consumes the proof, reserves `vendorNames/{gwynstone}`, writes `sellers/{uid}`
   with `shopifyVendorName`, `shipturtleVendorId = company_id` and `shopifyLocationId`, sets the
   `seller: true` custom claim, and writes an audit record. The app calls `getIdToken(true)` so the
   Products tab appears without waiting an hour for the token to refresh.
5. **`resolveSellerForVendorName` fires** on that write to `sellers/{uid}`. It queries `catalog` for products carrying
   her vendor name, sets `sellerId = uid` on each, and calls `forgetVendorCache()`.
   *This step is the one the current code is missing, and without it her Products tab is empty
   forever.* It also requires `mirrorProduct` to persist the raw `payload.vendor` string on the
   catalog document — today it stores only the resolved uid, so after a backfill there is nothing left
   to match on. **That one field is the prerequisite for this entire journey.**
6. **App reads `catalog` where `sellerId == uid`.** `CatalogRepository.productsBySeller` already
   exists. Her products render in her profile's Products tab.

What she sees: she logs in and her shop is already there. She never told the app she was a seller.

---

## 5a. Journey D — a buyer applies to sell, is approved, and comes back

The question this section exists to answer: **how does the backend learn that a role changed, and how
does the app find out?** Firebase does not tell anyone when a custom claim changes, Shipturtle does not
emit a webhook when a merchant approves a vendor, and the approval happens on a website the app cannot
see. Three silences in a row. Everything below is about closing them.

### What actually exists on the live site

Verified 2026-09-04. `littlebluemarket.com/pages/sell-with-us` embeds Shipturtle's hosted vendor
registration page in an iframe:

```
https://register.cdnserve.cloud/?company_id=1066319&shop_id=11859&custom_domain=vendors.littlebluemarket.com
```

`company_id 1066319` is the merchant (the same `merchant_id` on the vendor subscription record),
`shop_id 11859` is Shipturtle's internal shop id — **not** Shopify's `75519754395`. The form is
titled *"Apply to Sell on Little Blue Market"* and collects:

> Company Name\* · Contact Name\* · **Email\* with a built-in VERIFY EMAIL → 6-digit code step** ·
> Phone · Address, Country, City, State, Zip · **Vendor Identity\*** (BIPOC-Owned / Disabled Owned or
> Employer / LGBTQ+ Owned / Woman-Owned / Veteran or Military Spouse Owned / Ally) · whether they are
> listed on the LittleBlueCart.com directory\* · "Write YES" to accept the Community Ethics &
> Guidelines\* · what they sell · a confirmation checkbox over the full guidelines text

Then: the request lands under **Vendors → Approve Vendors** in the merchant's Shipturtle dashboard;
the merchant approves (`api/v1/approve-vendor-shop`); **Shipturtle emails the vendor their login
credentials**; the vendor sets up at `vendors.littlebluemarket.com` and picks a plan
(`/pages/seller-plans-pricing`).

Two findings that shape the whole design:

1. **Shipturtle verifies the applicant's email with its own 6-digit code, at application time.** So
   the email on a vendor record is a *verified* email, and Firebase Auth verifies the same address
   independently. Two independent verifications of one address is what makes email a sound join key
   rather than a guess. This is the single most useful fact in this section.
2. **The Vendor Identity options are the storefront's identity collections** — `BIPOC Owned`,
   `Woman Owned`, `LGBTQ+ Owned`, `Disabled Owned / Employer`, `Veteran / Military Spouse Owned`,
   `Ally Owned` are all live collections on the store. The initiatives the app renders as hashtags
   are declared here, at application time. One vocabulary, three surfaces.

### The rule: do not rebuild this form

The app opens the **same hosted page in a web view**, with `company_id`, `shop_id` and `custom_domain`
as above, and the applicant's verified email prefilled. It does not reimplement the fields natively.

Two reasons, and the second is the serious one. A native form would need Shipturtle's write API, which
is the paid add-on. And the "Write YES to confirm you agree to the Community Ethics & Guidelines"
step is a **legal consent over a specific text**. Reproducing that in a hand-built screen means the
thing the applicant agreed to is no longer provably the thing the merchant published. Keep the
agreement where the merchant controls it.

### The journey, front and back

**1. She signs up as a buyer.** Firebase Auth, email + code. `linkAccounts` runs: verified email →
Shopify customer if one exists → purchase backfill. She has a uid, a profile, a cart. No seller claim,
no `sellers/{uid}`. The app shows the buyer tab set.

**2. She taps "Sell with us"** (settings, or a prompt on her profile). The app writes

```
sellerApplications/{uid}   { status:'started', appliedEmail:<her verified email>,
                             startedAt, lastCheckedAt }
```

then opens the web view. `allow read: if isSelf(uid); allow create: if member() && isSelf(uid) &&
incoming().status == 'started'; allow update, delete: if false;` — she may declare that she started,
and nothing else. Every later transition is function-written.

**3. She fills in the application and verifies her email inside the form.** The app cannot see any of
this — it is a cross-origin page. On web-view dismissal the app asks one question, "Did you finish
your application?", and on yes sets `status:'applied'` through a callable, not a client write.

*Why prefill and lock the email:* if she applies with `hello@hershop.com` while her app account is
`grace@gmail.com`, nothing will ever match and she will sit in limbo blaming the app. Prefilled and
read-only in the handoff; and if she insists on a different business address, the app offers to verify
that second address to her account first, so both sides still agree.

**4. The merchant approves in Shipturtle, and nobody tells us.** There is no vendor-approval webhook —
Shipturtle's documented webhook surface is shipping and orders. This is the silence, and it has two
answers depending on whether the API add-on exists.

**5a. Today, with no Shipturtle API — the approval email carries a claim code.**
Shipturtle already emails approved vendors their dashboard credentials. The merchant adds one line to
that template:

> Selling on the app too? Open Little Blue Market, go to Profile → Sell with us, and enter this code:
> **LBM-7QK4-2M9P**

She enters it, the app calls `sellerClaimVendor({ code })`, and §8's transaction runs: verified email,
consume `vendorClaims/{sha256(code)}`, reserve `vendorNames/{normalized}`, write `sellers/{uid}`, set
the custom claim, write the audit record, flip `sellerApplications/{uid}.status = 'approved'`.

Deterministic. No polling, no webhook, no API. The code is the merchant's approval, in a form the app
can verify — and because it is single-use and bound to one vendor, forwarding it to a friend grants
that friend nothing the merchant did not intend.

**5b. Once the Shipturtle token exists — `sellerSyncVendorRoster`, scheduled.**
Every 15 minutes, for `sellerApplications` in `applied` only (never a scan of all users): fetch the
vendor roster, match `appliedEmail` against a vendor user's email, require **exactly one** match, then
run the identical grant transaction. Two matches grants nothing and logs — a wrong grant hands someone
another seller's catalogue, and an ungranted seller is a support ticket. The same job clears the claim
and stamps `sellers/{uid}.revokedAt` when a vendor is deactivated.

The claim code stays as the fallback. It costs nothing to keep and it covers the case where she
applied with an address the roster does not carry.

**5c. Belt and braces — `sellerRefreshStatus`, callable.**
On app foreground, if `sellerApplications/{uid}.status == 'applied'`, the app calls it. Rate-limited to
once per 5 minutes via `lastCheckedAt`, returning early rather than erroring so the UI never shows a
failure for pressing refresh. It does what 5b does, for one user, now.

### 6. How the app finds out — the part that is easy to get wrong

**A custom claim does not push.** `setCustomUserClaims` changes what Firebase will mint *next time*;
it does not invalidate the ID token the app is holding. That token lives up to an hour. So for up to
an hour after approval:

- `request.auth.token.seller` is still absent in **Firestore rules**
- `getIdTokenResult()` still returns the old claims
- `authStateChanges()` does **not** fire — the user did not change, only their claims did

Left alone, she is approved, gets the email, opens the app, and is still a buyer. That is the failure
this design has to prevent, and the fix is three lines in the right places:

1. **The signal is a document, not the token.** `sellerApplications/{uid}` is readable by her and the
   app already holds a snapshot listener on her own documents (`_SessionListenable` watches
   `users/{uid}`). When the grant transaction flips `status` to `approved`, that listener fires
   immediately — Firestore listeners are realtime and do not care about token age for a document she
   could already read.
2. **The response is a forced refresh.** On seeing `approved`, the app calls
   `FirebaseAuth.instance.currentUser!.getIdToken(true)`. The Firestore SDK picks up the new token
   automatically, so rules and every `request.auth.token.seller` check start passing within a second.
3. **The session listens to `idTokenChanges()`, not `authStateChanges()`.** `idTokenChanges()` fires
   on the forced refresh; `authStateChanges()` does not. Three exact edits:
   - `lib/data/firebase/firebase_auth_service.dart:38` — `_auth.authStateChanges()` becomes
     `_auth.idTokenChanges()`
   - `AuthUser` (`lib/data/auth/auth_service.dart`) gains `isSeller`, read from
     `getIdTokenResult().claims['seller']` rather than from any document
   - `lib/state/session.dart:56` — `bool get isSeller => profile.isSeller` becomes the claim, not the
     profile field. `isSellerProvider` at :128 keeps its shape, so no screen changes.

   The router redirect then re-runs and the Products tab, the Add button and the Sending tab appear.

   *Note the existing trap:* `session.dart` carries `themeMode`, so anything that rebuilds the session
   re-runs the router redirect, and `_SessionListenable` does not dedupe. Both are PR 6 leftovers in
   `CLAUDE.md`'s trap table and both get worse the moment claims start changing at runtime. Fix them
   in the same PR.

She sees: a modal — *"You're in. Welcome to Little Blue Market."* — and the tab bar grows.

### 7. The claim is a fast path, never the authority

`request.auth.token.seller` is what the **UI** and the **rules** read, because it is free and instant.
It is deliberately **not** what a write trusts on its own.

Revocation is the reason. When the merchant deactivates a vendor, the claim is cleared — but her
device keeps a token saying `seller: true` for up to an hour, and Firestore rules will keep believing
it. So every seller-side callable re-reads `sellers/{uid}` and `vendorNames/{name}` server-side before
touching Shopify (§8's three-fact check). A stale token can open a screen. It cannot publish a product.

### 8. State machine

```
(none) ─apply→ started ─callable→ applied ─grant→ approved ──→ [seller claim set]
                                     │                              │
                                     ├─merchant declines→ declined  └─revoked→ revoked
                                     └─14 days→ stale (nudge, not an error)
```

`declined` and `revoked` both keep `sellers/{uid}` for the audit trail and clear the claim. Products
already created stay on the storefront — removing them is the merchant's decision in Shopify, not a
side effect of a role change in our app.

---

## 6. Journey B — she adds a product from the app

The screen is the post-composer, so it must *feel* like posting. Underneath it is a product write to a
live commerce store, so it must behave like one.

### The UI half
The **Add** button lives on the Products tab of her own profile and appears only when
`users/{uid}.isSeller == true` and `canUploadProducts != false`. Tapping it opens the composer with a
product detail section: photos, title, description, price, quantity, SKU, variants, weight and
dimensions, collections, tags. The field set is deliberately the same one Shipturtle's own vendor form
asks for, so nothing she enters here is unusable on the website:

> Physical/Digital · Product name\* · Vendor name\* · Category · Status · Tags · Description\* ·
> Images\* · metafields (Collections, More Info, Related products, Search boosts, digital files) ·
> Has variants · Quantity\* · SKU · Barcode · Track quantity · Continue selling when out of stock ·
> Price\* · Cost per item · Compare at price · Tax (HSN) · Charge tax · L/W/H · Weight+unit · Remarks

Two things her form must *not* offer, because Shipturtle cannot carry them: **variant-level
metafields** (their form says so outright) and vendor-name editing (it is the join key).

### The backend half, step by step

1. **App → Firebase Storage.** Photos upload to `listings/{uid}/{file}`, matching the flat
   `avatars/{uid}/` and `posts/{uid}/` idiom the bucket already uses. Storage rules allow write only
   where the path uid matches the caller, image content types only, size-capped. The app gets back
   public download URLs.
   *Why Storage first:* Shopify's `FileCreateInput.originalSource` accepts an external image URL, so
   the function hands Shopify a URL instead of running a staged upload. One fewer round trip, and the
   seller keeps her originals.
2. **App → Firestore, `listings/{listingId}`, `status: 'draft'`.** A plain client write, allowed by
   rules because it is her own document under her own uid. Saves survive backgrounding; a half-filled
   listing is not lost. Money is `int` cents from the first keystroke.
3. **App → `sellerPublishListing({listingId})` (callable).** The client sends **only the id**. Every
   value is re-read server-side from the draft. A client-supplied price is the obvious thing to tamper
   with, and this is the mutation that would put it on a live storefront.
4. **`sellerPublishListing` validates and guards.**
   - `requireUid`, then `listing.sellerUid == uid` or `permission-denied`.
   - The three-fact seller check from §8: `request.auth.token.seller === true`, a live
     `sellers/{uid}` with `canUploadProducts !== false`, and
     `vendorNames/{normalize(shopifyVendorName)}.uid === uid`. All three, or `permission-denied`.
     The vendor name that goes to Shopify is read from `sellers/{uid}` — **never from the request** —
     because that string is what assigns every future sale.
   - Required fields present; `priceCents > 0`; at least one image.
   - **Idempotency.** Sets `status: 'submitting'` in a transaction that fails if it is already
     `submitting` or `live`. Before creating, queries Shopify for a product whose `app.draft_id`
     metafield equals `listingId`; if one exists, adopts it instead of creating a second. A flaky
     network must not put two copies of her hat on the storefront.
5. **`sellerPublishListing` → Shopify Admin `productSet`** (one call, `synchronous: true`):
   - `vendor:` **her `shopifyVendorName`, exactly.** This single field is what enrols the product with
     Shipturtle, attributes her payout, and lets `resolveSellerUid` find her. Everything else is detail.
   - `status: DRAFT` (see step 7), `title`, `descriptionHtml`, `productType`, `tags`
   - `productOptions` + `variants` (`ProductVariantSetInput`) with `optionValues` (required),
     `price`, `compareAtPrice`, `sku`, `barcode`, `taxable`,
     `inventoryItem: { cost, tracked, measurement: { weight } }`,
     `inventoryPolicy: CONTINUE|DENY`, and **`inventoryQuantities: [{ locationId, quantity }]`** —
     stock is set inline here, on create, so there is no second call to get wrong
   - `files: [{ originalSource: <Storage URL>, contentType: IMAGE }]`
   - `metafields: [{ namespace: "app", key: "draft_id", type: "single_line_text_field", value: listingId }]`
   - `collections` for the handles she picked
   Use `productSet` **only here, on create.** On edit it deletes every variant and option you omit;
   `sellerUpdateListing` uses `productVariantsBulkUpdate` and friends instead.
6. **Inventory — no separate call on create.** `inventoryQuantities` inside `productSet` sets the
   opening stock at `users/{uid}.shopifyLocationId ?? <shop default>`. It only works this way on
   create: on an existing variant Shopify will only let you update quantities at locations where it
   is *already* stocked. So **restock is a different function** — `sellerUpdateListing` uses
   `inventorySetQuantities` (`name: "available"`, `reason: "correction"`, with `compareQuantity` for
   the compare-and-set) and never `productSet`. For the opening number the app is the source of truth
   for exactly one write; after that, never again.
7. **`sellerPublishListing` does *not* publish. It submits for review.** A product created through
   Admin bypasses Shipturtle's merchant approval queue entirely — their flow is Submitted → Pending
   Approval → Live, reviewed in Products → Approve Products, with every field configurable as
   View / Requires Approval / Mandatory. Publishing straight to `ACTIVE` would put unreviewed
   listings on the marketplace and quietly delete a control the merchant already relies on.

   So the function leaves the product `DRAFT` and unpublished, writes `listings/{id}.status =
   'submitted'` with `submittedAt`, and returns. **`publishablePublish` is not called here at all** —
   it belongs to the approval path in §6a.

   **The app shows a modal, not a snackbar:**

   > **Under review**
   > *<title>* has been sent to Little Blue Market for approval. You'll see it in your shop as soon
   > as it's approved — usually within a day or two. We'll let you know.
   > **[ Got it ]**

   A modal because this is the one moment the seller's mental model diverges from what happened: she
   pressed Add and the thing is not in her shop. A snackbar she can scroll past is how that becomes a
   support ticket. The draft stays visible in her Products tab with an **Under review** chip, and
   tapping it shows the same explanation plus the merchant's remarks once there are any.

8. **`sellerPublishListing` seeds the mirror.** Admin SDK, bypassing rules: writes `catalog/{shopifyId}`
   and `catalog/{shopifyId}/spec/detail` from the values it just sent, plus `vendorName` and
   `sellerId: uid`. *Why not wait for the webhook:* `products/create` arrives seconds to minutes
   later, and the composer cannot spin that long. The seed and the webhook write the same document
   with `{merge: true}`, so the webhook simply overwrites it with the canonical version.
9. **`sellerPublishListing` returns `{ shopifyProductId }`** and stamps it onto the draft with
   `status: 'submitted'` (or `'live'` when auto-publish is on). On any failure it writes
   `status: 'failed'` and a human-readable `error`, and the composer shows a retry that re-calls the
   same idempotent function.
10. **Shopify → `shopifyWebhook` (`products/create`).** HMAC verified, then `mirrorProduct` rewrites
    `catalog/{id}` canonically — real image CDN URLs, real variant ids, real `available` flags.
    `resolveSellerUid` resolves her uid from the vendor name and the mirror is complete.
11. **Shipturtle → picks it up from Shopify** by vendor name, on its own sync. Nothing to call.
12. **She reposts it.** `ListingComposer` in `lib/widgets/composers.dart` already does exactly this —
    it picks from `productsBySeller` and calls `SocialRepository.createPost(NewPost.listing(...))`,
    writing `posts/{id}` as a `ListingPost` with `productId = shopifyProductId`, her caption and her
    hashtags; `onPostWritten` moves the counters. **It is written and currently unreachable**, because
    `productsBySeller` returns nothing while `catalog.sellerId` is empty. PR 16 is what switches this
    screen on; nothing about it needs rewriting.
    The product and the post stay separate documents on purpose: she can post one listing five times
    under five initiatives without five products existing.

**The composer can offer both in one tap** — "Add to my shop" and "Add and post" — because step 12
only needs the id that step 9 returned.

### Failure modes, and who owns each
| Fails | Result | Owner |
|---|---|---|
| Storage upload | Nothing left behind; draft keeps text | App, retry |
| Callable never returns | `status: 'submitting'`; the retry adopts by `draft_id` metafield | Function |
| `productSet` userErrors | `status: 'failed'` + message; no Shopify product | Function |
| `publishablePublish` fails after create | Product exists as DRAFT, unpublished; `status: 'failed'`, retry adopts by `draft_id` and publishes only | Function |
| Webhook never arrives | Mirror stays on the seed — degraded, not broken | Acceptable |
| Merchant rejects | Shipturtle marks it; app shows `rejected` once the token exists | Merchant |

---

## 6a. Learning that it was approved — push first, pull as the fallback

Two independent paths, because neither is reliable alone.

### Push — the webhook already fires
When the merchant approves in Shipturtle, the product's Shopify status and publication change, which
emits `products/update`. `mirrorProduct` already runs on that topic. Add to it:

- read the product's `app.draft_id` metafield
- if it names a `listings/{id}` document still in `submitted`, and the product is now `ACTIVE` **and**
  published to Online Store, set `status: 'live'`, `approvedAt`, and write a notification document
- if it is now `ARCHIVED`, or Shipturtle reports a rejection, set `status: 'rejected'` and carry the
  merchant's remark across — their vendor form has a **Merchant & vendor remarks** field, and a
  rejection with no reason is worse than no rejection

This makes approval feel instant and costs one extra branch in a function that already runs.

### Pull — `sellerRefreshListings`
A callable, invoked by pull-to-refresh on the Products tab and on cold start of that screen. Push
fails in ordinary ways — a missed webhook, an approval that changed nothing Shopify emits, a merchant
who approved in Shipturtle before the sync ran — and a seller staring at a listing stuck on **Under
review** will not trust the app again.

For each of the caller's listings in `submitted` that carries a `shopifyProductId`:

1. Read `product(id:) { status publishedOnCurrentPublication }` from Admin, batched — one query for
   up to 50 ids, not one call per listing.
2. `ACTIVE` and published ⇒ `status: 'live'`. `ARCHIVED` ⇒ `rejected`.
3. Once the Shipturtle token exists, also read their approval state, so *pending* stays distinct from
   *rejected*, and pull the remarks across.
4. **Rate-limit.** At most one refresh per listing per 60 s, tracked on the listing document; the
   callable returns early rather than erroring, so pull-to-refresh always feels like it worked.
5. Listings still `submitted` after 14 days get a "still with the merchant" note and a **Nudge**
   action that sends a message rather than another API call.

Idempotent by construction: every write is a status transition that is a no-op if already applied.

---

## 7. Journey C — a purchase, end to end

Included because it is where inventory and payment actually resolve, and it is already built.

1. `commerceAddLine` re-prices from `catalog/{id}/spec/detail` server-side and writes `carts/{uid}`.
2. `commerceLiveVariants` re-reads Admin before the buy sheet commits — the one read that must not be
   stale, because a few minutes of drift is how you sell the same thing twice.
3. `commerceBeginCheckout` calls Storefront `cartCreate` with `app_uid` on the cart and
   `app_seller_uid` per line, and returns `checkoutUrl`. **Nothing here claims a purchase happened.**
4. She pays on Shopify. Funds go to the marketplace owner's gateway. Shopify decrements inventory.
5. `orders/paid` → `normalizeOrder` → `recordPaidOrder`: one transaction keyed by Shopify's order id,
   so a retried webhook is a no-op; per-seller revenue split; one purchase doc per line.
6. Shipturtle splits the order per vendor, applies the 9.5% commission, and generates payout records.
   The merchant pays vendors from their own funds. Neither Firebase nor the app is in this path.
7. Fulfilment arrives from whichever side shipped: `fulfillmentAddTracking` if she used the app,
   `shipturtleWebhook` if she used her vendor dashboard. Both land in `recordFulfillment`, keyed by
   tracking number so an update replaces its shipment instead of appending a duplicate.

**Checkout on Flutter, still open:** Shopify's Checkout Sheet Kit ships for Swift and Kotlin, not
Flutter. Either a platform channel around the native kit or an in-app web view on `checkoutUrl`.
Decide before this ships — it changes the plugin list. Either way `orders/paid` remains the only
source of truth that money moved.

---

## 8. Selling is a grant, not a checkbox — and the rules that enforce it

### The breach as it exists today

This is not theoretical. Three things line up right now:

1. `ProfileRepository.becomeSeller()` (`firestore_profile_repository.dart:149`) writes
   `isSeller: true` onto the caller's own user document, straight from the client. The UI calls it
   from `edit_profile_screen.dart` and says *"Selling is on. Your storefront is live."*
2. `firestore.rules` locks `revenueCents`, `purchaseCount`, `shopifyCustomerId` and
   `shipturtleVendorId` on `users/{uid}` — but **not `isSeller`, and not `shopifyVendorName`.**
3. `resolveSellerUid` credits a sale by matching `users.shopifyVendorName == <product vendor>`
   (accepted when exactly one account claims it) or by `emailLower` + `isSeller`.

So any signed-in account can set `isSeller: true` and `shopifyVendorName: "Gwynstone"`, and — because
the real Gwynstone has not signed up yet, so there is exactly one claimant — inherit **551 products
and every dollar of their sales**. Two client writes. No function involved, no credential needed.

### The fix, in four parts

**1. Seller identity moves out of client reach.** Every field in §3's `sellers/{uid}` is
function-written and `allow write: if false`. There is no lock list to forget to extend.

**2. `isSeller` becomes a Firebase custom claim, not a document field.**
`sellerClaimVendor` calls `setCustomUserClaims(uid, { seller: true, vendor: <name> })`. A client
cannot mint a claim; it is signed into the ID token by Firebase Auth. Rules read
`request.auth.token.seller`, callables read `request.auth.token.seller`, and neither takes the
client's word for anything.

*Propagation caveat, worth handling rather than discovering:* a custom claim reaches the client on the
next token refresh, up to an hour. After granting, the function writes `sellers/{uid}` and the app
calls `getIdToken(true)` to force a refresh, so the Products tab appears immediately.

**3. `becomeSeller()` is deleted.** Not guarded — deleted, from `ProfileRepository`, from both
implementations and from the settings screen. It is replaced by
`requestSellerStatus(String claimCode)` → the `sellerClaimVendor` callable, which requires:

- `request.auth.token.email_verified == true` — the same rule `linkAccounts` already enforces, for
  the same reason: an unverified address lets anyone type a stranger's email
- **proof of the vendor record**, exactly one of:
  - a valid, unused, unexpired **claim code** from `vendorClaims/{sha256(code)}` — the launch path,
    needing nothing from Shipturtle
  - an exact, unique email match against Shipturtle's vendor roster — the automatic path, once their
    API token exists
  - a `vendorMappings/{email-slug}` document written by the merchant — the manual fallback
- **an unclaimed vendor name**, reserved in the same transaction via `vendorNames/{normalizedName}`

All three in one transaction, or none of them. Every grant and revoke is written to
`_internal/sellerAudit/{id}` with the uid, the vendor, the method and the timestamp — a wrong grant
must be traceable and reversible, not archaeology.

**4. Every seller write re-checks, server-side, at the moment it matters.**
`sellerPublishListing`, `sellerUpdateListing`, `sellerArchiveListing` and `fulfillmentAddTracking`
each verify, before touching Shopify:

```
request.auth.token.seller === true
sellers/{uid} exists, revokedAt == null, canUploadProducts !== false
vendorNames/{normalize(sellers/{uid}.shopifyVendorName)}.uid === uid
```

The vendor name sent to Shopify is read from `sellers/{uid}` and never from the request. Three
independent facts, none client-writable, all of which must agree.

### The rules

```
// Seller identity. Nothing client-side writes any of this.
match /sellers/{uid}      { allow read: if true;  allow write: if false; }
match /vendorNames/{name} { allow read: if true;  allow write: if false; }
match /vendorClaims/{h}   { allow read, write: if false; }

// The seller's own drafts.
match /listings/{listingId} {
  allow read:   if isSelf(existing().sellerUid);
  allow create: if seller() && isSelf(incoming().sellerUid)
                && incoming().status == 'draft'
                && incoming().shopifyProductId == null;
  allow update: if seller() && isSelf(existing().sellerUid)
                && untouched(['sellerUid','shopifyProductId','status','submittedAt','approvedAt'])
                && existing().status in ['draft','failed','rejected'];
  allow delete: if seller() && isSelf(existing().sellerUid)
                && existing().status == 'draft';
}

match /collections/{handle} { allow read: if true; allow write: if false; }

// The pending-role document. She may say she started; the outcome is not hers to write.
match /sellerApplications/{uid} {
  allow read:   if isSelf(uid);
  allow create: if member() && isSelf(uid)
                && incoming().status == 'started'
                && incoming().appliedEmail == request.auth.token.email;
  allow update, delete: if false;
}

// Add-to-cart as the affinity signal: written only by the commerce functions,
// so the public count cannot be inflated without a real cart line.
match /catalog/{productId}/carted/{uid} { allow read: if true; allow write: if false; }
```

with one new helper beside `member()`:

```
function seller() {
  return member() && request.auth.token.seller == true;
}
```

### Same file, two more edits

**Add to the `users/{uid}` lock list** — `isSeller` (kept only as a read-only display mirror the
function writes), `grossSalesCents`, `shopifyVendorName` and `shopifyLocationId` if any of them remain
on the user document at all. Prefer moving them; lock them either way.

**Remove the vote rules** — `match /votes/{uid}` under `threads/{threadId}` and under its `comments`,
and `upvotes` from the two `untouched` lists. Upvoting is gone (see `Planning/user-journeys.md` §2.4).

### Storage

Following the bucket's existing shape:

```
match /listings/{uid}/{file} {
  allow read:  if true;
  allow write: if signedIn() && request.auth.uid == uid && isImage() && underSize(10);
}
```

Public read is required, not optional: Shopify fetches the image from this URL server-side when
`files[].originalSource` is an external URL. A signed or private URL will not work.

## 9. Sequencing

Track A and B (PRs 1–15) are done. This is PR 16 onward, and the order is not negotiable — each step
is the prerequisite for the next. Client-side work for the journeys lives in
`Planning/user-journeys.md` §3 and interleaves here.

- **PR 16 — the join key and the seller guard.** Persist `payload.vendor` on `catalog` documents.
  Create `sellers/`, `vendorNames/`, `vendorClaims/` and their rules. Delete `becomeSeller()`; add
  `sellerClaimVendor`, the custom claim and the audit log. Add `resolveSellerForVendorName`. Stop
  caching misses in `resolveSellerUid`. Pass `lineItems.vendor` through in `backfillOrders`.
  **This PR closes a live privilege-escalation hole; it ships before anything else.**
- **PR 17 — the real catalog.** `backfillCatalog` bulk operation for the ~2,500 products.
  `syncCollections`. Fix `mirrorProduct` to use collections rather than `product_type` and to stop
  discarding every tag that lacks a `#`. Journey A works end to end after this.
- **PR 18 — the seller write path.** `listings/` + rules + Storage rules, the composer's product
  section, `sellerPublishListing`, the mirror seed, the idempotency metafield, the **Under review**
  modal, `sellerRefreshListings`, and the approval branch in `mirrorProduct`.
- **PR 19 — the journey changes.** Remove voting. Collapse the like into add-to-cart, with
  `saveCount` / `inCartsCount` written by the commerce functions. Relabel `revenueCents` →
  `grossSalesCents` / "Total sales". Add the tutorial card.
- **PR 19a — the role round-trip.** `sellerApplications/`, the web-view handoff to
  `register.cdnserve.cloud`, the claim-code entry screen, `idTokenChanges()` + forced refresh, and
  the `session.dart` / `_SessionListenable` dedupe fixes that runtime claim changes make urgent.
- **PR 20 — cart posts and reviews.** `CartPost`, the Cart tab on the profile,
  `commerceAddManyLines`, `onReviewWritten` and the delivered→review prompt.
- **PR 21 — Shipturtle, once the token lands.** Automatic `findVendor`, payout figures, approval and
  rejection status with remarks, and the real fulfilment endpoint in place of the placeholder in
  `fulfillment.ts`.

Definition of done is unchanged: `flutter analyze` clean, `flutter test` green, `npm test` green in
`functions/`, fix the cause and never the assertion — except where an assertion encodes behaviour
this plan explicitly changes (voting, likes, `revenueCents`), in which case update it and say so.

## 10. Still open

1. **Shipturtle API Integration add-on.** Blocks automatic vendor linking, payout figures, approval
   status, and the fulfilment push. Everything else routes around it.
2. **Auto-publish policy — decided.** App-created listings go to the merchant's approval queue as
   `DRAFT`, and the seller sees an **Under review** modal (§6 step 7, §6a). Auto-publish for trusted
   sellers stays on the shelf, gated on `canUploadProducts` plus an explicit merchant setting.
3. **Per-vendor Shopify location.** Confirm whether Shipturtle creates one location per vendor. If it
   does, `shopifyLocationId` must come from the vendor record; if not, everything sits at the shop
   default and multi-location stock is a fiction.
4. **Checkout surface on Flutter** — native kit via platform channel, or web view.
5. **Digital products.** Shipturtle's form supports them (three file slots, 20MB each). Out of scope
   for PR 18; the `listings` schema leaves room.
6. **Who issues claim codes, and how.** The mechanism is specified; the operational side is not.
   Two distinct populations: the **79 existing vendors** (bulk-issue, one code each, probably in a
   single announcement email) and **newly approved vendors** (one line added to the Shipturtle
   approval email template, which the merchant controls). Needed before PR 16 ships, not before it
   is written.
8. **Whether Shipturtle can call us on vendor approval at all.** Their documented webhook surface is
   shipping and orders; nothing suggests a vendor lifecycle event. Worth one question to
   team@shipturtle.com, because a real webhook would replace the whole of §5a step 5b with ten lines.
7. **Shoutout posts have no product, so they have no add-to-cart.** Collapsing the like into the cart
   leaves them with Comment and Repost only. Defensible — a shoutout is about a person, and what you
   do with a person you like is visit their shop — but it is a real reduction and worth watching once
   it is in front of people.
