# Little Blue Market — from prototype to functional app

## Context

`little_blue_market` is a complete, high-fidelity Flutter **prototype**. Every screen is drawn, themed, navigable, and covered by a smoke test — but nothing is real. All content lives in `abstract final class Fx` in [fixtures.dart](../lib/data/fixtures.dart) (927 lines of `static const`), every screen calls `Fx.*` **synchronously from `build()`**, the signed-in user is hardcoded (`Fx.meId = 'maya'`), verification accepts any 6 digits, and every edit — a sent chat message, an edited bio, a created forum — is discarded on pop. There is no HTTP client, no Firebase, no persistence, and no cart.

The goal is to make it functional against a **hybrid backend**: Firebase owns identity and all social data; Shopify (with ShipTurtle for multi-vendor splits, commissions, and payouts) keeps owning money and fulfilment, because a live website with real vendors already depends on it.

The constraint that shapes every decision below: **Shopify must be removable later without changing a screen or disrupting the user journey.** Three things make that real rather than aspirational — (1) every commerce call sits behind an app-owned repository interface returning app-owned models, (2) Flutter never holds a Shopify credential or speaks to Shopify directly, only through Cloud Functions, and (3) the catalog is mirrored into Firestore, so the feed, search, and profile grids already read from *our* database on day one.

**Decisions confirmed with you:** in-app cart → Shopify hosted checkout in a native sheet; Firebase Auth as the app's identity, linked to a Shopify customer by email; sellers can both pick existing Shopify products and create new ones; Milestone 1 = foundation + market + product + profile.

---

## Architecture

```
Flutter app  (no Shopify credentials, ever)
  │
  ├── Firebase Auth ......... identity: uid, email, isSeller
  ├── Cloud Firestore ....... users, catalog, posts, likes, comments, reviews,
  │                           forums, threads, chatroom, conversations,
  │                           carts, orders, purchases, hashtags
  ├── Firebase Storage ...... avatars, post photos
  │
  └── Cloud Functions ....... THE ONLY THING THAT TALKS TO COMMERCE
          ├── Shopify Storefront API .. live price/inventory, cart, checkout URL
          ├── Shopify Admin API ....... seller's products, create product, orders
          ├── Shopify webhooks ........ products/*, orders/paid, orders/fulfilled, refunds
          └── ShipTurtle API/webhooks . vendor attribution, commission, tracking numbers
```

Flutter calls Functions via `cloud_functions` `httpsCallable` — not `http`/`dio`. The Firebase ID token rides along automatically: no CORS, no base URL config, no new HTTP dependency.

### The catalog mirror — the single most important design decision

`Product` today is secretly a **join of two systems**: `title/priceCents/variants/type/description` are Shopify; `rating/likes/commentCount/tags` are Firestore. Screens must never compose that join.

Instead, Cloud Functions maintain a Firestore mirror at `catalog/{id}`, written on Shopify product webhooks, using **app-owned field names** plus the social counters. Feed, search, and grids read the mirror — one query, offline-capable, cheap. Only three moments hit Shopify live: product detail (authoritative stock), cart mutation, and checkout.

When Shopify is dropped, `catalog` is already the catalog. One sync function and one repository get rewritten. Zero screens move.

### Order attribution (buyer purchase counts + seller revenue)

The app attaches `app_uid` and per-line `app_seller_uid` as Shopify **cart attributes**, so app-originated orders are self-identifying. Website orders carry no attribute and fall back to email → `users` lookup, so **existing website purchases still land on the right app profile** — that is what makes the two front doors feel like one product.

`orders/paid` webhook (HMAC-verified; idempotent because the Shopify order id *is* the Firestore doc id):
1. Write `orders/{shopifyOrderId}` with normalized lines.
2. Per line, resolve the seller via the ShipTurtle vendor mapping and `FieldValue.increment` their `revenueCents`.
3. Increment the buyer's `purchaseCount`; write `purchases/{uid}/items/{lineId}`.
4. `orders/fulfilled` + ShipTurtle tracking webhooks append to `orders/{id}.shipments[]`, feeding the Shipping screen.

Step 3 is what powers *both* "what the user has bought and received" on the profile **and** the pick-an-item list in the review composer. Revenue and purchase counts live in Firestore, computed from events — when Shopify goes, our own order pipeline increments the same counters and the profile screen never knows.

### Existing website users must never be asked to make a second account

This is a hard requirement: people already buying and selling on the site open the app and are simply *in*. How that works differs for buyers and sellers, because they are different records in different systems.

**Buyers — matched on verified email.** The user enters the email they already use on the website and gets a one-time code. Firebase creates a uid behind the scenes, but the user fills in no signup form and chooses no password. A Cloud Function then finds the existing Shopify customer by email, stores `shopifyCustomerId` on `users/{uid}`, and backfills their order history, purchase count, and saved addresses. To them this reads as *logging in*, not signing up.

