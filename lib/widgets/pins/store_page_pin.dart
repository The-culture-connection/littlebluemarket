import 'package:flutter/material.dart';

import '../../legal_links.dart';
import '../../models/feed_item.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../product_art.dart';

/// One of Little Blue Market's own pages in the For you grid: the page's
/// picture, its title and a line of what it says, opened over the app
/// (Grace, 2026-10-28). Column width, like a forum thread, because it is a
/// thing to read rather than a banner.
class StorePagePin extends StatelessWidget {
  const StorePagePin({super.key, required this.item});

  final StorePageItem item;

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await openInApp(item.page.url)) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open ${item.page.url}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final page = item.page;

    return Semantics(
      button: true,
      label: 'Little Blue Market page: ${page.title}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(context),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: LbmRadius.imageR,
            boxShadow: c.shadowSoft,
          ),
          child: ClipRRect(
            borderRadius: LbmRadius.imageR,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (page.hasPhoto)
                  AspectRatio(
                    aspectRatio: 4 / 3,
                    child: ProductPhoto(
                      url: page.imageUrl,
                      cacheWidth: 500,
                      fallback: ColoredBox(color: c.skyMist),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'LITTLE BLUE MARKET',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LbmText.pinMeta.copyWith(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          color: c.accentText,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        page.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: LbmText.display.copyWith(
                          fontSize: 17,
                          height: 1.18,
                          color: c.ink,
                        ),
                      ),
                      if (page.blurb.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          page.blurb,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: LbmText.pinMeta.copyWith(
                            fontSize: 12.5,
                            height: 1.4,
                            color: c.ink2,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Read it',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: LbmText.pinTitle.copyWith(
                                fontSize: 13,
                                color: c.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: c.ink,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
