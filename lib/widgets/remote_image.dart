import 'package:flutter/material.dart';

import '../platform/platform_info.dart';
import '../theme/tokens.dart';

/// Hosts whose images a browser cannot draw directly.
///
/// littlebluecart.com serves its uploads with no `Access-Control-Allow-Origin`
/// header at all (checked 2026-09-14). A phone does a plain GET and does not
/// care, but Flutter's web renderers decode through a canvas, which the
/// browser refuses for a cross-origin image without that header, so every
/// directory listing's photo came out blank on the website.
///
/// The fix is same-origin: the web server that hands out the app also hands
/// out `/img?u=…`, fetching the picture itself. Keep this set in step with
/// the allowlist in `web-server/server.js`; a host missing there is a broken
/// image, a host missing here is a blank one.
const _hostsWithoutCors = {
  'littlebluecart.com',
  'www.littlebluecart.com',
  // Our own Storage, too. A Firebase download URL carries no
  // Access-Control-Allow-Origin either unless the bucket is given a CORS
  // configuration, and neither of ours has one, so an advert's photo was as
  // blank as a directory listing's (Grace, 2026-09-14). Unlike
  // littlebluecart.com this one we could fix properly at the bucket; until
  // someone with gcloud does, it goes the same way.
  'firebasestorage.googleapis.com',
};

/// The address to actually load [url] from.
///
/// Unchanged on a phone, where there is no such thing as a cross-origin
/// image. [onWeb] exists so this is testable: under `flutter test` the io
/// platform is compiled in, so the web branch would never otherwise run.
String resolveImageUrl(String url, {bool? onWeb}) {
  final isWeb = onWeb ?? (platformName == 'web');
  if (!isWeb || url.isEmpty) return url;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return url;
  if (!_hostsWithoutCors.contains(uri.host)) return url;
  return '/img?u=${Uri.encodeQueryComponent(url)}';
}

/// A photograph from the web, in a fixed shape, that **takes no room when it
/// cannot be shown**.
///
/// The directory card used to put `Image.network` inside an `AspectRatio` and
/// return an empty box from `errorBuilder`. The image failed, the box stayed,
/// and 227 businesses each reserved a 16:9 hole above their name
/// (Grace, 2026-09-14). `errorBuilder` cannot remove its own ancestor, so
/// the failure has to be remembered here and the box left out on the rebuild.
class RemoteImage extends StatefulWidget {
  const RemoteImage({
    super.key,
    required this.url,
    this.aspectRatio = 16 / 9,
    this.fill = false,
    this.fit = BoxFit.cover,
    this.cacheWidth = 600,
    this.borderRadius,
  });

  final String url;
  final double aspectRatio;

  /// How the picture sits in its box. `cover` fills and crops, which is
  /// right for a card in a list where every tile has to be the same shape.
  /// `contain` is for a box already cut to the picture's own shape, where
  /// cropping would be losing something for no reason.
  final BoxFit fit;

  /// Fill whatever room the parent gives instead of imposing
  /// [aspectRatio]. The promo popup has to fit on screen without
  /// scrolling, so there the words take their height and the picture takes
  /// what is left.
  final bool fill;
  final int cacheWidth;

  /// Rounds the picture itself. Omit inside something already clipped.
  final BorderRadius? borderRadius;

  @override
  State<RemoteImage> createState() => _RemoteImageState();
}

class _RemoteImageState extends State<RemoteImage> {
  bool _failed = false;

  @override
  void didUpdateWidget(RemoteImage old) {
    super.didUpdateWidget(old);
    // A recycled card showing a different listing deserves a fresh try.
    if (old.url != widget.url) _failed = false;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url.isEmpty || _failed) return const SizedBox.shrink();
    final c = context.c;

    Widget image = Image.network(
      resolveImageUrl(widget.url),
      fit: widget.fit,
      cacheWidth: widget.cacheWidth,
      errorBuilder: (_, _, _) {
        // Called during layout, so the rebuild cannot happen inline.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_failed) setState(() => _failed = true);
        });
        return ColoredBox(color: c.skyWash);
      },
    );
    final radius = widget.borderRadius;
    if (radius != null) {
      image = ClipRRect(borderRadius: radius, child: image);
    }
    if (widget.fill) return SizedBox.expand(child: image);
    return AspectRatio(aspectRatio: widget.aspectRatio, child: image);
  }
}
