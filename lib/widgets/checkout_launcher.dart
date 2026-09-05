import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/repositories/dev_error_sink.dart';

/// Opens the store's hosted checkout.
///
/// Behind an interface so the buy flow is testable: a widget test cannot open
/// a browser, and must not try. The real one uses an in-app browser tab
/// (a Chrome Custom Tab on Android), which needs no native configuration and
/// keeps the person inside the app's task.
///
/// Nothing here learns whether the person paid. The order arrives through the
/// paid-order webhook, which is the only truth about money.
abstract interface class CheckoutLauncher {
  /// True when something opened; false when nothing could.
  Future<bool> open(Uri url);
}

class UrlCheckoutLauncher implements CheckoutLauncher {
  const UrlCheckoutLauncher();

  @override
  Future<bool> open(Uri url) async {
    try {
      if (await launchUrl(url, mode: LaunchMode.inAppBrowserView)) return true;
    } catch (_) {
      // Fall through to the external browser.
    }
    try {
      // No in-app tab available. On Android that usually means Chrome has
      // never been opened on this device (its first-run screens block the
      // tab service). Say so in debug, so it is not mistaken for a bug.
      final external = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (external) {
        DevErrorSink.report(
          StateError(
            'Checkout opened in the external browser because no in-app tab '
            'was available. On an emulator: open Chrome once and dismiss its '
            'welcome screens, then retry.',
          ),
          null,
          'checkout launcher (fallback)',
        );
      }
      return external;
    } catch (_) {
      return false;
    }
  }
}

/// A launcher that records what it was asked to open. For tests and demos.
class RecordingCheckoutLauncher implements CheckoutLauncher {
  RecordingCheckoutLauncher({this.succeeds = true});

  final bool succeeds;
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return succeeds;
  }
}

final checkoutLauncherProvider = Provider<CheckoutLauncher>(
  (ref) => const UrlCheckoutLauncher(),
);

/// True from the moment a checkout was opened until the cart next has
/// something in it. The cart's empty state uses it to say "we'll confirm
/// shortly" rather than "your cart is empty" — the cart empties when the
/// paid-order webhook lands, and that is the moment the copy has to be true.
class CheckoutPendingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final checkoutPendingProvider = NotifierProvider<CheckoutPendingNotifier, bool>(
  CheckoutPendingNotifier.new,
);
