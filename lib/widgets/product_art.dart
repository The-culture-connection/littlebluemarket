import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/models.dart';
import '../theme/tokens.dart';
import 'remote_image.dart';

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
    this.natural = false,
  });

  final Product product;

  /// Feed media is 4:3; grid cells and thumbnails are square.
  final bool square;
  final BorderRadius? borderRadius;

  /// Take the photograph's own shape rather than 4:3. Detail pages only;
  /// see [ProductGallery.naturalAspect] for the limits it is clamped to.
  final bool natural;

  @override
  Widget build(BuildContext context) {
    final fitted = natural && !square && product.hasPhoto;
    final art = product.hasPhoto
        ? _Photo(product: product, fit: fitted ? BoxFit.contain : BoxFit.cover)
        : _Tile(product: product);
    final child = fitted
        ? _NaturalFrame(url: product.imageUrls.first, child: art)
        : AspectRatio(aspectRatio: square ? 1 : 4 / 3, child: art);
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
    this.cacheWidth = 600,
  });

  final String url;

  /// Shown when the image cannot be loaded — a packaging mistake for a bundled
  /// asset, a network blip for a URL. Either way the layout must not collapse.
  final Widget fallback;
  final BoxFit fit;

  /// Decode width. Null decodes the file at its own size, which is what the
  /// full-screen viewer wants: 600px is plenty for a card and mush at 5x.
  final int? cacheWidth;

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
      // Through the same-origin proxy on the web; unchanged on a phone.
      resolveImageUrl(url),
      fit: fit,
      cacheWidth: cacheWidth,
      errorBuilder: (context, _, _) => fallback,
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.product, this.fit = BoxFit.cover});

  final Product product;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.c.skyWash,
      child: ProductPhoto(
        url: product.imageUrls.first,
        fit: fit,
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
///
/// On a detail page the frame takes the shape of the photograph rather than
/// imposing 4:3 on it: a tall bottle was cropped top and bottom, a wide banner
/// was pillarboxed, and neither looked like what the seller uploaded
/// (Grace's testers, 2026-09-23). See [naturalAspect] for the limits.
class ProductGallery extends StatefulWidget {
  const ProductGallery({
    super.key,
    required this.product,
    this.borderRadius,
    this.natural = false,
    this.onTapPhoto,
  });

  final Product product;
  final BorderRadius? borderRadius;

  /// Take the first photograph's own shape instead of 4:3. For the detail
  /// page; the feed keeps one ratio so cards stay a predictable height.
  final bool natural;

  /// Opens the full-screen viewer, with the photo that was tapped.
  final void Function(int index)? onTapPhoto;

  /// The ratio to draw a photograph at, from its own pixels.
  ///
  /// Clamped, because "whatever the file says" is not a layout: a 1:6 label
  /// strip would be a hairline and a 6:1 one would push the price off the
  /// screen. 3:4 to 16:9 covers every shape a phone camera or a product shoot
  /// produces, and anything outside it is letterboxed inside the nearest
  /// allowed frame rather than distorted.
  static const minAspect = 3 / 4;
  static const maxAspect = 16 / 9;

  static double naturalAspect(double width, double height) {
    if (width <= 0 || height <= 0) return 4 / 3;
    return (width / height).clamp(minAspect, maxAspect);
  }

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
    final radius = widget.borderRadius ?? LbmRadius.imageR;

    if (images.length < 2) {
      final art = ProductArt(
        widget.product,
        borderRadius: widget.borderRadius,
        natural: widget.natural,
      );
      if (widget.onTapPhoto == null || images.isEmpty) return art;
      return GestureDetector(onTap: () => widget.onTapPhoto!(0), child: art);
    }

    return Column(
      children: [
        // One frame for the whole gallery, sized by the first photograph:
        // a PageView needs a height, and a frame that changed shape as you
        // swiped would jump the page under your thumb.
        _NaturalFrame(
          url: widget.natural ? images.first : null,
          child: ClipRRect(
            borderRadius: radius,
            child: PageView.builder(
              controller: _controller,
              itemCount: images.length,
              onPageChanged: (page) => setState(() => _page = page),
              itemBuilder: (context, i) => GestureDetector(
                onTap: widget.onTapPhoto == null
                    ? null
                    : () => widget.onTapPhoto!(i),
                child: ColoredBox(
                  color: context.c.skyWash,
                  child: ProductPhoto(
                    url: images[i],
                    // Inside a frame shaped by the first photograph, the
                    // others are shown whole rather than cropped to fit it.
                    fit: widget.natural ? BoxFit.contain : BoxFit.cover,
                    fallback: ProductArt(widget.product),
                  ),
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

/// Gives its child the shape of [url]'s own pixels, 4:3 until they are known.
///
/// The ratio has to come from the decoded image, which means a listener on
/// the image stream: `Image.network` knows its intrinsic size but does not
/// hand it to the layout, and an `AspectRatio` has to be told a number before
/// anything is drawn.
class _NaturalFrame extends StatefulWidget {
  const _NaturalFrame({required this.url, required this.child});

  /// Null keeps the 4:3 frame — the feed, and listings with no photograph.
  final String? url;
  final Widget child;

  @override
  State<_NaturalFrame> createState() => _NaturalFrameState();
}

class _NaturalFrameState extends State<_NaturalFrame> {
  double _aspect = 4 / 3;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_NaturalFrame old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _resolve();
  }

  void _resolve() {
    _detach();
    final url = widget.url;
    if (url == null || url.isEmpty) return;
    final asset = ProductPhoto.bundlePath(url);
    final provider = asset != null
        ? AssetImage(asset) as ImageProvider
        : NetworkImage(resolveImageUrl(url));
    final listener = ImageStreamListener((info, _) {
      final aspect = ProductGallery.naturalAspect(
        info.image.width.toDouble(),
        info.image.height.toDouble(),
      );
      if (!mounted || aspect == _aspect) return;
      setState(() => _aspect = aspect);
    }, onError: (_, _) {});
    _listener = listener;
    _stream = provider.resolve(createLocalImageConfiguration(context))
      ..addListener(listener);
  }

  void _detach() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      AspectRatio(aspectRatio: _aspect, child: widget.child);
}

/// One listing's photographs, full screen, pinchable.
///
/// Opened from the detail page. Double tap zooms in and out for the people
/// who never think to pinch, and the shade behind it is black so the
/// photograph is the only thing on screen.
class PhotoViewer extends StatefulWidget {
  const PhotoViewer({
    super.key,
    required this.product,
    this.initialIndex = 0,
  });

  final Product product;
  final int initialIndex;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _page = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.product.imageUrls;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: images.length,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (context, i) => _ZoomablePhoto(
              url: images[i],
              product: widget.product,
            ),
          ),
          Positioned(
            top: MediaQuery.viewPaddingOf(context).top + 6,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          if (images.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.viewPaddingOf(context).bottom + 18,
              child: Semantics(
                label: 'Photo ${_page + 1} of ${images.length}',
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < images.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Container(
                          width: i == _page ? 18 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(
                              alpha: i == _page ? 0.95 : 0.4,
                            ),
                            borderRadius: LbmRadius.pillR,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({required this.url, required this.product});

  final String url;
  final Product product;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto>
    with SingleTickerProviderStateMixin {
  final _view = TransformationController();
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  Animation<Matrix4>? _tween;

  /// Where the last double tap landed, so zooming in goes towards it.
  Offset _tapAt = Offset.zero;

  @override
  void dispose() {
    _anim.dispose();
    _view.dispose();
    super.dispose();
  }

  void _animateTo(Matrix4 target) {
    _tween = Matrix4Tween(begin: _view.value, end: target).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
    );
    _anim
      ..removeListener(_follow)
      ..addListener(_follow)
      ..forward(from: 0);
  }

  void _follow() {
    final tween = _tween;
    if (tween != null) _view.value = tween.value;
  }

  void _toggleZoom() {
    // Already zoomed: back to whole, wherever they are.
    if (_view.value.getMaxScaleOnAxis() > 1.05) {
      _animateTo(Matrix4.identity());
      return;
    }
    const scale = 2.5;
    _animateTo(
      Matrix4.identity()
        ..translateByDouble(
          -_tapAt.dx * (scale - 1),
          -_tapAt.dy * (scale - 1),
          0,
          1,
        )
        ..scaleByDouble(scale, scale, scale, 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (details) => _tapAt = details.localPosition,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _view,
        minScale: 1,
        maxScale: 5,
        child: Center(
          child: ProductPhoto(
            url: widget.url,
            fit: BoxFit.contain,
            // Full screen deserves the full file, not the 600px the cards use.
            cacheWidth: null,
            fallback: ProductArt(widget.product),
          ),
        ),
      ),
    );
  }
}

/// Opens [PhotoViewer] over everything, starting on [index].
Future<void> showPhotoViewer(
  BuildContext context,
  Product product, {
  int index = 0,
}) {
  if (product.imageUrls.isEmpty) return Future<void>.value();
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PhotoViewer(product: product, initialIndex: index),
    ),
  );
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