Three things make that true rather than nearly-true:
- **Prefill from Shopify.** Name and addresses come from the customer record, so `ProfileSetupScreen` opens populated instead of blank. Only the handle is genuinely new — auto-generate it from their name for buyers and let them change it later, so nothing blocks first entry. (Sellers must confirm a handle, since it is their storefront address.)
- **Normalize before matching** — lowercase and trim. Offer an "add another email" path, verified the same way, for anyone who bought under a different address or checked out as a guest.
- **No password is reused, and none can be.** Shopify never exposes password hashes, so the app is passwordless by necessity. This happens to align with Shopify's own new customer accounts, which are also one-time-code based — the app login will feel like the website login.

**Sellers — matched on their ShipTurtle vendor record**, not a Shopify customer. A vendor is not a customer, so email-matching against Shopify's customer table would silently fail for every seller and hand them an empty buyer profile. On first sign-in a Function checks the verified email against the ShipTurtle vendor list and, on a hit, sets `isSeller: true`, stores `shipturtleVendorId`, and links their catalog and revenue. **This is why the vendor ↔ app-user mapping rule in "Still outstanding" is a launch blocker, not a nice-to-have** — without it, no existing seller can log in as a seller. A user can be both, and the two lookups are independent.

⚠️ **Security constraint on the linking Function:** it must read the email from `context.auth.token.email` and require `email_verified`, never from a request parameter. Accepting a client-supplied email would let anyone type a stranger's address and inherit their order history and revenue. Linking happens once, server-side, and is not client-callable with arbitrary input.

**Optional addition, no architecture change:** a "Continue with Shopify" button using the Customer Account API to mint a Firebase custom token — literal SSO for people who prefer it. Because the linking layer is identical, this can be added later as a second provider without touching screens or data.

### Safety
- Admin tokens and webhook secrets live only in Cloud Functions Secret Manager. A leaked Admin token can drain the store.
- Every webhook verifies HMAC and is idempotent — Shopify retries aggressively.
- Firestore rules: `revenueCents`, `purchaseCount`, `orders`, `purchases` are **function-write-only**. Clients read their own and never write.

---

## Phase 0 — Credentials and secrets

Shopify tokens and the Firebase project are in hand. The rule that governs where each one lives:

> **The Flutter app ships to phones and can be decompiled. It gets Firebase client config and nothing else. Every Shopify credential lives only in Cloud Functions.** That is also what makes Shopify swappable — no screen, model, or build config mentions it.

### The Admin token expires every 24 hours — mint it, never store it

Your Admin token comes from Shopify's **client-credentials grant** and dies after ~24h. So there is no `SHOPIFY_ADMIN_ACCESS_TOKEN` secret to store; the long-lived credential is the **client secret**, and Functions exchange it for a short-lived Admin token on demand:

```
POST https://<shop>.myshopify.com/admin/oauth/access_token
     grant_type=client_credentials&client_id=…&client_secret=…
  -> { access_token, expires_in, scope }
```

`functions/src/shopify/token.ts` is the only place that call exists. Design:

1. **Module-scope cache** — a warm instance reuses the token across invocations.
2. **Firestore `_internal/shopifyAdminToken`** `{ token, expiresAt }` as the cross-instance cache, written in a transaction so a burst of cold starts doesn't stampede the OAuth endpoint. Firestore rules **deny all client access** to `_internal/**`; Functions reach it through the Admin SDK, which bypasses rules.
3. **Refresh at 80% of `expires_in`**, not at expiry — clock skew otherwise produces intermittent 401s that are miserable to debug.
4. **On any 401 from an Admin call: invalidate, mint once, retry once.** Never loop — a revoked app would spin forever.

Every Admin call goes through `withAdminToken(fn)`; no other module reads the token. This is lazy, so a cold start after an idle day pays one ~200 ms mint and nothing else — no scheduled refresh function needed.

⚠️ Verify whether your **Storefront private token** also expires. If it does, it goes through the same broker; if it's long-lived (the usual case), it stays a stored secret.

### Cloud Functions — secrets (Google Secret Manager)

Set with `firebase functions:secrets:set <NAME>`, which prompts for the value so it never lands in shell history. Read via `defineSecret('NAME')`, declared per-function with `{ secrets: [...] }`.

| Secret name | Value | Used for |
|---|---|---|
| `SHOPIFY_CLIENT_SECRET` | Client secret | Minting Admin tokens **and** verifying webhook HMACs |
| `SHOPIFY_STOREFRONT_PRIVATE_TOKEN` | Storefront **private** token | Server-side cart + checkout creation |
| `SHOPIFY_WEBHOOK_SECRET` | Webhook signing secret | Only for webhooks created in Shopify Admin → Notifications; app-registered webhooks are signed with the client secret instead. Set whichever path you use. |
| `SHIPTURTLE_API_KEY` | *(still needed)* | Vendor attribution, tracking numbers |

