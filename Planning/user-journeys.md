# User journeys — buyer, then unified

Companion to `Planning/backend-architecture.md`, which says which box owns what. This one says what a
person does, screen by screen, and which function moves underneath each tap.

Two product decisions are settled here and ripple through everything below:

- **The heart is gone. Adding to your cart is the affinity signal.** One action, not two.
- **Upvoting is gone.** Forums and threads are chronological and conversational, not ranked.

---

## Part 1 — The buyer

### 1.1 Arriving

Welcome GIF → welcome screen → **Sign in · Create a profile · Continue as a guest**.

| Choice | What happens | What they can do |
|---|---|---|
| Guest | `signInAnonymously()`. A real uid, so rules can require one and a cart survives signing up later | Marketplace tab only. Browse, search, build a cart |
| Create a profile | Email + code. `linkGuestToEmail` **upgrades the anonymous account in place**, so the cart they already built comes with them | Everything |
| Sign in | Same, plus `linkAccounts` finds their Shopify customer record and backfills purchase history | Everything |

`firestore.rules` already draws this line with `member()` — signed in *and* not anonymous. A guest can
read and can hold a cart; a guest cannot post, comment, review or message. Keep it that way: the
anonymous tier exists so the first thing a stranger sees is the market, not a wall.

The moment a guest tries to post, comment or check out, the app prompts to finish the profile
(`requireProfile` in `widgets/post_card.dart` already does this). **Their cart is not lost** — that is
the whole reason guests get a uid.

### 1.2 Scrolling the marketplace

The feed is `posts`, newest first, optionally narrowed by tag — the `tags CONTAINS + createdAt DESC`
index already exists. Three post kinds render today (listing, review, shoutout) and this plan adds a
fourth (cart).

Every card carries: author, image, body, **Add to cart**, **Comment**, **Repost**, and a count line
reading "*N* added · *M* comments".

Reads come from the `catalog` mirror, never from Shopify, so the feed paints offline and instantly.
The only read that goes live is stock, and only at the moment of buying (`commerceLiveVariants`).

### 1.3 Add to cart — which is also the like

This is the change with the widest blast radius, so it is specified exactly.

**UI.** `PostActionBar` in `lib/widgets/post_card.dart` currently renders Like, Comment and
optionally Add to cart as three separate actions. It becomes two: **Add to cart** and **Comment**,
plus Repost. The `liked` / `onLike` parameters and the heart icon go. The count line changes from
`'${Fmt.count(post.likeCount)} likes'` to `'${Fmt.count(post.saveCount)} added'`.

**Data.** The existing one-doc-per-person idempotency pattern is kept and renamed:

```
catalog/{productId}/carted/{uid}     marker, function-written, doc id = uid
catalog/{productId}.inCartsCount     live — how many carts hold it right now
catalog/{productId}.saveCount        monotonic — all-time adds, never decremented
posts/{postId}.saveCount             denormalised from the product, for the card
```

**Who writes it.** `commerceAddLine` and `commerceRemoveLine` — the Cloud Functions, using the Admin
SDK. Not the client. This matters: if the marker were client-writable, the count could be inflated
without a cart line ever existing, and the number on a card is now a public signal that sellers will
read. `carted/{uid}` is `allow read: if true; allow write: if false;`.

**Name it `inCartsCount`, not `cartCount`.** `cartCountProvider` already exists in
`lib/state/providers.dart` and means *how many items are in my own cart* — it drives the tab badge.
Two different `cartCount`s in one codebase is a bug waiting for a tired afternoon.

**Two counters, on purpose.** `saveCount` is what the card shows — it only goes up, so a card does
not visibly lose love when someone checks out. `inCartsCount` is what the *seller* sees on her own
listing: "3 people have this in their cart right now", which is genuinely actionable and is the
number that should drop when they buy or remove.

**Removing from the cart** deletes the marker and decrements `inCartsCount` only. **Checking out**
leaves the marker; `recordPaidOrder` converts it into a purchase document, and `inCartsCount` falls as
the cart clears.

