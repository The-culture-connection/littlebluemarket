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

  /// The splash artwork (Grace's Body.png): the cart and wordmark on
  /// `LbmConst.splashBlue`, 1080×1920. Shown full-bleed for a moment after
  /// the native launch screen, which is the same blue.
  static const splash = 'assets/images/splash-body.png';
}
