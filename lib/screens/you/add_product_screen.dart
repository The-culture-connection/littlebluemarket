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
  const AddProductScreen({super.key});

  @override
  ConsumerState<AddProductScreen> createState() => _AddProductScreenState();
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
  final _collections = <String>{};

  bool _busy = false;
  String _stage = '';
  String? _error;

  /// Set once a draft exists, so a retry re-sends the same id rather than
  /// making a second product.
  String? _draftId;

  @override
  void dispose() {
    for (final c in [_title, _description, _price, _quantity, _sku, _tags]) {
      c.dispose();
    }
    super.dispose();
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
    if (_photos.isEmpty) return 'Add at least one photo.';
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
      final urls = <String>[];
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
        tags: _tags.text
            .split(',')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList(),
      );
      _draftId = await repo.saveDraft(draft, id: _draftId);

      // 3. The function does the rest, by id.
      await _publish(repo);
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
      await _publish(ref.read(sellerRepositoryProvider));
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
      appBar: const LbmAppBar(title: 'Add a product'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            'It goes to Little Blue Market for approval first, then appears in '
            'your shop. Photos, a title and a price are all it needs.',
            style: LbmText.tiny.copyWith(color: c.ink2),
          ),
          const SizedBox(height: 14),
          const SectionHead('Photos'),
          _PhotoRow(
            photos: _photos,
            onAdd: _busy ? null : _pickPhotos,
            onRemove: _busy ? null : (i) => setState(() => _photos.removeAt(i)),
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
            _busy ? _stage : 'Add to my shop',
            onPressed: _busy ? null : _submit,
          ),
          const SizedBox(height: 8),
          Text(
            'Nothing is public until Little Blue Market approves it.',
            textAlign: TextAlign.center,
            style: LbmText.xtiny.copyWith(color: c.ink3),
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
