import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../router/nav.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/cart_pill.dart';
import '../../widgets/primitives.dart';
import '../../widgets/product_art.dart';
import '../../widgets/skeleton.dart';
import 'collection_screen.dart' show ShelfHeading, SlideRow;

/// The rows the Market screen is built from (Grace, 2026-11-16: "make the
/// market look more appealing to shop... make the screen look more dynamic
/// in general"). Each one is a heading and a row that slides, and each one
/// hides itself, heading and all, when it has nothing to show, so a quiet
/// day on the store costs a shorter screen rather than empty boxes.

/// A sliding row of products, each with its cart button on the photograph,
/// so a shopper can fill a cart from here without opening anything.
class ProductShelf extends StatelessWidget {
  const ProductShelf({
    super.key,
    required this.title,
    required this.products,
    this.subtitle,
    this.onSeeAll,
  });

  final String title;
  final String? subtitle;
  final AsyncValue<List<Product>> products;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final items = products.value?.where(isShoppable).toList();
    if (items == null) {
      if (products.hasError) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShelfHeading(title, subtitle: subtitle),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: ChipRailSkeleton(),
          ),
        ],
      );
    }
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShelfHeading(title, subtitle: subtitle, onSeeAll: onSeeAll),
        SlideRow(
          children: [
            for (final product in items) ShelfProductCard(product: product),
          ],
        ),
      ],
    );
  }
}

/// One product on a sliding row: the photograph, square, with the cart on
/// it, then the name and the price.
class ShelfProductCard extends StatelessWidget {
  const ShelfProductCard({super.key, required this.product});

  static const width = 144.0;

  final Product product;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox(
      width: width,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.goToProduct(product.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: width,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Radius.circular(16)),
                  boxShadow: c.shadowSoft,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ProductArt(
                      product,
                      square: true,
                      cacheWidth: 400,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(16),
                      ),
                    ),
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: CartPill(productId: product.id),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              product.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: LbmText.pinTitle.copyWith(
                fontSize: 12.5,
                height: 1.25,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              product.price,
              maxLines: 1,
              style: LbmText.pinMeta.copyWith(
                fontWeight: FontWeight.w800,
                color: c.ink2,
                fontFeatures: kTabularFigures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Shop by values": the ownership collections as a row of chips, always
/// there (Grace, 2026-11-16: "those are probably good to have on there all
/// the time"). Only the ones the store has, so a renamed collection costs a
/// chip rather than a dead end.
class OwnershipRail extends ConsumerWidget {
  const OwnershipRail({super.key, this.showHeading = true});

  final bool showHeading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final all = ref.watch(collectionsProvider).value;
    final known = all == null ? null : {for (final x in all) x.handle};
    final shown = [
      for (final (handle, label) in kOwnershipCollections)
        // While the list loads, every chip: they are the same six every
        // time, and holding them back made the row jump in late.
        if (known == null || known.contains(handle)) (handle, label),
    ];
    if (shown.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading)
          const ShelfHeading(
            'Shop by values',
            subtitle: 'Find shops by who runs them.',
          ),
        SlideRow(
          gap: 8,
          children: [
            for (final (i, (handle, label)) in shown.indexed)
              _ValueChip(
                label: label,
                icon: _icons[i % _icons.length],
                tint: i.isEven ? c.accentMist : c.skyMist,
                onTap: () => context.goToCollection(handle),
              ),
          ],
        ),
      ],
    );
  }

  static const _icons = [
    Icons.favorite_rounded,
    Icons.diversity_3_rounded,
    Icons.auto_awesome_rounded,
    Icons.military_tech_rounded,
    Icons.accessible_forward_rounded,
    Icons.handshake_rounded,
  ];
}

