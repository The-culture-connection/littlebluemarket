import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/repositories/repositories.dart';
import '../../models/models.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';

/// Journey B: a seller adds a product.
///
/// It must feel like posting and behave like a product write to a live store.
/// So: the form is short and forgiving, every check that can run on the phone
/// runs before anything is uploaded, and the one moment the seller's mental
/// model diverges from reality ("I pressed Add and it is not in my shop") is
/// a modal, not a snackbar.
class AddProductScreen extends ConsumerStatefulWidget {
  const AddProductScreen({super.key, this.existing});

  /// When set, the form edits this listing and pushes the change to the
  /// product already on the store. Photos stay as they are.
  final Listing? existing;

  @override
  ConsumerState<AddProductScreen> createState() => _AddProductScreenState();
}

/// Resolves the listing for `/you/edit-product/:id` and opens the form on it.
class EditProductScreen extends ConsumerWidget {
  const EditProductScreen({super.key, required this.listingId});

  final String listingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = ref.watch(listingsProvider);
    return LbmAsync<List<Listing>>(
      listings,
      skeleton: const LbmScreen(
        appBar: LbmAppBar(title: 'Edit product'),
        child: SizedBox.shrink(),
      ),
      onRetry: () => ref.invalidate(listingsProvider),
      data: (items) {
        for (final listing in items) {
          if (listing.id == listingId) {
            return AddProductScreen(existing: listing);
          }
        }
        return const LbmScreen(
          appBar: LbmAppBar(title: 'Edit product'),
          child: LbmEmpty(
            title: 'That product is not here',
            body:
                'It may have been removed. Pull to refresh your Products tab.',
          ),
        );
      },
    );
  }
}

class _PickedPhoto {
  const _PickedPhoto(this.bytes, this.contentType);
  final Uint8List bytes;
  final String contentType;
}

