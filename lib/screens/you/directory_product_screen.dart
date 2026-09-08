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
import '../../widgets/photo_source.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';

/// A directory business adds or edits a product it sells on its own website.
///
/// Shorter than the Market seller's form on purpose: no stock, no variants,
/// no category, because nothing here reaches Shopify. Photos, a name, an
/// optional price, a few words, and the address the Buy button opens, which
/// starts as the website on the directory listing.
class DirectoryProductScreen extends ConsumerStatefulWidget {
  const DirectoryProductScreen({super.key, this.productId});

  /// The document id (without the `dp_` prefix) when editing.
  final String? productId;

  @override
  ConsumerState<DirectoryProductScreen> createState() =>
      _DirectoryProductScreenState();
}

class _PickedPhoto {
  const _PickedPhoto(this.bytes, this.contentType);
  final Uint8List bytes;
  final String contentType;
}

class _DirectoryProductScreenState
    extends ConsumerState<DirectoryProductScreen> {
  final _title = TextEditingController();
  final _price = TextEditingController();
  final _description = TextEditingController();
  final _link = TextEditingController();
  final _photos = <_PickedPhoto>[];
  final _existingUrls = <String>[];
  bool _prefilled = false;
  bool _busy = false;
  String _stage = '';
  String? _error;

  bool get _editing => widget.productId != null;

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _description.dispose();
    _link.dispose();
    super.dispose();
  }

  void _prefill(Product product) {
    if (_prefilled) return;
    _prefilled = true;
    _title.text = product.title;
    _price.text = product.priceCents == 0
        ? ''
        : (product.priceCents / 100).toStringAsFixed(2);
    _description.text = product.description;
    _link.text = product.buyUrl ?? '';
    _existingUrls.addAll(product.imageUrls);
  }

  Future<void> _pickPhotos() async {
    final source = await choosePhotoSource(context);
    if (source == null || !mounted) return;
    try {
      final picker = ImagePicker();
      final picked = source == ImageSource.camera
          ? [
              ?await picker.pickImage(
                source: ImageSource.camera,
                imageQuality: 85,
                maxWidth: 2000,
              ),
            ]
          : await picker.pickMultiImage(
              imageQuality: 85,
              maxWidth: 2000,
              limit: NewDirectoryProduct.photosMax,
            );
      if (picked.isEmpty || !mounted) return;
      final loaded = <_PickedPhoto>[];
      for (final file in picked) {
        loaded.add(_PickedPhoto(await file.readAsBytes(), pickedContentType(file)));
      }
      if (!mounted) return;
      setState(() {
        _photos.addAll(loaded);
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not read that photo. Try another.');
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give the product a name.');
      return;
    }
    final priceText = _price.text.trim();
    final cents = priceText.isEmpty ? 0 : parseDollars(priceText);
    if (cents == null) {
      setState(() => _error = 'The price should look like 24 or 24.50.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _stage = 'Saving…';
    });
    try {
      final urls = [..._existingUrls];
      if (_photos.isNotEmpty) {
        setState(() => _stage = 'Uploading photos…');
        final seller = ref.read(sellerRepositoryProvider);
        for (final photo in _photos) {
          urls.add(
            await seller.uploadListingPhoto(
              photo.bytes,
              contentType: photo.contentType,
            ),
          );
        }
      }
      setState(() => _stage = 'Saving…');
      await ref
          .read(directoryRepositoryProvider)
          .saveProduct(
            NewDirectoryProduct(
              title: title,
              description: _description.text,
              priceCents: cents,
              imageUrls: urls.take(NewDirectoryProduct.photosMax).toList(),
              buyUrl: _link.text,
            ),
            id: widget.productId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _editing ? 'Saved.' : 'Added. It is in the feed and on your profile.',
          ),
        ),
      );
      context.pop();
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

  Future<void> _delete() async {
    final id = widget.productId;
    if (id == null || _busy) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this product?'),
        content: const Text('It leaves your profile and the feed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(directoryRepositoryProvider).deleteProduct(id);
      if (!mounted) return;
      context.pop();
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(error).body;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final id = widget.productId;

    // Edit mode: the product comes from the live list; prefilled once.
    if (id != null && !_prefilled) {
      final mine = ref.watch(myDirectoryProductsProvider).value;
      final match = mine
          ?.where((p) => p.id == '${Product.externalPrefix}$id')
          .firstOrNull;
      if (match != null) _prefill(match);
    }
    // New product: the link starts as the website on the listing.
    if (id == null && _link.text.isEmpty) {
      final listings = ref.watch(myDirectoryListingsProvider).value ?? const [];
      final site = listings.map((l) => l.website).firstWhere(
        (w) => w.isNotEmpty,
        orElse: () => '',
      );
      if (site.isNotEmpty) _link.text = site;
    }

    return LbmScreen(
      appBar: LbmAppBar(title: _editing ? 'Edit product' : 'Add a product'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        children: [
          LbmCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Sold on your website',
                  style: LbmText.display.copyWith(fontSize: 18, color: c.ink),
                ),
                const SizedBox(height: 6),
                Text(
                  'It shows on your profile and in the feed. The Buy button '
                  'opens the address below, so people finish on your site.',
                  style: LbmText.tiny.copyWith(color: c.ink2, height: 1.5),
                ),
                const SizedBox(height: 14),
                _PhotoRow(
                  existing: _existingUrls,
                  picked: _photos,
                  onAdd: _busy ? null : _pickPhotos,
                  onRemoveExisting: (i) =>
                      setState(() => _existingUrls.removeAt(i)),
                  onRemovePicked: (i) => setState(() => _photos.removeAt(i)),
                ),
                const SizedBox(height: 12),
                LbmField(
                  label: 'Name',
                  controller: _title,
                  hintText: 'What is it?',
                ),
                const SizedBox(height: 12),
                LbmField(
                  label: 'Price (optional)',
                  controller: _price,
                  hintText: 'Leave empty to say "See website"',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 12),
                LbmField(
                  label: 'A few words',
                  controller: _description,
                  hintText: 'What it is, who it is for.',
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                LbmField(
                  label: 'Where people buy it',
                  controller: _link,
                  hintText: 'https://yourwebsite.com/product',
                  keyboardType: TextInputType.url,
                  helper: 'Starts as the website on your directory listing.',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: LbmText.tiny.copyWith(
                      fontWeight: FontWeight.w700,
                      color: c.clay,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                PillButton(
                  _busy ? _stage : (_editing ? 'Save changes' : 'Add to my profile'),
                  onPressed: _busy ? null : _save,
                ),
                if (_editing) ...[
                  const SizedBox(height: 8),
                  PillButton(
                    'Remove this product',
                    style: PillStyle.quiet,
                    onPressed: _busy ? null : _delete,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.existing,
    required this.picked,
    required this.onAdd,
    required this.onRemoveExisting,
    required this.onRemovePicked,
  });

  final List<String> existing;
  final List<_PickedPhoto> picked;
  final VoidCallback? onAdd;
  final ValueChanged<int> onRemoveExisting;
  final ValueChanged<int> onRemovePicked;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget tile(Widget image, VoidCallback onRemove) => Stack(
      children: [
        ClipRRect(
          borderRadius: LbmRadius.imageR,
          child: SizedBox(width: 84, height: 84, child: image),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: CircleIconButton(
            icon: Icons.close_rounded,
            iconSize: 14,
            tooltip: 'Remove',
            onPressed: onRemove,
          ),
        ),
      ],
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < existing.length; i++)
          tile(
            Image.network(
              existing[i],
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => ColoredBox(color: c.skyWash),
            ),
            () => onRemoveExisting(i),
          ),
        for (var i = 0; i < picked.length; i++)
          tile(
            Image.memory(picked[i].bytes, fit: BoxFit.cover),
            () => onRemovePicked(i),
          ),
        if (existing.length + picked.length < NewDirectoryProduct.photosMax)
          InkWell(
            onTap: onAdd,
            borderRadius: LbmRadius.imageR,
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: c.skyMist,
                borderRadius: LbmRadius.imageR,
              ),
              child: Icon(Icons.add_a_photo_outlined, color: c.ink3),
            ),
          ),
      ],
    );
  }
}
