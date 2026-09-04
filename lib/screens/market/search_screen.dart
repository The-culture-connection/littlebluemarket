import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';
import '../../widgets/skeleton.dart';

/// The search entry point: scope, the initiative hashtags, and recent searches.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();

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
    context.goToResults(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final scope = ref.watch(searchFiltersProvider).scope;
    final tags = ref.watch(popularTagsProvider);
    final recents = ref.watch(recentSearchesProvider);

    return LbmScreen(
      appBar: LbmAppBar(
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
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 4),
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final option in SearchScope.values)
                  LbmChip(
                    option.label,
                    style: option == scope ? ChipStyle.on : ChipStyle.quiet,
                    onTap: () =>
                        ref.read(searchFiltersProvider.notifier).setScope(option),
                  ),
              ],
            ),
          ),
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
            empty: const LbmEmpty(
              title: 'Nothing searched yet',
              compact: true,
            ),
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
            onTap: () => context.goToResults(tag.tag),
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
