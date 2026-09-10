# Little Blue Market — Flutter app

A marketplace app: goods, services, reviews and shoutouts in one feed, with a
community and forums alongside. Originally a port of the clickable prototype in
`../lbm-prototype`; now backed by Firebase for identity and everything social,
and by Shopify for commerce, behind an interface designed so Shopify can be
replaced without a screen changing.

```bash
flutter pub get
flutter run                 # THE PRODUCTION APP: little-blue-cart-prod, the real shop (since 2026-09-08)
flutter test                # ~455 tests, always on the demo backend
flutter build apk --release --split-per-abi
flutter build ipa           # macOS only
```

Bundle id `com.littlebluemarket.app` on both platforms. Portrait only.

## Two backends, one flag

The app runs on either of two backends, chosen at build time. Both render the
same screens; that equivalence is the test strategy.

```bash
flutter run                                        # Firebase + the commerce proxy (the default since cutover)
flutter run --dart-define=LBM_BACKEND=fixtures     # the built-in demo data
flutter run --dart-define=LBM_DEV=true             # a DEVELOPER build: corner badge, error strip with
                                                   # Copy for Claude, raw causes, the Diagnostics row
flutter run --dart-define=LBM_DEV=true \
            --dart-define=LBM_EMULATORS=true       # ...against local emulators
```