class _ValueChip extends StatelessWidget {
  const _ValueChip({
    required this.label,
    required this.icon,
    required this.tint,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: tint,
        borderRadius: LbmRadius.pillR,
        child: InkWell(
          borderRadius: LbmRadius.pillR,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: c.ink),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: LbmText.pinTitle.copyWith(
                    fontSize: 13,
                    color: c.ink,
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

/// "Shop by vendor": the first shops A to Z as faces, and the way into all
/// of them (Grace, 2026-11-16: "Let shoppers browse by vendor").
class VendorRail extends ConsumerWidget {
  const VendorRail({super.key});

  /// Enough faces to say "there are lots of us", few enough to load fast.
  static const shown = 14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendors = ref.watch(allVendorsProvider);
    final all = vendors.value;
    if (all == null && vendors.hasError) return const SizedBox.shrink();
    if (all != null && all.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShelfHeading(
          'Shop by vendor',
          subtitle: all == null
              ? null
              : '${Fmt.count(all.length)} small businesses, A to Z',
          onSeeAll: context.goToVendors,
        ),
        if (all == null)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: ChipRailSkeleton(),
          )
        else
          SlideRow(
            gap: 4,
            children: [
              for (final person in all.take(shown)) _VendorFace(person: person),
              _SeeAllVendors(count: all.length),
            ],
          ),
      ],
    );
  }
}

class _VendorFace extends StatelessWidget {
  const _VendorFace({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.goToSeller(person.id),
      child: SizedBox(
        width: 84,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [c.accent, c.sky],
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: c.paper, width: 3),
                ),
                child: Avatar(person, size: AvatarSize.sm),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              person.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: LbmText.pinMeta.copyWith(
                fontSize: 11.5,
                height: 1.2,
                fontWeight: FontWeight.w800,
                color: c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeeAllVendors extends StatelessWidget {
  const _SeeAllVendors({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: context.goToVendors,
      child: SizedBox(
        width: 84,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.accentDeep,
              ),
              child: Icon(
                Icons.arrow_forward_rounded,
                color: c.accentInk,
                size: 26,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'All $count',
              maxLines: 2,
              textAlign: TextAlign.center,
              style: LbmText.pinMeta.copyWith(
                fontSize: 11.5,
                height: 1.2,
                fontWeight: FontWeight.w800,
                color: c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Holiday Gift Guide's cover, across the top of the Market.
class GiftGuideCover extends StatelessWidget {
  const GiftGuideCover({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    const white = LbmConst.onGradient;
    const guide = kGiftGuide;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Semantics(
        button: true,
        label: '${guide.kicker}. ${guide.title}. Open the gift guide',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: context.goToGiftGuide,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(22)),
              gradient: LinearGradient(
                begin: const Alignment(-0.7, -0.9),
                end: const Alignment(0.7, 0.9),
                colors: c.heroGradient,
                stops: LbmColors.heroStops,
              ),
              boxShadow: c.shadowLift,
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(22)),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FractionallySizedBox(
                        widthFactor: 0.55,
                        heightFactor: 1,
                        child: ShaderMask(
                          // An alpha ramp under dstIn, not colours: it fades
                          // the picture into the gradient behind the words.
                          shaderCallback: (rect) => const LinearGradient(
                            colors: [Colors.transparent, LbmPalette.navy],
                            stops: [0, 0.45],
                          ).createShader(rect),
                          blendMode: BlendMode.dstIn,
                          child: ProductPhoto(
                            url: guide.heroImageUrl,
                            cacheWidth: 700,
                            fallback: const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          guide.kicker.toUpperCase(),
                          style: LbmText.pinMeta.copyWith(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.4,
                            color: white.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(height: 5),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 210),
                          child: Text(
                            'The Gift Guide',
                            style: LbmText.headline.copyWith(
                              fontSize: 28,
                              color: white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 200),
                          child: Text(
                            'Gifts for everyone on your list, from shops '
                            'that share your values.',
                            style: LbmText.pinMeta.copyWith(
                              fontSize: 12.5,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              color: white.withValues(alpha: 0.92),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: white,
                            borderRadius: LbmRadius.pillR,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 15,
                              vertical: 8,
                            ),
                            child: Text(
                              'Shop the guide',
                              style: LbmText.pinTitle.copyWith(
                                fontSize: 12.5,
                                color: LbmPalette.navy,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
