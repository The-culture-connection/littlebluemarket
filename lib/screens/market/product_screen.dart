import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repositories.dart' show RepositoryException;
import '../../models/feed_item.dart';
import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/composers.dart';
import '../../widgets/detail_sheet.dart';
import '../../widgets/lbm_toast.dart';
import '../../widgets/masonry.dart';
import '../../widgets/pins/product_pin.dart';
import '../../widgets/post_card.dart';
import '../../widgets/primitives.dart';
import '../../widgets/product_art.dart';
import '../../widgets/sheets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/tips.dart' show showCartTipOnce;

/// One listing: the photographs, then everything about it.
///
/// The picture runs edge to edge and the sheet is pulled up over its bottom,
/// so the page reads as a thing sitting on the photograph rather than a
/// photograph sitting in a card in a page. There is no app bar over it; Back,
/// share and the cart float on the picture instead.
class ProductScreen extends ConsumerWidget {
  const ProductScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(productDetailProvider(productId));

    return ColoredBox(
      color: context.c.paper,
      child: LbmAsync<ProductDetail>(
        detail,
        skeleton: const SafeArea(child: ProductDetailSkeleton()),
        onRetry: () => ref.invalidate(productDetailProvider(productId)),
        data: (detail) => _Body(productId: productId, detail: detail),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.productId, required this.detail});

  final String productId;
  final ProductDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final product = detail.product;
    final seller = detail.seller;
    final spec = detail.spec;
    // Live, so a review posted a moment ago counts here too. The bundled
    // rating is the fallback until the stream's first value.
    final liveRating =
        ref.watch(ratingProvider(productId)).value ?? detail.rating;
    final isGuest = ref.watch(isGuestProvider);
    final selected = ref
        .watch(selectedVariantProvider(productId))
        .clamp(0, spec.variants.isEmpty ? 0 : spec.variants.length - 1);
    // Carried into both the cart and the buy sheet. The prototype kept the
    // selection in the screen's own state, so the sheet never saw it and
    // charged the product's price rather than the variant's.
    final variant = spec.variants.isEmpty ? null : spec.variants[selected];

    // One variant called "Default Title" is Shopify's way of saying there are
    // no options; a tester saw the raw name and asked why.
    final hasOptions = !(spec.variants.length == 1 &&
        spec.variants.first.isPlaceholder);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        DetailGallery(
          child: ProductGallery(
            product: product,
            // Edge to edge, no corners: the sheet below covers its bottom.
            natural: true,
            onTapPhoto: (i) => showPhotoViewer(context, product, index: i),
          ),
        ),
        DetailBody(
          children: [
            DetailSheet(
              children: [
                if (seller != null) _MakerRow(seller: seller, product: product),
                if (seller != null) const SizedBox(height: 14),
                Text(
                  product.title,
                  style: LbmText.display.copyWith(fontSize: 24, color: c.ink),
                ),
                const SizedBox(height: 10),
                _PriceLine(
                  product: product,
                  variant: variant,
                  rating: liveRating,
                  onReviews: () => context.goToReviews(productId),
                ),
                if (hasOptions) ...[
                  const SizedBox(height: 12),
                  _VariantChips(
                    variants: spec.variants,
                    selected: selected,
                    onSelect: (i) => ref
                        .read(selectedVariantsProvider.notifier)
                        .select(productId, i),
                  ),
                ],
                if (product.saveCount > 0) ...[
                  const SizedBox(height: 12),
                  _ProofLine(count: product.saveCount),
                ],
                const SizedBox(height: 14),
                _BuyRow(
                  product: product,
                  productId: productId,
                  spec: spec,
                  variant: variant,
                  isGuest: isGuest,
                ),
                const SizedBox(height: 16),
                _FactsRow(spec: spec),
                const SizedBox(height: 16),
                Text(
                  product.description,
                  style: TextStyle(fontSize: 14, height: 1.55, color: c.ink2),
                ),
                const SizedBox(height: 12),
                TagChips(product.tags, onTap: (tag) => context.goToTag(tag)),
              ],
            ),

            if (hasOptions) ...[
              DetailSection(
                title: 'Options',
                child: LbmCard(
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      for (var i = 0; i < spec.variants.length; i++)
                        _VariantRow(
                          variant: spec.variants[i],
                          selected: i == selected,
                          onTap: () => ref
                              .read(selectedVariantsProvider.notifier)
                              .select(productId, i),
                        ),
                    ],
                  ),
                ),
              ),
            ],

