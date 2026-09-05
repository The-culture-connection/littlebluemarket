import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/theme/tokens.dart';

/// Relative luminance, per WCAG 2.x.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('the accent contrast split', () {
    // This is the nuance most likely to get flattened by a later edit: the
    // pure accent is too light to carry white text, so solid buttons in light
    // mode use the deeper shade instead. If someone "simplifies" accentDeep to
    // equal accent in light mode, these fail.
    test('the pure accent is NOT readable under white — hence the split', () {
      expect(
        _contrast(LbmColors.light.accent, Colors.white),
        lessThan(4.5),
        reason:
            'If this ever passes, the reason for accentDeep has gone away. '
            'Check the palette before deleting the split.',
      );
    });

    test('light mode: a solid button carries its label readably', () {
      expect(
        _contrast(LbmColors.light.accentDeep, LbmColors.light.accentInk),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('dark mode: the pure accent carries a dark plum label readably', () {
      expect(
        _contrast(LbmColors.dark.accentDeep, LbmColors.dark.accentInk),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('light and dark resolve accentDeep differently', () {
      expect(LbmColors.light.accentDeep, isNot(LbmColors.light.accent));
      expect(LbmColors.dark.accentDeep, LbmColors.dark.accent);
    });

    test('accent text on its own tint is readable in both modes', () {
      expect(
        _contrast(LbmColors.light.accentMist, LbmColors.light.accentText),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(LbmColors.dark.accentMist, LbmColors.dark.accentText),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('body ink', () {
    test('primary ink is readable on paper and on surface', () {
      for (final t in [LbmColors.light, LbmColors.dark]) {
        expect(_contrast(t.paper, t.ink), greaterThanOrEqualTo(4.5));
        expect(_contrast(t.surface, t.ink), greaterThanOrEqualTo(4.5));
      }
    });

    test('secondary ink is readable on surface', () {
      for (final t in [LbmColors.light, LbmColors.dark]) {
        expect(_contrast(t.surface, t.ink2), greaterThanOrEqualTo(4.5));
      }
    });
  });

  group('palette values', () {
    test('the accent itself is the same hue in both modes', () {
      expect(LbmColors.light.accent, const Color(0xFFD56ED1));
      expect(LbmColors.dark.accent, const Color(0xFFD56ED1));
    });

    test('paper in light mode is the welcome screen blue family', () {
      expect(LbmColors.light.paper, const Color(0xFF9CBFE3));
    });
  });
}
