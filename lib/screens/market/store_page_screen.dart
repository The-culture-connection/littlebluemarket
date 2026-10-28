import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../legal_links.dart';
import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/promos.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/product_art.dart';
import '../../widgets/screen.dart';

/// One of Little Blue Market's pages, posted to the feed, on the app's own
/// screen (Grace, 2026-10-28, from the QA suite: "I wanted the pages to be
/// posted and able to be opened natively in the app").
///
/// Drawn from the blocks the backend read off the page when it was posted:
/// headings, paragraphs, bullet points, pictures and buttons, in the app's
/// own type and colours, dark mode included. The page on the store is still
/// one tap away at the foot, for anything a form or a widget does there.
class StorePageScreen extends ConsumerWidget {
  const StorePageScreen({super.key, required this.pageId});

  final String pageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pages = ref.watch(storePagesProvider);
    final page = pages.value?.where((p) => p.id == pageId).firstOrNull;

    return LbmScreen(
      appBar: LbmAppBar(
        title: page?.title ?? 'Little Blue Market',
        showBack: context.canPop(),
        actions: const [HomeButton()],
      ),
      child: switch ((pages.isLoading && page == null, page)) {
        (true, _) => const Center(child: CircularProgressIndicator()),
        (_, null) => const LbmEmpty(
          title: 'This page is no longer posted',
          body: 'It may have been taken down from the feed.',
        ),
        (_, final StorePage page) when page.readsInApp => _PageBody(page: page),
        (_, final StorePage page) => _Unread(page: page),
      },
    );
  }
}

/// A posted page with nothing to draw yet: the backend reads it now, and
/// the words arrive on the same listener that drew the card. Only when the
/// page has no words at all (a lookup form) does it offer the website, and
/// then only on a tap.
class _Unread extends ConsumerWidget {
  const _Unread({required this.page});

  final StorePage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final read = ref.watch(storePageReadProvider(page.id));
    final nothing = read.hasError || (read.value ?? 1) == 0;
    if (!nothing) {
      return const Center(child: CircularProgressIndicator());
    }
    return LbmEmpty(
      title: 'This page is best seen on the website',
      body:
          'It is a form or a tool rather than something to read, so the app '
          'cannot show it on its own screen.',
      action: PillButton(
        'Open littlebluemarket.com',
        icon: Icons.open_in_new_rounded,
        expand: false,
        onPressed: () => openStorePageLink(context, page.url),
      ),
    );
  }
}

class _PageBody extends ConsumerWidget {
  const _PageBody({required this.page});

  final StorePage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final posted = ref.watch(storePagesProvider).value ?? const [];

    Future<void> follow(String url) =>
        openStorePageLink(context, url, posted: posted);

    Widget tappable(String link, Widget child) => link.isEmpty
        ? child
        : Semantics(
            link: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => follow(link),
              child: child,
            ),
          );

    Widget block(PageBlock b) => switch (b.kind) {
      PageBlockKind.heading => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: tappable(
          b.link,
          Semantics(
            header: true,
            child: Text(
              b.text,
              style: LbmText.display.copyWith(
                fontSize: 21,
                height: 1.2,
                color: c.ink,
                decoration: b.link.isEmpty ? null : TextDecoration.underline,
                decorationColor: c.ink,
              ),
            ),
          ),
        ),
      ),
      PageBlockKind.text => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: tappable(
          b.link,
          Text(
            b.text,
            style: LbmText.pinMeta.copyWith(
              fontSize: 15,
              height: 1.55,
              fontWeight: FontWeight.w500,
              color: c.ink,
            ),
          ),
        ),
      ),
      PageBlockKind.bullet => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 9, right: 10),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: c.accentText,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Expanded(
              child: Text(
                b.text,
                style: LbmText.pinMeta.copyWith(
                  fontSize: 15,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                  color: c.ink,
                ),
              ),
            ),
          ],
        ),
      ),
      PageBlockKind.image => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: tappable(
          b.link,
          ClipRRect(
            borderRadius: LbmRadius.imageR,
            // Its own shape, whatever that is, and no room at all when it
            // will not load.
            child: ProductPhoto(
              url: b.url,
              fit: BoxFit.fitWidth,
              cacheWidth: 1000,
              fallback: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
      PageBlockKind.button => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: PillButton(b.text, onPressed: () => follow(b.url)),
      ),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
      children: [
        Text(
          'LITTLE BLUE MARKET',
          style: LbmText.pinMeta.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            color: c.accentText,
          ),
        ),
        for (final b in page.blocks) block(b),
        const SizedBox(height: 20),
        PillButton(
          'See it on littlebluemarket.com',
          style: PillStyle.ghost,
          icon: Icons.open_in_new_rounded,
          onPressed: () => follow(page.url),
        ),
      ],
    );
  }
}

/// Where a link on a store page goes in the app.
///
/// A collection opens the app's own collection screen, and another posted
/// page opens here too. Anything else (a product, a page that is not posted,
/// another site) opens over the app in the in-app browser, as the store's
/// info pages in Edit profile do.
Future<void> openStorePageLink(
  BuildContext context,
  String url, {
  List<StorePage> posted = const [],
}) async {
  final target = storePageLinkTarget(url, posted: posted);
  switch (target) {
    case (kind: StoreLinkKind.collection, :final value):
      context.goToCollection(value);
    case (kind: StoreLinkKind.page, :final value):
      context.goToStorePage(value);
    case (kind: StoreLinkKind.web, :final value):
      final messenger = ScaffoldMessenger.of(context);
      if (!await openInApp(value)) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not open $value')),
        );
      }
  }
}

enum StoreLinkKind { collection, page, web }

/// Pure, so the rules are tested without a router.
({StoreLinkKind kind, String value}) storePageLinkTarget(
  String url, {
  List<StorePage> posted = const [],
}) {
  final uri = Uri.tryParse(url);
  final ours =
      uri != null &&
      uri.host.replaceFirst('www.', '') == 'littlebluemarket.com';
  if (ours) {
    final parts = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (parts.length == 2 && parts[0] == 'collections' && parts[1] != 'all') {
      return (kind: StoreLinkKind.collection, value: parts[1]);
    }
    final page = posted
        .where((p) => p.readsInApp && Uri.tryParse(p.url)?.path == uri.path)
        .firstOrNull;
    if (page != null) return (kind: StoreLinkKind.page, value: page.id);
  }
  return (kind: StoreLinkKind.web, value: url);
}
