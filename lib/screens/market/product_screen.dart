import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/fixtures.dart';
import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/primitives.dart';
import '../../widgets/product_art.dart';
import '../../widgets/screen.dart';
import '../../widgets/sheets.dart';

/// The full record behind a post: options and stock, the spec table, the
/// rating breakdown, shipping and pickup, returns, and the seller strip.
class ProductScreen extends ConsumerStatefulWidget {
  const ProductScreen({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final product = Fx.product(widget.productId);
    final seller = Fx.person(product.sellerId);
    final spec = Fx.spec(widget.productId);
    final isGuest = ref.watch(isGuestProvider);

    final selected =
        _selected ??
        0; // the first variant is the default until one is picked

    return LbmScreen(
      appBar: LbmAppBar(
        title: 'Product details',
        actions: [
          CircleIconButton(
            icon: Icons.send_outlined,
            tooltip: 'Share',
            onPressed: () {},
          ),
        ],
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          LbmCard(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: ProductArt(product, borderRadius: LbmRadius.imageR),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          LbmChip(
                            product.type,
                            style: ChipStyle.quiet,
                            fontSize: 11,
                          ),
                          LbmChip(
                            spec.subtitle,
                            style: ChipStyle.quiet,
                            fontSize: 11,
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Text(
                        product.title,
                        style: LbmText.display.copyWith(
                          fontSize: 23,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Stars(product.rating, size: 12),
                              const SizedBox(width: 7),
                              Text(
                                product.rating.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: c.ink,
                                ),
                              ),
                            ],
                          ),
                          InlineLink(
                            '${product.ratingCount} reviews',
                            fontSize: 11.5,
                            onTap: () => context.goToReviews(widget.productId),
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Text(
                        product.description,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.55,
                          color: c.ink2,
                        ),
                      ),
                      const SizedBox(height: 9),
                      TagChips(
                        product.tags,
                        onTap: (tag) => context.goToResults(tag),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SectionHead('Options'),
          LbmCard(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (var i = 0; i < spec.variants.length; i++)
                  _VariantRow(
                    variant: spec.variants[i],
                    selected: i == selected,
                    onTap: () => setState(() => _selected = i),
                  ),
              ],
            ),
          ),

          const SectionHead('Details'),
          LbmCard(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            child: RowStack(
              children: [
                for (final row in spec.rows) _SpecRowTile(row: row),
              ],
            ),
          ),

          const SectionHead('What buyers rated it'),
          _RatingBreakdown(product: product, rating: Fx.rating(widget.productId)),

          const SectionHead('Shipping & pickup'),
          LbmCard(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            child: RowStack(
              children: [
                for (final row in spec.shipping) _ShippingRowTile(row: row),
              ],
            ),
          ),

          const SectionHead('Returns & guarantee'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: c.skyMist,
                borderRadius: LbmRadius.cardR,
              ),
              child: Text(
                spec.returns,
                style: TextStyle(fontSize: 13.5, height: 1.55, color: c.ink),
              ),
            ),
          ),

          const SectionHead('Sold by'),
          LbmCard(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            child: ListRow(
              crossAxisAlignment: CrossAxisAlignment.start,
              leading: Avatar(seller),
              onTap: () => context.goToSeller(seller.id),
              title: Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                  children: [
                    TextSpan(text: '${seller.name} '),
                    TextSpan(
                      text: seller.handle,
                      style: TextStyle(color: c.skyDeep),
                    ),
                  ],
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      seller.bio,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: c.ink2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${product.locationLabel()} · ${seller.posts} posts',
                      style: LbmText.xtiny.copyWith(
                        color: c.ink2,
                        fontFeatures: kTabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: PillButton(
              'Ask a question',
              style: PillStyle.ghost,
              onPressed: () => requireProfile(
                context,
                ref,
                () => context.goToDm(seller.id),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 26),
            child: Row(
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        spec.lead,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: LbmText.xtiny.copyWith(color: c.ink2),
                      ),
                      Text(
                        product.price,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LbmText.display.copyWith(
                          fontSize: 22,
                          color: c.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PillButton(
                    isGuest ? 'Buy · sign up' : 'Buy',
                    onPressed: () => requireProfile(
                      context,
                      ref,
                      () => showBuySheet(context, product),
                    ),
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
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 11,
            ),
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
            child: Text(
              row.label,
              style: LbmText.tiny.copyWith(color: c.ink2),
            ),
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
