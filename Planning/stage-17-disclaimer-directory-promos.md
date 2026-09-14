# Stage 17, the six changes Grace asked for on 2026-09-14

Grace's list, in her words, with what it becomes in code. The order below is
the order of work: the two small ones first, so something is tappable within
the hour, then the promos, then the whole directory, which is the big one.

| # | Grace's ask | Checkpoint | Size |
|---|-------------|-----------|------|
| 4 | The three dots on posts do nothing; make them report | CP-17A | one line |
| 1 | A disclaimer after the tutorial | CP-17B | small |
| 3, 5, 6 | Adverts, Little Blue announcements, fading popups | CP-17C, CP-17D | medium |
| 2 | Pull the whole littlebluecart.com directory, browse it by category, search it, claim from it | CP-17E, CP-17F | large |

Decisions Grace made when this was planned (2026-09-14):

- **Adverts and announcements are uploaded from the admin website**, the
  Railway one she already signs in to, not from the app's Admin screen.
  Picking image files is a computer job.
- **The disclaimer's second line is about sellers and the bio on their Little
  Blue Market profile**, not their social media bios.
- **A popup shows once per app opening**, and never the same one twice.
- **Unclaimed directory listings stay out of the Market feed.** They live
  under Browse the directory and in search. A listing enters the feed when
  its owner claims it, exactly as it does today.

---

## 1. CP-17A, the three dots report (Grace's #4)

`lib/widgets/post_card.dart:639` is `onPressed: () {}`. An empty callback,
never wired. Everything it needs already exists and already works from two
other screens: `showMoreSheet` in `lib/widgets/report_sheet.dart`, which
offers Report, sends guests to make a profile first, refuses to let someone
report themselves, and writes through `reportRepositoryProvider`. The reports
land in the Admin screen's reports section, which is already built.

The only real work: `_PostHead` is a `StatelessWidget` and `showMoreSheet`
needs a `WidgetRef`. It becomes a `ConsumerWidget`. The author's name and
handle are already in hand there, so nothing new is read.

Same fix, same sheet, on the post screen and the seller feed, which already
call it. Nothing to change there.

## 2. CP-17B, the disclaimer (Grace's #1)

A new `lib/widgets/keep_it_here_dialog.dart`, shown by `app_shell.dart`
immediately after `showFirstTour(context)` returns. That covers "through or
skipped" in one line, because Skip pops the same dialog.

Not dismissible by tapping outside; one **I understand** button. Remembered
by the same `Tips.firstTour` write that already follows the tour, so the pair
is shown once per phone. Copy, as agreed:

> **Keeping Little Blue Cart alive**
>
> To keep Little Blue Cart alive, we ask buyers and sellers to keep
> transactions inside the platform where possible, and to report any seller
> or buyer who tries to push a purchase to another platform.
>
> We also ask sellers to add their Little Blue Cart link to the bio on their
> profile.
>
> To report someone, tap the three dots on any post or profile.

That last line only becomes true once CP-17A lands, which is why CP-17A goes
first.

## 3. CP-17C and CP-17D, adverts and announcements (Grace's #3, #5, #6)

Grace asked for adverts, then asked for announcements "exactly like the
advertisement feature". They are one feature with two flavours, so they are
built as one: one collection, one admin form, one popup. Two names on one
mechanism cannot drift apart into two different-looking popups.

### The data

`promos/{id}`, written only by a callable:

```
kind        'ad' | 'announcement'
title       string, 60 max
caption     string, 180 max
imageUrls   string[], up to 4, in Storage under promos/
ctaLabel    string, 24 max, the button's words ("Shop the sale")
ctaUrl      string, where the button goes
audience    'all' | 'sellers' | 'buyers' | 'directory'  (AnnouncementAudience, reused)
active      bool
createdAt   timestamp
startsAt    timestamp, optional
endsAt      timestamp, optional
impressions int, clicks int   (FieldValue.increment, never read-modify-write)
```

