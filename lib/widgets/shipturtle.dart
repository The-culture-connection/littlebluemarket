import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/providers.dart';

/// The address Shipturtle lives at when the backend has not said otherwise.
///
/// The real one; `appConfig` only confirms it, so a config that is slow or
/// unreachable does not leave the seller with nowhere to go.
const kShipturtleFallbackUrl = 'https://app.shipturtle.com/';

/// Opens Shipturtle in the phone's browser.
///
/// One place, because the app hands off to Shipturtle from four: the row in
/// Edit profile, the shop screen, each listing under review, and the dialog
/// after a product is sent for approval. Orders, shipping and payouts are
/// Shipturtle's, and this app does not draw a second version of them.
Future<void> openShipturtle(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  var url = kShipturtleFallbackUrl;
  try {
    url = (await ref.read(appConfigProvider.future)).shipturtleUrl;
  } on Object {
    // The default above is the real address; the config only confirms it.
  }
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    messenger.showSnackBar(SnackBar(content: Text('Could not open $url')));
  }
}