### Cloud Functions — non-secret config (`functions/.env.<projectId>`, gitignored)

Identifiers, not credentials — and Secret Manager bills per access, so don't put them there.

| Name | Value |
|---|---|
| `SHOPIFY_STORE_DOMAIN` | `<shop>.myshopify.com` |
| `SHOPIFY_API_VERSION` | pin it explicitly; Shopify deprecates quarterly |
| `SHOPIFY_SHOP_ID` | shop id |
| `SHOPIFY_CLIENT_ID` | public by design in OAuth |
| `SHOPIFY_STOREFRONT_PUBLIC_TOKEN` | Safe on a client, but we proxy everything, so it stays server-side too |

Two credentials you already have go **unused**: the `SHOPIFY_ADMIN_TOKEN` currently in your `.env` (stale within 24h — useful only for a manual `curl` smoke test), and the **Customer Account API client ID**, which we don't need because Firebase Auth is the identity layer. Keep it in case that decision is ever revisited.

### Firebase — almost nothing to configure

- **Cloud Functions need no Firebase credentials.** `initializeApp()` uses Application Default Credentials inside the Functions runtime. **Do not create a service account key** — an unnecessary long-lived key is a liability.
- **The Flutter app** gets its config from `flutterfire configure`, which generates `lib/firebase_options.dart`, `android/app/google-services.json`, and `ios/Runner/GoogleService-Info.plist`. These contain the Web API key and project identifiers, which are **public by design** — they identify the project, they don't authorize anything. Security comes from Firestore rules and App Check, not from hiding them.
- **A service account JSON is needed only** for CI or a local seed script running outside the emulator: keep it gitignored and point `GOOGLE_APPLICATION_CREDENTIALS` at its path. Never in the app, never committed.
- Confirm the project is on **Blaze** — Functions and inbound webhooks require it.
- Enable **App Check** before launch so only your app binary can call the Functions that spend Shopify quota.

### Repo layout and git workflow

The git repo is rooted at **`little_blue_market/`** (remote: `The-culture-connection/littlebluemarket`), and `.env` plus `shopify_recovery_codes.txt` live in the parent folder, **outside** it. Verified: nothing sensitive is tracked today. Keep it that way.

Cloud Functions will live at `little_blue_market/functions/` — **inside** the repo — so before the first Functions commit, extend `.gitignore`:

```
functions/.env*
functions/lib/
functions/node_modules/
*-service-account*.json
firebase-debug.log
.firebase/
```

Per your instruction, **each phase ends with a commit and a push to `main`**, gated on `flutter analyze` clean and `flutter test` green. Because Track A keeps the app runnable at every PR, each of those pushes is a working build rather than a checkpoint.

Please **don't paste token values into chat or into any file I read** — set them via `firebase functions:secrets:set` and I'll reference them by name only.

### Still outstanding

- ShipTurtle API credentials.
- **The ShipTurtle vendor ↔ app-user mapping rule** (probably vendor email). ⚠️ **Launch blocker.** Undefined today, and it blocks both revenue attribution *and* the ability of any existing seller to log into the app as a seller.
- Confirm the Shopify app's granted scopes cover `read_products, write_products, read_orders, read_customers, write_customers, read_inventory` — the client-credentials token carries whatever the app was granted, so a missing scope surfaces as a 403 at runtime rather than at setup.

---

## Track A — Client refactor on fixtures (PRs 1–10)

The app stays fully runnable and demo-able at every step, with **zero Firebase dependency** until PR 11. This is deliberate: it lets the entire UI, state, and async surface be finished and tested before any backend risk is introduced.

### PR 1 — UI removals and consolidations

