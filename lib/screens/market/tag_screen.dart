import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/feed_item.dart';
import '../../models/models.dart';
import '../../state/providers.dart';
import '../../state/tags.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/detail_sheet.dart';
import '../../widgets/filter_chips.dart';
import '../../widgets/lbm_toast.dart';
import '../../widgets/masonry.dart';
import '../../widgets/pins/cart_pin.dart';
import '../../widgets/pins/directory_pin.dart';
import '../../widgets/pins/makers_rail.dart';
import '../../widgets/pins/product_pin.dart';
import '../../widgets/pins/review_pin.dart';
import '../../widgets/pins/shoutout_pin.dart';
import '../../widgets/primitives.dart';
import '../../widgets/product_art.dart';
import '../../widgets/sheets.dart';
import '../../widgets/skeleton.dart';

/// A hashtag as a place.
///
/// A tag used to open a search results screen, which is a page of results
/// rather than somewhere you can be: you could not follow it, nothing told
/// you when something new arrived under it, and coming back meant searching
/// again. Every `#tag` in the app lands here now.
class TagScreen extends ConsumerStatefulWidget {
  const TagScreen({super.key, required this.tag});

  /// The key, without its hash. See [tagKey].
  final String tag;

  @override
  ConsumerState<TagScreen> createState() => _TagScreenState();
}

class _TagScreenState extends ConsumerState<TagScreen> {
  var _filter = 'all';

  static const _filters = <(String, String)>[
    ('all', 'All'),
    ('product', 'Products'),
    ('review', 'Reviews'),
    ('post', 'Posts'),
    ('maker', 'Makers'),
  ];

