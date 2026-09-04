import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/models.dart';
import '../theme/tokens.dart';

/// The line art used on listings without a photograph, transcribed from the
/// prototype's `GLYPH` map. Stroke width and caps are part of the look.
const _glyphs = <ProductGlyph, String>{
  ProductGlyph.jar:
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="none" '
      'stroke="currentColor" stroke-width="3" stroke-linecap="round" '
      'stroke-linejoin="round"><rect x="16" y="24" width="32" height="30" '
      'rx="9"/><path d="M22 24v-6h20v6"/><path d="M24 35h16"/></svg>',
  ProductGlyph.bowl:
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="none" '
      'stroke="currentColor" stroke-width="3" stroke-linecap="round" '
      'stroke-linejoin="round"><path d="M8 30h48c0 12-10.7 22-24 22S8 42 8 '
      '30Z"/><path d="M18 30c0-7 6-12 14-12s14 5 14 12"/></svg>',
  ProductGlyph.camera:
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="none" '
      'stroke="currentColor" stroke-width="3" stroke-linecap="round" '
      'stroke-linejoin="round"><rect x="7" y="18" width="50" height="34" '
      'rx="11"/><path d="M22 18l4-6h12l4 6"/><circle cx="32" cy="35" '
      'r="9"/></svg>',
  ProductGlyph.candle:
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="none" '
      'stroke="currentColor" stroke-width="3" stroke-linecap="round" '
      'stroke-linejoin="round"><rect x="19" y="26" width="26" height="28" '
      'rx="9"/><path d="M32 26v-6"/><path d="M32 20c4-4 1-8-1-10 0 5-5 5-3 9 1 '
      '1.6 2.5 1.6 4 1Z"/></svg>',
  ProductGlyph.zine:
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="none" '
      'stroke="currentColor" stroke-width="3" stroke-linecap="round" '
      'stroke-linejoin="round"><path d="M32 20c-6-4-13-4-20-3v32c7-1 14-1 20 '
      '3 6-4 13-4 20-3V17c-7-1-14-1-20 3Z"/><path d="M32 20v32"/></svg>',
  ProductGlyph.mug:
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="none" '
      'stroke="currentColor" stroke-width="3" stroke-linecap="round" '
      'stroke-linejoin="round"><rect x="12" y="20" width="30" height="30" '
      'rx="10"/><path d="M42 27h5a7 7 0 0 1 0 14h-5"/></svg>',
};

/// A listing's image: a real photograph where there is one, otherwise the
/// illustrated pastel tile.
class ProductArt extends StatelessWidget {
  const ProductArt(
    this.product, {
    super.key,
    this.square = false,
    this.borderRadius,
  });

  final Product product;

  /// Feed media is 4:3; grid cells and thumbnails are square.
  final bool square;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final child = AspectRatio(
      aspectRatio: square ? 1 : 4 / 3,
      child: product.hasPhoto
          ? _Photo(product: product)
          : _Tile(product: product),
    );
    if (borderRadius == null) return child;
    return ClipRRect(borderRadius: borderRadius!, child: child);
  }
}

/// One listing photograph, from the bundle or the network.
///
/// The demo backend serves an `asset://` URL so the app stays correct offline;
/// live listings carry ordinary URLs. Everything above this widget just holds a
/// list of strings and never has to know which is which.
class ProductPhoto extends StatelessWidget {
  const ProductPhoto({
    super.key,
    required this.url,
    required this.fallback,
    this.fit = BoxFit.cover,
  });

  final String url;

  /// Shown when the image cannot be loaded — a packaging mistake for a bundled
  /// asset, a network blip for a URL. Either way the layout must not collapse.
  final Widget fallback;
  final BoxFit fit;

  static const _assetScheme = 'asset://';

  /// The bundle path behind an `asset://` URL, or null for a network URL.
  static String? bundlePath(String url) =>
      url.startsWith(_assetScheme) ? url.substring(_assetScheme.length) : null;

  @override
  Widget build(BuildContext context) {
    final asset = bundlePath(url);
    if (asset != null) {
      return Image.asset(
        asset,
        fit: fit,
        errorBuilder: (context, _, _) => fallback,
      );
    }
    return Image.network(
      url,
      fit: fit,
      errorBuilder: (context, _, _) => fallback,
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.c.skyWash,
      child: ProductPhoto(
        url: product.imageUrls.first,
        fallback: _Tile(product: product),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final from = Color(product.tileFrom ?? 0xFFDCE9F7);
    final to = Color(product.tileTo ?? 0xFF9CBFE3);
    return DecoratedBox(
      decoration: BoxDecoration(
        // `linear-gradient(150deg, c1, c2)`
        gradient: LinearGradient(
          begin: const Alignment(-0.5, -0.866),
          end: const Alignment(0.5, 0.866),
          colors: [from, to],
        ),
      ),
      child: DecoratedBox(
        // The soft highlight: `radial-gradient(110% 80% at 76% 14%, ...)`
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.52, -0.72),
            radius: 0.9,
            colors: [Color(0x80FFFFFF), Color(0x00FFFFFF)],
            stops: [0, 0.6],
          ),
        ),
        child: Center(
          child: FractionallySizedBox(
            widthFactor: 0.42,
            heightFactor: 0.42,
            child: Opacity(
              opacity: 0.52,
              child: SvgPicture.string(
                _glyphs[product.glyph] ?? _glyphs[ProductGlyph.jar]!,
                colorFilter: const ColorFilter.mode(
                  LbmConst.artInk,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The little cloud that marks the end of a feed. Decorative only.
class Puff extends StatelessWidget {
  const Puff({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Center(
        child: Opacity(
          opacity: 0.4,
          child: CustomPaint(
            size: const Size(66, 22),
            painter: _PuffPainter(context.c.ink2),
          ),
        ),
      ),
    );
  }
}

class _PuffPainter extends CustomPainter {
  const _PuffPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    void blob(double cx, double cy, double rx, double ry) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
        paint,
      );
    }

    blob(14, 15, 13, 6);
    blob(34, 12, 16, 8);
    blob(55, 16, 10, 5);
  }

  @override
  bool shouldRepaint(_PuffPainter old) => old.color != color;
}

/// A swipeable gallery of a listing's photographs.
///
/// Falls back to the single [ProductArt] when there is one image or none, so a
/// service listing with only its illustrated tile does not grow a page
/// indicator it cannot use.
class ProductGallery extends StatefulWidget {
  const ProductGallery({super.key, required this.product, this.borderRadius});

  final Product product;
  final BorderRadius? borderRadius;

  @override
  State<ProductGallery> createState() => _ProductGalleryState();
}

class _ProductGalleryState extends State<ProductGallery> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.product.imageUrls;
    if (images.length < 2) {
      return ProductArt(widget.product, borderRadius: widget.borderRadius);
    }

    final radius = widget.borderRadius ?? LbmRadius.imageR;
    return Column(
      children: [
        ClipRRect(
          borderRadius: radius,
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: PageView.builder(
              controller: _controller,
              itemCount: images.length,
              onPageChanged: (page) => setState(() => _page = page),
              itemBuilder: (context, i) => ColoredBox(
                color: context.c.skyWash,
                child: ProductPhoto(
                  url: images[i],
                  fallback: ProductArt(widget.product),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _Dots(count: images.length, active: _page),
      ],
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      label: 'Photo ${active + 1} of $count',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Container(
                width: i == active ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == active ? c.accent : c.ink3.withValues(alpha: 0.4),
                  borderRadius: LbmRadius.pillR,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