Rules: `allow read: if resource.data.active == true || admin();` and
`allow write: if false;`. The `admin()` half is not decoration: without it,
pressing Pause would make the row disappear from the admin website's own
list and Resume would be unreachable. Storage gets `promos/{file}`, public read, written
only by a token carrying the admin claim, images under 10 MB, matching the
shape of the four paths already there.

An **announcement keeps everything it does today**: `adminSendAnnouncement`
still writes `announcements/{id}`, still pushes to the audience topic, still
shows under the bell. It gains `imageUrls`, `ctaLabel` and `ctaUrl`, and it
now also writes a `promos/{id}` document with `kind: 'announcement'` so the
same news can fade in on the feed. An **advert** writes only the promo
document: no push, no bell row, because an advert is not news.

New callables in `functions/src/promos.ts`: `adminPromoSave`,
`adminPromoSetActive`, `adminPromoDelete`. Each one checks the admin claim
the way `admin.ts` already does. Reading the list in the admin website goes
straight to Firestore, the way the feedback list already does.

### The admin website

Two new cards in `admin-web/public/index.html`, under the announcement form.
**Adverts and popups**: the kind, the audience, title, caption, a file picker
(straight to Storage through the Firebase web SDK, newly imported on that
page), the button's wording, the link, an optional start and end, and a live
preview of the popup drawn as the phone draws it, so Grace sees what people
will see before she posts it. **Live now**: everything posted, newest first,
with seen and tapped counts and Pause, Resume and Delete on each.

The existing announcement card stays where it is: it is the fastest path to
"tell everyone something", and it now carries the optional photo and button.

### The popup (Grace's #6, "non abrasive so quickly fade in/out")

