import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/models/brand_tints.dart';
import 'package:little_blue_market/theme/app_theme.dart';
import 'package:little_blue_market/theme/tokens.dart';

/// The Little Blue Cart brand guide (2026-10-22): eight colours and two
/// fonts, and "nothing outside of it".
///
/// A colour passes if its RGB is a guide colour, white, or one of the
/// declared tints in [LbmPalette.mixes]; any alpha is allowed, because a
/// guide colour made see-through is still that colour. These tests read the
/// tokens and the source, so a stray hex or a third font fails here rather
/// than reaching a screen.
void main() {
  final allowed = {
    for (final c in [...LbmPalette.brand, ...LbmPalette.mixes])
      c.toARGB32() & 0xFFFFFF,
  };
  bool onBrand(Color c) => allowed.contains(c.toARGB32() & 0xFFFFFF);
  String hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  group('colours', () {
    test('every token in both themes is a brand colour', () {
      for (final (name, t) in [
        ('light', LbmColors.light),
        ('dark', LbmColors.dark),
      ]) {
        final colours = {
          'paper': t.paper,
          'surface': t.surface,
          'scrim': t.scrim,
          'ink': t.ink,
          'ink2': t.ink2,
          'ink3': t.ink3,
          'sky': t.sky,
          'skyDeep': t.skyDeep,
          'skyMist': t.skyMist,
          'skyWash': t.skyWash,
          'accent': t.accent,
          'accentDeep': t.accentDeep,
          'accentInk': t.accentInk,
          'accentMist': t.accentMist,
          'accentText': t.accentText,
          'sage': t.sage,
          'sageMist': t.sageMist,
          'clay': t.clay,
          'cardStock': t.cardStock,
          for (final s in [...t.shadowSoft, ...t.shadowLift]) 'shadow': s.color,
          for (final g in [...t.heroGradient, ...t.shoutoutGradient])
            'gradient': g,
        };
        for (final MapEntry(:key, :value) in colours.entries) {
          expect(onBrand(value), isTrue, reason: '$name.$key is ${hex(value)}');
        }
      }
    });

    test('the fixed colours and avatar tints are brand colours', () {
      for (final c in [
        LbmConst.slate,
        LbmConst.artInk,
        LbmConst.welcomeBlue,
        LbmConst.onWelcome,
        LbmConst.chatInk,
        LbmConst.onGradient,
        LbmConst.splashBlue,
        ...LbmConst.makerTints,
        for (final t in kAvatarTints) Color(t),
      ]) {
        expect(onBrand(c), isTrue, reason: hex(c));
      }
    });

    test('the data layer and the widgets hand out the same tints', () {
      expect(
        LbmConst.makerTints.map((c) => c.toARGB32()).toList(),
        kAvatarTints,
      );
      for (final id in ['a', 'uid_123', 'qa_seed_maya', 'Flybabies']) {
        expect(LbmConst.makerTintFor(id).toARGB32(), avatarTintFor(id));
      }
    });

    test('a tint from the old palette is drawn in a brand colour', () {
      // 0xFF5C8FCB was the first of the old avatar tints.
      expect(kAvatarTints, contains(brandTint(0xFF5C8FCB, 'someone')));
      expect(brandTint(0xFFD270D1, 'someone'), 0xFFD270D1);
      expect(kAvatarTints, contains(brandTint(null, 'someone')));
    });

    test('initials are readable on every avatar tint', () {
      for (final tint in LbmConst.makerTints) {
        final ink = LbmConst.initialsOn(tint);
        expect(
          _contrast(tint, ink),
          greaterThanOrEqualTo(3.0),
          reason: 'initials on ${hex(tint)}',
        );
      }
    });

    test('no colour in the app source is outside the guide', () {
      // Any 0xAARRGGBB literal and any named Material colour, in every Dart
      // file the app ships. The QA suite's own markings (lib/qa) belong to
      // the testing tool, not the app, and the Firebase settings file holds
      // no colours.
      final literal = RegExp(r'0x([0-9A-Fa-f]{2})([0-9A-Fa-f]{6})\b');
      // Flutter's Colors, not LbmColors.
      final named = RegExp(r'(?<![A-Za-z])Colors\.(\w+)');
      final problems = <String>[];
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final path = file.path.replaceAll(r'\', '/');
        if (path.startsWith('lib/qa/') ||
            path.endsWith('firebase_options.dart')) {
          continue;
        }
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          for (final m in literal.allMatches(line)) {
            // Hash masks such as `& 0x7fffffff` are arithmetic, not colour.
            if (line.contains('& ${m.group(0)}')) continue;
            final rgb = int.parse(m.group(2)!, radix: 16);
            if (!allowed.contains(rgb)) {
              problems.add('$path:${i + 1} ${m.group(0)}');
            }
          }
          for (final m in named.allMatches(line)) {
            if (m.group(1) == 'transparent' || m.group(1) == 'white') continue;
            problems.add('$path:${i + 1} Colors.${m.group(1)}');
          }
        }
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  });

  group('fonts', () {
    test('the theme uses the two brand fonts', () {
      expect(kDisplayFont, 'Playfair Display');
      expect(kBodyFont, 'Montserrat');
    });

    test('the app bundles those two families and no others', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final families = RegExp(
        r'^\s+- family: (.+)$',
        multiLine: true,
      ).allMatches(pubspec).map((m) => m.group(1)!.trim()).toSet();
      expect(families, {'Playfair Display', 'Montserrat'});
    });

    test('no screen names a font of its own', () {
      final problems = <String>[];
      final named = RegExp(r'''fontFamily:\s*['"]''');
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (named.hasMatch(lines[i])) problems.add('${file.path}:${i + 1}');
        }
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  });
}

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
