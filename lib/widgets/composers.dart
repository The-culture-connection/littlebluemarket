import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/repositories.dart';
import '../models/models.dart';
import '../state/providers.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'async.dart';
import 'primitives.dart';
import 'product_art.dart';
import 'sheets.dart';
import 'skeleton.dart';

/// The sheet behind the + on your own profile.
///
/// Three kinds of post, and which ones are offered depends on who is asking: a
/// buyer can review what they bought and shout out a seller, and a seller can
/// also list a good or a service.
Future<void> showNewPostSheet(BuildContext context, WidgetRef ref) {
  final isSeller = ref.read(isSellerProvider);

  return showLbmSheet(context, (sheetContext) {
    final c = sheetContext.c;

    void open(Widget composer) {
      Navigator.of(sheetContext).pop();
      showLbmSheet(context, (_) => composer);
    }

    return LbmSheet(
      children: [
        Text(
          'What are you posting?',
          style: LbmText.display.copyWith(fontSize: 21, color: c.ink),
        ),
        const SizedBox(height: 14),
        if (isSeller)
          _Option(
            title: 'A good or a service',
            subtitle: 'Something from your storefront',
            onTap: () => open(const ListingComposer()),
          ),
        _Option(
          title: 'A review',
          subtitle: 'Attached to something you bought',
          onTap: () => open(const ReviewComposer()),
        ),
        _Option(
          title: 'A shoutout',
          subtitle: 'Name a seller other people should find',
          onTap: () => open(const ShoutoutComposer()),
        ),
        const SizedBox(height: 4),
        Text(
          'Every post can carry initiative hashtags. Reviews stay attached to '
          'the product they came from.',
          style: LbmText.xtiny.copyWith(color: c.ink3, height: 1.55),
        ),
      ],
    );
  });
}

class _Option extends StatelessWidget {
  const _Option({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ListRow(
        background: c.skyWash,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Icon(Icons.chevron_right_rounded, color: c.ink3, size: 22),
        onTap: onTap,
      ),
    );
  }
}

// ------------------------------------------------------------------- review

/// Pick something you bought, rate it, say why.
///
/// The list comes from the order pipeline, so you can only review a purchase
/// that actually happened — which is what makes a review worth reading.
class ReviewComposer extends ConsumerStatefulWidget {
  const ReviewComposer({super.key});

  @override
  ConsumerState<ReviewComposer> createState() => _ReviewComposerState();
}

class _ReviewComposerState extends ConsumerState<ReviewComposer> {
  final _text = TextEditingController();
  Purchase? _picked;
  int _rating = 5;
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final picked = _picked;
    if (picked == null || _text.text.trim().isEmpty || _saving) return;
    setState(() => _saving = true);

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(socialRepositoryProvider)
          .addReview(
            NewReview(
              productId: picked.productId,
              rating: _rating,
              text: _text.text.trim(),
              purchaseId: picked.id,
            ),
          );
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Review posted')));
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(describeError(error).body)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final purchases = ref.watch(purchasesProvider);