            DetailSection(
              title: 'Details',
              child: LbmCard(
                margin: const EdgeInsets.symmetric(horizontal: 14),
                child: RowStack(
                  children: [
                    for (final row in spec.rows) _SpecRowTile(row: row),
                  ],
                ),
              ),
            ),

            DetailSection(
              title: 'Reviews',
              action: _WriteReviewLink(productId: productId),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RatingBreakdown(product: product, rating: liveRating),
                  _LatestReviews(productId: productId),
                ],
              ),
            ),

            DetailSection(
              title: 'Shipping & pickup',
              child: LbmCard(
                margin: const EdgeInsets.symmetric(horizontal: 14),
                child: RowStack(
                  children: [
                    for (final row in spec.shipping) _ShippingRowTile(row: row),
                  ],
                ),
              ),
            ),

            DetailSection(
              title: 'Returns & guarantee',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: c.skyMist,
                    borderRadius: LbmRadius.cardR,
                  ),
                  child: Text(
                    spec.returns,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.55,
                      color: c.ink,
                    ),
                  ),
                ),
              ),
            ),

            if (seller == null)
              DetailSection(
                title: 'Sold by',
                // Every vendor in the catalogue has a shop profile now, so
                // this is the rare case of a product whose vendor string went
                // missing altogether rather than the ordinary "not signed up".
                child: LbmCard(
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Text(
                    'We do not have a shop on record for this listing. You '
                    'can still buy it.',
                    style: TextStyle(fontSize: 13, height: 1.5, color: c.ink2),
                  ),
                ),
              )
            else
              _AlsoSoldBy(seller: seller, exceptId: productId),

            const SizedBox(height: 40),
          ],
        ),
      ],
    );
  }
}

/// Who makes it, and the one-tap way to ask them something.
class _MakerRow extends ConsumerWidget {
  const _MakerRow({required this.seller, required this.product});

  final Person seller;
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;

    return Row(
      children: [
        Avatar(seller, onTap: () => context.goToSeller(seller.id)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                seller.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LbmText.pinTitle.copyWith(fontSize: 14, color: c.ink),
              ),
              Text(
                // STATIC COPY — there is no reply-time data anywhere in this
                // system. The place is real; the hour is a drawing from the
                // mockup and must not be read as a measurement.
                '${product.locationLabel()} · usually replies within a day',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LbmText.pinMeta.copyWith(color: c.ink2),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        LbmChip(
          'Ask',
          accent: true,
          fontSize: 12.5,
          onTap: () =>
              requireProfile(context, ref, () => context.goToDm(seller.id)),
        ),
      ],
    );
  }
}

/// The price, what it is rated, and the way to the reviews.
class _PriceLine extends StatelessWidget {
  const _PriceLine({
    required this.product,
    required this.variant,
    required this.rating,
    required this.onReviews,
  });

  final Product product;
  final Variant? variant;
  final RatingSummary rating;
  final VoidCallback onReviews;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // The selected variant's price, not the product's: choosing the large
    // one and being charged for the small one is the bug this prevents.
    final cents = variant?.priceCents ?? product.priceCents;

    return Wrap(
      spacing: 12,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          Fmt.money(cents),
          style: LbmText.display.copyWith(fontSize: 26, color: c.ink),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stars(rating.average, size: 13),
            const SizedBox(width: 7),
            InlineLink(
              '${rating.total} reviews',
              fontSize: 12,
              onTap: onReviews,
            ),
          ],
        ),
      ],
    );
  }
}

