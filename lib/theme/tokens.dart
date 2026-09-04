import 'package:flutter/material.dart';

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

  /// `0 3px 14px -5px` — the card shadow.
  final List<BoxShadow> shadowSoft;

  /// `0 10px 28px -10px` — the floating tab bar and raised sheets.
  final List<BoxShadow> shadowLift;

  static const light = LbmColors(
    paper: Color(0xFF9CBFE3),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF152E52),
    ink2: Color(0xFF31507B),
    ink3: Color(0xFF6B87AD),
    sky: Color(0xFF70A0D0),
    skyDeep: Color(0xFF2A5992),
    skyMist: Color(0xFFDCE9F7),
    skyWash: Color(0xFFF0F5FC),
    accent: Color(0xFFD56ED1),
    accentDeep: Color(0xFFA93BA5),
    accentInk: Color(0xFFFFFFFF),
    accentMist: Color(0xFFF7E2F6),
    accentText: Color(0xFF7E2A7A),
    sage: Color(0xFF4E8A69),
    sageMist: Color(0xFFDDEDE4),
    clay: Color(0xFFC4796B),
    shadowSoft: [
      BoxShadow(
        color: Color(0x570D2342),
        offset: Offset(0, 3),
        blurRadius: 14,
        spreadRadius: -5,
      ),
    ],
    shadowLift: [
      BoxShadow(
        color: Color(0x700D2342),
        offset: Offset(0, 10),
        blurRadius: 28,
        spreadRadius: -10,
      ),
    ],
  );

  static const dark = LbmColors(
    paper: Color(0xFF101E38),
    surface: Color(0xFF1A2C4E),
    ink: Color(0xFFE8F0FB),
    ink2: Color(0xFFA6BEDB),
    ink3: Color(0xFF7A93B5),
    sky: Color(0xFF70A0D0),
    skyDeep: Color(0xFF9CC3EC),
    skyMist: Color(0xFF24406B),
    skyWash: Color(0xFF16294A),
    accent: Color(0xFFD56ED1),
    // On navy the pure accent is light enough to carry a dark plum label.
    accentDeep: Color(0xFFD56ED1),
    accentInk: Color(0xFF2A0A28),
    accentMist: Color(0xFF3B1F3A),
    accentText: Color(0xFFEFA8EC),
    sage: Color(0xFF8CC3A2),
    sageMist: Color(0xFF24422F),
    clay: Color(0xFFDE9A8C),
    shadowSoft: [
      BoxShadow(
        color: Color(0x80000000),
        offset: Offset(0, 3),
        blurRadius: 14,
        spreadRadius: -5,
      ),
    ],
    shadowLift: [
      BoxShadow(
        color: Color(0x9E000000),
        offset: Offset(0, 10),
        blurRadius: 30,
        spreadRadius: -10,
      ),
    ],
  );

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
    List<BoxShadow>? shadowSoft,
    List<BoxShadow>? shadowLift,
  }) {
    return LbmColors(
      paper: paper ?? this.paper,
      surface: surface ?? this.surface,
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
      shadowSoft: BoxShadow.lerpList(shadowSoft, other.shadowSoft, t)!,
      shadowLift: BoxShadow.lerpList(shadowLift, other.shadowLift, t)!,
    );
  }
}

/// Tokens that do not change between light and dark.
abstract final class LbmConst {
  /// The GIF's button fill. Onboarding only — never re-skinned.
  static const slate = Color(0xFF5F6A82);

  /// Line art on the pastel product tiles, fixed across modes.
  static const artInk = Color(0xFF173257);

  /// The hero blue the welcome animation is painted on. The still and the GIF
  /// letterbox against this, so it must not be themed.
  static const welcomeBlue = Color(0xFF70A0D0);

  /// Ink used on top of [welcomeBlue].
  static const onWelcome = Color(0xFFF3F8FE);
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
