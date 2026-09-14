import 'package:url_launcher/url_launcher.dart';

/// The store's policies, hosted on littlebluemarket.com so the merchant edits
/// them there and the app never ships a stale copy.
abstract final class LegalLinks {
  static const privacyPolicy =
      'https://littlebluemarket.com/policies/privacy-policy';
  static const termsOfService =
      'https://littlebluemarket.com/policies/terms-of-service';

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
