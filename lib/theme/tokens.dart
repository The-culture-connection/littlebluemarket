import 'package:flutter/material.dart';

/// The Little Blue Cart brand palette, and nothing else (brand guide,
/// 2026-10-22: "make sure everything is inline with these guidelines and
/// nothing is outside of it").
///
/// Eight colours from the guide, plus white for cards and type on dark
/// fills. Every colour in the app is one of these, one of these with
/// transparency, or one of the [mixes] below, each of which is a guide
/// colour laid over white or navy at a stated strength (a tint, the way a
/// printer would make one). `test/design_tokens_test.dart` holds the app
/// to that, so a stray hex cannot creep back in.
abstract final class LbmPalette {
  static const navy = Color(0xFF253856);
  static const blue = Color(0xFF70A0D2);
  static const orchid = Color(0xFFD270D1);
  static const cream = Color(0xFFFAF2C6);
  static const greyBlue = Color(0xFFB3BDCA);
  static const gold = Color(0xFFC49919);
  static const sky = Color(0xFF89C9F4);
  static const sand = Color(0xFFD3CABC);
  static const white = Color(0xFFFFFFFF);

  /// The guide's colours, in the guide's order, then white.
  static const brand = [
    navy,
    blue,
    orchid,
    cream,
    greyBlue,
    gold,
    sky,
    sand,
    white,
  ];

  /// Blue at 22% on white: chip fills and tints on a white card.
  static const blueMist = Color(0xFFDFEAF5);

  /// Blue at 8% on white: the faintest inset panel.
  static const blueWash = Color(0xFFF4F7FB);

  /// Orchid at 18% on white: the selected tab, a highlighted row.
  static const orchidMist = Color(0xFFF7E5F7);

  /// Blue at 14% on navy: cards and sheets in dark mode, one step up from
  /// the navy page.
  static const navyRaised = Color(0xFF304767);

  /// Blue at 28% on navy: chip fills in dark mode.
  static const navyMist = Color(0xFF3A5579);

  /// Blue at 8% on navy: inset panels in dark mode.
  static const navyWash = Color(0xFF2B4060);

  /// Orchid at 28% on navy: the selected tab in dark mode.
  static const orchidOnNavy = Color(0xFF554878);

  /// Every tint above, so the test can tell a tint from a stray colour.
  static const mixes = [
    blueMist,
    blueWash,
    orchidMist,
    navyRaised,
    navyMist,
    navyWash,
    orchidOnNavy,
  ];
}

/// The prototype's design tokens, carried on [ThemeData] as an extension.
///
/// Every colour in the app comes from here; nothing is hardcoded per-screen.
/// The light and dark sets are transcribed from `.viewport` and
/// `.viewport[data-skin="dark"]` in the prototype.
@immutable
class LbmColors extends ThemeExtension<LbmColors> {
  const LbmColors({
    required this.paper,
    required this.surface,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.sky,
    required this.skyDeep,
    required this.skyMist,
    required this.skyWash,
    required this.accent,
    required this.accentDeep,
    required this.accentInk,
    required this.accentMist,
    required this.accentText,
    required this.sage,
    required this.sageMist,
    required this.clay,
    required this.cardStock,
    required this.scrim,
    required this.shadowSoft,
    required this.shadowLift,
  });

  /// App background. The welcome screen's cornflower blue — the point is that
  /// the app sits on it rather than on white.
  final Color paper;

  /// Cards, sheets, bars.
  final Color surface;

  /// Primary ink.
  final Color ink;

  /// Secondary text.
  final Color ink2;

  /// Tertiary text / placeholder.
  final Color ink3;

  /// The hero blue, from the animation.
  final Color sky;

  /// Links.
  final Color skyDeep;

  /// Chip fills, tints.
  final Color skyMist;

  /// Subtle inset panels.
  final Color skyWash;

  /// The accent — chips, dots, stars, progress, active states.
  ///
  /// Never put white text on this; it is only ~3:1. See [accentDeep].
  final Color accent;

  /// Solid fills that carry [accentInk] label text.
  ///
  /// In light mode this is a deeper shade of the same hue, because the pure
  /// accent under white text is below the readable threshold. In dark mode it
  /// is the pure accent, which carries a dark plum label instead. Reach for
  /// this **only** when the fill sits under [accentInk] text; everything else
  /// uses [accent].
  final Color accentDeep;

