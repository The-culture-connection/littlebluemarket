import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/repositories.dart';
import '../models/models.dart';
import '../state/providers.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'async.dart';
import 'lbm_toast.dart';
import 'photo_source.dart';
import 'primitives.dart';
import 'product_art.dart';
import 'sheets.dart';
import 'tag_entry.dart';
import 'skeleton.dart';

/// The uids of the members a text names with @, looked up by handle. A
/// handle nobody holds is left as text.
Future<List<String>> resolveMentionUids(
  WidgetRef ref,
  String text, {
  String? except,
}) async {
  final profiles = ref.read(profileRepositoryProvider);
  final uids = <String>[];
  for (final handle in parseMentionHandles(text)) {
    try {
      final person = await profiles.personByHandle(handle);
      if (person != null && person.id != except && !uids.contains(person.id)) {
        uids.add(person.id);
      }
    } on RepositoryException {
      // A lookup that fails costs a notification, not the post.
    }
  }
  return uids;
}

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
  const ReviewComposer({super.key, this.initialPurchaseId});

  /// Opened from "How was it?": this purchase is picked already.
  final String? initialPurchaseId;

  @override
  ConsumerState<ReviewComposer> createState() => _ReviewComposerState();
}

class _ReviewComposerState extends ConsumerState<ReviewComposer> {
  final _text = TextEditingController();
  var _tags = <String>[];
  Purchase? _picked;
  int _rating = 5;
  bool _saving = false;
  bool _preselected = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Words are optional: the rules ask for a rating between one and five and
  /// nothing else, and a star on its own is a real answer to "how was it".
  /// Making people write a paragraph is how a review count stays at zero.
  Future<void> _submit() async {
    final picked = _picked;
    if (picked == null || _saving) return;
    setState(() => _saving = true);

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final mentioned = await resolveMentionUids(ref, _text.text);
      await ref
          .read(socialRepositoryProvider)
          .addReview(
            NewReview(
              productId: picked.productId,
              rating: _rating,
              text: _text.text.trim(),
              purchaseId: picked.id,
              tags: {..._tags, ...parseHashtags(_text.text)}.toList(),
              mentionedUids: mentioned,
            ),
          );
      // Raised before the sheet closes, so there is still a context to hang
      // it on. The overlay it goes into belongs to the root navigator and
      // outlives the sheet.
      if (mounted) {
        LbmToast.show(
          context,
          title: 'Review posted',
          subtitle: 'The maker will see it',
          thumbnailUrl: picked.imageUrl,
        );
      }
      navigator.pop();
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(describeError(error).body)),
      );
    }
  }

  /// Ready-made words, for the people who have an opinion but not a sentence.
  static const _quickReplies = [
    'Would buy again',
    'Great gift',
    'Better than the photos',
    'Arrived quickly',
    'Beautifully packaged',
  ];

  void _appendQuickReply(String phrase) {
    final existing = _text.text.trim();
    setState(() {
      _text.text = existing.isEmpty ? phrase : '$existing. $phrase';
      _text.selection = TextSelection.collapsed(offset: _text.text.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final purchases = ref.watch(purchasesProvider);

    return LbmSheet(
      children: [
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
            if (!_preselected && widget.initialPurchaseId != null) {
              _preselected = true;
              for (final p in reviewable) {
                if (p.id == widget.initialPurchaseId) _picked = p;
              }
            }
            // Exactly one thing waiting: there is nothing to choose, so the
            // sheet opens on the stars rather than on a list of one.
            _picked ??= reviewable.length == 1 ? reviewable.first : null;
            final picked = _picked;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (picked == null) ...[
                  Text(
                    'Which one?',
                    style: LbmText.display.copyWith(
                      fontSize: 21,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (final purchase in reviewable)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PurchaseRow(
                        purchase: purchase,
                        selected: false,
                        onTap: () => setState(() => _picked = purchase),
                      ),
                    ),
                ] else ...[
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.all(
                          Radius.circular(12),
                        ),
                        child: SizedBox(
                          width: 46,
                          height: 46,
                          child: ColoredBox(
                            color: c.skyWash,
                            child:
                                picked.imageUrl == null ||
                                    picked.imageUrl!.isEmpty
                                ? Icon(Icons.image_outlined, color: c.ink3)
                                : ProductPhoto(
                                    url: picked.imageUrl!,
                                    cacheWidth: 140,
                                    fallback: ColoredBox(color: c.skyMist),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          'How was the ${picked.title}?',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: LbmText.display.copyWith(
                            fontSize: 20,
                            height: 1.15,
                            color: c.ink,
                          ),
                        ),
                      ),
                      if (reviewable.length > 1)
                        TextButton(
                          onPressed: () => setState(() => _picked = null),
                          child: const Text('Change'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // The stars first, and big: this is the whole review for
                  // most people, and everything under it is optional.
                  Center(
                    child: _StarPicker(
                      rating: _rating,
                      size: 40,
                      onChanged: (rating) => setState(() => _rating = rating),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Tap a star. That on its own counts.',
                      style: LbmText.pinMeta.copyWith(color: c.ink2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final phrase in _quickReplies)
                        LbmChip(
                          phrase,
                          style: ChipStyle.quiet,
                          fontSize: 12.5,
                          onTap: () => _appendQuickReply(phrase),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LbmField(
                    label: 'Anything else? (optional)',
                    controller: _text,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 10),
                  TagEntry(
                    tags: _tags,
                    onChanged: (tags) => setState(() => _tags = tags),
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
        purchase.delivered
            ? 'Received ${purchase.age} ago'
            : 'Ordered ${purchase.age} ago',
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
  const _StarPicker({
    required this.rating,
    required this.onChanged,
    this.size = 30,
  });

  final int rating;
  final ValueChanged<int> onChanged;

  /// Big on the review sheet, where the stars are the review.
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var star = 1; star <= 5; star++)
          Semantics(
            button: true,
            label: '$star star${star == 1 ? '' : 's'}',
            child: InkResponse(
              radius: size * 0.75,
              onTap: () => onChanged(star),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(
                  star <= rating
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: size,
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
  var _tags = <String>[];
  Person? _mentioned;
  List<Person> _matches = const [];
  bool _saving = false;
  Uint8List? _photo;
  String _photoType = 'image/jpeg';

  Future<void> _pickPhoto() async {
    final source = await choosePhotoSource(context);
    if (source == null || !mounted) return;
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photo = bytes;
        _photoType = pickedContentType(file);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open your photos: $error')),
      );
    }
  }

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
      final social = ref.read(socialRepositoryProvider);
      final photo = _photo;
      final imageUrls = photo == null
          ? const <String>[]
          : [await social.uploadPostPhoto(photo, contentType: _photoType)];
      final mentioned = await resolveMentionUids(ref, _text.text);
      await social.createPost(
        NewPost.shoutout(
          text: _text.text.trim(),
          aboutSellerId: _mentioned?.id,
          tags: {..._tags, ...parseHashtags(_text.text)}.toList(),
          imageUrls: imageUrls,
          mentionedUids: mentioned,
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
        const SizedBox(height: 10),
        TagEntry(
          tags: _tags,
          onChanged: (tags) => setState(() => _tags = tags),
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
        const SizedBox(height: 12),
        Row(
          children: [
            PillButton(
              _photo == null ? 'Add a photo' : 'Change photo',
              small: true,
              expand: false,
              style: PillStyle.quiet,
              icon: Icons.add_a_photo_outlined,
              onPressed: _saving ? null : _pickPhoto,
            ),
            if (_photo != null) ...[
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  _photo!,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 6),
              PillButton(
                'Remove',
                small: true,
                expand: false,
                style: PillStyle.ghost,
                onPressed: _saving ? null : () => setState(() => _photo = null),
              ),
            ],
          ],
        ),
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
  const ListingComposer({super.key, this.product});

  /// The product to post, when the seller has already said which.
  ///
  /// Tapping Post on a tile in your own Products tab arrives here with the
  /// product in hand, so the picker would be a list of one thing they have
  /// already chosen. Null from the Post button on your profile, where
  /// picking is the first thing to do.
  final Product? product;

  @override
  ConsumerState<ListingComposer> createState() => _ListingComposerState();
}

class _ListingComposerState extends ConsumerState<ListingComposer> {
  final _caption = TextEditingController();
  var _tags = <String>[];
  Product? _picked;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _picked = widget.product;
  }

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
      final mentioned = await resolveMentionUids(ref, _caption.text);
      await ref
          .read(socialRepositoryProvider)
          .createPost(
            NewPost.listing(
              productId: picked.id,
              caption: _caption.text.trim().isEmpty
                  ? null
                  : _caption.text.trim(),
              tags: {
                ...picked.tags,
                ..._tags,
                ...parseHashtags(_caption.text),
              }.toList(),
              mentionedUids: mentioned,
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

  /// The caption, the hashtags and the button. The same tail whether the
  /// product was picked here or handed in, so the two doors cannot drift.
  List<Widget> _tail(BuildContext context) => [
    const SizedBox(height: 8),
    LbmField(
      label: 'Say something about it (optional)',
      controller: _caption,
      maxLines: 3,
    ),
    const SizedBox(height: 10),
    TagEntry(tags: _tags, onChanged: (tags) => setState(() => _tags = tags)),
    const SizedBox(height: 14),
    PillButton(
      _saving ? 'Posting…' : 'Post it',
      onPressed: _saving ? null : _submit,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final uid = ref.watch(currentUidProvider);
    final products = uid == null
        ? const AsyncValue<List<Product>>.data([])
        : ref
              .watch(sellerProductsProvider(uid))
              .whenData(
                (all) => [
                  for (final p in all)
                    if (!p.isGone) p,
                ],
              );

    final chosen = widget.product;
    if (chosen != null) {
      return LbmSheet(
        children: [
          Text(
            'Post this to the feed',
            style: LbmText.display.copyWith(fontSize: 21, color: c.ink),
          ),
          const SizedBox(height: 14),
          ListRow(
            background: c.accentMist,
            borderRadius: const BorderRadius.all(Radius.circular(18)),
            leading: SizedBox(
              width: 40,
              child: ProductArt(
                chosen,
                square: true,
                borderRadius: const BorderRadius.all(Radius.circular(10)),
              ),
            ),
            title: Text(chosen.title, maxLines: 2),
            subtitle: Text(chosen.price),
          ),
          ..._tail(context),
        ],
      );
    }

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
              if (_picked != null) ..._tail(context),
            ],
          ),
        ),
      ],
    );
  }
}
