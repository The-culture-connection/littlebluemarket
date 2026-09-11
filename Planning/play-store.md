# Google Play: the first upload, and every one after

Everything you need to put Little Blue Market on the Play Store, and to do it
again next time without surprises. The app is `com.littleblue.market`.

## 1. The two keys, which is what the SHA confusion is about

There are two signing keys. They have different fingerprints, and mixing them
up is the usual cause of a rejected upload.

| Key | Who holds it | What it is for | Where its fingerprint is |
|---|---|---|---|
| **Upload key** | You | Signs the `.aab` before you upload it. Play checks it to know the upload is really from you. | `..\android-signing\README.txt`, and the build script prints it |
| **App signing key** | Google | Play strips your signature and re-signs the app with this before sending it to phones. | Play Console → Test and release → Setup → App signing |

The app signing key is created by Google on your first upload and never
changes. The upload key is ours, and it must be the same file every single
time. That file is `..\android-signing\upload-keystore.jks`. If it is ever
lost, Play Console → Setup → App signing → **Request upload key reset** issues
a new one; nothing else recovers it, so keep the folder backed up.

**Do any SHA fingerprints need registering?** Not for this app as it stands.
Fingerprints matter for Google Sign-In, phone sign-in, App Check and dynamic
links. Little Blue Market signs people in with an email address and a
password, so Firebase needs no fingerprint at all, and none is registered.
If Google Sign-In is ever added, the fingerprint to put in the Firebase
console is **Google's app signing SHA-1**, not ours. Ours would only be needed
as a second entry for testing a build straight from this machine.

## 2. Build a bundle

On Windows, in the project folder:

```
scripts\build-android-release.ps1
```

It builds `flutter build appbundle --release`, signs it with the upload key,
copies the result to `..\android-signing\releases\` named by version, and
prints the file path plus the upload key's fingerprints.

Before building, raise the version in `pubspec.yaml`:

```
version: 0.3.2+4
```

The part after the `+` is the **version code**. Play refuses a version code it
has already seen, so it must go up by at least one on every upload, forever.
The part before the `+` is what people see in the store listing.

## 3. The first upload

1. **play.google.com/console** → Create app. Name it Little Blue Market, pick
   English (United States), App, Free, and accept the declarations.
2. **Test and release → Production → Create new release.** The first time it
   offers Play App Signing; accept it (the default, "Use Google-generated
   key"). This is what creates the app signing key.
3. Upload the `.aab` from `..\android-signing\releases\`.
4. Release name fills in from the version. Write a line or two of release
   notes.
5. Play will not let you roll out until the **App content** section is
   finished. That is the next part.

## 4. App content, answered for this app

- **Privacy policy**: `https://littlebluemarket.com/policies/privacy-policy`
- **App access**: most of the app is browsable as a guest, but posting,
  buying, messaging and selling need an account. Give the reviewer a working
  email and password for a test account, under "All or some functionality is
  restricted". Make one on a real build first and check it can sign in.
- **Ads**: no, the app contains no ads.
- **Content rating**: fill in the questionnaire. It is a shopping and social
  app with user-generated content, user-to-user messaging, and no violence,
  sex, drugs or gambling. Say yes to user-generated content and to users
  interacting, and mention that reports and bans exist (they do: the "..."
  menu on any profile or post, and the admin dashboard).
- **Target audience**: 18 and over. Do not tick any child age band; the app
  takes payment and has open messaging.
- **Data safety**: the app collects, all linked to the account:
  - *Name* and *Email address*, for account management.
  - *Photos*, for profile pictures, product photos and posts.
  - *Precise location*, optional, only when someone taps Near me, for app
    functionality. It is not shared and not used for advertising.
  - *Purchase history*, for orders and the profile.
  - *Messages*, meaning direct messages, the room, posts and comments.
  Everything is encrypted in transit. People can ask for their account to be
  deleted. No data is sold, and there is no advertising or analytics SDK in
  the app.
- **Government apps, Financial features, Health**: no to all.
- **Data deletion**: the app has its own page for this, reachable without
  signing in, on the phone and in a browser:
  `https://lbm-web-production.up.railway.app/delete-account`
  Paste that as the **Data deletion URL**. It offers both answers Google asks
  about: delete the account and everything with it, or delete the data and
  keep the account. Requests land in the app's Admin screen under "Delete my
  account requests".

## 5. Every upload after the first

1. Raise the version code in `pubspec.yaml`.
2. `scripts\build-android-release.ps1`
3. Play Console → Production → Create new release → upload the new `.aab`.

Nothing about the keys changes, because the script always uses the same
keystore.

## 6. If Play refuses the upload

| What it says | What it means | What to do |
|---|---|---|
| "Your Android App Bundle is signed with the wrong key" | The bundle was signed with a different keystore than the first upload | Use `..\android-signing\upload-keystore.jks`. If it is gone, Play Console → Setup → App signing → Request upload key reset |
| "Version code N has already been used" | That number is taken | Raise the `+N` in `pubspec.yaml` and build again |
| "Your app currently targets API level N and must target at least M" | Android's yearly requirement moved | Upgrade Flutter, then rebuild; the target level comes from the Flutter SDK |
| "You need to declare a privacy policy" | App content is unfinished | Section 4 above |
| Google Sign-In fails only on the Play build (not applicable today) | The app signing SHA-1 is not in Firebase | Copy SHA-1 from Play Console → Setup → App signing into Firebase console → Project settings → Android app → Add fingerprint |
