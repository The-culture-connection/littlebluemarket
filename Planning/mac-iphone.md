# Running the app on your iPhone (a Mac is required)

*Written for Grace, 2026-09-08. Apple only lets iPhone apps be built on a Mac with Xcode, so this is a one-time setup on a Mac, then a two-line routine each time. Nothing here touches the backend: the same Firebase project and the same Cloud Functions serve Android and iPhone.*

## One-time setup on the Mac (about an hour, mostly downloads)

1. **Xcode.** App Store → Xcode → Get (it is large). Open it once, accept the licence, let it install its components. Then in Terminal: `sudo xcode-select -s /Applications/Xcode.app` and `sudo xcodebuild -runFirstLaunch`.
2. **Homebrew, CocoaPods, Git.** In Terminal:
   ```
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   brew install cocoapods git
   ```
3. **Flutter.** Download the macOS installer from docs.flutter.dev/get-started/install/macos, follow its steps, then `flutter doctor`. It must show a green tick for Xcode and CocoaPods. (Android Studio is not needed for the iPhone.)
4. **Firebase tools.** `npm install -g firebase-tools` (install Node from nodejs.org first if `npm` is not found), then `firebase login`, then `dart pub global activate flutterfire_cli`.
5. **The code.** Sign in to GitHub in the browser, then:
   ```
   cd ~/Documents
   git clone https://github.com/The-culture-connection/littlebluemarket.git little_blue_market
   cd little_blue_market
   flutter pub get
   ```
   Git asks for your GitHub login the first time; a personal access token is the password.
6. **Firebase's iPhone file.** Already in the repo since 2026-09-09: `ios/Runner/GoogleService-Info.plist` is the **production** project's (little-blue-cart-prod); the dev project's copy is in `firebase/config/dev/` and `scripts/use-env.sh dev` swaps it in for a dev session. Nothing to generate. One Xcode step the first time: in Xcode's left panel, right-click the **Runner** folder → **Add Files to "Runner"…** → pick `ios/Runner/GoogleService-Info.plist` → make sure **Runner** is ticked under Targets → Add. That puts the file in the app bundle.
7. **Your iPhone.** Settings → Privacy & Security → **Developer Mode** → on (iOS 16 and newer; the phone restarts). Plug it into the Mac with a cable and tap **Trust** on the phone.
8. **Signing, once.** `open ios/Runner.xcworkspace` (the workspace, not the project). In Xcode: click **Runner** at the top of the left panel → the **Runner** target → **Signing & Capabilities**. Tick **Automatically manage signing** and pick your **Team** (your Apple Developer account; add it under Xcode → Settings → Accounts if it is not listed). Bundle identifier is `com.littleblue.market`. **Push Notifications** and **Background Modes → Remote notifications** are already listed; if Xcode shows a red error about them, click **Try Again** once it has registered the identifier with Apple.
9. **Push key, once (Apple + Firebase consoles).** Apple Developer → Certificates, Identifiers & Profiles → **Identifiers** → `com.littleblue.market` → tick **Push Notifications** → Save. **Keys** → **+** → name `LBM FCM` → tick **Apple Push Notifications service (APNs)** → Continue → Register → **Download** the `.p8` (offered once; keep it outside the repo) and note the **Key ID** and your **Team ID** (top right of the developer site). Firebase console → **little-blue-cart-prod** (production; the same upload on little-blue-610e5 only if you also test iPhone push against dev) → Project settings → **Cloud Messaging** → Apple app configuration → **APNs Authentication Key → Upload**: the `.p8`, Key ID, Team ID. The consoles part of this step needs no Mac and can be done any time (Planning/checkpoints.md, CP-P7).

## Every time: run the app on the phone

```
cd ~/Documents/little_blue_market
git pull
scripts/run-live-mac.sh
```

The script lists the devices it can see; run it again with your phone's name in quotes, e.g. `scripts/run-live-mac.sh "Grace's iPhone"`. The first build takes several minutes (CocoaPods). The first time the app opens on the phone iOS may say the developer is untrusted: Settings → General → VPN & Device Management → your account → **Trust**, then open the app again.

`run-live-mac.sh` is the **developer build** (it passes `LBM_DEV=true`, so the corner badge and the error strip are on; the project is whatever `ios/Runner/GoogleService-Info.plist` says, production unless you ran `scripts/use-env.sh dev` first). The badge should read **DEV · live · little-blue-cart-prod**. `scripts/run-prod-mac.sh <device id>`, or a plain `flutter run -d <device id>`, is the production app exactly as customers get it: no badge, no strip.

