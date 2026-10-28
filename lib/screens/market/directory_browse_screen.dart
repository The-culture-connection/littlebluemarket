// Flutter's own Page (a Navigator route) is not wanted here; Page is the
// app's page-of-results model.
import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/directory_listing_card.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';
import '../../widgets/skeleton.dart';

/// The horizontal "Browse the directory" rail on the feed.
///
/// Deliberately the same shape as [CollectionRail] a few lines above it: one
/// chip per category, in the site's own words, hidden entirely when there
/// are none. Grace asked for the directory to be browsable "in the same way
/// that there is Browse the shop by category", so the two rails are siblings
/// rather than two different ideas stacked on each other.
class DirectoryRail extends ConsumerWidget {
  const DirectoryRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final categories = ref.watch(directoryCategoriesProvider);

    return LbmAsync<List<DirectoryCategory>>(
      categories,
      skeleton: const Padding(
        padding: EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: ChipRailSkeleton(),
      ),
      // Nothing mirrored yet is not an error worth a red card on the feed.
      errorBuilder: (_, _) => const SizedBox.shrink(),
      isEmpty: (items) => items.isEmpty,
      empty: const SizedBox.shrink(),
      data: (items) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Row(
                children: [
                  Expanded(
                    // A heading rather than a caption (Grace, 2026-10-21):
                    // at 12.5 it read as a footnote to the rail.
                    child: Text(
                      'Browse the directory',
                      style: LbmText.display.copyWith(
                        fontSize: 18,
                        color: c.ink,
                      ),
                    ),
                  ),
                  Text(
                    'littlebluecart.com',
                    style: LbmText.tiny.copyWith(color: c.ink3),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 7),
                itemBuilder: (context, i) => LbmChip(
                  items[i].name,
                  onTap: () => context.goToDirectoryCategory(items[i].slug),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every published business in one directory category, newest first.
///
/// A page at a time, because nobody knows yet how many listings
/// littlebluecart.com has and a category screen must not read the whole
/// directory to draw a screenful.
class DirectoryCategoryScreen extends ConsumerStatefulWidget {
  const DirectoryCategoryScreen({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<DirectoryCategoryScreen> createState() =>
      _DirectoryCategoryScreenState();
}

class _DirectoryCategoryScreenState
    extends ConsumerState<DirectoryCategoryScreen> {
  /// Pages after the first, which the provider owns.
  final _more = <DirectoryListing>[];
  String? _cursor;
  bool _loading = false;
  bool _started = false;

  Future<void> _loadMore() async {
    final cursor = _cursor;
    if (_loading || cursor == null) return;
    setState(() => _loading = true);
    try {
      final page = await ref
          .read(directoryRepositoryProvider)
          .listingsInCategory(widget.slug, cursor: cursor);
      if (!mounted) return;
      setState(() {
        _more.addAll(page.items);
        _cursor = page.cursor;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final category = ref.watch(directoryCategoryProvider(widget.slug));
    final first = ref.watch(directoryCategoryPageProvider(widget.slug));

    // The first page's cursor arrives with the page, not before it.
    if (!_started && first.value != null) {
      _started = true;
      _cursor = first.value!.cursor;
    }

    return LbmScreen(
      appBar: LbmAppBar(
        title: category?.name ?? 'Directory',
        actions: const [HomeButton()],
      ),
      child: RefreshIndicator(
        onRefresh: () async {
          setState(() {
            _more.clear();
            _cursor = null;
            _started = false;
          });
          ref.invalidate(directoryCategoryPageProvider(widget.slug));
        },
        child: LbmAsync<Page<DirectoryListing>>(
          first,
          skeleton: const PostCardSkeleton(count: 3),
          onRetry: () =>
              ref.invalidate(directoryCategoryPageProvider(widget.slug)),
          isEmpty: (page) => page.isEmpty,
          empty: const LbmEmpty(
            title: 'Nothing here yet',
            body:
                'No published businesses are filed under this category on '
                'littlebluecart.com right now.',
          ),
          data: (page) {
            final listings = [...page.items, ..._more];
            return ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 26),
              children: [
                if (category != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                    child: Text(
                      category.countLabel,
                      style: LbmText.tiny.copyWith(color: c.ink2),
                    ),
                  ),
                for (final listing in listings)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                    child: DirectoryListingCard(
                      listing: listing,
                      showClaim: true,
                    ),
                  ),
                if (_cursor != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                    child: PillButton(
                      _loading ? 'Loading…' : 'Show more',
                      style: PillStyle.ghost,
                      onPressed: _loading ? null : _loadMore,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The whole directory, a category to a row: where the Directory button in
/// the tab bar lands (Grace, 2026-10-21).
///
/// The same categories as the rail on the feed, in the site's own words and
/// with the count beside each, so the two never disagree about what is
/// there. Public data, so a guest gets it too.
class DirectoryHomeScreen extends ConsumerWidget {
  const DirectoryHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final categories = ref.watch(directoryCategoriesProvider);

    return LbmScreen(
      appBar: const LbmAppBar(title: 'Directory', actions: [HomeButton()]),
      child: LbmAsync<List<DirectoryCategory>>(
        categories,
        skeleton: const ListRowSkeleton(rows: 6),
        onRetry: () => ref.invalidate(directoryCategoriesProvider),
        isEmpty: (items) => items.isEmpty,
        empty: const LbmEmpty(
          title: 'The directory is on its way',
          body:
              'Businesses listed on littlebluecart.com show up here as soon '
              'as they are published.',
        ),
        data: (items) => ListView(
          padding: const EdgeInsets.only(top: 4, bottom: 26),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
              child: Text(
                'Small businesses from littlebluecart.com, by category.',
                style: LbmText.tiny.copyWith(color: c.ink2),
              ),
            ),
            LbmCard(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              child: RowStack(
                children: [
                  for (final category in items)
                    ListRow(
                      title: Text(category.name),
                      subtitle: Text(category.countLabel),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: c.ink3,
                      ),
                      onTap: () => context.goToDirectoryCategory(category.slug),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
