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
    // Color.r/g/b are 0..1 doubles on current Flutter, not 0..255. Dividing
    // by 255 again collapsed every channel to near zero and every pair of
    // colours to a ratio of 1, which is how this test passed while measuring
    // nothing.
    double channel(double v) {
      if (v <= 0.04045) return v / 12.92;
      return math.pow((v + 0.055) / 1.055, 2.4).toDouble();
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

  final backgrounds = <String, Color>{
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

  group('the dark palette is measured too', () {
    // Every dark value was chosen by running this arithmetic rather than by
    // looking at it. A colour that clears 4.5:1 on cream fails badly on
    // near-black, and the ink colours invert completely.
    const dark = KoruPalette.dark;

    test('every dark text colour clears 4.5:1 on the dark surface', () {
      final colours = <String, Color>{
        'ink': dark.ink,
        'inkSoft': dark.inkSoft,
        'inkFaint': dark.inkFaint,
        'leaf': dark.leaf,
        'clay': dark.clay,
        'gold': dark.gold,
      };
      colours.forEach((name, colour) {
        final r = ratio(colour, dark.surface);
        expect(r, greaterThanOrEqualTo(4.5),
            reason: 'dark $name is ${r.toStringAsFixed(2)}:1 on the surface');
      });
    });

    test('light and dark really are different palettes', () {
      // If these ever matched, the app would look the same in both and the
      // whole set of dark values would be decoration.
      expect(luminance(KoruPalette.dark.cream),
          lessThan(luminance(KoruPalette.light.cream)),
          reason: 'the background inverts');
      expect(luminance(KoruPalette.dark.ink),
          greaterThan(luminance(KoruPalette.light.ink)),
          reason: 'the text inverts');
    });

    test('a soft fill separates from the accent sitting on it', () {
      // The fill inverts with the mode, which is the whole point: in the light
      // palette leafSoft is lighter than the text printed on it, in the dark
      // palette it is darker. Pinning the direction stops somebody "fixing" one
      // of them to look like the other and losing the chip.
      expect(luminance(KoruPalette.light.leafSoft),
          greaterThan(luminance(KoruPalette.light.leaf)));
      expect(luminance(KoruPalette.dark.leafSoft),
          lessThan(luminance(KoruPalette.dark.leaf)));

      // And in both, the accent on its own fill is readable.
      for (final p in [KoruPalette.light, KoruPalette.dark]) {
        expect(ratio(p.leaf, p.leafSoft), greaterThanOrEqualTo(4.5),
            reason: 'accent on its own fill');
      }
    });
  });

  group('the app-wide palette follows the system', () {
    test('setBrightness switches what KoruColors hands out', () {
      addTearDown(() => KoruColors.setBrightness(Brightness.light));
      final lightInk = KoruColors.ink;
      final lightCream = KoruColors.cream;

      KoruColors.setBrightness(Brightness.dark);
      expect(KoruColors.ink, isNot(lightInk));
      expect(KoruColors.cream, isNot(lightCream));
      // Light on dark. If this ever inverts, every screen reads as blank.
      expect(luminance(KoruColors.ink), greaterThan(luminance(KoruColors.cream)));

      KoruColors.setBrightness(Brightness.light);
      expect(KoruColors.ink, lightInk);
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