| Change | Where |
|---|---|
| Remove the share/arrow icon | [post_card.dart:190](../lib/widgets/post_card.dart#L190) and the duplicated row at [post_screen.dart:299](../lib/screens/market/post_screen.dart#L299) |
| Save/bookmark → **Add to cart** icon (wired for real in PR 10) | [post_card.dart:192](../lib/widgets/post_card.dart#L192), [post_screen.dart:301](../lib/screens/market/post_screen.dart#L301) |
| **Unify the two action rows** — `_PostActions` and `_PostActionRow` are copy-paste duplicates | extract one public `PostActionBar` in `post_card.dart`, use in both |
| Remove points entirely | `points` field ([models.dart:20,39](../lib/models/models.dart#L20)); 8 literals in `fixtures.dart`; `_PointsPill` ([profile_identity.dart:81,135-191](../lib/widgets/profile_identity.dart#L135)); `showPointsSheet` ([sheets.dart:150](../lib/widgets/sheets.dart#L150)); `PointsDiamond` (`product_art.dart:193`) becomes dead |
| Remove the (i) icon | app-bar leading at [profile_screen.dart:38-42](../lib/screens/you/profile_screen.dart#L38), plus the inline `info_outline` inside the points pill |
| Remove Hot/New/Top | [forum_screen.dart:23-24,68-83](../lib/screens/community/forum_screen.dart#L68) — `_sort` is never read, so `ForumScreen` drops to `StatelessWidget` |

`LbmAppBar` already handles `leading: null` with `showBack: false`, so dropping the (i) is safe.

### PR 2 — Typed models + one formatting file

Pre-formatted display strings become real types. Formatting moves to `lib/models/formatting.dart`:

```dart
abstract final class Fmt {
  static String money(int cents);           // absorbs formatCents (models.dart:116)
  static String count(int n);               // 2412 -> "2,412"
  static String relative(DateTime t, {DateTime? now});  // "3d", "1w"
  static String clock(DateTime t);
  static String inboxAge(DateTime t);       // "2m" / "Yesterday" / "Mon"
  static String distanceMiles(double mi);
}
extension PersonFormat  on Person  { String get revenueLabel; }
extension ProductFormat on Product { String get price; String get locationLabel; }
```

Extension getters keep call sites nearly diff-free (`product.price` is unchanged). All time formatters take an injectable `now` via `nowProvider` — otherwise relative-time tests are flaky and fixture ages drift as the repo ages. Add `intl`, confined to this one file.

| Today | Becomes |
|---|---|
| `Person.revenue` = `'$4,820'` | `int revenueCents` |
| `Person.points` | deleted |
| `TagCount.count` = `'2,412 posts'` | `int postCount` |
| `Variant.price` String / `Variant.stock` free text | `int priceCents`, `bool availableForSale`, `int? quantityAvailable`, `String? availabilityNote` (services genuinely need free text) |
| `Variant.selected` | **deleted** — UI state in a data model; becomes `selectedVariantProvider(productId)` |
| `Review.age`, `ForumThread.age`, `ChatMessage.time`, `DmSummary.age` | `DateTime createdAt` |
| `ChatMessage.mine`, `DmMessage.mine` | **deleted** — derive `authorId == currentUid`. This is what kills the `Fx.meId` hardcode |
| `Forum.members` = `'312 members'` | `int memberCount` |
| `Product.photo` (asset key) | `List<String> imageUrls` — the detail screen needs a slideshow; fixtures emit `asset://…` and a small `LbmImage` branches on scheme so the demo stays offline |
| `Product.location` = `'Detroit, MI · 4 mi'` | `String cityState`, `double? lat/lng`, `bool freeShipping` — that one field packs three unrelated facts |
| `Shipment.step` | deleted — derive from `ShipmentState.index + 1` |
| `Person.tint` | keep (JSON-safe), but derive as a deterministic hash of uid, and add `String? avatarUrl` |

Also split `ProductSpec`: `histogram` moves to a new `RatingSummary` served by `SocialRepository` (it is social data, not commerce). ⚠️ `ratingTotal`'s `.clamp(1, …)` ([models.dart:192](../lib/models/models.dart#L192)) is a divide-by-zero guard that will make a zero-review product read **"1 rated"** — handle explicitly.

**Do not add `freezed`.** Against ~15 mostly-immutable models, build_runner watch cost, `part` files, and doc-comment loss don't pay for themselves. Instead: hand-written `copyWith` on the ~6 classes that actually mutate (`Person`, `Cart`, `CartLine`, `SearchFilters`, `Session`, `Product`), and **serialization in a separate mapper layer, not on the models** — `lib/data/firebase/mappers.dart`, `lib/data/shopify/shopify_mappers.dart`. This isn't taste: `Product` needs *two* wire formats (Shopify variant JSON vs. the Firestore mirror doc), which a single `fromJson` would have to pretend away. Keeping mappers out of `models/` is also what mechanically enforces "no Shopify types in widgets." Revisit freezed past ~30 models.

### PR 3 — New models

```dart
// post.dart — sealed, so PostCard switches exhaustively
sealed class Post { String get id; String get authorId; DateTime get createdAt;
                    List<String> get tags; int get likeCount; int get commentCount;
                    bool get likedByMe; }
final class ListingPost  extends Post { final Product product; }
final class ReviewPost   extends Post { final String productId; final int rating;
                                        final String text; final List<String> imageUrls; }
final class ShoutoutPost extends Post { final String text; final List<String> imageUrls;
                                        final String? aboutSellerId; }
```

Plus `Cart`/`CartLine`/`CheckoutHandoff`, `Order`/`OrderLine`, `Purchase`, `Comment`, `Message` (unifies `ChatMessage` + `DmMessage`, with `MessageStatus {sending, sent, failed}` for optimistic sends), `Address`, `SearchScope` enum, `SearchFilters`, `SearchResults`.

⚠️ `SearchFilters` **must** implement `==`/`hashCode` — it is a `.family` argument, and value equality is the only thing stopping a refetch on every rebuild.

### PR 4 — The repository seam

```
lib/data/
  repositories/     # pure Dart. No firebase/shopify imports allowed in here.
    catalog_repository.dart      commerce_repository.dart
    social_repository.dart       messaging_repository.dart
    profile_repository.dart      fulfillment_repository.dart
    search_repository.dart       exceptions.dart
  fixtures/         fixture_data.dart (today's Fx), fixture_store.dart, fixture_repositories.dart
  firebase/         mappers.dart, firestore_*_repository.dart, firebase_auth_service.dart
  shopify/          proxy_client.dart, shopify_*_repository.dart, shopify_mappers.dart
  providers.dart    # bindings + the backend flag
```

`SearchRepository` is deliberately **separate** from `CatalogRepository` — search is the one piece most likely to move to Algolia/Typesense independently (see Risk 8).

`exceptions.dart` defines `NotFoundException`, `OfflineException`, `PermissionException`, `RateLimitException`, `BackendException`. `LbmAsync` maps these to friendly copy — `e.toString()` never reaches a user.

**`Fx` becomes a fixture implementation**, moving to `lib/data/fixtures/fixture_data.dart` and seeding a **mutable** `FixtureStore` (streams for chatroom/conversations, mutable people/recents/likes/cart). This fixes today's discarded-state bugs *for free*: `chatroom_screen.dart:44` send, `dm_screen.dart:26` send, `search_screen.dart:153` recent-search removal, `edit_profile_screen.dart` fields, `new_forum_screen.dart` create — all currently die on pop. Once they write to `FixtureStore` and read back through the same `Stream`, **the widget code is final**: swapping in Firestore changes nothing above the repository line.

Bind with one flag, per repository:

```dart
enum Backend { fixtures, live }
final backendProvider = Provider<Backend>((ref) =>
    const String.fromEnvironment('LBM_BACKEND') == 'live' ? Backend.live : Backend.fixtures);

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) =>
    switch (ref.watch(backendProvider)) {
      Backend.fixtures => FixtureCatalogRepository(ref.watch(fixtureStoreProvider)),
      Backend.live     => ShopifyCatalogRepository(ref.watch(proxyClientProvider)),
    });
```

Run live with `flutter run --dart-define=LBM_BACKEND=live`. Because these are providers, not consts, each repository flips independently — which matters, since Firebase lands two PRs before Shopify.

Add `fixtureLatencyProvider` (0 in tests, ~250 ms in debug) so loading states get exercised in the demo but never hang `pumpAndSettle`. Add `test/no_fixture_imports_test.dart`, which greps `lib/screens/**` and `lib/widgets/**` for `data/fixtures` and fails — cheap, and the only thing that prevents backsliding.

### PR 5 — Async UI convention

`lib/widgets/async.dart` — **one** `LbmAsync<T>` widget rather than 20 scattered `.when()` blocks, because it bakes in three rules the design needs:

1. **Keep stale data while refreshing.** Skeleton only when `isLoading && !hasValue`; when both, render the data with a 2px accent progress line. Without this, every pull-to-refresh blanks a screen the design has no blank state for.
2. **Errors are copy, never exceptions** — `describeError()` maps the `exceptions.dart` types to sentences, with an `LbmCard` + ghost `PillButton('Try again')` calling `ref.invalidate`.
3. **Empty is first-class** (`isEmpty` / `empty` params), so `post_screen.dart:247` and `results_screen.dart:91` stop hand-rolling it inconsistently.

`lib/widgets/skeleton.dart` adds shape-matched skeletons (`PostCardSkeleton`, `GridSkeleton`, `IdentitySkeleton`, `ChipRailSkeleton`) built from `c.skyWash`, not spinners. ⚠️ **The pulse must be finite or gated on `MediaQuery.disableAnimationsOf`** — `screens_smoke_test.dart` pumps 23 routes × 2 themes through `pumpAndSettle`, and an infinitely repeating animation hangs every one of them.

Riverpod 3 patterns: `FutureProvider.family` for one-shot reads, `StreamProvider.family` for live Firestore collections, `AsyncNotifierProvider` for user-mutating state (cart, filters, composer). ⚠️ Riverpod 3 autoDisposes by default — add a `ref.cacheFor(Duration)` extension and apply it to `productProvider`/`specProvider`/`personProvider`, or the feed grid reloads every image on every back-navigation.

### PR 6 — Real session (still on fixtures)

```dart
sealed class Session {}
final class GuestSession       extends Session {}
final class OnboardingSession  extends Session { final String uid, email; }  // authed, no profile doc
final class MemberSession      extends Session { final String uid; final Person profile;
                                                 bool get isSeller => profile.isSeller; }
```

`SessionNotifier extends StreamNotifier<Session>` composes `authStateChanges()` with `profiles.watchPerson(uid)`. The existing passwordless UI in `auth_screens.dart` maps cleanly onto Firebase email-link or phone OTP — the screens stay; only `_confirm()` and `_finish()` change.

Three fixes worth calling out:

- **Move `themeMode` out of `Session`.** Today [session.dart:16](../lib/state/session.dart#L16) carries it and `app_router.dart:195` listens to the whole `sessionProvider` — so toggling the theme re-runs the router redirect. Give it `themeModeProvider`, persisted via `shared_preferences`.
- **Use Firebase anonymous auth for guests.** A guest gets a uid, so rules can require `request.auth != null`, and `linkWithCredential` upgrades anon → real on signup **preserving the cart** — which today's "Buy · sign up" flow silently throws away.
- **`_SessionListenable` must dedupe on session *type*.** Otherwise every Cloud-Function counter increment on `users/{uid}` (a like, a new post) re-runs the router redirect.

Keep the derived provider names (`isGuestProvider`, plus new `currentUidProvider`, `meProvider`, `isSellerProvider`) so `app_shell.dart:73`, `feed_screen.dart:32`, `post_screen.dart:30`, `product_screen.dart:35` and `requireProfile` ([sheets.dart:138](../lib/widgets/sheets.dart#L138)) compile unchanged. Add a sibling `requireSeller`.

Redirect gains an onboarding branch and must **not** bounce while `session.isLoading` (or cold start flashes guest → member). `main.dart` already `deferFirstFrame()`s for artwork — extend it to await the first non-loading session under the same timeout.

Kill `Fx.meId` by setting `FixtureAuthService.demoUid = 'maya'` — the hardcode survives in exactly one place, on the fixture backend only. Set `isSeller: false` on fixture person **dee** (already buyer-shaped: `revenue: '$0'`, no tags) so the buyer-vs-seller Edit Profile split is testable offline from day one — `screens_smoke_test.dart` already visits `/market/seller/dee`.

### PRs 7–10 — Screens go async

| PR | Screens |
|---|---|
| **7** | Market: feed, post, product, reviews, results, search |
| **8** | Profile, seller feed, edit profile (seller/buyer split), shipping |
| **9** | Community: chatroom, forums, forum, thread, new-forum → real streams and real sends |
| **10** | Messaging (inbox + DM; route becomes `/dm/:conversationId` with `?to=` for "message this seller"), then Commerce: `Cart`, buy sheet → `cartProvider`, variant selection wired through, checkout handoff stub. **Un-skip the fixture-import guard test.** |

Illustrative shape, [feed_screen.dart:59-81](../lib/screens/market/feed_screen.dart#L59):

```dart
// before — FeedScreen is stateful only to hold a _nearMe flag that filters nothing
itemCount: 6,                                     // hard-coded against Fx.tags (8 entries)
itemBuilder: (context, i) => LbmChip(Fx.tags[i].tag, ...)
for (final id in Fx.feedOrder) PostCard(Fx.product(id)),

// after — drops to ConsumerWidget; _nearMe moves into SearchFilters
LbmAsync<List<TagCount>>(ref.watch(popularTagsProvider),
  skeleton: const ChipRailSkeleton(),
  data: (tags) => ListView.separated(itemCount: tags.length, ...)),   // no more RangeError
LbmAsync<List<Post>>(ref.watch(feedProvider),
  skeleton: const PostCardSkeleton(count: 3),
  isEmpty: (posts) => posts.isEmpty, empty: const EmptyFeed(),
  data: (posts) => Column(children: [for (final p in posts) PostCard(post: p)])),
```

⚠️ A `SectionHead('${r.products.length} products')` **must move inside** `data:` — the count doesn't exist while loading.

**At the end of PR 10 the client is finished**: fully async, fully repository-backed, every screen's final code written, zero Firebase dependency.

---

## Track B — Live backends (PRs 11–15)

| PR | Contents |
|---|---|
| **11** | Firebase bootstrap: `firebase_core/auth/firestore/storage`, `firebase_options.dart`, rules + indexes in a root `firebase/` dir, `FirebaseAuthService` behind the flag. Fixtures still serve all data. |
| **12** | Live social + profile + messaging: `Firestore*Repository` + `mappers.dart` + an **emulator seed script that writes the fixture content**, so live and fixture render identical screens — that equivalence is the whole test strategy. |
| **13** | CF commerce proxy + `Shopify*Repository` + the `catalog` mirror + the product-webhook sync function + `orders/paid` attribution. |
| **14** | ShipTurtle: live `FulfillmentRepository`, order → shipment webhooks, seller tracking-number entry. |
| **15** | Cleanup: dead fixture fields, tighten rules, Firestore offline persistence, retry/backoff, analytics. |

**Milestone 1 = Track A complete + PRs 11–13** (market, product, profile, cart, checkout, order attribution all live). Community, forums, and seller tools go live in Milestone 2 (PRs 14–15 plus the feature work below).

---

## Feature work mapped to your seven items

**1. Search** — geolocation via `geolocator` ("near me", with a permission flow) and `geocoding` (typed address), default radius **20 miles**, persisted so the feed and search agree. `catalog` docs carry `lat`/`lng`/`geohash`; query bounding boxes then filter to the exact radius client-side. The scope chips — cosmetic today at `search_screen.dart:25` (4 scopes) and `results_screen.dart:29` (3 scopes, a different list) — collapse into one `SearchScope` enum on `SearchFilters` and actually filter: hashtags, keywords, seller name, good/service type.

**2. Market feed** — chronological `posts` stream replacing the hardcoded `Fx.feedOrder`; listing / review / shoutout posts in one stream; working like (optimistic + `likes/{uid}` subcollection + `FieldValue.increment`), working comment, working add-to-cart, product reviews surfacing in-feed. Arrow removed, Save → Add to cart.

**3. Profile detail** — real post count, real revenue (sellers only), profile photo from Storage, bio, username. Points gone. The "Bought & received" tab reads `purchases/{uid}/items`. **Message button works** → `conversationWith(personId)` → real DM thread.

**4. Product detail** — swipeable `PageView` + dot indicator over `imageUrls`; title, description, comments with like counts, reviews; Buy **and** Add to cart.

**5. Community** — one global `chatroom/messages` collection, streamed and paginated. Keep the pull-down-for-forums gesture ([chatroom_screen.dart:36-42](../lib/screens/community/chatroom_screen.dart#L36)) exactly as-is. Replace the hardcoded `'1,284 here now'` (line 82) with real presence or drop it.

**6. Forums** — the create form exists; clear its hardcoded demo text ([new_forum_screen.dart:18-24](../lib/screens/community/new_forum_screen.dart#L18)) and make Create write a doc. Join via `forums/{id}/members/{uid}` + counter → real member counts. Upvote forums, threads, and thread comments (a `votes/{uid}` subcollection + denormalized counter, optimistic). New thread (a no-op today at `forum_screen.dart:95`) and thread comments (the composer has no `onSend`) become real. Real `threadCount`. Hot/New/Top removed. ⚠️ `Fx.comments` is one global list rendered under *every* thread (`thread_screen.dart:137`) — must become a `threads/{id}/comments` subcollection.

**7. Edit profile** — split by `isSellerProvider`. Today [edit_profile_screen.dart:109-134](../lib/screens/you/edit_profile_screen.dart#L109) hardcodes "Payouts & bank · Ends in 4471" for *everyone including buyers*.
- *Buyers*: name, photo, bio, hashtags (make the inert `'+ add'` chip at line 99 work), shipping addresses, a "Start selling" row that flips `isSeller`, Save that actually persists, messages entry point, and the ⋯ overflow opening package/shipping info.
- *Sellers additionally*: post goods/services from Shopify (pick existing via Admin API, or create new — photos to Storage then to Shopify, mirrored back by webhook), a **Manage sales** tab in [shipping_screen.dart](../lib/screens/you/shipping_screen.dart) for entering tracking number + courier (writes a fulfilment to Shopify/ShipTurtle, reusing the existing `Sending`/`Receiving` segments and `_TrackBar`), and revenue.

**Post composer** (`showNewPostSheet`, [sheets.dart:488](../lib/widgets/sheets.dart#L488)) — **Review** lists purchased items from `purchases/`; **Shoutout** gets @-mention autocomplete over sellers; **Listing** (sellers) picks or creates a Shopify product.

---

## Verification

**The existing test suite is the migration's safety net and should be extended, not replaced.** [screens_smoke_test.dart](../test/screens_smoke_test.dart) renders 23 routes × 2 brightnesses and fails on layout overflow; `guest_gating_test.dart`, `text_scaling_test.dart`, and `design_tokens_test.dart` guard the rest. (`visual_check.dart` writes reference screenshots to `test/shots/` but is deliberately not `_test`-suffixed, so `flutter test` skips it — regenerate with `flutter test test/visual_check.dart --update-goldens` after PR 1's UI removals.)

**Per PR:** `flutter analyze` clean, full `flutter test` green, `flutter run` on a device. Track A keeps `LBM_BACKEND=fixtures`, so the smoke test covers every step of the refactor.

**Add to the suite as you go:**
- `test/no_fixture_imports_test.dart` (PR 4, skipped until PR 10).
- `'/market/results?q=zzzz'` to `_routes` — it will fail until a real empty state exists (see Risk 1).
- `LbmAsync` widget tests for loading / stale-refresh / error / empty.
- Cloud Functions unit tests for **webhook HMAC verification, order normalization, and counter idempotency** — the pieces where a bug silently corrupts money data.
- Firestore rules tests (`@firebase/rules-unit-testing`) proving a client cannot write `revenueCents` or `purchaseCount`.

**Critical end-to-end paths, tested manually against Shopify test mode:**
- **Purchase attribution** — sign in as a test buyer, add to cart, complete checkout; within seconds the buyer's purchase count increments, the item appears under "Bought & received", and the seller's revenue rises by the correct **line** amount.
- **Website order still attributes** — place an order on the live website with a known app user's email and confirm it lands on their app profile. This is the regression that would hurt real users.
- **Existing buyer logs in without signing up** — take a real website customer's email, sign in on the app, and confirm: no signup form, name and addresses prefilled from Shopify, and past orders visible under "Bought & received".
- **Existing seller logs in as a seller** — same, for a ShipTurtle vendor: `isSeller` true, storefront products present, revenue populated.
- **Linking cannot be spoofed** — call the link Function with someone else's email as a parameter and confirm it is ignored in favour of the verified token claim.
- **Webhook idempotency** — replay the same `orders/paid` payload twice; counters must not double.
- **Search radius** — a listing 15 miles away appears, one 25 miles away does not, a typed address changes the result set.
- **Guest → member upgrade preserves the cart.**

---

## Risks (all verified against the code)

1. **`Fx.search` never returns empty** — [fixtures.dart:912](../lib/data/fixtures.dart#L912) falls back to `['p1','p4']`, so `results_screen.dart` has no empty state for products or sellers, and `SectionHead('0 products')` would read badly. Make the fixture search honest in PR 4 and add the failing smoke route.
2. **`SellerFeedScreen` fabricates a storefront** — [seller_feed_screen.dart:40](../lib/screens/market/seller_feed_screen.dart#L40) falls back to `['p1','p4','p5']` for a person with no products, so **dee the buyer currently displays Kali's products as her own**; line 43 then pads by duplicating (`[...source, ...source].take(9)`), which with real data yields duplicate widget keys and duplicate analytics. Both go in PR 8. The `_tab` index is also tracked but ignored — the tab must actually switch the grid.
3. **Silent wrong-record fallbacks are a privacy bug the moment profiles are real** — `Fx.product` (`:247`), `Fx.person` (`:134`), `Fx.spec` (`:579`) return `p1`/`maya` on a miss; `Fx.forum`/`Fx.thread` use `orElse: () => first`. A bad deep link shows *someone else's profile*. Repos must throw `NotFoundException`; screens need a not-found state.
4. **Badges are decided by grid position, not data** — `seller_feed_screen.dart:93` (`i % 3 == 1 ? 'Review'`) and `profile_screen.dart:105` (`_tab == 1 && i < 2 ? 'Reviewed'`). Once `Post` is sealed, the badge comes from `post is ReviewPost`.
5. **The buy sheet ignores the selected variant** — `product_screen.dart:293` passes only `product`, and [sheets.dart:284](../lib/widgets/sheets.dart#L284) totals `p.priceCents * _quantity + Fx.shippingCents`. With real variant prices this ships **wrong totals**. Fix in PR 10 alongside `selectedVariantProvider`.
6. **DMs are one global thread** — `dm_screen.dart:24` loads the same `Fx.dmThread` for all four inbox rows, and line 144 pins `Fx.product('p1')` as "the order this conversation is about" for every conversation. The route is keyed by `personId`, so real data needs a `conversationWith(personId)` hop before the first message renders — resolve the id at the inbox row to hide that latency.
7. **Shopify checkout completion is the weak joint.** The app can't reliably observe that checkout finished. Treat `orders/paid` as the only truth and have the post-checkout screen say "we'll confirm shortly" rather than asserting success. Also verify whether Shopify's Checkout Sheet Kit has a current Flutter binding; the fallback is `flutter_inappwebview` watching for the thank-you URL.
8. **Firestore cannot serve this feed natively.** "Goods and services in one stream, filtered by hashtag, within N miles" is not one Firestore query — no native geo, and array-contains + orderBy + range still can't combine with a geohash range. For v1, run the geo query first and rank text client-side over the candidate set; fine at current volume. Decide on Typesense/Algolia before PR 13 — this is exactly why `SearchRepository` is split out.
9. **Firestore counters under contention** — always `FieldValue.increment`, never read-modify-write, for likes, upvotes, revenue, member counts.
10. **`PostCard` has no design for review or shoutout posts.** The prototype only renders listings. PR 7 should render `ListingPost` fully and give the other two a minimal card — don't let a missing design block the data layer.
11. **The Admin token broker is a single point of failure for every seller-side feature.** If minting fails, product listing, product creation, and order lookup all break at once. It needs its own unit tests (cache hit, expiry refresh, 401-retry-once, concurrent-cold-start transaction) and an alert on repeated mint failures — a silently expired app registration would otherwise look like "the seller tab is broken."
