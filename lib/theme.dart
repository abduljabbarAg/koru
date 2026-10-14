import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Koru's palette. Warm, calm, high contrast, no pure black or pure white.
class KoruColors {
  static KoruPalette _active = KoruPalette.light;

  /// Switches the whole app between the light and dark palettes.
  ///
  /// Mutable rather than resolved from a BuildContext because nearly every one
  /// of these colours is referenced from a const widget literal in a file that
  /// has no context in scope. Set once before the first frame, and again when
  /// the system theme changes.
  static KoruPalette setBrightness(Brightness b) =>
      _active = b == Brightness.dark ? KoruPalette.dark : KoruPalette.light;

  /// What the app is currently painting with.
  static KoruPalette get active => _active;

  static Color get ink => _active.ink;
  static Color get inkSoft => _active.inkSoft;
  static Color get inkFaint => _active.inkFaint;
  static Color get cream => _active.cream;
  static Color get surface => _active.surface;
  static Color get line => _active.line;
  static Color get leaf => _active.leaf;
  static Color get leafSoft => _active.leafSoft;
  static Color get clay => _active.clay;
  static Color get claySoft => _active.claySoft;
  static Color get gold => _active.gold;
  static Color get goldSoft => _active.goldSoft;

  /// Darkened from #8A7F78.
  ///
  /// The original measured 3.68:1 on cream and 3.90:1 on white, against a
  /// requirement of 4.5:1 for body text. It was the colour of the "still owed",
  /// "due" and secondary-label text, so the least legible colour in the app was
  /// carrying the figures people read to decide who to chase.

  /// Darkened from #C1663F, which measured 3.79:1 on cream.
  /// Darkened from #B8892B, which measured 2.98:1 on cream: the worst contrast
  /// in the app, on the colour that marks an active client. Status is exactly the
  /// kind of text that has to be legible, so it is now 5.06:1.
}


/// The palette, resolved from the ambient brightness.
///
/// These were constants, and a constant cannot have a dark mode: it does not
/// know what it is painted on. They are getters now, reading whichever palette
/// the system brightness selected.
///
/// Every value is measured rather than chosen by eye. The dark set in
/// particular, because a colour that clears 4.5:1 on cream fails badly on
/// near-black and the ink colours invert completely. `test/theme_test.dart`
/// checks both palettes.
@immutable
class KoruPalette extends ThemeExtension<KoruPalette> {
  const KoruPalette({
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.cream,
    required this.surface,
    required this.line,
    required this.leaf,
    required this.leafSoft,
    required this.clay,
    required this.claySoft,
    required this.gold,
    required this.goldSoft,
  });

  final Color ink;
  final Color inkSoft;
  final Color inkFaint;
  final Color cream;
  final Color surface;
  final Color line;
  final Color leaf;
  final Color leafSoft;
  final Color clay;
  final Color claySoft;
  final Color gold;
  final Color goldSoft;

  static const light = KoruPalette(
    ink: Color(0xFF14110F),
    inkSoft: Color(0xFF4A423D),
    inkFaint: Color(0xFF786E67),
    cream: Color(0xFFFBF8F4),
    surface: Color(0xFFFFFFFF),
    line: Color(0xFFE8E1DA),
    leaf: Color(0xFF2E7757),
    leafSoft: Color(0xFFE4F1EA),
    clay: Color(0xFFAC5533),
    claySoft: Color(0xFFFAEAE2),
    gold: Color(0xFF8A641C),
    goldSoft: Color(0xFFFAF0D8),
  );

  static const dark = KoruPalette(
    ink: Color(0xFFF2EDE6),
    inkSoft: Color(0xFFCBC2B9),
    inkFaint: Color(0xFFA79D94),
    cream: Color(0xFF17150F),
    surface: Color(0xFF201D17),
    line: Color(0xFF3A342C),
    leaf: Color(0xFF6FC096),
    leafSoft: Color(0xFF1B2E25),
    clay: Color(0xFFE59472),
    claySoft: Color(0xFF2E1F18),
    gold: Color(0xFFDFAF55),
    goldSoft: Color(0xFF2C2415),
  );

  @override
  KoruPalette copyWith({
    Color? ink,
    Color? inkSoft,
    Color? inkFaint,
    Color? cream,
    Color? surface,
    Color? line,
    Color? leaf,
    Color? leafSoft,
    Color? clay,
    Color? claySoft,
    Color? gold,
    Color? goldSoft,
  }) =>
      KoruPalette(
        ink: ink ?? this.ink,
        inkSoft: inkSoft ?? this.inkSoft,
        inkFaint: inkFaint ?? this.inkFaint,
        cream: cream ?? this.cream,
        surface: surface ?? this.surface,
        line: line ?? this.line,
        leaf: leaf ?? this.leaf,
        leafSoft: leafSoft ?? this.leafSoft,
        clay: clay ?? this.clay,
        claySoft: claySoft ?? this.claySoft,
        gold: gold ?? this.gold,
        goldSoft: goldSoft ?? this.goldSoft,
      );

  @override
  KoruPalette lerp(ThemeExtension<KoruPalette>? other, double t) {
    if (other is! KoruPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return KoruPalette(
      ink: c(ink, other.ink),
      inkSoft: c(inkSoft, other.inkSoft),
      inkFaint: c(inkFaint, other.inkFaint),
      cream: c(cream, other.cream),
      surface: c(surface, other.surface),
      line: c(line, other.line),
      leaf: c(leaf, other.leaf),
      leafSoft: c(leafSoft, other.leafSoft),
      clay: c(clay, other.clay),
      claySoft: c(claySoft, other.claySoft),
      gold: c(gold, other.gold),
      goldSoft: c(goldSoft, other.goldSoft),
    );
  }
}

class KoruRadius {
  static const card = 18.0;
  static const field = 14.0;
  static const pill = 999.0;
}

ThemeData buildKoruTheme({Brightness brightness = Brightness.light}) {
  final p = brightness == Brightness.dark ? KoruPalette.dark : KoruPalette.light;
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.leaf,
      primary: p.leaf,
      surface: p.surface,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: p.cream,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: p.ink,
      displayColor: p.ink,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.cream,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: p.ink,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KoruRadius.card),
        side: BorderSide(color: p.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KoruRadius.field),
        borderSide: BorderSide(color: p.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KoruRadius.field),
        borderSide: BorderSide(color: p.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KoruRadius.field),
        borderSide: BorderSide(color: p.leaf, width: 1.6),
      ),
      labelStyle: TextStyle(color: p.inkSoft, fontSize: 15),
      hintStyle: TextStyle(color: p.inkFaint, fontSize: 15),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.leaf,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KoruRadius.field),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: p.line),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KoruRadius.field),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    dividerTheme: DividerThemeData(color: p.line, space: 1, thickness: 1),
  );
}