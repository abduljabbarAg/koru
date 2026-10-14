import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koru/theme.dart';

/// Contrast is measured, not judged by eye.
///
/// Three of the palette's colours failed WCAG AA for body text and one of them
/// was carrying a client status, which is exactly the kind of text that has to
/// be legible. These run the real arithmetic so a palette edit that darkens one
/// colour and lightens another cannot quietly put it back.
void main() {
  /// WCAG relative luminance.
  double luminance(Color c) {
    double channel(double v) {
      final c = v / 255.0;
      // Written out rather than as a ternary over `**`, which does not parse
      // the way it reads.
      if (c <= 0.04045) return c / 12.92;
      return math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  }

  double ratio(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  const backgrounds = <String, Color>{
    'cream': KoruColors.cream,
    'surface': KoruColors.surface,
  };

  group('every text colour clears 4.5:1 on every background', () {
    final textColours = <String, Color>{
      'ink': KoruColors.ink,
      'inkSoft': KoruColors.inkSoft,
      'inkFaint': KoruColors.inkFaint,
      'leaf': KoruColors.leaf,
      'clay': KoruColors.clay,
      'gold': KoruColors.gold,
    };

    textColours.forEach((name, colour) {
      backgrounds.forEach((bgName, bg) {
        test('$name on $bgName', () {
          final r = ratio(colour, bg);
          expect(
            r,
            greaterThanOrEqualTo(4.5),
            reason: '$name is only ${r.toStringAsFixed(2)}:1 on $bgName',
          );
        });
      });
    });
  });

  test('ink is still the highest contrast, so hierarchy survives', () {
    // Darkening the pale colours must not make them compete with the body text.
    expect(luminance(KoruColors.ink), lessThan(luminance(KoruColors.inkSoft)));
    expect(luminance(KoruColors.inkSoft), lessThan(luminance(KoruColors.inkFaint)));
  });

  test('the soft fills stay lighter than the text that sits on them', () {
    expect(luminance(KoruColors.leafSoft), greaterThan(luminance(KoruColors.leaf)));
    expect(luminance(KoruColors.claySoft), greaterThan(luminance(KoruColors.clay)));
    expect(luminance(KoruColors.goldSoft), greaterThan(luminance(KoruColors.gold)));
  });
}
