import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/location.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/filter_chips.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';
import '../../widgets/skeleton.dart';
import 'collection_screen.dart' show CollectionTiles;
import 'directory_browse_screen.dart' show DirectoryRail;

/// The search entry point: scope, the initiative hashtags, and recent searches.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery = ''});

  /// What the search pill on the results screen was showing, so tapping it
  /// opens the field with that word in it rather than empty.
  final String initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final _controller = TextEditingController(text: widget.initialQuery);

  @override
  void initState() {
    super.initState();
    // Selected, not just present: the likeliest next act is replacing it.
    if (widget.initialQuery.isNotEmpty) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initialQuery.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    // Recorded before navigating, so it is in the list when you come back.
    await ref.read(searchRepositoryProvider).recordSearch(trimmed);
    ref.invalidate(recentSearchesProvider);
    if (!mounted) return;
    ref.read(searchFiltersProvider.notifier).setQuery(trimmed);
    // Replaces this screen: see LbmNavigation.replaceWithResults.
    context.replaceWithResults(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final filters = ref.watch(searchFiltersProvider);
    final scope = filters.scope;
    final tags = ref.watch(popularTagsProvider);
    final recents = ref.watch(recentSearchesProvider);

    return LbmScreen(
      appBar: LbmAppBar(
        // The field is half of a search, so Back out of it goes where Back
        // out of the results goes.
        onBack: () => context.leaveSearch(),
        titleWidget: LbmField(
          controller: _controller,
          hintText: 'Search goods, services, sellers, #tags',
          pill: true,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: _submit,
        ),
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Scope, and beside it Near me — the same button, in the same
          // place, as on the results screen this leads to.
          //
          // It is a *toggle on the search*, not a way into the feed's Near me
          // tab. It was the latter, which was wrong twice over: it left the
          // screen you were searching on, and it never narrowed a search at
          // all, so typing a word afterwards searched the whole market again
          // (Grace, 2026-09-28: "there should be a near me toggle for the
          // search"). Turned on here, the next search is constrained to the
          // radius, which is what `SearchFilters.isGeoConstrained` has always
          // meant and what both repositories already honour.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final option in SearchScope.values)
                        LbmChip(
                          option.label,
                          style: option == scope
                              ? ChipStyle.on
                              : ChipStyle.quiet,
                          onTap: () => ref
                              .read(searchFiltersProvider.notifier)
                              .setScope(option),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                NearMeButton(
                  active: filters.nearMe,
                  onTap: () => toggleNearMe(context, ref),
                ),
              ],
            ),
          ),
          // What "near" currently means, said only while it is on. A search
          // silently narrowed to twenty miles, with nothing on screen saying
          // so, is the sort of thing somebody reports as "search is broken".
          if (filters.nearMe)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
              child: Row(
                children: [
                  Icon(Icons.place_outlined, size: 14, color: c.ink2),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Searching within '
                      '${Fmt.distanceMiles(filters.radiusMiles)} of '
                      '${filters.origin?.label ?? 'you'}',
                      style: LbmText.pinMeta.copyWith(color: c.ink2),
                    ),
                  ),
                ],
              ),
            ),
          if (filters.nearMe)
            FilterChips(
              items: [
                for (final miles in const [5.0, 10.0, 25.0, 50.0])
                  (miles.toString(), Fmt.distanceMiles(miles)),
              ],
              selected: filters.radiusMiles.toString(),
              onSelect: (value) => ref
                  .read(searchFiltersProvider.notifier)
                  .setRadius(double.parse(value)),
            ),
          // The store's real taxonomy, and littlebluecart.com's beside it.
          // Both used to sit on top of the Market feed, where they pushed the
          // first photograph below the fold and answered a question nobody
          // had asked yet. Browsing by category is a thing you come looking
          // for, so it lives on the screen you come looking on.
          //
          // Tiles rather than a rail for the Market's seven: this is the
          // browse hub, and a hub whose main act is hidden behind a sideways
          // drag is not one (Grace, 2026-09-28). The directory stays a rail;
          // it is the second question, and it has far more than seven.
          const SectionHead('Browse the Market'),
          const CollectionTiles(),
          const DirectoryRail(),
          const SectionHead('Popular right now — initiatives'),
          LbmAsync<List<TagCount>>(
            tags,
            skeleton: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: GridSkeleton(count: 4),
            ),
            onRetry: () => ref.invalidate(popularTagsProvider),
            isEmpty: (tags) => tags.isEmpty,
            empty: const LbmEmpty(title: 'No hashtags yet', compact: true),
            data: (tags) => _TagGrid(tags: tags),
          ),
          const SectionHead('Recent searches'),
          LbmAsync<List<String>>(
            recents,
            skeleton: const ListRowSkeleton(rows: 3, withAvatar: false),
            isEmpty: (recents) => recents.isEmpty,
            empty: const LbmEmpty(title: 'Nothing searched yet', compact: true),
            data: (recents) => Column(
              children: [
                LbmCard(
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  child: RowStack(
                    children: [
                      for (final recent in recents)
                        ListRow(
                          leading: Icon(
                            Icons.search_rounded,
                            size: 18,
                            color: c.ink3,
                          ),
                          title: Text(
                            recent,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.ink,
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: c.ink3,
                            ),
                            tooltip: 'Remove',
                            // Persisted now, rather than dropped on pop.
                            onPressed: () async {
                              await ref
                                  .read(searchRepositoryProvider)
                                  .removeRecentSearch(recent);
                              ref.invalidate(recentSearchesProvider);
                            },
                          ),
                          onTap: () => _submit(recent),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Center(
                    child: TextButton(
                      onPressed: () async {
                        await ref
                            .read(searchRepositoryProvider)
                            .clearRecentSearches();
                        ref.invalidate(recentSearchesProvider);
                      },
                      child: Text(
                        'Clear recent searches',
                        style: TextStyle(
                          fontFamily: kBodyFont,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: c.skyDeep,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _TagGrid extends StatelessWidget {
  const _TagGrid({required this.tags});

  final List<TagCount> tags;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 9,
          crossAxisSpacing: 9,
          // The tile holds two lines of text, so its height has to grow with
          // the reader's text size rather than stay pinned.
          mainAxisExtent: MediaQuery.textScalerOf(context).scale(68),
        ),
        itemCount: tags.length,
        itemBuilder: (context, i) {
          final tag = tags[i];
          return LbmCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            onTap: () => context.goToTag(tag.tag),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    tag.tag,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: c.accentText,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Flexible(
                  child: Text(
                    tag.countLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LbmText.xtiny.copyWith(
                      color: c.ink2,
                      fontFeatures: kTabularFigures,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
