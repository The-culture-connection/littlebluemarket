import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/repositories.dart';
import '../models/models.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'async.dart';
import 'composers.dart';
import 'primitives.dart';
import 'sheets.dart';

/// Post the cart as it is right now.
///
/// A cart post is a snapshot: the items are copied into the post at this
/// moment and never change again, however the cart itself changes. At most
/// 24 items; the rules refuse more, so the composer says so first.
Future<void> showPostCartSheet(BuildContext context, WidgetRef ref, Cart cart) {
  return showLbmSheet(context, (_) => _CartComposer(cart: cart));
}

class _CartComposer extends ConsumerStatefulWidget {
  const _CartComposer({required this.cart});

  final Cart cart;

  @override
  ConsumerState<_CartComposer> createState() => _CartComposerState();
}

class _CartComposerState extends ConsumerState<_CartComposer> {
  final _caption = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  List<CartPostItem> get _items {
    final seen = <String>{};
    return [
      for (final line in widget.cart.lines)
        if (seen.add(line.productId))
          CartPostItem(
            productId: line.productId,
            title: line.title,
            imageUrl: line.imageUrl,
            sellerId: line.sellerId,
            priceCents: line.unitPriceCents,
          ),
    ].take(CartPost.maxItems).toList();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final mentioned = await resolveMentionUids(ref, _caption.text);
      await ref
          .read(socialRepositoryProvider)
          .createPost(
            NewPost.cart(
              items: _items,
              caption: _caption.text.trim().isEmpty
                  ? null
                  : _caption.text.trim(),
              tags: parseHashtags(_caption.text),
              mentionedUids: mentioned,
            ),
          );
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Cart posted')));
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
    final items = _items;
    final distinct = {for (final l in widget.cart.lines) l.productId}.length;
    final trimmed = distinct > CartPost.maxItems;

    return LbmSheet(
      children: [
        Text(
          'Post your cart',
          style: LbmText.display.copyWith(fontSize: 21, color: c.ink),
        ),
        const SizedBox(height: 6),
        Text(
          trimmed
              ? 'A cart post holds up to ${CartPost.maxItems} things; the first '
                    '${CartPost.maxItems} go in. It is a snapshot: your cart can '
                    'change afterwards and the post will not.'
              : '${items.length} ${items.length == 1 ? 'thing' : 'things'}, as '
                    'they are right now. It is a snapshot: your cart can change '
                    'afterwards and the post will not.',
          style: LbmText.tiny.copyWith(color: c.ink2),
        ),
        const SizedBox(height: 14),
        LbmField(
          label: 'Say something about it (optional)',
          controller: _caption,
          maxLines: 3,
          autofocus: true,
        ),
        const SizedBox(height: 14),
        PillButton(
          _saving ? 'Posting…' : 'Post it',
          onPressed: _saving || items.isEmpty ? null : _submit,
        ),
      ],
    );
  }
}
