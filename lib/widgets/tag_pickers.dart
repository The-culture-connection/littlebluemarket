import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/repositories.dart';
import '../models/models.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'async.dart';
import 'primitives.dart';
import 'product_art.dart';
import 'sheets.dart';

/// Tagging a product or a person in the forums (Grace, 2026-10-21: "add
/// ability to tag products or other profiles in forums").
///
/// Two small search sheets rather than typing alone: an @handle works if you
/// know it, but nobody knows the exact title of the mug they want to
/// spotlight, and most people do not know the handle of the shop they mean
/// either. Each sheet hands back what was picked, or null.

/// Search the market and pick one product.
Future<Product?> showProductPicker(BuildContext context) =>
    showLbmSheet<Product>(context, (_) => const _ProductPicker());

/// Search the people on the app and pick one.
Future<Person?> showPersonPicker(BuildContext context) =>
    showLbmSheet<Person>(context, (_) => const _PersonPicker());

/// The two buttons under a forum field: Tag a product, Tag someone.
///
/// A person is written into the text as their @handle, which is how every
/// other mention in the app is stored and linked; a product is kept beside
/// the text and drawn as a card.
class TagButtons extends StatelessWidget {
  const TagButtons({
    super.key,
    required this.onProduct,
    required this.onPerson,
    this.productsFull = false,
  });

  final ValueChanged<Product> onProduct;
  final ValueChanged<Person> onPerson;

  /// At [kMaxTaggedProducts]: the product button stops offering more.
  final bool productsFull;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        LbmChip(
          'Tag a product',
          trailingIcon: Icons.sell_outlined,
          style: ChipStyle.quiet,
          onTap: productsFull
              ? null
              : () async {
                  final product = await showProductPicker(context);
                  if (product != null) onProduct(product);
                },
        ),
        LbmChip(
          'Tag someone',
          trailingIcon: Icons.alternate_email_rounded,
          style: ChipStyle.quiet,
          onTap: () async {
            final person = await showPersonPicker(context);
            if (person != null) onPerson(person);
          },
        ),
      ],
    );
  }
}

/// The products picked so far, each with a way to take it back off.
class TaggedProductChips extends ConsumerWidget {
  const TaggedProductChips({
    super.key,
    required this.productIds,
    required this.onRemove,
  });

  final List<String> productIds;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (productIds.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final id in productIds)
          LbmChip(
            ref.watch(productProvider(id)).value?.title ?? 'Product',
            trailingIcon: Icons.close_rounded,
            style: ChipStyle.on,
            onTap: () => onRemove(id),
          ),
      ],
    );
  }
}

/// Puts `@handle ` into [controller] at the cursor, with a space before it
/// when the text there does not already end in one.
void insertMention(TextEditingController controller, Person person) {
  final handle = person.handle.startsWith('@')
      ? person.handle
      : '@${person.handle}';
  final text = controller.text;
  final selection = controller.selection;
  final at = selection.isValid ? selection.start : text.length;
  final before = text.substring(0, at);
  final after = text.substring(selection.isValid ? selection.end : at);
  final lead = before.isEmpty || before.endsWith(' ') ? '' : ' ';
  final insert = '$lead$handle ';
  controller.value = TextEditingValue(
    text: '$before$insert$after',
    selection: TextSelection.collapsed(offset: before.length + insert.length),
  );
}

/// The search-as-you-type part both sheets share.
mixin _Debounced<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  final query = TextEditingController();
  Timer? _debounce;
  String _asked = '';

  void search(String text);

  @override
  void initState() {
    super.initState();
    query.addListener(() {
      final text = query.text.trim();
      if (text == _asked) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), () {
        _asked = text;
        if (mounted) search(text);
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    query.dispose();
    super.dispose();
  }
}

class _ProductPicker extends ConsumerStatefulWidget {
  const _ProductPicker();

  @override
  ConsumerState<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends ConsumerState<_ProductPicker>
    with _Debounced {
  AsyncValue<List<Product>> _found = const AsyncData([]);

  @override
  Future<void> search(String text) async {
    if (text.isEmpty) {
      setState(() => _found = const AsyncData([]));
      return;
    }
    setState(() => _found = const AsyncLoading());
    try {
      final results = await ref
          .read(searchRepositoryProvider)
          .search(SearchFilters(query: text));
      if (!mounted || query.text.trim() != text) return;
      setState(() => _found = AsyncData(results.products.take(12).toList()));
    } on RepositoryException catch (error, stack) {
      if (mounted) setState(() => _found = AsyncError(error, stack));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LbmSheet(
      children: [
        Text(
          'Tag a product',
          style: LbmText.display.copyWith(fontSize: 21, color: c.ink),
        ),
        const SizedBox(height: 12),
        LbmField(
          controller: query,
          hintText: 'Search the market',
          autofocus: true,
          pill: true,
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.45,
          ),
          child: LbmAsync<List<Product>>(
            _found,
            skeleton: const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            isEmpty: (items) => items.isEmpty,
            empty: LbmEmpty(
              title: query.text.trim().isEmpty
                  ? 'Type what you are looking for'
                  : 'Nothing by that name',
              compact: true,
            ),
            data: (items) => ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final product in items)
                  ListRow(
                    leading: ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(9)),
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: ProductArt(product, square: true),
                      ),
                    ),
                    title: Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(product.price),
                    onTap: () => Navigator.of(context).pop(product),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PersonPicker extends ConsumerStatefulWidget {
  const _PersonPicker();

  @override
  ConsumerState<_PersonPicker> createState() => _PersonPickerState();
}

class _PersonPickerState extends ConsumerState<_PersonPicker> with _Debounced {
  AsyncValue<List<Person>> _found = const AsyncData([]);

  @override
  Future<void> search(String text) async {
    final words = text.startsWith('@') ? text.substring(1) : text;
    if (words.isEmpty) {
      setState(() => _found = const AsyncData([]));
      return;
    }
    setState(() => _found = const AsyncLoading());
    try {
      final people = await ref
          .read(profileRepositoryProvider)
          .searchPeople(words, limit: 10);
      if (!mounted || query.text.trim() != text) return;
      setState(() => _found = AsyncData(people));
    } on RepositoryException catch (error, stack) {
      if (mounted) setState(() => _found = AsyncError(error, stack));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LbmSheet(
      children: [
        Text(
          'Tag someone',
          style: LbmText.display.copyWith(fontSize: 21, color: c.ink),
        ),
        const SizedBox(height: 12),
        LbmField(
          controller: query,
          hintText: 'Search by name or @handle',
          autofocus: true,
          pill: true,
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.45,
          ),
          child: LbmAsync<List<Person>>(
            _found,
            skeleton: const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            isEmpty: (items) => items.isEmpty,
            empty: LbmEmpty(
              title: query.text.trim().isEmpty
                  ? 'Type a name or a shop'
                  : 'Nobody by that name',
              compact: true,
            ),
            data: (items) => ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final person in items)
                  ListRow(
                    leading: Avatar(person, size: AvatarSize.sm),
                    title: Text(person.name),
                    subtitle: Text(person.handle),
                    onTap: () => Navigator.of(context).pop(person),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