**Xcode's own Run button** builds with whatever flags the *last* `flutter run` wrote into `ios/Flutter/Generated.xcconfig`. After a `run-live-mac.sh` session that used to mean a DEV build from Xcode too; since 2026-09-09 the script puts the production settings back when it exits. If Xcode ever shows the badge anyway, run `flutter build ios --config-only` once in `little_blue_market` and build again.

## What the phone can and cannot test

- Everything in `manual-test.md` works on the iPhone the same as on the emulator.
- Push (J15 steps 1–3, 17–18) needs a **real** iPhone; the Simulator cannot receive APNs. Allow notifications on the Notifications screen, then **Send me a test notification** and lock the phone.
- Xcode's Run button builds the app **without** the live flag, so it starts on demo data. Use the script.

## Archiving: TestFlight now, the App Store later

An archive is the signed, release build Apple distributes. `flutter run` puts a debug build on one plugged-in phone; an archive goes through App Store Connect to any tester's phone (TestFlight) and, after review, to everyone.

**Before the first archive (once, in the browser):** appstoreconnect.apple.com → **My Apps** → **+** → New App → platform iOS, name `Little Blue Market`, bundle ID `com.littleblue.market` (it is listed because Xcode registered it in step 8), SKU `littlebluemarket`. Nothing else has to be filled in for TestFlight.

**Each archive (Terminal, in `little_blue_market`):**

```
git pull
scripts/use-env.sh prod
flutter build ipa --release
```

That takes five to ten minutes and prints where the archive is, `build/ios/archive/Runner.xcarchive`, and the `.ipa` next to it. Since the production cutover (2026-09-08) a plain build **is** the production app: no `--dart-define` needed, and none must be added (`LBM_DEV=true` would ship the developer surfaces). `use-env.sh prod` only makes sure a dev session did not leave the dev config in place.

**Upload it:** `open build/ios/archive/Runner.xcarchive` opens Xcode's Organizer on that archive → **Distribute App** → **TestFlight & App Store** (or "App Store Connect") → keep the defaults → **Upload**. Xcode signs it with your Team, switches the push entitlement to production on its own, and uploads. Ten to thirty minutes later the build appears in App Store Connect → your app → **TestFlight**. Add yourself and any testers under **Internal Testing**; they install the TestFlight app from the App Store and get an invite by email. Apple may ask one export-compliance question the first time; the app uses only standard https, so the answer is that it does not use non-exempt encryption.

**Version numbers:** each upload needs a higher build number. It comes from `pubspec.yaml`'s `version:` line (`0.3.0+1`: the `+1` is the build number). Bump the number after the `+` before each archive, or run `flutter build ipa --release --build-number=2`.

**What an archive today would contain:** the dev backend, the dev Shopify test shop and the live littlebluecart.com directory. That is right for TestFlight testers now. It is **not** right for the App Store: that needs the cutover (a production Firebase project, the real shop, the checklist in `answers-to-open-questions.md` Part 2) and a build made against it. Do not submit for App Store review before the cutover is done.

## If it fails

- `flutter doctor` red on Xcode or CocoaPods → finish steps 1–2; `sudo gem install cocoapods` is the older way if Homebrew's fails.
- `No valid code signing certificates` → step 8, pick the Team; Xcode creates the certificate.
- `Unable to install ... device is locked` → unlock the phone and keep it unlocked during install.
- `no valid "aps-environment" entitlement string found` in Xcode's console → the Push Notifications capability is not on the signed build (step 8).
- Push never arrives but the test button says sent → `firebase functions:log --only pushTestMe --project prod`: `third-party-auth-error` means the `.p8`, Key ID or Team ID do not match (step 9).
- The test button says **"No phone is registered for notifications yet"** after Allow → the phone never got Apple's push token. Since 2026-09-09 the app prints Apple's answer: in the `flutter run` output or Xcode's console, search for **`LBM push:`**. `APNs token received` means Apple is fine and the problem is on the Firebase side (log above). `APNs registration FAILED: …` names the cause: *no valid "aps-environment" entitlement* → the Push Notifications capability is not on the signed build (step 8; a free Apple ID cannot add it); a network error → the phone's Wi-Fi blocks Apple's push port, try cellular. No `LBM push:` line at all → Apple was never asked: delete the app from the phone, rebuild, tap Allow again, wait ten seconds. On a developer build the error strip also shows "iPhone gave no APNs token after 6 s".
- Anything else: paste the last 30 lines of the Terminal to Claude with the step number.