  /// Text on [accentDeep].
  final Color accentInk;

  /// Accent tint backgrounds.
  final Color accentMist;

  /// Accent-coloured text on [accentMist].
  final Color accentText;

  /// Delivered / success.
  final Color sage;
  final Color sageMist;
  final Color clay;

  /// The cream stock of a directory business card.
  ///
  /// Its own colour rather than [surface], because the card is meant to read
  /// as a printed thing laid on the grid: white is every other pin, and a
  /// business card that matched them would be one more white rectangle.
  final Color cardStock;

  /// What the app is dimmed to behind a popup: dull, dark and grey on
  /// purpose, so the blue underneath goes quiet.
  ///
  /// Its own colour rather than [ink] with an alpha, for two reasons found
  /// the hard way on 2026-09-14: [ink] is a navy, so a scrim made from it
  /// reads as dark blue rather than grey; and in dark mode [ink] is nearly
  /// white, so the same expression washed the screen out instead of
  /// dimming it. The alpha is baked in here.
  final Color scrim;

  /// `0 3px 14px -5px` — the card shadow.
  final List<BoxShadow> shadowSoft;

  /// `0 10px 28px -10px` — the floating tab bar and raised sheets.
  final List<BoxShadow> shadowLift;

  // Light: navy type on the blue page, white cards, navy buttons with white
  // labels, orchid for the small bright moments (Grace's choices of
  // 2026-10-22). Alpha variants are written as literals so the sets stay
  // const: 0xCC253856 is navy at 80%.
  static const light = LbmColors(
    // The brand blue (Grace, 2026-10-22, changed from sky the same day).
    paper: LbmPalette.blue,
    surface: LbmPalette.white,
    scrim: Color(0xB3253856),
    ink: LbmPalette.navy,
    ink2: Color(0xCC253856),
    ink3: Color(0x99253856),
    sky: LbmPalette.blue,
    skyDeep: LbmPalette.navy,
    skyMist: LbmPalette.blueMist,
    skyWash: LbmPalette.blueWash,
    accent: LbmPalette.orchid,
    accentDeep: LbmPalette.navy,
    accentInk: LbmPalette.white,
    accentMist: LbmPalette.orchidMist,
    accentText: LbmPalette.navy,
    sage: LbmPalette.blue,
    sageMist: LbmPalette.blueMist,
    clay: LbmPalette.orchid,
    cardStock: LbmPalette.cream,
    shadowSoft: [
      BoxShadow(
        color: Color(0x57253856),
        offset: Offset(0, 3),
        blurRadius: 14,
        spreadRadius: -5,
      ),
    ],
    shadowLift: [
      BoxShadow(
        color: Color(0x70253856),
        offset: Offset(0, 10),
        blurRadius: 28,
        spreadRadius: -10,
      ),
    ],
  );

  // Dark: the navy page, cards a tint lighter, white and grey-blue type,
  // sky buttons with navy labels. Navy is the guide's only dark colour, so
  // the shadows are deep navy rather than black.
  static const dark = LbmColors(
    paper: LbmPalette.navy,
    surface: LbmPalette.navyRaised,
    scrim: Color(0xD9253856),
    ink: LbmPalette.white,
    ink2: LbmPalette.greyBlue,
    ink3: Color(0xB3B3BDCA),
    sky: LbmPalette.blue,
    skyDeep: LbmPalette.sky,
    skyMist: LbmPalette.navyMist,
    skyWash: LbmPalette.navyWash,
    accent: LbmPalette.orchid,
    accentDeep: LbmPalette.sky,
    accentInk: LbmPalette.navy,
    accentMist: LbmPalette.orchidOnNavy,
    accentText: LbmPalette.white,
    sage: LbmPalette.sky,
    sageMist: LbmPalette.navyMist,
    clay: LbmPalette.orchid,
    cardStock: LbmPalette.navyRaised,
    shadowSoft: [
      BoxShadow(
        color: Color(0xCC253856),
        offset: Offset(0, 3),
        blurRadius: 14,
        spreadRadius: -5,
      ),
    ],
    shadowLift: [
      BoxShadow(
        color: Color(0xF2253856),
        offset: Offset(0, 10),
        blurRadius: 30,
        spreadRadius: -10,
      ),
    ],
  );