class _AddProductScreenState extends ConsumerState<AddProductScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _sku = TextEditingController();
  final _tags = TextEditingController();
  final _photos = <_PickedPhoto>[];
  final _existingUrls = <String>[];
  final _collections = <String>{};
  final _categoryQuery = TextEditingController();
  List<ProductCategory> _categoryHits = const [];
  ProductCategory? _category;
  int _categorySearch = 0;

  bool _busy = false;
  String _stage = '';
  String? _error;

  /// Set once a draft exists, so a retry re-sends the same id rather than
  /// making a second product.
  String? _draftId;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _draftId = existing.id;
      _title.text = existing.title;
      _description.text = existing.description;
      _price.text = (existing.priceCents / 100).toStringAsFixed(2);
      _quantity.text = existing.quantity.toString();
      _sku.text = existing.sku ?? '';
      _tags.text = existing.tags.join(', ');
      _collections.addAll(existing.collectionHandles);
      _existingUrls.addAll(existing.imageUrls);
      if (existing.categoryId != null) {
        _category = ProductCategory(
          id: existing.categoryId!,
          name: (existing.categoryName ?? '').split(' > ').last,
          fullName: existing.categoryName ?? '',
        );
        _categoryQuery.text = _category!.fullName;
      }
    }
    _categoryQuery.addListener(_onCategoryTyped);
  }

  @override
  void dispose() {
    _categoryQuery
      ..removeListener(_onCategoryTyped)
      ..dispose();
    for (final c in [_title, _description, _price, _quantity, _sku, _tags]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Searches the store's taxonomy as the seller types. The last answer
  /// wins, so a slow early reply cannot overwrite a fast later one.
  Future<void> _onCategoryTyped() async {
    final query = _categoryQuery.text.trim();
    if (_category != null && query == _category!.fullName) return;
    final ticket = ++_categorySearch;
    if (query.length < 2) {
      if (_categoryHits.isNotEmpty) setState(() => _categoryHits = const []);
      return;
    }
    try {
      final hits = await ref
          .read(sellerRepositoryProvider)
          .searchCategories(query);
      if (!mounted || ticket != _categorySearch) return;
      setState(() => _categoryHits = hits);
    } on RepositoryException {
      // A failed suggestion is not an error worth a card; the field still
      // works without one.
    }
  }

  void _pickCategory(ProductCategory category) {
    setState(() {
      _category = category;
      _categoryHits = const [];
      _categoryQuery.text = category.fullName;
    });
  }

  Future<void> _pickPhotos() async {
    try {
      final picked = await ImagePicker().pickMultiImage(
        imageQuality: 85,
        maxWidth: 2000,
        limit: 8,
      );
      if (picked.isEmpty || !mounted) return;
      final loaded = <_PickedPhoto>[];
      for (final file in picked) {
        final bytes = await file.readAsBytes();
        final type = file.mimeType ?? _guessType(file.name);
        loaded.add(_PickedPhoto(bytes, type));
      }
      if (!mounted) return;
      setState(() {
        _photos.addAll(loaded);
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not open your photos: $error');
    }
  }

  static String _guessType(String name) =>
      name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';

  /// The checks that need no network, before anything is uploaded.
  String? _validate() {
    if (_title.text.trim().isEmpty) return 'Give it a title.';
    final cents = parseDollars(_price.text);
    if (cents == null) return 'Enter the price as dollars, like 12 or 12.50.';
    if (cents <= 0) return 'Set a price above \$0.';
    final quantity = int.tryParse(_quantity.text.trim());
    if (quantity == null || quantity < 0) {
      return 'Quantity must be a whole number, zero or more.';
    }
    if (_photos.isEmpty && _existingUrls.isEmpty) {
      return 'Add at least one photo.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final repo = ref.read(sellerRepositoryProvider);
    try {
      // 1. Photos first: nothing is left behind if this fails.
      setState(() => _stage = 'Uploading photos…');
      final urls = <String>[..._existingUrls];
      for (final photo in _photos) {
        urls.add(
          await repo.uploadListingPhoto(
            photo.bytes,
            contentType: photo.contentType,
          ),
        );
      }

      // 2. The draft, under the seller's own uid.
      setState(() => _stage = 'Saving the draft…');
      final draft = ListingDraft(
        title: _title.text,
        description: _description.text,
        priceCents: parseDollars(_price.text)!,
        quantity: int.parse(_quantity.text.trim()),
        sku: _sku.text,
        imageUrls: urls,
        collectionHandles: _collections.toList()..sort(),
        category: _category,
        tags: _tags.text
            .split(',')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList(),
      );
      _draftId = await repo.saveDraft(draft, id: _draftId);

      // 3. The function does the rest, by id.
      if (_editing) {
        await _update(repo);
      } else {
        await _publish(repo);
      }
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _error = describeError(error).body);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _stage = '';
        });
      }
    }
  }

  /// Sends the same id again. Safe: the function adopts what it already made.
  Future<void> _retry() async {
    final id = _draftId;
    if (id == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(sellerRepositoryProvider);
      if (_editing) {
        await _update(repo);
      } else {
        await _publish(repo);
      }
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _error = describeError(error).body);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _stage = '';
        });
      }
    }
  }

  Future<void> _update(SellerRepository repo) async {
    setState(() => _stage = 'Saving to the store…');
    await repo.updateListing(_draftId!);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Saved to the store.')));
    context.pop();
  }

  Future<void> _publish(SellerRepository repo) async {
    setState(() => _stage = 'Sending it to the store…');
    final result = await repo.publishListing(_draftId!);
    if (!mounted) return;
    await showUnderReviewDialog(
      context,
      title: _title.text.trim(),
      stockSet: result.stockSet,
    );
    if (!mounted) return;
    context.go('/you');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final collections = ref.watch(collectionsProvider);

    return LbmScreen(
      appBar: LbmAppBar(title: _editing ? 'Edit product' : 'Add a product'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            _editing
                ? 'Changes go straight to the product on the store. Photos '
                      'cannot be changed here yet.'
                : 'It goes to Little Blue Market for approval first, then '
                      'appears in your shop. Photos, a title and a price are '
                      'all it needs.',
            style: LbmText.tiny.copyWith(color: c.ink2),
          ),
          const SizedBox(height: 14),
          const SectionHead('Photos'),
          if (_editing)
            _ExistingPhotos(urls: _existingUrls)
          else
            _PhotoRow(
              photos: _photos,
              onAdd: _busy ? null : _pickPhotos,
              onRemove: _busy
                  ? null
                  : (i) => setState(() => _photos.removeAt(i)),
            ),
          const SectionHead('The product'),
          LbmCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LbmField(
                  label: 'Title',
                  controller: _title,
                  hintText: 'What is it?',
                  readOnly: _busy,
                ),
                const SizedBox(height: 12),
                LbmField(
                  label: 'Description',
                  controller: _description,
                  maxLines: 4,
                  hintText: 'What it is made of, who it is for, how it ships',
                  readOnly: _busy,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: LbmField(
                        label: 'Price (USD)',
                        controller: _price,
                        hintText: '12.50',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        readOnly: _busy,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: LbmField(
                        label: 'Quantity',
                        controller: _quantity,
                        keyboardType: TextInputType.number,
                        readOnly: _busy,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LbmField(
                  label: 'SKU (optional)',
                  controller: _sku,
                  readOnly: _busy,
                ),
                const SizedBox(height: 12),
                LbmField(
                  label: 'Tags (optional, comma-separated)',
                  controller: _tags,
                  hintText: 'gift, handmade',
                  readOnly: _busy,
                ),
              ],
            ),
          ),
          const SectionHead('Category'),
          LbmCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "The store's product category, e.g. Sweatshirts or Lip "
                  'Balms. Start typing and pick one.',
                  style: LbmText.tiny.copyWith(color: c.ink2),
                ),
                const SizedBox(height: 10),
                LbmField(
                  label: 'Category (optional)',
                  controller: _categoryQuery,
                  hintText: 'sweatshirt',
                  readOnly: _busy,
                ),
                if (_category != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: LbmChip(_category!.name, style: ChipStyle.on),
                      ),
                      const SizedBox(width: 8),
                      PillButton(
                        'Clear',
                        small: true,
                        expand: false,
                        style: PillStyle.ghost,
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _category = null;
                                _categoryQuery.clear();
                              }),
                      ),
                    ],
                  ),
                ],
                if (_categoryHits.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  LbmCard(
                    color: c.skyWash,
                    child: RowStack(
                      children: [
                        for (final hit in _categoryHits)
                          ListRow(
                            title: Text(hit.name),
                            subtitle: Text(
                              hit.fullName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _pickCategory(hit),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SectionHead('Collections'),
          LbmCard(
            padding: const EdgeInsets.all(16),
            child: LbmAsync<List<Collection>>(
              collections,
              skeleton: const SizedBox(height: 32),
              errorBuilder: (_, _) => Text(
                'Collections could not be loaded; you can add them later.',
                style: LbmText.tiny.copyWith(color: c.ink3),
              ),
              isEmpty: (items) => items.isEmpty,
              empty: Text(
                'The store has no collections yet.',
                style: LbmText.tiny.copyWith(color: c.ink3),
              ),
              data: (items) => Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final item in items)
                    LbmChip(
                      item.title,
                      style: _collections.contains(item.handle)
                          ? ChipStyle.on
                          : ChipStyle.plain,
                      onTap: _busy
                          ? null
                          : () => setState(() {
                              if (!_collections.remove(item.handle)) {
                                _collections.add(item.handle);
                              }
                            }),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (_error != null) ...[
            LbmCard(
              color: c.skyWash,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _error!,
                    style: LbmText.tiny.copyWith(
                      fontWeight: FontWeight.w700,
                      color: c.clay,
                    ),
                  ),
                  if (_draftId != null) ...[
                    const SizedBox(height: 10),
                    PillButton(
                      'Try again',
                      small: true,
                      expand: false,
                      style: PillStyle.quiet,
                      onPressed: _busy ? null : _retry,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          PillButton(
            _busy ? _stage : (_editing ? 'Save changes' : 'Add to my shop'),
            onPressed: _busy ? null : _submit,
          ),
          const SizedBox(height: 8),
          Text(
            _editing
                ? 'Price and stock change on the store right away.'
                : 'Nothing is public until Little Blue Market approves it.',
            textAlign: TextAlign.center,
            style: LbmText.xtiny.copyWith(color: c.ink3),
          ),
        ],
      ),
    );
  }
}

/// The photos already on the store, read-only in edit mode.
class _ExistingPhotos extends StatelessWidget {
  const _ExistingPhotos({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        children: [
          for (final url in urls)
            Container(
              width: 88,
              margin: const EdgeInsets.only(right: 8),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: c.skyWash,
              ),
              child: url.startsWith('asset://')
                  ? Image.asset(url.substring(8), fit: BoxFit.cover)
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ColoredBox(color: c.skyWash),
                    ),
            ),
        ],
      ),
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.photos,
    required this.onAdd,
    required this.onRemove,
  });

  final List<_PickedPhoto> photos;
  final VoidCallback? onAdd;
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        children: [
          GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 88,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: c.skyWash,
                borderRadius: BorderRadius.circular(14),
              ),
              // Scaled down rather than overflowing at 2.0 text: the tile is
              // a fixed square and the label is decoration.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_a_photo_outlined, color: c.accentDeep),
                    const SizedBox(height: 4),
                    Text(
                      photos.isEmpty ? 'Add photos' : 'Add more',
                      style: LbmText.xtiny.copyWith(
                        color: c.accentText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          for (var i = 0; i < photos.length; i++)
            Stack(
              children: [
                Container(
                  width: 88,
                  margin: const EdgeInsets.only(right: 8),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: c.skyWash,
                  ),
                  child: Image.memory(photos[i].bytes, fit: BoxFit.cover),
                ),
                if (onRemove != null)
                  Positioned(
                    top: 4,
                    right: 12,
                    child: GestureDetector(
                      onTap: () => onRemove!(i),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: c.surface,
                          shape: BoxShape.circle,
                          boxShadow: c.shadowSoft,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The modal behind "Add": the product is not in the shop yet, and this is
/// where the seller learns that on purpose.
Future<void> showUnderReviewDialog(
  BuildContext context, {
  required String title,
  bool stockSet = true,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final c = dialogContext.c;
      return AlertDialog(
        backgroundColor: c.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(22)),
        ),
        title: Text(
          'Under review',
          style: LbmText.display.copyWith(fontSize: 21, color: c.ink),
        ),
        content: Text(
          '"$title" has been sent to Little Blue Market for approval. '
          "You'll see it in your shop as soon as it's approved, usually "
          "within a day or two. We'll let you know."
          '${stockSet ? '' : '\n\nStock could not be set yet; the store will '
                    'ask for it on approval.'}',
          style: LbmText.body.copyWith(color: c.ink2, fontSize: 14),
        ),
        actions: [
          PillButton(
            'Got it',
            small: true,
            expand: false,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      );
    },
  );
}