/// The options as chips, so the choice is visible without opening a list.
class _VariantChips extends StatelessWidget {
  const _VariantChips({
    required this.variants,
    required this.selected,
    required this.onSelect,
  });

  final List<Variant> variants;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (var i = 0; i < variants.length; i++)
          LbmChip(
            variants[i].name,
            style: i == selected ? ChipStyle.on : ChipStyle.quiet,
            fontSize: 12.5,
            onTap: () => onSelect(i),
          ),
      ],
    );
  }
}

/// How many carts it is in.
///
/// A count and nothing else. The mockup shows faces beside it, of "people
/// you have bought from", and there is no such list: a product does not
/// record who carted it, only how many did.
class _ProofLine extends StatelessWidget {
  const _ProofLine({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        Icon(Icons.shopping_cart_outlined, size: 15, color: c.ink2),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '$count ${count == 1 ? 'person has' : 'people have'} this in '
            'their cart',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: LbmText.pinMeta.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: c.ink2,
            ),
          ),
        ),
      ],
    );
  }
}

/// Shipping, pickup and returns at a glance, before the description.
class _FactsRow extends StatelessWidget {
  const _FactsRow({required this.spec});

  final ProductSpec spec;

  @override
  Widget build(BuildContext context) {
    /// The first line of a policy, which is the part that answers the
    /// question; the rest is further down the page.
    String firstLine(String text, String fallback) {
      final trimmed = text.trim();
      if (trimmed.isEmpty) return fallback;
      final stop = trimmed.indexOf(RegExp(r'[.\n]'));
      return stop <= 0 ? trimmed : trimmed.substring(0, stop);
    }

    final shipping = spec.shipping.isEmpty
        ? 'Ask the maker'
        : firstLine(spec.shipping.first.value, 'Ask the maker');

    // IntrinsicHeight so the three tiles are as tall as the wordiest one:
    // stretching in a Row means filling the cross axis, and inside a column
    // that has no height yet there is nothing to fill.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _FactTile(
              icon: Icons.local_shipping_outlined,
              label: 'Shipping',
              value: shipping,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: _FactTile(
              icon: Icons.storefront_outlined,
              label: 'Pickup',
              // No pickup field exists on a listing, so this asks rather than
              // claiming one way or the other.
              value: 'Ask the maker',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _FactTile(
              icon: Icons.assignment_return_outlined,
              label: 'Returns',
              value: firstLine(spec.returns, 'Ask the maker'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FactTile extends StatelessWidget {
  const _FactTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
      decoration: BoxDecoration(
        color: c.skyWash,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: c.skyDeep),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LbmText.pinMeta.copyWith(
              fontWeight: FontWeight.w900,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: LbmText.pinMeta.copyWith(fontSize: 11, color: c.ink2),
          ),
        ],
      ),
    );
  }
}

/// "Write one", beside the reviews heading.
///
/// Only somebody who bought it can review it, and the copy says which it is
/// rather than opening a composer that refuses.
class _WriteReviewLink extends ConsumerWidget {
  const _WriteReviewLink({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchases = ref.watch(purchasesProvider).value ?? const <Purchase>[];
    Purchase? mine;
    for (final purchase in purchases) {
      if (purchase.productId == productId && purchase.canReview) {
        mine = purchase;
        break;
      }
    }

    if (mine == null) return const SizedBox.shrink();
    final purchase = mine;

    return InlineLink(
      'Write one',
      fontSize: 12.5,
      onTap: () => requireProfile(
        context,
        ref,
        () => showLbmSheet(
          context,
          (_) => ReviewComposer(initialPurchaseId: purchase.id),
        ),
      ),
    );
  }
}

/// The rest of this maker's shelf.
///
/// The cross-sell Grace asked for, and deliberately not "also in carts with
/// this": nothing records which products share a cart, so that section would
/// have been made up.
class _AlsoSoldBy extends ConsumerWidget {
  const _AlsoSoldBy({required this.seller, required this.exceptId});

