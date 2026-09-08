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
6. **Firebase's iPhone file.** Still in `little_blue_market`:
   ```
   flutterfire configure --project=little-blue-610e5 --platforms=ios
   ```
   Pick the existing iOS app (`com.littleblue.market`) if it asks. This writes `ios/Runner/GoogleService-Info.plist`. Commit it: `git add ios/Runner/GoogleService-Info.plist && git commit -m "iOS Firebase config" && git push`. It is public configuration, safe in the repo.
7. **Your iPhone.** Settings → Privacy & Security → **Developer Mode** → on (iOS 16 and newer; the phone restarts). Plug it into the Mac with a cable and tap **Trust** on the phone.
8. **Signing, once.** `open ios/Runner.xcworkspace` (the workspace, not the project). In Xcode: click **Runner** at the top of the left panel → the **Runner** target → **Signing & Capabilities**. Tick **Automatically manage signing** and pick your **Team** (your Apple Developer account; add it under Xcode → Settings → Accounts if it is not listed). Bundle identifier is `com.littleblue.market`. **Push Notifications** and **Background Modes → Remote notifications** are already listed; if Xcode shows a red error about them, click **Try Again** once it has registered the identifier with Apple.
9. **Push key, once (Apple + Firebase consoles).** Apple Developer → Certificates, Identifiers & Profiles → **Identifiers** → `com.littleblue.market` → tick **Push Notifications** → Save. **Keys** → **+** → name `LBM FCM` → tick **Apple Push Notifications service (APNs)** → Continue → Register → **Download** the `.p8` (offered once; keep it outside the repo) and note the **Key ID** and your **Team ID** (top right of the developer site). Firebase console → Project settings → **Cloud Messaging** → Apple app configuration → **APNs Authentication Key → Upload**: the `.p8`, Key ID, Team ID.

## Every time: run the app on the phone

```
cd ~/Documents/little_blue_market
git pull
scripts/run-live-mac.sh
```

The script lists the devices it can see; run it again with your phone's name in quotes, e.g. `scripts/run-live-mac.sh "Grace's iPhone"`. The first build takes several minutes (CocoaPods). The first time the app opens on the phone iOS may say the developer is untrusted: Settings → General → VPN & Device Management → your account → **Trust**, then open the app again.

The corner badge must read **DEV · live · little-blue-610e5**. If it says fixtures, the `--dart-define` did not reach the build; use the script, not Xcode's Run button.

## What the phone can and cannot test

- Everything in `manual-test.md` works on the iPhone the same as on the emulator.
- Push (J15 steps 1–3, 17–18) needs a **real** iPhone; the Simulator cannot receive APNs. Allow notifications on the Notifications screen, then **Send me a test notification** and lock the phone.
- Xcode's Run button builds the app **without** the live flag, so it starts on demo data. Use the script.

## If it fails

- `flutter doctor` red on Xcode or CocoaPods → finish steps 1–2; `sudo gem install cocoapods` is the older way if Homebrew's fails.
- `No valid code signing certificates` → step 8, pick the Team; Xcode creates the certificate.
- `Unable to install ... device is locked` → unlock the phone and keep it unlocked during install.
- `no valid "aps-environment" entitlement string found` in Xcode's console → the Push Notifications capability is not on the signed build (step 8).
- Push never arrives but the test button says sent → `firebase functions:log --only pushTestMe --project dev`: `third-party-auth-error` means the `.p8`, Key ID or Team ID do not match (step 9).
- Anything else: paste the last 30 lines of the Terminal to Claude with the step number.