  /// Behind the one announcement at the top of the feed: navy into the
  /// brand blue. The violet that used to sit in the middle is not in the
  /// brand guide, so it is gone (2026-10-22). Navy holds most of the way so
  /// the white type stays on navy.
  List<Color> get heroGradient => const [
    LbmPalette.navy,
    LbmPalette.navy,
    LbmPalette.blue,
  ];

  /// Where the hero's colours sit along that gradient.
  static const heroStops = [0.0, 0.6, 1.0];

  /// Behind a shoutout: the same idea, blue into navy, because a shoutout is
  /// about a maker rather than about the market.
  List<Color> get shoutoutGradient => const [LbmPalette.blue, LbmPalette.navy];

  @override
  LbmColors copyWith({
    Color? paper,
    Color? surface,
    Color? ink,
    Color? ink2,
    Color? ink3,
    Color? sky,
    Color? skyDeep,
    Color? skyMist,
    Color? skyWash,
    Color? accent,
    Color? accentDeep,
    Color? accentInk,
    Color? accentMist,
    Color? accentText,
    Color? sage,
    Color? sageMist,
    Color? clay,
    Color? cardStock,
    Color? scrim,
    List<BoxShadow>? shadowSoft,
    List<BoxShadow>? shadowLift,
  }) {
    return LbmColors(
      paper: paper ?? this.paper,
      surface: surface ?? this.surface,
      scrim: scrim ?? this.scrim,
      ink: ink ?? this.ink,
      ink2: ink2 ?? this.ink2,
      ink3: ink3 ?? this.ink3,
      sky: sky ?? this.sky,
      skyDeep: skyDeep ?? this.skyDeep,
      skyMist: skyMist ?? this.skyMist,
      skyWash: skyWash ?? this.skyWash,
      accent: accent ?? this.accent,
      accentDeep: accentDeep ?? this.accentDeep,
      accentInk: accentInk ?? this.accentInk,
      accentMist: accentMist ?? this.accentMist,
      accentText: accentText ?? this.accentText,
      sage: sage ?? this.sage,
      sageMist: sageMist ?? this.sageMist,
      clay: clay ?? this.clay,
      cardStock: cardStock ?? this.cardStock,
      shadowSoft: shadowSoft ?? this.shadowSoft,
      shadowLift: shadowLift ?? this.shadowLift,
    );
  }