  final Person seller;
  final String exceptId;

  /// Enough to be worth scrolling, not so many it becomes a second feed.
  static const _cap = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(sellerProductsProvider(seller.id)).value;
    if (products == null) return const SizedBox.shrink();

    final others = [
      for (final product in products)
        if (product.id != exceptId && !product.isGone) product,
    ].take(_cap).toList();

    if (others.isEmpty) return const SizedBox.shrink();

    return DetailSection(
      title: 'Also sold by ${seller.name}',
      action: InlineLink(
        'Their shop',
        fontSize: 12.5,
        onTap: () => context.goToSeller(seller.id),
      ),
      child: LbmMasonry.fixed(
        children: [
          for (final product in others)
            ProductPin(
              key: ValueKey('also_${product.id}'),
              item: ProductItem(
                ListingPost(
                  id: 'also_${product.id}',
                  authorId: product.sellerId,
                  createdAt: DateTime.now(),
                  tags: product.tags,
                  likeCount: 0,
                  commentCount: 0,
                  likedByMe: false,
                  product: product,
                ),
                proof: product.saveCount >= ProductItem.proofThreshold,
              ),
            ),
        ],
      ),
    );
  }
}

/// The price and the two ways to act on it.
///
/// One widget rather than a row built inline, because it now has to read the
/// same at the top of the page as it did at the bottom.
class _BuyRow extends ConsumerWidget {
  const _BuyRow({
    required this.product,
    required this.productId,
    required this.spec,
    required this.variant,
    required this.isGuest,
  });

  final Product product;
  final String productId;
  final ProductSpec spec;
  final Variant? variant;
  final bool isGuest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;

    // A directory business sells on its own website: no cart, and Buy opens
    // the site. Anyone may tap it, signed in or not.
    if (product.isExternal) {
      return PillButton(
        'Buy on their website',
        icon: Icons.open_in_new_rounded,
        onPressed: () => openBuyUrl(context, ref, product),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (spec.lead.isNotEmpty) ...[
          Text(
            spec.lead,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: LbmText.xtiny.copyWith(color: c.ink2),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            // The big one, and the only orchid thing on the page.
            Expanded(
              flex: 3,
              child: _AddToCartButton(
                productId: productId,
                variant: variant,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              flex: 2,
              child: PillButton(
                isGuest ? 'Buy · sign up' : 'Buy now',
                style: PillStyle.quiet,
                onPressed: () => requireProfile(
                  context,
                  ref,
                  () => showBuySheet(context, product, variant: variant),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Add to cart, full width, with the same bounce the pin's pill has.
///
/// A [CartPill] in everything but shape: same provider, same toast, same
/// second tap taking the line back out. The detail page needs a button
/// rather than a pill, and the two must not drift apart in behaviour.
class _AddToCartButton extends ConsumerStatefulWidget {
  const _AddToCartButton({required this.productId, required this.variant});

  final String productId;
  final Variant? variant;

  @override
  ConsumerState<_AddToCartButton> createState() => _AddToCartButtonState();
}

class _AddToCartButtonState extends ConsumerState<_AddToCartButton>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  late final Animation<double> _bounce = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.06,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.06,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.elasticOut)),
      weight: 65,
    ),
  ]).animate(_controller);

  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _tap(CartLine? line) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (line != null) {
        await ref.read(commerceRepositoryProvider).removeLine(line.id);
        return;
      }
      await showCartTipOnce(context, ref);
      if (!mounted) return;
      await addToCart(
        context,
        ref,
        widget.productId,
        variantId: widget.variant?.name,
        announce: false,
      );
      if (!mounted) return;
      _controller.forward(from: 0);
      final product = ref.read(productProvider(widget.productId)).value;
      LbmToast.show(
        context,
        title: 'In your little blue cart',
        subtitle: product?.title,
        thumbnailUrl: product?.imageUrls.firstOrNull,
        action: ('View', context.goToCart),
      );
    } on RepositoryException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(describeError(error).body)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider).value;
    final line = cart?.lines.cast<CartLine?>().firstWhere(
      (l) => l?.productId == widget.productId,
      orElse: () => null,
    );

    return ScaleTransition(
      scale: _bounce,
      child: PillButton(
        line == null ? 'Add to cart' : 'In your cart',
        icon: line == null ? null : Icons.check_rounded,
        onPressed: _busy
            ? null
            : () => requireProfile(context, ref, () => _tap(line)),
      ),
    );
  }
}

class _VariantRow extends StatelessWidget {
  const _VariantRow({
    required this.variant,
    required this.selected,
    required this.onTap,
  });