    return LbmSheet(
      children: [
        Text(
          'Review something you bought',
          style: LbmText.display.copyWith(fontSize: 21, color: c.ink),
        ),
        const SizedBox(height: 14),
        LbmAsync<List<Purchase>>(
          purchases,
          skeleton: const ListRowSkeleton(rows: 2, withAvatar: false),
          isEmpty: (all) => all.where((p) => p.canReview).isEmpty,
          empty: const LbmEmpty(
            title: 'Nothing to review yet',
            body: 'Reviews open up once an order lands.',
            compact: true,
          ),
          data: (all) {
            final reviewable = all.where((p) => p.canReview).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final purchase in reviewable)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PurchaseRow(
                      purchase: purchase,
                      selected: _picked?.id == purchase.id,
                      onTap: () => setState(() => _picked = purchase),
                    ),
                  ),
                if (_picked != null) ...[
                  const SizedBox(height: 8),
                  _StarPicker(
                    rating: _rating,
                    onChanged: (rating) => setState(() => _rating = rating),
                  ),
                  const SizedBox(height: 12),
                  LbmField(
                    label: 'What should other people know?',
                    controller: _text,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 14),
                  PillButton(
                    _saving ? 'Posting…' : 'Post review',
                    onPressed: _saving ? null : _submit,
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PurchaseRow extends ConsumerWidget {
  const _PurchaseRow({
    required this.purchase,
    required this.selected,
    required this.onTap,
  });

  final Purchase purchase;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final product = ref.watch(productProvider(purchase.productId));

    return ListRow(
      background: selected ? c.accentMist : c.skyWash,
      borderRadius: const BorderRadius.all(Radius.circular(18)),
      leading: SizedBox(
        width: 40,
        child: LbmAsync<Product>(
          product,
          skeleton: const LbmSkeleton(height: 40, radius: 10),
          errorBuilder: (_, _) => const LbmSkeleton(height: 40, radius: 10),
          data: (product) => ProductArt(
            product,
            square: true,
            borderRadius: const BorderRadius.all(Radius.circular(10)),
          ),
        ),
      ),
      title: Text(purchase.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        purchase.delivered ? 'Received ${purchase.age} ago' : 'On its way',
      ),
      trailing: Icon(
        selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded,
        size: 20,
        color: selected ? c.accentDeep : c.ink3,
      ),
      onTap: onTap,
    );
  }
}

class _StarPicker extends StatelessWidget {
  const _StarPicker({required this.rating, required this.onChanged});

  final int rating;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        for (var star = 1; star <= 5; star++)
          Semantics(
            button: true,
            label: '$star star${star == 1 ? '' : 's'}',
            child: InkResponse(
              radius: 22,
              onTap: () => onChanged(star),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(
                  star <= rating
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 30,
                  color: star <= rating ? c.accent : c.ink3,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ----------------------------------------------------------------- shoutout

/// Name a seller other people should find.
class ShoutoutComposer extends ConsumerStatefulWidget {
  const ShoutoutComposer({super.key});

  @override
  ConsumerState<ShoutoutComposer> createState() => _ShoutoutComposerState();
}

class _ShoutoutComposerState extends ConsumerState<ShoutoutComposer> {
  final _text = TextEditingController();
  Person? _mentioned;
  List<Person> _matches = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onChanged);
  }

  @override
  void dispose() {
    _text
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  /// Resolves the last @-mention as it is typed, so the shoutout can carry a
  /// real seller id rather than a string that happens to look like a handle.
  Future<void> _onChanged() async {
    final text = _text.text;
    final at = text.lastIndexOf('@');
    if (at == -1) {
      if (_matches.isNotEmpty) setState(() => _matches = const []);
      return;
    }
    final fragment = text.substring(at + 1).split(RegExp(r'\s')).first;
    if (fragment.isEmpty) return;

    final people = await ref
        .read(profileRepositoryProvider)
        .searchPeople(fragment, limit: 4);
    if (!mounted) return;
    setState(() => _matches = people);
  }

  Future<void> _submit() async {
    if (_text.text.trim().isEmpty || _saving) return;
    setState(() => _saving = true);

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(socialRepositoryProvider)
          .createPost(
            NewPost.shoutout(
              text: _text.text.trim(),
              aboutSellerId: _mentioned?.id,
            ),
          );
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Shoutout posted')));
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(describeError(error).body)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return LbmSheet(
      children: [
        Text(
          'Shout out a seller',
          style: LbmText.display.copyWith(fontSize: 21, color: c.ink),
        ),
        const SizedBox(height: 6),
        Text(
          'Type @ to name them.',
          style: LbmText.tiny.copyWith(color: c.ink2),
        ),
        const SizedBox(height: 14),
        LbmField(
          label: 'Your shoutout',
          controller: _text,
          maxLines: 4,
          autofocus: true,
        ),
        if (_matches.isNotEmpty) ...[
          const SizedBox(height: 10),
          LbmCard(
            color: c.skyWash,
            child: RowStack(
              children: [
                for (final person in _matches)
                  ListRow(
                    leading: Avatar(person, size: AvatarSize.sm),
                    title: Text(person.name),
                    subtitle: Text(person.handle),
                    onTap: () {
                      final at = _text.text.lastIndexOf('@');
                      _text.text =
                          '${_text.text.substring(0, at)}${person.handle} ';
                      _text.selection = TextSelection.collapsed(
                        offset: _text.text.length,
                      );
                      setState(() {
                        _mentioned = person;
                        _matches = const [];
                      });
                    },
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        PillButton(
          _saving ? 'Posting…' : 'Post shoutout',
          onPressed: _saving ? null : _submit,
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ listing

/// Post one of your storefront listings to the feed.
///
/// Reads from the seller's own catalog rather than asking them to retype it,
/// which is what "post the goods you already uploaded" means.
class ListingComposer extends ConsumerStatefulWidget {
  const ListingComposer({super.key});

  @override
  ConsumerState<ListingComposer> createState() => _ListingComposerState();
}

class _ListingComposerState extends ConsumerState<ListingComposer> {
  final _caption = TextEditingController();
  Product? _picked;
  bool _saving = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final picked = _picked;
    if (picked == null || _saving) return;
    setState(() => _saving = true);

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(socialRepositoryProvider)
          .createPost(
            NewPost.listing(
              productId: picked.id,
              caption: _caption.text.trim().isEmpty
                  ? null
                  : _caption.text.trim(),
              tags: picked.tags,
            ),
          );
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Posted')));
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(describeError(error).body)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final uid = ref.watch(currentUidProvider);
    final products = uid == null
        ? const AsyncValue<List<Product>>.data([])
        : ref.watch(sellerProductsProvider(uid));

    return LbmSheet(
      children: [
        Text(
          'Post a listing',
          style: LbmText.display.copyWith(fontSize: 21, color: c.ink),
        ),
        const SizedBox(height: 14),
        LbmAsync<List<Product>>(
          products,
          skeleton: const ListRowSkeleton(rows: 2, withAvatar: false),
          isEmpty: (products) => products.isEmpty,
          empty: const LbmEmpty(
            title: 'Nothing in your storefront yet',
            body: 'Add it to your store and it shows up here.',
            compact: true,
          ),
          data: (products) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final product in products)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListRow(
                    background: _picked?.id == product.id
                        ? c.accentMist
                        : c.skyWash,
                    borderRadius: const BorderRadius.all(Radius.circular(18)),
                    leading: SizedBox(
                      width: 40,
                      child: ProductArt(
                        product,
                        square: true,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(10),
                        ),
                      ),
                    ),
                    title: Text(product.title, maxLines: 2),
                    subtitle: Text(product.price),
                    trailing: Icon(
                      _picked?.id == product.id
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 20,
                      color: _picked?.id == product.id ? c.accentDeep : c.ink3,
                    ),
                    onTap: () => setState(() => _picked = product),
                  ),
                ),
              if (_picked != null) ...[
                const SizedBox(height: 8),
                LbmField(
                  label: 'Say something about it (optional)',
                  controller: _caption,
                  maxLines: 3,
                ),
                const SizedBox(height: 14),
                PillButton(
                  _saving ? 'Posting…' : 'Post it',
                  onPressed: _saving ? null : _submit,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