  @override
  LbmColors lerp(ThemeExtension<LbmColors>? other, double t) {
    if (other is! LbmColors) return this;
    return LbmColors(
      paper: Color.lerp(paper, other.paper, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      ink3: Color.lerp(ink3, other.ink3, t)!,
      sky: Color.lerp(sky, other.sky, t)!,
      skyDeep: Color.lerp(skyDeep, other.skyDeep, t)!,
      skyMist: Color.lerp(skyMist, other.skyMist, t)!,
      skyWash: Color.lerp(skyWash, other.skyWash, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentDeep: Color.lerp(accentDeep, other.accentDeep, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
      accentMist: Color.lerp(accentMist, other.accentMist, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      sage: Color.lerp(sage, other.sage, t)!,
      sageMist: Color.lerp(sageMist, other.sageMist, t)!,
      clay: Color.lerp(clay, other.clay, t)!,
      cardStock: Color.lerp(cardStock, other.cardStock, t)!,
      shadowSoft: BoxShadow.lerpList(shadowSoft, other.shadowSoft, t)!,
      shadowLift: BoxShadow.lerpList(shadowLift, other.shadowLift, t)!,
    );
  }
}

/// Tokens that do not change between light and dark.
abstract final class LbmConst {
  /// The GIF's button fill. Onboarding only — never re-skinned.
  static const slate = LbmPalette.navy;

  /// Line art on the pastel product tiles, fixed across modes.
  static const artInk = LbmPalette.navy;

  /// The hero blue the welcome animation is painted on. The still and the GIF
  /// letterbox against this, so it must not be themed.
  static const welcomeBlue = LbmPalette.blue;

  /// Ink used on top of [welcomeBlue].
  static const onWelcome = LbmPalette.white;

  /// The open-chat pin's background, fixed across modes.
  ///
  /// It is the one tile in the grid that is deliberately dark, which is how a
  /// scroll past it registers as "something is happening" without a label.
  /// [LbmColors.ink] cannot do that job: it inverts, so in dark mode the tile
  /// came out near-white and its white type vanished. This is light mode's
  /// ink, held still — dark enough to carry [onGradient] in either theme, and
  /// darker than the white cards around it.
  static const chatInk = LbmPalette.navy;

  /// Type on the hero and shoutout gradients.
  ///
  /// Those gradients are deep in both themes, so their label does not flip
  /// with the palette the way [LbmColors.accentInk] does. A themed ink here
  /// would go dark-on-dark the moment the phone switched to dark mode.
  static const onGradient = LbmPalette.white;

  /// The exact background of the app icon (`assets/images/splash-icon.png`,
  /// sampled), and of the native launch screens on both phones
  /// (`android/.../values/colors.xml` `lbm_splash`, `LaunchScreen.storyboard`).
  /// Keep the three in step or the launch flashes.
  static const splashBlue = LbmPalette.blue;

  /// The avatar tints, for something with initials and no photograph.
  ///
  /// The guide's eight colours, the same eight `kAvatarTints` (models) hands
  /// a person, so a directory business with no picture sits in the same
  /// family as a maker with none. Initials are navy on all of them but navy
  /// itself, which carries white: see [initialsOn].
  static const makerTints = [
    LbmPalette.blue,
    LbmPalette.orchid,
    LbmPalette.gold,
    LbmPalette.sky,
    LbmPalette.sand,
    LbmPalette.greyBlue,
    LbmPalette.cream,
    LbmPalette.navy,
  ];

  /// The colour of initials on [tint]: white on navy, navy on everything
  /// else in the palette, which is readable on all of them.
  static Color initialsOn(Color tint) =>
      tint.toARGB32() == LbmPalette.navy.toARGB32()
      ? LbmPalette.white
      : LbmPalette.navy;

  /// A stable tint for [id], hashed the way `tintFor` hashes a uid.
  static Color makerTintFor(String id) {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return makerTints[hash % makerTints.length];
  }
}

/// How things move when something happens: bouncy, never slow.
///
/// Every entrance overshoots and settles (the mockup's
/// `cubic-bezier(.34,1.56,.64,1)`), and everything lands in 550 to 700 ms,
/// which reads as playful rather than as waiting. One place for the numbers
/// so a toast, a badge and a new pin all bounce the same way.
abstract final class LbmMotion {
  /// The overshoot: past the mark by a little, then back.
  static const overshoot = Cubic(0.34, 1.56, 0.64, 1);

  /// A toast or banner dropping in.
  static const enter = Duration(milliseconds: 600);

  /// Anything leaving: quicker than it came, and without the bounce.
  static const exit = Duration(milliseconds: 300);

  /// A new pin growing in at the top of the feed.
  static const grow = Duration(milliseconds: 700);

  /// A badge or dot arriving.
  static const wobble = Duration(milliseconds: 550);

  /// A button hopping to be noticed.
  static const hop = Duration(milliseconds: 700);

  /// The bell swinging.
  static const ring = Duration(milliseconds: 800);

  /// [duration], or none at all when the phone asks for no animation.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false
      ? Duration.zero
      : duration;
}

/// Corner radii. "Cute and soft, not rigid" — rounded everything, and no hard
/// 1px grid anywhere.
abstract final class LbmRadius {
  static const card = 22.0;
  static const image = 18.0;

  /// Buttons, chips, tab pills, avatars.
  static const pill = 999.0;
  static const sheet = 30.0;
  static const field = 16.0;

  static const cardR = BorderRadius.all(Radius.circular(card));
  static const imageR = BorderRadius.all(Radius.circular(image));
  static const pillR = BorderRadius.all(Radius.circular(pill));
  static const fieldR = BorderRadius.all(Radius.circular(field));
  static const sheetR = BorderRadius.vertical(top: Radius.circular(sheet));
}

extension LbmThemeAccess on BuildContext {
  /// The app's colour tokens for the current brightness.
  LbmColors get c => Theme.of(this).extension<LbmColors>()!;
}