  final Variant variant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Container(
            color: selected ? c.skyWash : null,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? c.skyDeep : c.skyMist,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: c.skyDeep,
                            shape: BoxShape.circle,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        variant.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                      Text(
                        variant.stockLabel,
                        style: LbmText.xtiny.copyWith(color: c.ink2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  variant.price,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                    fontFeatures: kTabularFigures,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SpecRowTile extends StatelessWidget {
  const _SpecRowTile({required this.row});

  final SpecRow row;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                row.label,
                style: LbmText.xtiny.copyWith(
                  fontWeight: FontWeight.w800,
                  color: c.ink3,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              row.value,
              style: TextStyle(fontSize: 13.5, height: 1.5, color: c.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShippingRowTile extends StatelessWidget {
  const _ShippingRowTile({required this.row});

  final SpecRow row;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(row.label, style: LbmText.tiny.copyWith(color: c.ink2)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              row.value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: c.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingBreakdown extends StatelessWidget {
  const _RatingBreakdown({required this.product, required this.rating});

  final Product product;
  final RatingSummary rating;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final total = rating.total;

    return LbmCard(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                product.rating.toStringAsFixed(1),
                style: LbmText.display.copyWith(
                  fontSize: 34,
                  height: 1,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 2),
              Stars(product.rating, size: 10),
              const SizedBox(height: 2),
              Text(
                total == 0 ? 'No ratings yet' : '$total rated',
                style: LbmText.xtiny.copyWith(
                  color: c.ink2,
                  fontFeatures: kTabularFigures,
                ),
              ),
            ],
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              children: [
                for (final bar in rating.bars)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 9,
                          child: Text(
                            '${bar.stars}',
                            style: LbmText.xtiny.copyWith(
                              color: c.ink2,
                              fontFeatures: kTabularFigures,
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: LbmRadius.pillR,
                            child: LinearProgressIndicator(
                              value: total == 0 ? 0 : bar.count / total,
                              minHeight: 8,
                              backgroundColor: c.skyWash,
                              valueColor: AlwaysStoppedAnimation(c.accent),
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        SizedBox(
                          width: 16,
                          child: Text(
                            '${bar.count}',
                            textAlign: TextAlign.right,
                            style: LbmText.xtiny.copyWith(
                              color: c.ink2,
                              fontFeatures: kTabularFigures,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The two most recent reviews, live, with the way to all of them.
///
/// A review posted from the profile lands under the product within seconds;
/// without this the page showed a count and nothing to read.
class _LatestReviews extends ConsumerWidget {
  const _LatestReviews({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(reviewsProvider(productId));
    return LbmAsync<List<Review>>(
      reviews,
      skeleton: const SizedBox.shrink(),
      errorBuilder: (_, _) => const SizedBox.shrink(),
      isEmpty: (all) => all.isEmpty,
      empty: const SizedBox.shrink(),
      data: (all) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: LbmCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RowStack(
                children: [for (final review in all.take(2)) ReviewRow(review)],
              ),
              if (all.length > 2)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                  child: InlineLink(
                    'See all ${all.length} reviews',
                    onTap: () => context.goToReviews(productId),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
