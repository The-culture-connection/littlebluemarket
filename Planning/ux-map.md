# Little Blue Market — UX map (final, Sept 25 2026)

Companion to `Planning/feed-and-details-mockup.html`. Pinterest-style grid; the photo is the card; orchid is reserved for cart actions.

## The optimal path

1. **Land on a moment.** Welcome popup once ("adding to cart is the like"), then the feed opens on the announcement hero.
2. **Scroll the grid.** Products, reviews, cart posts, forum threads, an Open-chat moment, a poll and a shoutout all in one two-column masonry. Filter chips: All · Products · Reviews · Carts · Forums · Chat · Community.
3. **Cart from the grid.** Tap the pill on a photo → bounce, toast with the photo, cart badge ticks. No screen change.
4. **Open a product.** Gallery with dots → maker row with **Ask** → price, variants, proof ("340 carted · Rae and 2 people you've bought from") → one big Add to cart + Buy now → ship / pickup / returns facts → description → Reviews (histogram, verified/with-photos chips, maker replies, Write one) → Talk about it (comments + quick chips) → Also sold by this seller (their other products).
5. **Ask the maker.** Ask opens a DM already "about" that product; the maker can drop a product card that carts from inside the thread.
6. **Buy → deliver → review.** After delivery a "How was the jam?" nudge appears in the feed and a quiet banner on the You tab. One-tap stars, chips, optional photo. The review becomes a pin. No points.
7. **Review → someone else's cart.** Review pins show the photo with a star strip; the reviewer sees "4 carted from this review".
8. **Community in the feed.** Forum pins: question + best reply + who's in it + Join in. Chat pin: live dot, last two messages, "14 in the last hour". Tapping lands inside with quick replies preloaded.
9. **Tags are collections.** Every #tag has a page (hero, filters, grid) with Follow and Notify me; following puts its posts in your Following tab, Notify sends a push + bell on every new post under it. Profile setup asks for 3 tags and follows them.
10. **Post your cart.** Cart screen → "Post this cart" → snapshot pin with a collage and Add all. Other people's carts are bundles.
11. **Admin levers.** Announcements are hero pins, polls are pins, a pinned message tops Open chat — all from the admin site.

## The three loops (each ends back in the grid)

- **Buy loop:** see → cart → buy → deliver → review → review becomes a pin → someone else sees it.
- **Talk loop:** see a thread / the room in the feed → tap in → reply with a chip → the thread shows in your feed as it moves → you come back.
- **Maker loop:** listing approved → "post it?" push → pin in feed → carted count → drop alerts → restock pin → repeat.

## Feed mix and rules

Roughly half products, a fifth reviews + carts, a fifth community, one admin item per screen.

- Never two of the same kind in a row (products excepted).
- One chat moment per screen-height, max.
- Forum pins only for forums you joined, threads with 5+ replies, or threads near you.
- One admin pin per screen: announcement or poll; hero treatment only for the newest.
- A dismissed nudge stays gone 7 days.
- No raw auto-posting of the catalog: products enter as maker posts, "new in the shop" batches, restock/drop pins, and rails.

## Pin kinds (client renders by `kind`)

product · review · cart · forum · chat · poll · announcement · shoutout · nudge · makers-rail

## Backend needed for the feed assembly function

- posts, reviews, cart posts — exist.
- hot threads: query `threads` by `commentCount` + recency, plus "forums you joined".
- chat moment: rolling 1-hour message count + last 2 messages from `chatroom`.
- announcements: exist; polls: new `polls` collection with per-user vote docs.
- per-user nudges: delivered-not-reviewed, carted-not-bought (3 days), followed maker posted.

## Decisions locked on Sept 25

- Welcome screen + GIF unchanged.
- No points, levels or streaks anywhere.
- You hub is quiet: identity, tags, four stats, one review banner, one sell row, tabs, grid. No shipping or orders.
- Seller "Under review" links out to Shipturtle; there is no Orders screen.
- Product detail cross-sell is "Also sold by this seller", not "also in carts".
- Full plan: `Planning/redesign-plan.md`.

## Build order for Claude Code

1. **Frontend** — `PinCard` variants + `SliverMasonryGrid` (flutter_staggered_grid_view) in `feed_screen.dart`; filter chips; cart pill with `AnimatedScale` + toast.
2. **Frontend** — product detail rebuilt from the mockup (gallery, variants, proof, facts, reviews block, comments, related masonries); review detail; cart-post detail.
3. **Frontend** — forum thread / open chat / DM get quick-reply chips and product cards in messages.
4. **Backend** — feed assembly Cloud Function returning a mixed, ordered list by `kind`; hot-threads + chat-moment queries; polls collection + rules.
5. **Backend** — nudge generation (delivery → review prompt; carted-not-bought; maker posted).
