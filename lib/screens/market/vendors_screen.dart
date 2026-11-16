import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';
import '../../widgets/skeleton.dart';

/// Every shop on the market, A to Z, with a box to narrow it (Grace,
/// 2026-11-16: "Let shoppers browse by vendor on the app in the market
/// portion of the app"). A shop opens its storefront: its products, its
/// reviews, and a way to message it.
class VendorsScreen extends ConsumerStatefulWidget {
  const VendorsScreen({super.key});

  @override
  ConsumerState<VendorsScreen> createState() => _VendorsScreenState();
}

class _VendorsScreenState extends ConsumerState<VendorsScreen> {
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vendors = ref.watch(allVendorsProvider);

    return LbmScreen(
      appBar: LbmAppBar(
        title: 'Shop by vendor',
        showBack: context.canPop(),
        actions: const [HomeButton()],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
            child: LbmField(
              controller: _query,
              hintText: 'Find a shop by name',
              pill: true,
              textInputAction: TextInputAction.search,
            ),
          ),
          Expanded(
            child: LbmAsync<List<Person>>(
              vendors,
              skeleton: const ListRowSkeleton(rows: 8),
              onRetry: () => ref.invalidate(allVendorsProvider),
              isEmpty: (all) => all.isEmpty,
              empty: const LbmEmpty(
                title: 'No shops yet',
                body: 'Shops appear here as soon as they list a product.',
              ),
              data: (all) {
                final shown = filterVendors(all, _query.text);
                if (shown.isEmpty) {
                  return LbmEmpty(
                    title: 'No shop called "${_query.text.trim()}"',
                    body: 'Try part of the name, or search everything.',
                    action: PillButton(
                      'Search the market',
                      expand: false,
                      onPressed: () =>
                          context.goToResults(_query.text.trim()),
                    ),
                  );
                }
                final rows = _withLetters(shown);
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(allVendorsProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 28),
                    itemCount: rows.length,
                    itemBuilder: (context, i) => switch (rows[i]) {
                      final String letter => _Letter(letter),
                      final Person person => _VendorRow(person: person),
                      _ => const SizedBox.shrink(),
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// The shops with a letter before each run of them.
  static List<Object> _withLetters(List<Person> vendors) {
    final rows = <Object>[];
    String? last;
    for (final v in vendors) {
      final letter = vendorLetter(v.name);
      if (letter != last) rows.add(letter);
      last = letter;
      rows.add(v);
    }
    return rows;
  }
}

class _Letter extends StatelessWidget {
  const _Letter(this.letter);

  final String letter;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
      child: Semantics(
        header: true,
        child: Text(
          letter,
          style: LbmText.display.copyWith(fontSize: 18, color: c.ink2),
        ),
      ),
    );
  }
}

class _VendorRow extends StatelessWidget {
  const _VendorRow({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: ListRow(
        background: c.surface,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        leading: Avatar(person, size: AvatarSize.sm),
        title: Text(
          person.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: LbmText.pinTitle.copyWith(fontSize: 14, color: c.ink),
        ),
        subtitle: person.cityState.isEmpty
            ? null
            : Text(
                person.cityState,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LbmText.xtiny.copyWith(color: c.ink2),
              ),
        trailing: Icon(Icons.chevron_right_rounded, color: c.ink3),
        onTap: () => context.goToSeller(person.id),
      ),
    );
  }
}
