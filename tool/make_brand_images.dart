// Generates every brand image from one source: the app icon (Grace's
// "Body (2).png", 1024×1024, the cart on LbmConst.splashBlue).
//
//   dart run tool/make_brand_images.dart [path/to/source.png]
//   dart run flutter_launcher_icons      # then regenerate the launcher icons
//
// Writes:
//   assets/icon/app-icon.png            the icon as-is (iOS + legacy Android)
//   assets/icon/app-icon-fg.png         the icon padded to Android's adaptive
//                                       safe zone so round masks never clip it
//   assets/images/splash-icon.png       the icon the Flutter SplashOverlay
//                                       centres on the blue
//   android/.../drawable-*/launch_icon.png   the native launch screen, centred,
//                                       at every density (mdpi..xxxhdpi)
//   ios/.../LaunchImage.imageset/*.png  the native launch screen at 1x/2x/3x
//
// `package:image` is a transitive dependency (via flutter_launcher_icons), so
// this script has no dependency of its own to add.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:image/image.dart' as img;

/// LbmConst.splashBlue, the icon's own background. Keep in step.
final splashBlue = img.ColorRgba8(0x70, 0xA0, 0xD1, 0xFF);

/// The icon's size on a launch screen, in dp / pt. Big enough that the cart
/// (about 85% of the icon's width) reads clearly, small enough to sit
/// comfortably on a small phone.
const launchIconDp = 200;

void main(List<String> args) {
  final root = Directory.current.path;
  final srcPath = args.isNotEmpty ? args.first : '$root/../Body (2).png';
  final src = img.decodePng(File(srcPath).readAsBytesSync());
  if (src == null) {
    stderr.writeln('Could not decode $srcPath');
    exit(1);
  }
  if (src.width != src.height) {
    stderr.writeln('Source must be square; got ${src.width}×${src.height}');
    exit(1);
  }
  stdout.writeln('Source: $srcPath (${src.width}×${src.height})');

  // 1. The launcher icon, as-is at 1024.
  _write('assets/icon/app-icon.png', _resize(src, 1024));

  // 2. The adaptive foreground: the icon scaled to 72% and centred on the
  // blue, so the cart stays inside the 66% safe zone under every mask.
  final fg = img.Image(width: 1024, height: 1024, numChannels: 4);
  img.fill(fg, color: splashBlue);
  final inner = _resize(src, (1024 * 0.72).round());
  img.compositeImage(fg, inner,
      dstX: (1024 - inner.width) ~/ 2, dstY: (1024 - inner.height) ~/ 2);
  _write('assets/icon/app-icon-fg.png', fg);

  // 3. The Flutter splash overlay's image.
  _write('assets/images/splash-icon.png', _resize(src, 1024));

  // 4. Android native launch screen, one per density.
  const densities = {
    'mdpi': 1.0,
    'hdpi': 1.5,
    'xhdpi': 2.0,
    'xxhdpi': 3.0,
    'xxxhdpi': 4.0,
  };
  for (final e in densities.entries) {
    _write('android/app/src/main/res/drawable-${e.key}/launch_icon.png',
        _resize(src, (launchIconDp * e.value).round()));
  }

  // 5. iOS native launch screen at 1x/2x/3x.
  const iosDir = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
  _write('$iosDir/LaunchImage.png', _resize(src, launchIconDp));
  _write('$iosDir/LaunchImage@2x.png', _resize(src, launchIconDp * 2));
  _write('$iosDir/LaunchImage@3x.png', _resize(src, launchIconDp * 3));

  stdout.writeln('Done. Now run: dart run flutter_launcher_icons');
}

img.Image _resize(img.Image src, int size) {
  if (src.width == size) return src.clone();
  return img.copyResize(src,
      width: size, height: size, interpolation: img.Interpolation.cubic);
}

void _write(String relPath, img.Image image) {
  final file = File(relPath)..parent.createSync(recursive: true);
  file.writeAsBytesSync(img.encodePng(image));
  stdout.writeln('  wrote $relPath (${image.width}×${image.height})');
}