**Tutorial note — required, not optional.** Removing a heart from a social feed reads as a missing
feature unless it is explained. The onboarding tutorial gets a card:

> **♡ is now 🛒** — On Little Blue Market, adding something to your cart is how you show a maker you
> love their work. There is no separate like. Your cart is a wishlist you can act on, and you can
> post it whenever you want.

Place it in the first-run tutorial and again as a one-time tip the first time a card is tapped.

### 1.4 Searching

Search is its own screen: popular hashtags on top, recent searches below, a query box, and a
**near me** toggle.

- Hashtag, keyword or product type, over the `catalog` mirror.
- Radius search uses the `active + geohash` index; geohash prefixes are range-scanned, so the hash is
  the last ordered field and text ranking happens over the candidate set.
- Recent searches are per-user and local to their profile document.

**Two fixes this depends on** (PR 17 in the architecture plan): the store's real taxonomy is its **92
collections**, not `product_type` — which is literally `"physical"` on live products — and
`mirrorProduct` currently discards every tag that does not start with `#`, which is all of them. Until
both land, search by type or tag returns nothing for real catalog data.

### 1.5 Buying

1. Tap **Add to cart** on a card, or open the product and pick a variant.
2. `commerceAddLine` prices the line **server-side** from `catalog/{id}/spec/detail`. No client-supplied
   price is accepted anywhere in this app.
3. Cart screen renders from `carts/{uid}`, which is theirs alone by rule.
4. Checkout: `commerceBeginCheckout` calls Storefront `cartCreate`, stamping `app_uid` on the cart and
   `app_seller_uid` on every line, and returns `checkoutUrl`. **Nothing at this point claims a
   purchase happened** — the post-checkout screen says "we'll confirm shortly".
5. They pay on Shopify. Funds land in the marketplace owner's gateway.
6. `orders/paid` → `normalizeOrder` → `recordPaidOrder`: one transaction keyed by Shopify's order id,
   so a retried webhook is a no-op. Purchase documents appear under `users/{uid}/purchases`, one per
   line, and the Bought grid fills in.

Before the buy sheet commits, `commerceLiveVariants` re-reads stock straight from Admin. It is the one
read that must not come from the mirror: a few minutes of staleness is how the same thing gets sold
twice.

### 1.6 Receiving, then reviewing

`recordFulfillment` — fed either by the seller using the app or by Shipturtle's webhook when she
shipped from her vendor dashboard — writes the shipment onto the order and flips
`purchases/{id}.delivered`.

**Delivered is what unlocks a review.** The Receiving tab shows a "How was it?" prompt on each
delivered, unreviewed purchase.

1. The composer writes `catalog/{productId}/reviews/{reviewId}` with `authorId`, `rating` 1–5, body,
   photos, and **`purchaseId`**.
2. Rules already enforce the shape: `member()`, `authorIsSelf()`, `rating is int` in 1..5. They cannot
   check the purchase is real — a rule cannot read another user's private subcollection.