  @override
  Widget build(BuildContext context) {
    final key = tagKey(widget.tag);
    final posts = ref.watch(tagFeedProvider(key));

    return ColoredBox(
      color: context.c.paper,
      child: LbmAsync<List<Post>>(
        posts,
        skeleton: const SafeArea(child: GridSkeleton(count: 6)),
        onRetry: () => ref.invalidate(tagFeedProvider(key)),
        data: (all) => _Body(
          tag: key,
          posts: all,
          filter: _filter,
          filters: _filters,
          onFilter: (next) => setState(() => _filter = next),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.tag,
    required this.posts,
    required this.filter,
    required this.filters,
    required this.onFilter,
  });

  final String tag;
  final List<Post> posts;
  final String filter;
  final List<(String, String)> filters;
  final ValueChanged<String> onFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final followed = ref.watch(followedTagsProvider).value ?? const <String>{};
    final notified = ref.watch(notifiedTagsProvider).value ?? const <String>{};
    final isFollowing = followed.contains(tag);
    final isNotifying = notified.contains(tag);

    // The first photograph anybody posted under it, as the hero. A tag with
    // nothing to show gets the sky gradient instead of an empty grey box.
    final hero = _heroPhoto(posts);

    final makers = <String>{for (final post in posts) post.authorId};
    final people = [
      for (final id in makers) ref.watch(personProvider(id)).value,
    ].nonNulls.toList();

    final shown = _shown(posts);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        DetailGallery(
          actions: const [FloatingCartButton()],
          child: SizedBox(
            height: 240,
            child: hero == null
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: const Alignment(-0.6, -0.8),
                        end: const Alignment(0.6, 0.8),
                        colors: c.shoutoutGradient,
                      ),
                    ),
                  )
                : ColoredBox(
                    color: c.skyMist,
                    child: ProductPhoto(
                      url: hero,
                      fallback: ColoredBox(color: c.skyMist),
                    ),
                  ),
          ),
        ),
        DetailBody(
          children: [
            DetailSheet(
              children: [
                Text(
                  'COLLECTION',
                  style: LbmText.pinMeta.copyWith(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                    color: c.ink2,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  tagLabel(tag),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: LbmText.headline.copyWith(color: c.ink),
                ),
                const SizedBox(height: 7),
                Text(
                  // "On this page", not "in the world": these are the posts
                  // loaded so far, and saying otherwise would be a number we
                  // have not counted.
                  '${posts.length} ${posts.length == 1 ? 'post' : 'posts'} '
                  'here · ${people.length} '
                  '${people.length == 1 ? 'maker' : 'makers'}',
                  style: LbmText.pinMeta.copyWith(fontSize: 12.5, color: c.ink2),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: PillButton(
                        isFollowing ? 'Following' : 'Follow',
                        icon: isFollowing ? Icons.check_rounded : null,
                        style: isFollowing ? PillStyle.quiet : PillStyle.solid,
                        onPressed: () => _toggleFollow(
                          context,
                          ref,
                          on: !isFollowing,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: PillButton(
                        isNotifying ? 'Notifying you' : 'Notify me',
                        icon: isNotifying
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_none_rounded,
                        style: PillStyle.ghost,
                        onPressed: () =>
                            _toggleNotify(context, ref, on: !isNotifying),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilterChips(
              items: filters,
              selected: filter,
              onSelect: onFilter,
            ),
            const SizedBox(height: 12),
            if (filter == 'maker')
              if (people.isEmpty)
                const LbmEmpty(
                  title: 'Nobody yet',
                  body: 'The first person to post under this tag lands here.',
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: MakersRail(
                    item: MakersRailItem(people),
                    title: 'Posting under ${tagLabel(tag)}',
                  ),
                )
            else if (shown.isEmpty)
              LbmEmpty(
                title: 'Nothing under ${tagLabel(tag)} yet',
                body: 'Follow it and it will fill up as people post.',
              )
            else
              LbmMasonry.fixed(
                children: [
                  for (final post in shown) _pinFor(post),
                ],
              ),
            const SizedBox(height: 40),
          ],
        ),
      ],
    );
  }

  /// Posts narrowed to the chip that is on.
  List<Post> _shown(List<Post> all) => switch (filter) {
    'product' => [for (final p in all) if (p is ListingPost) p],
    'review' => [for (final p in all) if (p is ReviewPost) p],
    'post' => [
      for (final p in all)
        if (p is ShoutoutPost || p is CartPost) p,
    ],
    _ => all,
  };

  Widget _pinFor(Post post) => switch (post) {
    ListingPost p => ProductPin.of(
      p,
      key: ValueKey(p.id),
      proof: p.product.saveCount >= ProductItem.proofThreshold,
    ),
    ReviewPost p => ReviewPin.of(p, key: ValueKey(p.id)),
    CartPost p => CartPin.of(p, key: ValueKey(p.id)),
    ShoutoutPost p => ShoutoutPin.of(p, key: ValueKey(p.id)),
    DirectoryPost p => DirectoryPin(
      key: ValueKey(p.id),
      item: DirectoryItem(p),
    ),
  };

  static String? _heroPhoto(List<Post> posts) {
    for (final post in posts) {
      final url = switch (post) {
        ListingPost p => p.product.imageUrls.firstOrNull,
        ReviewPost p => p.imageUrls.firstOrNull,
        ShoutoutPost p => p.imageUrls.firstOrNull,
        CartPost p => p.items.firstOrNull?.imageUrl,
        DirectoryPost _ => null,
      };
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  void _toggleFollow(
    BuildContext context,
    WidgetRef ref, {
    required bool on,
  }) {
    requireProfile(context, ref, () async {
      await ref
          .read(socialRepositoryProvider)
          .setFollowingTag(tag, on: on);
      if (!context.mounted) return;
      if (on) {
        LbmToast.show(
          context,
          title: 'Following ${tagLabel(tag)}',
          subtitle: 'New posts under it will show up in your Market',
        );
      }
    });
  }

  void _toggleNotify(
    BuildContext context,
    WidgetRef ref, {
    required bool on,
  }) {
    requireProfile(context, ref, () async {
      await ref.read(socialRepositoryProvider).setTagNotify(tag, on: on);
      if (!context.mounted) return;
      LbmToast.show(
        context,
        title: on
            ? 'We will tell you about ${tagLabel(tag)}'
            : 'No more alerts for ${tagLabel(tag)}',
        subtitle: on ? 'Following it too' : null,
      );
    });
  }
}
