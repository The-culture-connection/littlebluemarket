import 'package:flutter/material.dart';

import '../../data/fixtures.dart';
import '../../router/nav.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';

/// Search gets its own screen: popular hashtags on top as initiative tiles,
/// recent searches below. The scope row narrows a query to hashtag, keyword, or
/// product type.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  int _scope = 0;
  late List<String> _recents = List.of(Fx.recentSearches);

  static const _scopes = ['All', 'Hashtags', 'Keywords', 'Product type'];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    context.goToResults(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return LbmScreen(
      appBar: LbmAppBar(
        titleWidget: LbmField(
          controller: _controller,
          hintText: 'Search…',
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
                for (var i = 0; i < _scopes.length; i++)
                  LbmChip(
                    _scopes[i],
                    style: i == _scope ? ChipStyle.on : ChipStyle.quiet,
                    onTap: () => setState(() => _scope = i),
                  ),
              ],
            ),
          ),
          const SectionHead('Popular right now — initiatives'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 9,
                crossAxisSpacing: 9,
                // The tile holds two lines of text, so its height has to grow
                // with the reader's text size rather than stay pinned.
                mainAxisExtent: MediaQuery.textScalerOf(context).scale(68),
              ),
              itemCount: Fx.tags.length,
              itemBuilder: (context, i) {
                final tag = Fx.tags[i];
                return LbmCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
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
          ),
          const SectionHead('Recent searches'),
          LbmCard(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            child: RowStack(
              children: [
                for (final recent in _recents)
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
                      icon: Icon(Icons.close_rounded, size: 18, color: c.ink3),
                      tooltip: 'Remove',
                      onPressed: () => setState(() => _recents.remove(recent)),
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
                onPressed: () => setState(() => _recents = []),
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
    );
  }
}
