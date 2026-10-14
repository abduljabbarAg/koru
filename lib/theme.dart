import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Koru's palette. Warm, calm, high contrast, no pure black or pure white.
class KoruColors {
  static const ink = Color(0xFF14110F);
  static const inkSoft = Color(0xFF4A423D);
  /// Darkened from #8A7F78.
  ///
  /// The original measured 3.68:1 on cream and 3.90:1 on white, against a
  /// requirement of 4.5:1 for body text. It was the colour of the "still owed",
  /// "due" and secondary-label text, so the least legible colour in the app was
  /// carrying the figures people read to decide who to chase.
  static const inkFaint = Color(0xFF786E67);
  static const cream = Color(0xFFFBF8F4);
  static const surface = Color(0xFFFFFFFF);
  static const line = Color(0xFFE8E1DA);

  static const leaf = Color(0xFF2F7A5A);
  static const leafSoft = Color(0xFFE4F1EA);
  /// Darkened from #C1663F, which measured 3.79:1 on cream.
  static const clay = Color(0xFFAC5533);
  static const claySoft = Color(0xFFFAEAE2);
  /// Darkened from #B8892B, which measured 2.98:1 on cream: the worst contrast
  /// in the app, on the colour that marks an active client. Status is exactly the
  /// kind of text that has to be legible, so it is now 5.06:1.
  static const gold = Color(0xFF8A641C);
  static const goldSoft = Color(0xFFFAF0D8);
}

class KoruRadius {
  static const card = 18.0;
  static const field = 14.0;
  static const pill = 999.0;
}

ThemeData buildKoruTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: KoruColors.leaf,
      primary: KoruColors.leaf,
      surface: KoruColors.surface,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: KoruColors.cream,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: KoruColors.ink,
      displayColor: KoruColors.ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: KoruColors.cream,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: KoruColors.ink,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    ),
    cardTheme: CardThemeData(
      color: KoruColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KoruRadius.card),
        side: const BorderSide(color: KoruColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: KoruColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KoruRadius.field),
        borderSide: const BorderSide(color: KoruColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KoruRadius.field),
        borderSide: const BorderSide(color: KoruColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KoruRadius.field),
        borderSide: const BorderSide(color: KoruColors.leaf, width: 1.6),
      ),
      labelStyle: const TextStyle(color: KoruColors.inkSoft, fontSize: 15),
      hintStyle: const TextStyle(color: KoruColors.inkFaint, fontSize: 15),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: KoruColors.leaf,
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
        foregroundColor: KoruColors.ink,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: KoruColors.line),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KoruRadius.field),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    dividerTheme: const DividerThemeData(color: KoruColors.line, space: 1, thickness: 1),
  );
}