`lib/widgets/promo_popup.dart`, mounted in the `MaterialApp` builder inside
`FeedbackLayer` (so it floats over every tab and every sheet, and a bug
report's screenshot shows the popup the person was looking at):

- Fades in over 400 ms, 3 seconds after the feed settles, so it never
  competes with the first paint.
- A card, not a full-screen barrier, and it does not block the screen behind
  it: the photo, the title, the caption, the CTA pill, and an X.
- Fades out on the X, on the CTA, on a flick downwards, or on its own after
  12 seconds. Deliberately no tap-outside barrier: a transparent barrier that
  swallows or competes for the tap is how a "non abrasive" popup becomes the
  thing that ate your tap on a product.
- **Once per app opening**, and never the same promo twice: the seen ids live
  in `SharedPreferences` beside `Tips`, and a session flag in a provider
  stops a second one after a tab change.
- The CTA opens the link with `url_launcher`, the same
  `LaunchMode.externalApplication` the directory card already uses.
- Off under `FLUTTER_TEST`, like every other timer in this app, or it breaks
  every widget test (see `kUnderFlutterTest` in `dev_error_sink.dart`).
- Audience is decided on the phone from the same two facts
  `AnnouncementAudience.includes` already takes, `isSeller` and
  `directoryLinked`. No per-person query.

Counting: one `impressions` increment when it fades in, one `clicks` when the
CTA is tapped, both `FieldValue.increment` from a callable. Grace sees both
numbers in the admin website's list.

## 4. CP-17E and CP-17F, the whole directory (Grace's #2)

### What is there now

`syncListings(ownerUid, wpUserId, ...)` in `functions/src/directory.ts`
mirrors **one member's** listings into `directoryListings/{wpPostId}`, and
`syncAllDirectoryListings` runs it for every account in `directory` whose
status is `linked`. So the mirror only ever holds listings belonging to
someone who already made an app account and matched by email. Grace wants all
of them, before anyone signs up.

The crawl to do it already exists and is already paid for: `crawlIndex` in
the same file pages through `wp/v2/vendors_dir_ltg` a hundred at a time to
build the owner index, because littlebluecart.com blanks `?author=` queries.
Without the application password it sees published listings only, which is
exactly the set we want to show strangers.

### The backend change

A new `syncPublicDirectory(lookups)` in `functions/src/directory.ts`:

1. Page through every **published** listing id.
2. Fetch the records in batches with the existing `listingsByIds`, resolve
   category, tag and location term ids to names through the existing
   `cachedTermNames` (24 hour cache, already there).
3. Build a `wpUserId -> uid` map once, from the `directory` collection, so a
   listing whose owner has already linked keeps its `ownerUid`.
4. `set(..., { merge: true })` each one into `directoryListings/{wpPostId}`,
   plus three new fields for browsing and search:
   - `categorySlugs: string[]`, the slugged category names
   - `titleWords: string[]` and `titleLower`, exactly the two fields
     `catalog` already carries so `FirestoreSearchRepository`'s pattern can be
     reused rather than reinvented
   - `unclaimed: bool`
5. **No feed post.** `syncListings` writes `posts/directory_{id}` for a
   published listing; the public crawl deliberately does not, per Grace's
   decision. A claimed listing still gets its post from `syncListings`, which
   is untouched.
6. Never blank an `ownerUid` that is already set: the existing value is read
   in the same batch and `ownerUid` is only written when the map has an
   answer or the document is new.
7. Roll up `directoryCategories/{slug}` as `{ name, slug, count, updatedAt }`
   so the app can draw the rail from one small read instead of counting
   listings on the phone.

Wired into the existing six-hourly `directorySyncScheduled`, plus an
`adminSyncDirectory` callable so Grace can force it from the admin website
and watch the count come back.

Rules already allow it: `directoryListings` is `allow read: if
resource.data.status == 'publish'`, which is every document the crawl writes.
`directoryCategories` needs a new public-read block. Indexes needed:
`(status, categorySlugs array-contains, updatedAt desc)` and
`(status, titleWords array-contains)`.

### The app

Mirroring "Browse the shop" exactly, because Grace asked for it in the same
shape:

- `DirectoryRail`, a second rail on the feed titled **Browse the directory**,
  one `LbmChip` per category from `directoryCategories`, hidden entirely when
  the collection is empty, the same way `CollectionRail` hides.
- `DirectoryCategoryScreen`, the listings in one category, drawn with the
  `DirectoryListingCard` that already exists.
- Directory results inside the existing search screen, as a third section
  beside products and sellers, using the `titleWords` and `titleLower`
  pattern copied from `FirestoreSearchRepository`.
- On an unclaimed listing card, one line: **Is this your business?** It goes
  to the directory link screen that already exists, and the flow from there
  is the one Grace has already tapped through: match by email, claim every
  listing at once, apply the listing to the profile. No new claim mechanism.

Two notes from building it:

- **The search results screen needed restructuring, not just an extra
  section.** `ResultsScreen` replaces its whole body with a "Nothing for
  …" card when the catalogue finds nothing, so a directory section placed
  inside `_Results` was invisible in exactly the case it mattered most: a
  word that matches only a directory business. The section now sits as a
  sibling below the catalogue's results, and the catalogue's empty card is
  suppressed when the directory has hits. A test covers it.
- `directoryCategories` needed its own public-read rules block;
  `directoryListings` already allowed anyone to read a published listing,
  so the crawl needed no rule change of its own.
New repository methods on `DirectoryRepository` (the interface stays pure
Dart, the Firestore class implements it, the fixture class gets demo rows so
`run-fixtures` still works): `watchDirectoryCategories()`,
`watchListingsInCategory(slug)`, `searchDirectory(query)`.

### The risk worth naming

Nobody knows how many published listings littlebluecart.com has. The crawl is
capped at 100 pages of 100, so 10,000, and every read is a Firestore write on
our side. `adminSyncDirectory` reports the count before the scheduled job
starts doing it every six hours, so the first number Grace sees is the first
time it runs, by hand, on dev. If it is in the thousands the rollup and the
rail still work, but the category screens want paging, which is why the
screens take a cursor from the start.
