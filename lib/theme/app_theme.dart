
import 'package:flutter/material.dart';

import 'tokens.dart';

/// Fraunces — display. Screen titles, prices, wordmark, stat values, thread
/// titles, and the italic section labels.
const kDisplayFont = 'Fraunces';

/// Nunito — UI and body.
const kBodyFont = 'Nunito';

/// There is no monospace in this design. Tracking numbers and other figures
/// that need to line up use Nunito with tabular figures.
const kTabularFigures = [FontFeature.tabularFigures()];

/// Text styles named for their role in the prototype rather than for a
/// Material slot, so screen code reads the way the design does.
abstract final class LbmText {
  /// Screen and card titles. `.serif`, Fraunces 700.
  static const display = TextStyle(
    fontFamily: kDisplayFont,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    height: 1.15,
  );

  /// The italic section label that sits above a group of cards.
  static const sectionLabel = TextStyle(
    fontFamily: kDisplayFont,
    fontWeight: FontWeight.w600,
    fontStyle: FontStyle.italic,
    fontSize: 14.5,
    height: 1.3,
  );

  /// Body copy. 15/1.5 is the viewport default.
  static const body = TextStyle(fontSize: 15, height: 1.5);

  /// `.tiny`
  static const tiny = TextStyle(fontSize: 12.5, height: 1.5);

  /// `.xtiny`
  static const xtiny = TextStyle(fontSize: 11.5, height: 1.45);

  /// `.label` — the small caps-ish field label.
  static const fieldLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.36,
    height: 1.3,
  );

  /// Figures that need to line up: prices, counts, tracking numbers.
  static const numeric = TextStyle(fontFeatures: kTabularFigures);
}

ThemeData buildLbmTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final t = isDark ? LbmColors.dark : LbmColors.light;

  // Material's own ColorScheme is kept in step with the tokens so that any
  // stock Material widget that slips through still lands in the palette.
  final scheme = ColorScheme(
    brightness: brightness,
    // `accentDeep` is the fill that carries `accentInk`, which is exactly the
    // primary/onPrimary contract. Keeping the split here means a stock
    // FilledButton is readable without any per-widget correction.
    primary: t.accentDeep,
    onPrimary: t.accentInk,
    primaryContainer: t.accentMist,
    onPrimaryContainer: t.accentText,
    secondary: t.skyDeep,
    onSecondary: isDark ? const Color(0xFF10233F) : Colors.white,
    secondaryContainer: t.skyMist,
    onSecondaryContainer: t.ink,
    tertiary: t.sage,
    onTertiary: isDark ? const Color(0xFF10231A) : Colors.white,
    tertiaryContainer: t.sageMist,
    onTertiaryContainer: t.sage,
    error: t.clay,
    onError: Colors.white,
    errorContainer: t.clay.withValues(alpha: 0.18),
    onErrorContainer: t.clay,
    surface: t.surface,
    onSurface: t.ink,
    onSurfaceVariant: t.ink2,
    surfaceContainerLowest: t.surface,
    surfaceContainerLow: t.skyWash,
    surfaceContainer: t.skyWash,
    surfaceContainerHigh: t.skyMist,
    surfaceContainerHighest: t.skyMist,
    outline: t.ink3,
    outlineVariant: t.skyMist,
    shadow: Colors.black,
    scrim: const Color(0xFF1D3E68),
    inverseSurface: t.ink,
    onInverseSurface: t.paper,
    inversePrimary: t.accent,
  );

  TextStyle body(double size, FontWeight weight, {double? height}) => TextStyle(
    fontFamily: kBodyFont,
    fontSize: size,
    fontWeight: weight,
    height: height,
    color: t.ink,
  );

  TextStyle display(double size, {double height = 1.15}) => TextStyle(
    fontFamily: kDisplayFont,
    fontSize: size,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    height: height,
    color: t.ink,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: kBodyFont,
    scaffoldBackgroundColor: t.paper,
    canvasColor: t.paper,
    splashFactory: InkSparkle.splashFactory,
    extensions: [t],
    textTheme: TextTheme(
      displayLarge: display(34),
      displayMedium: display(29, height: 1.1),
      displaySmall: display(23),
      headlineMedium: display(21, height: 1.2),
      headlineSmall: display(19),
      titleLarge: display(18),
      titleMedium: body(14, FontWeight.w800, height: 1.3),
      titleSmall: body(13.5, FontWeight.w800, height: 1.3),
      bodyLarge: body(15, FontWeight.w400, height: 1.5),
      bodyMedium: body(14, FontWeight.w400, height: 1.55),
      bodySmall: body(12.5, FontWeight.w400, height: 1.5),
      labelLarge: body(15, FontWeight.w800, height: 1.2),
      labelMedium: body(12.5, FontWeight.w700, height: 1.3),
      labelSmall: body(11.5, FontWeight.w700, height: 1.4),
    ),
    iconTheme: IconThemeData(color: t.ink, size: 22),
    dividerColor: t.skyWash,
    dividerTheme: DividerThemeData(color: t.skyWash, thickness: 1, space: 1),
    // The design has no hard 1px grid, so sheets and dialogs carry the same
    // soft radii as everything else.
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: const Color(0xFF1D3E68).withValues(alpha: 0.4),
      shape: const RoundedRectangleBorder(borderRadius: LbmRadius.sheetR),
      showDragHandle: false,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      barrierColor: const Color(0xFF1D3E68).withValues(alpha: 0.4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(26)),
      ),
      insetPadding: const EdgeInsets.all(22),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.ink,
      contentTextStyle: TextStyle(
        fontFamily: kBodyFont,
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: t.paper,
      ),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: LbmRadius.pillR),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.accent,
      selectionColor: t.accent.withValues(alpha: 0.28),
      selectionHandleColor: t.accent,
    ),
  );
}
