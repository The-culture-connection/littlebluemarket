import 'package:url_launcher/url_launcher.dart';

/// The store's policies, hosted on littlebluemarket.com so the merchant edits
/// them there and the app never ships a stale copy.
abstract final class LegalLinks {
  static const privacyPolicy =
      'https://littlebluemarket.com/policies/privacy-policy';

  /// The **store's** policy: buying, delivery, returns. Not the app's
  /// terms of use, which is why [termsRoute] exists as well.
  static const storeTerms =
      'https://littlebluemarket.com/policies/terms-of-service';

  /// The app's own terms of use, held in the app rather than on the web, so
  /// somebody agreeing to them during sign-up is never shown a spinner or a
  /// 404. See `screens/onboarding/eula_screen.dart`.
  static const termsRoute = '/terms';

  /// Apple's standard Terms of Use (EULA), which govern the monthly
  /// membership as an App Store subscription. App Review requires a working
  /// link to it beside the purchase button and on the product page (rejected
  /// on 2026-10-01 for the product page).
  static const subscriptionTerms =
      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

  /// Where someone asks for their account or their data to be removed. A
  /// route inside the app, so it works on a phone and in a browser; the
  /// website address below is what the app stores ask for.
  static const deleteAccountRoute = '/delete-account';
  static const deleteAccountUrl =
      'https://lbm-web-production.up.railway.app/delete-account';
}

/// Where the app sends someone who wants to support Little Blue Cart or to
/// advertise in it (Grace, 2026-09-14). Kept here with the policies so every
/// address the app opens is declared in one file.
abstract final class LbmLinks {
  /// Venmo. Opens in the browser, which hands over to the Venmo app when it
  /// is installed.
  static const donate = 'https://www.venmo.com/u/littlebluecart';

  /// The partner guide: what advertising here involves and what it costs.
  static const advertise = 'https://canva.link/lbcpartnerguide';

  /// Published contact for support, which the app stores require the terms
  /// to carry, and which section 11 of the terms prints.
  ///
  /// Grace's choice, 2026-09-14. **The mailbox has to be watched**, because
  /// this is the address a reviewer writes to and the one a person uses
  /// when the bug button is not enough. Published contact information that
  /// bounces, or that nobody reads, is worse than none.
  ///
  /// Separate from the address the app *sends* confirmation email from
  /// (SMTP_USER / MAIL_FROM, CP-M1). They may be the same mailbox, but one
  /// is where people write to and the other is what signs outgoing mail, so
  /// changing this one changes nothing about that.
  static const supportEmail = 'erin@littlebluecart.com';
}

/// Little Blue Market's own pages on the store, shown inside the app
/// (Grace, 2026-10-28: "Way to show shopify pages in the app"). The words
/// live on the store, where they are edited, and the app only points at
/// them, so nothing here goes stale when a page is rewritten. Checked
/// against the store's sitemap on 2026-10-28; a page renamed on the store
/// needs its address changed here.
abstract final class MarketPages {
  static const about = 'https://littlebluemarket.com/pages/about';
  static const shopperFaqs = 'https://littlebluemarket.com/pages/shopper-faqs';
  static const trackOrder =
      'https://littlebluemarket.com/pages/track-your-order';
  static const refunds = 'https://littlebluemarket.com/policies/refund-policy';
  static const contact = 'https://littlebluemarket.com/pages/contact';
  static const communityGuidelines =
      'https://littlebluemarket.com/pages/community-ethics-guidelines';
  static const accessibility =
      'https://littlebluemarket.com/pages/accessibility-statement';
}

/// Opens one of the store's pages over the app, in the phone's own browser
/// sheet (Safari's on an iPhone, a Chrome tab on Android), so Done returns
/// to exactly where the person was rather than leaving the app. Falls back
/// to the full browser where there is no such sheet, as on the website.
/// False when nothing could open it; never throws.
Future<bool> openInApp(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  try {
    if (await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) return true;
  } on Object {
    // No in-app browser here; the full one below.
  }
  return openLegalLink(url);
}

/// Opens a policy in the phone's browser. False when nothing could open it,
/// so the caller can say so; never throws.
Future<bool> openLegalLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    return false;
  }
}
