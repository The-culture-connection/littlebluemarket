/// The app's own bundled artwork.
///
/// Separate from the fixtures because these are not content: the cart mark and
/// the welcome animation ship with the app whatever the backend is, and a
/// screen referencing them is not reaching into demo data.
abstract final class LbmAssets {
  static const welcomeIntro = 'assets/images/welcome-intro.gif';

  /// The GIF's exact final frame. See the welcome handoff in README.md.
  static const welcomeStill = 'assets/images/welcome-still.png';

  static const cartMark = 'assets/images/logo-cart.png';

  /// The splash image (Grace's "Body (2).png", the app icon itself): the
  /// cart on `LbmConst.splashBlue`, 1024×1024. SplashOverlay centres it on
  /// the same blue for a moment after the native launch screen, which shows
  /// the identical icon in the identical place. Regenerate every copy with
  /// `dart run tool/make_brand_images.dart`.
  static const splash = 'assets/images/splash-icon.png';
}