Which Firebase project a live build talks to is decided by two committed
files, `android/app/google-services.json` and `lib/firebase_options.dart`. The
repo carries the **production** ones (`little-blue-cart-prod`); the dev
project's copies live in `firebase/config/dev/` and `scripts/use-env.ps1 dev`
swaps them in (`run-live.ps1 -Dev` does that for you and swaps back when it exits; plain `run-live.ps1` is the developer build against production, Grace's default since 2026-09-09).
`LBM_DEV` is about what the app *shows*; the config files are about *where it
talks*. A plain `flutter run` is therefore exactly what a customer gets.

The fixture backend is not a stub. It honours writes, returns real empty
states, and throws when something is missing — so screen code written against
it needs no changes when Firestore arrives. It is also what the whole test
suite runs on.

### Bringing the live backend up

```bash
# 1. Firebase client config. Needs the account that owns the project; this is
#    the one step that cannot be scripted here.
flutterfire configure --project=little-blue-cart-dev

# 2. Secrets. Prompts for each value, so nothing lands in shell history.
firebase functions:secrets:set SHOPIFY_CLIENT_SECRET
firebase functions:secrets:set SHOPIFY_STOREFRONT_PRIVATE_TOKEN
firebase functions:secrets:set SHOPIFY_WEBHOOK_SECRET

# 3. Non-secret config, in functions/.env.little-blue-cart-dev
#    SHOPIFY_STORE_DOMAIN, SHOPIFY_API_VERSION, SHOPIFY_CLIENT_ID

# 4. Rules, indexes and functions.
firebase deploy --only firestore:rules,firestore:indexes,storage,functions
```

### Working against emulators

```bash
firebase emulators:start --only firestore,auth,functions
node functions/scripts/seed.mjs      # the fixture content, in Firestore
cd little_blue_market && flutter run \
  --dart-define=LBM_DEV=true --dart-define=LBM_EMULATORS=true
```

### Production

`little-blue-cart-prod` is the production Firebase project (`prod` alias in
`.firebaserc`); `little-blue-610e5` stays the dev project (`dev`). The real
shop is `little-blue-cart-dev.myshopify.com` (littlebluemarket.com; the word
"dev" in its name is Shopify history). Production tooling mirrors the dev
tooling with a `-prod` suffix: `scripts/deploy-prod.ps1` (tests → deploy →
webhooks on the real shop → doctor), `scripts/doctor-prod.ps1`,
`scripts/prod-secrets.ps1` (Secret Manager from `PARENT\.env.littlebluemarket`),
`scripts/run-prod.ps1`, and `npm run <script>:prod` inside `functions/`.
Non-secret params live in `functions/.env.little-blue-cart-prod` (gitignored,
like the dev one). The admin website (`admin-web/`) points at production;
`firebase-config.dev.js` is the dev copy.

## Where things live

```
lib/
  models/           the domain, plus one file that formats it
  data/
    repositories/   the seam: plain Dart interfaces, no backend types
    fixtures/       the demo backend
    firebase/       Firestore, Auth, Storage
    shopify/        the commerce proxy client
  state/            session and providers
functions/          the commerce proxy, catalog mirror and order pipeline
firebase/           security rules and indexes
```

The rule that keeps the seam real: **screens never import an implementation.**
`test/no_fixture_imports_test.dart` enforces it.

---

## What was ported, and what deliberately was not

The prototype is a design reference. Its state model — one `S` object and a
`render()` that rewrites `innerHTML` — was **not** carried over, as its README
asks. What was carried over is the visual system, the screen inventory, the
navigation graph, and the copy.

| Prototype | Here |
|---|---|
| One global `S` + full re-render | `go_router` + Riverpod; each screen owns its own local state |
| Screens switched by a `switch` on a string | Real routes with per-tab back stacks |
| Overlays in the same render pass | `showModalBottomSheet` / `showDialog` |
| Fake iOS status bar drawn in the viewport | The real system status bar, via `SafeArea` + `SystemUiOverlayStyle` |
| Phone bezel, left rail, caption panel | Dropped — prototype chrome, not the app |
| `★`, `◆`, `→`, `×`, `›` as text | Drawn as icons (see "Glyphs" below) |

### Layout

```
lib/
  main.dart              app entry; holds the first frame until the welcome art is decoded
  theme/
    tokens.dart          LbmColors ThemeExtension — every colour in the app
    app_theme.dart       ThemeData, type scale, the two ColorSchemes
  models/models.dart     domain types
  data/fixtures.dart     the mock content, ported verbatim
  state/session.dart     guest vs signed-in
  router/
    app_router.dart      routes and the three shell branches
    nav.dart             branch-aware navigation helpers
  widgets/               the shared vocabulary: cards, chips, pills, avatars, sheets
  screens/
    onboarding/          welcome handoff + passwordless auth
    market/  community/  you/
```

Swap `data/fixtures.dart` for a repository backed by the real API; nothing
outside it knows where the data came from.

---

## Three things that are easy to get subtly wrong

### 1. The welcome handoff

`welcome-still.png` is the GIF's exact resting frame. Both are drawn into the
same `540 × 623` box on a screen painted `#70A0D0`, so the artwork has no
visible edge and **nothing moves** when the GIF is removed. The three buttons
(Create a Profile, Sign in, Continue as a guest) are ordinary widgets *below*
the artwork since 2026-09-08 (Grace's `Body.gif` re-export, which drops the
painted buttons): crisp at any size, readable by a screen reader, tappable from
the first frame. There are no hotspots to re-measure any more.
`test/welcome_handoff_test.dart` asserts the two images share a rect, that the
buttons sit under the artwork and never overlap, and that nothing moves at the
handoff.

Details worth knowing:

- **The asset is made from `Body.gif` (1080×1920, 123 frames) with gifsicle:**
  frames 0–121 (frame 122 is the loop's jump back to the start), cropped to
  the top `1080×1245` (below that the source is empty), halved to 540 wide,
  128 colours, `--lossy=60 -O3 --no-loopcount`. 774 KB, 4070 ms, stops on the
  resting frame. The still is frame 115 of the source, cropped the same way.
- **The duration constant is 4190 ms**: a little margin past the 4070 ms of
  frames. The countdown does not start until the GIF's first frame has
  painted, and a backstop timer guarantees the intro ends even if the GIF
  never decodes.
- Reduce-motion skips the animation entirely, as the prototype's
  `prefers-reduced-motion` rule does.

### 2. The accent contrast split

`#D56ED1` under white is about 3:1 — below the readable threshold. So:

- **light mode**: solid fills that carry white text use `accentDeep` (`#A93BA5`);
  everything else — chips, dots, stars, progress bars — uses the pure `accent`.
- **dark mode**: `accentDeep` *is* the pure accent, and it carries a dark plum
  label (`accentInk`, `#2A0A28`) instead.

This is structural, not incidental: `accentDeep`/`accentInk` are a pair, and the
only correct reason to reach for `accentDeep` is that `accentInk` text is going
on top of it. It is also wired to `ColorScheme.primary`/`onPrimary`, so a stock
Material button lands in the right place without correction.
`test/design_tokens_test.dart` measures the actual contrast ratios and fails if
the split is ever flattened.

### 3. Glyphs the bundled fonts do not carry

Neither Fraunces nor Nunito has `★`, `◆`, `→`, or `⋯`. Relying on the platform's
font fallback gets you a mismatched glyph at best and a tofu box at worst, so
these are drawn instead: stars and arrows are Material icons, the points diamond
is a rotated square. If you add copy, keep it to characters the two families
actually have.

Both families are bundled as static instances under `assets/fonts/` rather than
fetched at runtime, so the app is correct offline and on first launch.

---

## Auth

The prototype's Create-a-profile and Sign-in screens show password fields, and
its README flags them as out of date: the store uses Shopify's passwordless
customer accounts. The real flow is built here instead:

```
email → six-digit code → (first time only) handle, photo, bio
```

There is no password field anywhere. The screens are UI only — wire
`EmailScreen`, `VerifyScreen` and `ProfileSetupScreen` to the customer accounts
API.

---

## Still to do

- **The checkout web view.** The cart, the handoff and the order pipeline are
  built; what is missing is the last hop that opens the returned `checkoutUrl`.
  Shopify ships a Checkout Sheet Kit for Swift and Kotlin but **not for
  Flutter**, so this needs a platform channel around the native kit or an
  in-app web view. Either way the `orders/paid` webhook stays the only proof
  that a purchase happened.
- **ShipTurtle credentials, and the rule that maps one of its vendors to an app
  account.** Both outstanding. Revenue attribution is built and unit-tested but
  cannot be *verified* against real vendors until they exist — see
  `Planning/i-have-a-prototype-vivid-dongarra.md`.
- **`flutterfire configure`.** Needs the Firebase account that owns the
  project, so the live backend cannot start until it has been run once.
- **App icon and splash.** Still Flutter's defaults.
- **iOS build.** Unverified — this was built and tested on Windows, so Android is
  confirmed and the iOS project is configured but never compiled. No dependency
  here has native iOS code (`go_router`, `riverpod` and `flutter_svg` are pure
  Dart), so there are no pods to resolve, but it needs a real `flutter build ipa`
  on a Mac.
- **Two known issues in the animation asset**, both needing a re-export rather
  than a code fix: the final frame reads "Continue as a **geust**", and the
  welcome buttons are sharp rectangles while the rest of the app is pill-shaped.

---

## Tests

```
design_tokens_test.dart    contrast ratios, including the accent split
welcome_handoff_test.dart  the handoff, the buttons under the artwork, touch targets
guest_gating_test.dart     what a guest can and cannot reach
screens_smoke_test.dart    every screen renders and scrolls, light and dark
text_scaling_test.dart     every screen at 2.0 text scale (the app clamps to 1.35)
```

The smoke and scaling tests exist because this design came from a fixed 390-wide
mockup, where a row of text either fits or it does not. Overflow throws in a
test, so those fail loudly rather than shipping a striped banner.

`test/visual_check.dart` is not part of the suite — it renders every screen with
the real fonts into `test/shots/` so you can look at them:

```bash
flutter test test/visual_check.dart --update-goldens
```
# littlebluemarket

## The web app on Railway

The same Flutter app, built for the browser and served from Railway. In a
desktop browser it sits inside a phone-sized frame; on a phone's browser it
fills the screen. It talks to the production Firebase project, exactly like the
phone app; push notifications are the one thing it does not do.

- `Dockerfile.web` builds it (Flutter, then a small Node server in `web-server/`).
- Locally: `flutter build web --release`, then `cd web-server && npm install && LBM_WEB_DIR=../build/web npm start`, open http://localhost:3000.
- Railway: New service from this GitHub repo, root directory `/`, variable
  `RAILWAY_DOCKERFILE_PATH=Dockerfile.web`, then Generate Domain. Add that
  domain under Firebase console → Authentication → Settings → Authorized
  domains, or sign-in is refused in the browser.
- The first build takes 10 to 15 minutes (it downloads Flutter); later ones are
  faster. Every push to `main` redeploys.
