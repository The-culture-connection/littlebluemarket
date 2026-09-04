import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'primitives.dart';

/// A placeholder block in the shape of the thing that is loading.
///
/// Shape-matched rather than a spinner: a spinner tells you to wait, a skeleton
/// tells you what you are waiting for, and the layout does not jump when the
/// content lands.
///
/// The fade-in is deliberately **finite**. A repeating shimmer is the usual
/// choice, but `screens_smoke_test.dart` drives 23 routes through
/// `pumpAndSettle`, and an animation that never completes hangs every one of
/// them. A one-shot fade reads as alive and always settles.
class LbmSkeleton extends StatelessWidget {
  const LbmSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 7,
  });

  const LbmSkeleton.block({super.key, this.width, required this.height})
    : radius = LbmRadius.image;

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final block = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: c.skyWash,
        borderRadius: BorderRadius.circular(radius),
      ),
    );

    if (MediaQuery.disableAnimationsOf(context)) return block;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.45, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: block,
    );
  }
}

/// The feed, mid-load.
class PostCardSkeleton extends StatelessWidget {
  const PostCardSkeleton({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: LbmCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                    child: Row(
                      children: [
                        const LbmSkeleton(width: 38, height: 38, radius: 19),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            LbmSkeleton(width: 120, height: 12),
                            SizedBox(height: 6),
                            LbmSkeleton(width: 80, height: 10),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: LbmSkeleton.block(height: double.infinity),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LbmSkeleton(width: 140, height: 11),
                        SizedBox(height: 10),
                        LbmSkeleton(height: 12),
                        SizedBox(height: 6),
                        LbmSkeleton(width: 220, height: 12),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A three-column product grid, mid-load.
class GridSkeleton extends StatelessWidget {
  const GridSkeleton({super.key, this.count = 9});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 7,
          crossAxisSpacing: 7,
        ),
        itemCount: count,
        itemBuilder: (context, i) =>
            const LbmSkeleton.block(height: double.infinity),
      ),
    );
  }
}

/// Rows in a card, mid-load.
class ListRowSkeleton extends StatelessWidget {
  const ListRowSkeleton({super.key, this.rows = 4, this.withAvatar = true});

  final int rows;
  final bool withAvatar;

  @override
  Widget build(BuildContext context) {
    return LbmCard(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  if (withAvatar) ...[
                    const LbmSkeleton(width: 34, height: 34, radius: 17),
                    const SizedBox(width: 11),
                  ],
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LbmSkeleton(width: 130, height: 12),
                        SizedBox(height: 7),
                        LbmSkeleton(height: 10),
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

/// The profile header, mid-load.
class IdentitySkeleton extends StatelessWidget {
  const IdentitySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(14, 4, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LbmSkeleton(width: 74, height: 74, radius: 37),
              SizedBox(width: 14),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: LbmSkeleton(height: 34)),
                    SizedBox(width: 8),
                    Expanded(child: LbmSkeleton(height: 34)),
                    SizedBox(width: 8),
                    Expanded(child: LbmSkeleton(height: 34)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          LbmSkeleton(width: 160, height: 16),
          SizedBox(height: 8),
          LbmSkeleton(height: 12),
          SizedBox(height: 6),
          LbmSkeleton(width: 240, height: 12),
        ],
      ),
    );
  }
}

/// The horizontal hashtag rail, mid-load.
class ChipRailSkeleton extends StatelessWidget {
  const ChipRailSkeleton({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, i) => const Center(
          child: LbmSkeleton(width: 96, height: 26, radius: 999),
        ),
      ),
    );
  }
}

/// The product detail body, mid-load.
class ProductDetailSkeleton extends StatelessWidget {
  const ProductDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 26),
      children: const [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: LbmSkeleton.block(height: double.infinity),
        ),
        SizedBox(height: 16),
        LbmSkeleton(width: 200, height: 20),
        SizedBox(height: 10),
        LbmSkeleton(height: 12),
        SizedBox(height: 6),
        LbmSkeleton(height: 12),
        SizedBox(height: 6),
        LbmSkeleton(width: 180, height: 12),
        SizedBox(height: 22),
        ListRowSkeleton(rows: 3, withAvatar: false),
      ],
    );
  }
}