3. **New Firestore trigger `onReviewWritten`** does the part rules cannot: verifies
   `users/{authorId}/purchases/{purchaseId}` exists, is delivered, and names this product. If not, it
   deletes the review. If so it increments `catalog/{id}/rating` histogram, sets `purchases/{id}.reviewed = true`,
   and creates the `ReviewPost` in the feed.
   *This function is referenced by the existing rules comment ("checked by the function that mirrors
   it onto the product") and does not exist yet.*
4. The review appears on the product, in the seller's feed, and under the hashtags it was tagged with —
   reviews stay tied to the product they were posted from.

### 1.7 The cart on their profile, and posting it

The profile mirrors Instagram: followers = revenue, following = things bought, ⋯ opens shipping,
envelope opens messages. **Add a Cart tab** beside Bought.

**Posting a cart** is a new post kind. The critical design constraint: a post must be a **snapshot**,
never a live reference to the cart. A cart changes by the minute; a post that mutated after
publication — or emptied itself at checkout — would be a bug people notice immediately.

```
posts/{postId}
  kind        'cart'
  authorId    uid
  caption     string?
  items       [{ productId, title, imageUrl, sellerId, priceCents }]   ≤ 24, frozen at post time
  itemCount   int
  tags        [string]
  saveCount, commentCount   int, function-written
```

Rendering: a horizontally scrolling row of the items with **Add all to my cart** →
new callable `commerceAddManyLines(productIds)`, which is `commerceAddLine` in a loop with one
transaction and the same server-side pricing. Items that have gone out of stock are skipped and
reported, not silently dropped.

**Privacy line, stated so it does not get blurred later:** `carts/{uid}` stays `allow read, write: if
isSelf(uid)` — a cart is private. A cart *post* is a deliberate, explicit publication of a copy. The
two are different documents and only one of them is public. Nothing in the app should ever read
another person's live cart.

Model work: `CartPost` as a fourth `final class` on the sealed `Post`. Because `Post` is sealed, every
`switch` over it becomes a compile error until it handles the new kind — which is exactly why it was
sealed, and the fastest way to find every render site.

### 1.8 Community and forums, as a buyer

Covered in Part 2 — they are identical for buyers and sellers, which is the point.

---

## Part 2 — The unified journey

There is one account type. A seller is a buyer with a verified vendor grant; nothing else differs.
The tab bar, the feed, the cart and the community are the same product for both.

### 2.1 What changes when someone becomes a seller

Exactly three things appear, all keyed off a **custom claim on the auth token**, not a client-writable
field (see `Planning/backend-architecture.md` §8):

1. A **Products** tab on their own profile, with the **Add** button.
2. A **Sending** tab in shipping, and the ability to add tracking.
3. A **Total sales** row.

Everything else — feed, cart, search, forums, chatroom, reviews — is unchanged. A seller browsing the
marketplace is just a person browsing the marketplace.

### 2.2 Total sales, not revenue

`users/{uid}.revenueCents` is renamed **`grossSalesCents`** and labelled **"Total sales"** everywhere
it appears.

Why: `recordPaidOrder` increments it by the gross line total, but the vendor plan takes **9.5%
commission**, the marketplace owner holds the funds, and Shipturtle computes the actual payout. A
number labelled "revenue" or "earnings" is a promise of money that is roughly a tenth wrong. "Total
sales" is exactly what the figure is.

Files: `functions/src/orders.ts` (`recordPaidOrder`), `firebase/firestore.rules` (the `untouched`
lock list), `lib/data/firebase/mappers.dart`, `lib/models/models.dart` (`Person`),
`lib/screens/you/profile_screen.dart`, `lib/screens/you/edit_profile_screen.dart`,
`lib/data/fixtures/`, and the tests that assert on it.

No payable figure is shown at all until Shipturtle's payout API is available. When it is,
`payoutsPaidCents` and `payoutsPendingCents` come **from Shipturtle** as separate fields. Do not
re-derive them locally — product-level and category-level commission overrides exist and any local
calculation will drift.

### 2.3 Writing in the community

One open chatroom, with an arrow at the top that swipes down to forums.

- `chatroom/{messageId}`, `allow create: if member() && authorIsSelf()`.
- History is immutable: `allow update: if false`. You may delete your own message and nothing else.
- Guests read but cannot post. The composer shows the finish-your-profile prompt instead.

### 2.4 Forums — creating, reading, commenting

**Upvoting is removed entirely.** Threads and comments are chronological. What goes:

| Where | What is deleted |
|---|---|
| `lib/models/models.dart` | the `upvotes` field on both vote-carrying models (lines ~367, ~388) |
| `lib/data/repositories/repositories.dart` | `voteThread`, `voteThreadComment`, `voteForum` |
| `lib/data/firebase/firestore_social_repository.dart` | all vote implementations and the `votes` subcollection reads |
| `lib/data/fixtures/` | vote fixtures and the fixture repository's vote methods |
| `lib/screens/community/thread_screen.dart`, `forum_screen.dart` | the arrows, the score, the tap handlers |
| `firebase/firestore.rules` | `match /votes/{uid}` under threads and thread comments; `upvotes` from the two `untouched` lists |
| `lib/data/firebase/mappers.dart` | `upvotes` mapping |

Hot / New / Top were already removed in PR 1, so nothing is left that needs a score. Ordering is
`forumId ASC + createdAt DESC`, an index that already exists — **this change removes work, it does not
add any.**

What remains, and is the whole point of the surface:

- **Creating a forum.** `createForum(NewForum)` → `forums/{id}`. Rules require `memberCount == 1` and
  `threadCount == 0` at creation, so nobody starts a forum that claims a following. Counters move by
  `FieldValue.increment` from the `members/{uid}` subcollection, never by writing a total.
- **Joining.** `members/{uid}`, doc id = uid, so joining twice is idempotent.
- **Threads.** Reddit-shaped: title, body, comments. `authorIsSelf()`, `commentCount == 0` at
  creation, and `authorId` / `createdAt` / `commentCount` locked against later edits.
- **Comments.** `threads/{id}/comments/{commentId}`, `member() && authorIsSelf()`. Editable and
  deletable by their author, by nobody else.

`thread_screen.dart:137` still renders one global `Fx.comments` list under every thread. That is a
PR 9 trap and must be gone before this ships, or every thread shows the same conversation.

### 2.5 Posting, across all four kinds

| Kind | Who | Body | Subject |
|---|---|---|---|
| `listing` | seller | caption + a product from her own shop | `productId` |
| `review` | buyer | rating + body, gated on a delivered purchase | `productId` + `purchaseId` |
| `shoutout` | anyone | text about a seller | none |
| `cart` *(new)* | anyone | caption + frozen snapshot of their cart | the items |

`ListingComposer` in `lib/widgets/composers.dart` already implements the listing case — it reads
`productsBySeller` rather than making her retype anything. It is written and currently unreachable
only because `catalog.sellerId` is empty; PR 16 switches it on.

Hashtags on any post are initiatives. `onPostWritten` moves `hashtags/{tag}.postCount` by increment —
a counter per tag rather than a count query, because Firestore charges per document a count reads and
this is on the first screen of the app.

**Note the split:** product tags come from Shopify and describe the object. Post hashtags are typed
by people and describe the initiative. `mirrorProduct` conflating them — by keeping only `#`-prefixed
product tags — is the bug that makes both empty.

### 2.6 The action bar, final form

Every post card, every kind:

**🛒 Add to cart** (products only) · **💬 Comment** · **↻ Repost** · "*N* added · *M* comments"

A shoutout has no product, so it shows Comment and Repost only. That is the honest consequence of
collapsing the like into the cart, and it is fine: shoutouts are about a person, and the thing you
do with a person you like is go to their shop.

---

## Part 3 — Sequencing

Slots into the architecture plan's PR list.

- **PR 16** — the join key and the seller guard. Nothing here works without it.
- **PR 17** — real catalog: bulk backfill, collections, tags. Search and browse become true.
- **PR 18** — the seller write path: `listings/`, the composer, `sellerPublishListing`, the
  under-review modal, `sellerRefreshListings`.
- **PR 19** — **this document's client work**: remove voting, collapse like into cart,
  `saveCount`/`inCartsCount`, `grossSalesCents` relabel, the tutorial card.
- **PR 20** — `CartPost`, the Cart tab on the profile, `commerceAddManyLines`, `onReviewWritten` and
  the delivered→review prompt.
- **PR 21** — Shipturtle, once the API token lands: automatic vendor linking, payout figures,
  approval and rejection status, the real fulfilment endpoint.

Definition of done is unchanged: `flutter analyze` clean, `flutter test` green, `npm test` green in
`functions/`, fix the cause and never the assertion. Removing voting will break tests that assert on
it — those assertions encode behaviour this plan explicitly changes, so update them and say so in the
commit.
