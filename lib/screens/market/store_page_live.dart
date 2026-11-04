import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../legal_links.dart';
import '../../router/nav.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/primitives.dart';
import 'store_page_screen.dart' show StoreLinkKind, storePageLinkTarget;

/// The store's own page, inside the app, on a phone (Grace, 2026-11-04:
/// "I also want the page to match the original page as much as possible.
/// font, and background color included").
///
/// The real page in a web view, so every font, colour and section is the
/// store's own, with the parts that belong to the website rather than to
/// the page hidden: its header and menu (the app has its own bar, with Back
/// and Home), its footer, the cookie banner and the wishlist pop-ups. The
/// web app cannot frame the store (Shopify refuses to be shown inside
/// another site), so there the rebuilt version is drawn instead.
class StorePageLive extends StatefulWidget {
  const StorePageLive({super.key, required this.url});

  final String url;

  @override
  State<StorePageLive> createState() => _StorePageLiveState();
}

/// The website's own furniture. Matched by the theme's section groups and
/// tags, which survive a theme's settings being changed.
const storeChromeCss = '''
.shopify-section-group-header-group,
.shopify-section-group-footer-group,
.shopify-section-header,
.shopify-section-footer,
sticky-header, header.header, footer.footer,
[id*="__announcement"], [id*="__cookie-banner"], #shopify-pc__banner,
#menu-drawer, mini-cart, cart-drawer,
.swym-storefront-layout-root-component, #swym-storefront-extention-render-container,
.swym-consent-popup, .swym-education-tooltip,
shopify-chat, #shopify-chat, inbox-online-store-chat,
.skip-to-content-link
{ display: none !important; }
body { padding-top: 0 !important; }
''';

/// Adds [storeChromeCss] to the page once, and again if the theme rebuilds
/// the head after loading.
String get _hideChromeJs =>
    '''
(function () {
  var id = 'lbc-app-hide';
  if (document.getElementById(id)) return;
  var s = document.createElement('style');
  s.id = id;
  s.textContent = ${_jsString(storeChromeCss)};
  (document.head || document.documentElement).appendChild(s);
})();
''';

String _jsString(String s) =>
    "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll('\n', ' ')}'";

class _StorePageLiveState extends State<StorePageLive> {
  late final WebViewController _web;
  bool _loading = true;
  String? _failed;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _route,
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
            _web.runJavaScript(_hideChromeJs).ignore();
          },
          onPageFinished: (_) async {
            await _web.runJavaScript(_hideChromeJs).catchError((_) {});
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != true || !mounted) return;
            setState(() {
              _loading = false;
              _failed = error.description;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  /// The store's pages stay in here; a collection opens the app's own
  /// screen, where it can go in the app's cart; anything off the store goes
  /// to the in-app browser.
  NavigationDecision _route(NavigationRequest request) {
    if (!request.isMainFrame) return NavigationDecision.navigate;
    final uri = Uri.tryParse(request.url);
    if (uri == null || !uri.scheme.startsWith('http')) {
      openInApp(request.url).ignore();
      return NavigationDecision.prevent;
    }
    final target = storePageLinkTarget(request.url);
    if (target.kind == StoreLinkKind.collection) {
      context.goToCollection(target.value);
      return NavigationDecision.prevent;
    }
    final ours = uri.host.replaceFirst('www.', '') == 'littlebluemarket.com';
    if (!ours) {
      openInApp(request.url).ignore();
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (_failed != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This page did not load',
                style: LbmText.display.copyWith(fontSize: 20, color: c.ink),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Check the connection and try again.\n($_failed)',
                style: LbmText.pinMeta.copyWith(color: c.ink2),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              PillButton(
                'Try again',
                expand: false,
                onPressed: () {
                  setState(() {
                    _failed = null;
                    _loading = true;
                  });
                  _web.loadRequest(Uri.parse(widget.url));
                },
              ),
            ],
          ),
        ),
      );
    }
    // Back walks back through the store's pages first, then leaves.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _web.canGoBack()) {
          await _web.goBack();
        } else if (context.mounted) {
          // pop, not maybePop: maybePop would ask this PopScope again.
          Navigator.of(context).pop();
        }
      },
      child: Stack(
        children: [
          WebViewWidget(controller: _web),
          // Covers the page until its header has been taken off, so the
          // website's menu never flashes up first.
          if (_loading)
            Positioned.fill(
              child: ColoredBox(
                color: c.paper,
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
