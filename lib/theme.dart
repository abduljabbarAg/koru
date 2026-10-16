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
  static Color get surfaceAlt => _active.surfaceAlt;
  static Color get onAccent => _active.onAccent;
  static Color get shadow => _active.shadow;

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
    required this.surfaceAlt,
    required this.onAccent,
    required this.shadow,
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
  final Color surfaceAlt;
  final Color onAccent;
  final Color shadow;

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
    surfaceAlt: Color(0xFFEFEBE7),
    onAccent: Color(0xFFFFFFFF),
    shadow: Color(0x14000000),
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
    surfaceAlt: Color(0xFF2C2820),
    onAccent: Color(0xFF14110F),
    shadow: Color(0x40000000),
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
    Color? surfaceAlt,
    Color? onAccent,
    Color? shadow,
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
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        onAccent: onAccent ?? this.onAccent,
        shadow: shadow ?? this.shadow,
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
      surfaceAlt: c(surfaceAlt, other.surfaceAlt),
      onAccent: c(onAccent, other.onAccent),
      shadow: c(shadow, other.shadow),
    );
  }
}

/// Icon and touch sizes.
///
/// Small, but they are the numbers that decide whether two screens look like
/// one app: the badge beside a row, the icon inside a notice, and the smallest
/// thing a thumb is expected to hit.
class KoruSize {
  /// The leading square on a row. Also what today.dart's row inset is built
  /// from, so changing this moves the separators on the Today screen with it.
  static const badge = 34.0;

  /// An icon beside running text.
  static const icon = 18.0;

  /// An icon beside a label, or in a button.
  static const iconSm = 16.0;

  /// The smallest comfortable tap target.
  static const touch = 44.0;

  /// The height of a full-width button.
  static const button = 52.0;

  /// The height of a button inside a card, where there is no need to shout.
  static const buttonInCard = 44.0;
}

/// Every corner in the app is one of these.
///
/// Before this there were 8, 10, 12, 14, 16, 18, 22, 24 and 999 in use,
/// which is what a screen full of one-off boxes looks like. The scale is now
/// four shapes: a small inner corner, the field and chip corners, the card
/// corner everything visible sits on, and the pill. Geometry is the cheapest
/// way to make two screens look like one app.
class KoruRadius {
  /// Inside a card: chips in a panel, a nested block.
  static const xs = 10.0;

  /// A nested block inside a card.
  static const sm = 14.0;

  /// Text fields, buttons and selectable rows.
  static const field = 16.0;

  /// A chat bubble.
  static const bubble = 20.0;

  /// The corner on every card in the app.
  static const card = 22.0;

  /// A bottom sheet, and the sheet that rises out of one.
  static const sheet = 28.0;

  /// A status pill, a tag, anything that is its own outline.
  static const pill = 999.0;
}

/// The spacing scale, plus the four gaps that repeat on every screen.
///
/// The app used to space itself with whatever number was nearest: 8, 10, 12,
/// 14, 16, 18, 20, 22, 24 and a scattering of 6. Nothing about those numbers
/// said anything, so two screens built by two people a week apart never lined
/// up. Everything here is on a four-pixel grid with one two-pixel step for the
/// inside of a pill.
class KoruSpace {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;

  /// The left and right edge of a scrolling screen.
  ///
  /// Wider than the sixteen most of the app used. On a phone that is the
  /// difference between a list that is asking to be read and a list that is
  /// pressed against the bezel.
  static const gutter = 20.0;

  /// Between one section and the next.
  static const section = 24.0;

  /// Inside a card that holds a form or a readout.
  static const card = 16.0;

  /// Inside a row in a grouped list.
  static const row = 16.0;

  /// Below the last thing on a screen, so nothing sits on the edge.
  static const tail = 40.0;

  /// The space left at the bottom of a screen with a floating action button.
  static const aboveFab = 92.0;
}

/// Depth.
///
/// Two rules, and they are what stops a card looking like a sticker. A surface
/// never goes darker than [KoruColors.surface] — depth comes from the shadow,
/// not from a second grey — and the shadow is only ever the palette's own
/// `shadow`, which already differs between the two brightnesses. Three levels,
/// used the same way on every screen: a card resting on the page, something
/// floating above it, and something under a finger.
class KoruElevation {
  /// Content that sits flat in the page flow, separated by a hairline.
  static List<BoxShadow> get none => const <BoxShadow>[];

  /// A card on the page.
  static List<BoxShadow> get low => <BoxShadow>[
        BoxShadow(
          color: KoruColors.shadow,
          blurRadius: 10,
          spreadRadius: -4,
          offset: const Offset(0, 2),
        ),
      ];

  /// Something that floats: a sheet, a menu, a floating action button.
  static List<BoxShadow> get raised => <BoxShadow>[
        BoxShadow(
          color: KoruColors.shadow,
          blurRadius: 22,
          spreadRadius: -6,
          offset: const Offset(0, 8),
        ),
      ];

  /// Under a press.
  static List<BoxShadow> get pressed => <BoxShadow>[
        BoxShadow(
          color: KoruColors.shadow,
          blurRadius: 4,
          spreadRadius: -2,
          offset: const Offset(0, 1),
        ),
      ];
}

/// The type scale, named by the job a piece of text does rather than by its
/// size.
///
/// Every screen picked its own font sizes, and the app ended up with twenty-one
/// of them, two of which differed from their neighbour by half a pixel. A named
/// role means a screen asks for "a row title" and gets the same thing every
/// other row title in the app gets.
///
/// The sizes are chosen so that the two screens already redesigned — Today and
/// Settings — render at exactly the sizes listed here, which is why this scale
/// is 28/22/30/24/16/15/13.5/12.5/11/10.5 and not a prettier set of round
/// numbers.
class KoruType {
  /// The name of a screen. 28, bold, tight.
  static TextStyle get display => TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.9,
        height: 1.12,
        color: KoruColors.ink,
      );

  /// A bar title, or the title on a sheet.
  static TextStyle get title => TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.2,
        color: KoruColors.ink,
      );

  /// A sheet title. Smaller than a bar title, because a sheet is not a
  /// destination.
  static TextStyle get sheetTitle => TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        height: 1.25,
        color: KoruColors.ink,
      );

  /// The one figure a screen is about.
  static TextStyle get metric => TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        height: 1.1,
        color: KoruColors.ink,
      );

  /// A figure in a row of tiles. A step below [metric].
  static TextStyle get stat => TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        height: 1.15,
        color: KoruColors.ink,
      );

  /// The name of a client, a deadline, a project.
  static TextStyle get rowTitle => TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: KoruColors.ink,
      );

  /// The same, one step down, for rows that are already dense — a calendar
  /// entry, a payment line.
  static TextStyle get rowTitleCompact => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: KoruColors.ink,
      );

  /// A paragraph the reader is expected to read: a reply, a note, an
  /// explanation.
  static TextStyle get body => TextStyle(
        fontSize: 15,
        height: 1.45,
        color: KoruColors.inkSoft,
      );

  /// A paragraph in `ink`, where it is the content rather than the support.
  static TextStyle get bodyStrong => TextStyle(
        fontSize: 15,
        height: 1.45,
        color: KoruColors.ink,
      );

  /// A second paragraph: the small print under a control.
  static TextStyle get bodySmall => TextStyle(
        fontSize: 13.5,
        height: 1.4,
        color: KoruColors.inkFaint,
      );

  /// Metadata on a row: a date, a figure, where a client came from.
  static TextStyle get meta => TextStyle(
        fontSize: 12.5,
        height: 1.35,
        color: KoruColors.inkFaint,
      );

  /// The small caption that completes a card.
  static TextStyle get caption => TextStyle(
        fontSize: 13,
        height: 1.4,
        color: KoruColors.inkFaint,
      );

  /// Above a section. Uppercase, tracked out, never a sentence.
  static TextStyle get label => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        height: 1.2,
        color: KoruColors.inkFaint,
      );

  /// The least text there is: a clock in a chat bubble.
  static TextStyle get micro => TextStyle(
        fontSize: 10.5,
        height: 1.2,
        color: KoruColors.inkFaint,
      );

  /// A button, and anything that behaves like one.
  static TextStyle get button => TextStyle(
        fontSize: 15.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        height: 1.2,
        color: KoruColors.ink,
      );

  /// A pill, a badge, a chip.
  static TextStyle get badge => TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        height: 1.2,
        color: KoruColors.ink,
      );
}

/// How long things take.
///
/// One curve for anything arriving and one for anything leaving, and one
/// duration for both. Motion in this app is confirmation, not choreography: it
/// says "this happened" and then it is over.
class KoruMotion {
  /// A state change the reader should not notice as motion.
  static const quick = Duration(milliseconds: 140);

  /// The screen or a card arriving.
  static const settle = Duration(milliseconds: 420);

  /// The one curve anything moving in uses.
  static const easeOut = Curves.easeOutCubic;
}

/// Builds the corner and the hairline a card is made of.
///
/// One function rather than the shape written out at each of the forty places
/// a card is built, because a card that is 18 in one place and 22 in another
/// is the single most obvious way for an app to look assembled rather than
/// designed.
class KoruSurfaces {
  /// The rounded outline every card shares.
  ///
  /// [line] is taken rather than read from [KoruColors] so the theme can be built
  /// for the dark palette before the app-wide palette has caught up with it,
  /// which it has not at the moment `darkTheme` is constructed.
  static RoundedRectangleBorder card({Color? line}) => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KoruRadius.card),
        side: KoruBorders.hairline(line),
      );
}

/// The borders in the app: a hairline between rows, and an accent outline for a
/// card whose colour is carrying meaning.
class KoruBorders {
  /// The separator. Null reads the app-wide palette, which is what a widget
  /// wants; pass a colour when building a theme for a palette that is not active
  /// yet.
  static BorderSide hairline([Color? line]) =>
      BorderSide(color: line ?? KoruColors.line);

  /// An accent outline, softened so it reads as a tint rather than a box.
  static BorderSide accent(Color colour) =>
      BorderSide(color: colour.withValues(alpha: 0.45));

  /// The outline on a selected row.
  static BorderSide selected([Color? leaf]) => BorderSide(
        color: leaf ?? KoruColors.leaf,
        width: 1.6,
      );
}

ThemeData buildKoruTheme({Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  final p = dark ? KoruPalette.dark : KoruPalette.light;

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.leaf,
      primary: p.leaf,
      surface: p.surface,
      brightness: brightness,
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
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: p.ink,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      iconTheme: IconThemeData(color: p.ink, size: 22),
      // Follows the palette rather than assuming a light phone: a light status
      // bar over the dark palette put white icons on a near-black bar.
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: p.surface,
        systemNavigationBarIconBrightness:
            dark ? Brightness.light : Brightness.dark,
      ),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: KoruSurfaces.card(line: p.line),
    ),
    dividerTheme: DividerThemeData(
      color: p.line,
      space: 1,
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: KoruSpace.lg,
        vertical: KoruSpace.md + 2,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KoruRadius.field),
        borderSide: KoruBorders.hairline(p.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KoruRadius.field),
        borderSide: KoruBorders.hairline(p.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KoruRadius.field),
        borderSide: KoruBorders.selected(p.leaf),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KoruRadius.field),
        borderSide: BorderSide(color: p.clay),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KoruRadius.field),
        borderSide: BorderSide(color: p.clay, width: 1.6),
      ),
      labelStyle: TextStyle(color: p.inkSoft, fontSize: 15),
      hintStyle: TextStyle(color: p.inkFaint, fontSize: 15),
      helperStyle: TextStyle(color: p.inkFaint, fontSize: 12.5, height: 1.35),
      helperMaxLines: 2,
      floatingLabelStyle: TextStyle(
        color: p.leaf,
        fontWeight: FontWeight.w600,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.leaf,
        // The palette's own accent foreground, not a hard-coded white. In the
        // dark palette the brand green is light, and white on it measured 1.9:1.
        foregroundColor: p.onAccent,
        minimumSize: const Size.fromHeight(KoruSize.button),
        padding: const EdgeInsets.symmetric(horizontal: KoruSpace.xl),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KoruRadius.field),
        ),
        textStyle: KoruType.button.copyWith(color: p.onAccent),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        minimumSize: const Size.fromHeight(KoruSize.button),
        side: KoruBorders.hairline(p.line),
        padding: const EdgeInsets.symmetric(horizontal: KoruSpace.xl),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KoruRadius.field),
        ),
        textStyle: KoruType.button,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.leaf,
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KoruRadius.pill),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: p.inkFaint),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.leaf,
      foregroundColor: p.onAccent,
      elevation: 3,
      focusElevation: 3,
      hoverElevation: 4,
      highlightElevation: 6,
      extendedTextStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KoruRadius.field),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.leaf,
      titleTextStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: p.ink,
      ),
      subtitleTextStyle: TextStyle(
        fontSize: 12.5,
        height: 1.35,
        color: p.inkFaint,
      ),
      minVerticalPadding: KoruSpace.md,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: KoruSpace.lg,
        vertical: KoruSpace.xs,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KoruRadius.field),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surface,
      selectedColor: p.leafSoft,
      side: KoruBorders.hairline(p.line),
      showCheckmark: false,
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: p.inkSoft,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: KoruSpace.md,
        vertical: KoruSpace.sm,
      ),
      shape: const StadiumBorder(),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: p.ink,
      ),
      contentTextStyle: TextStyle(
        fontSize: 14.5,
        height: 1.45,
        color: p.inkSoft,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KoruRadius.sheet),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.cream,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: p.shadow,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KoruRadius.sheet),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.ink,
      contentTextStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: p.cream,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KoruRadius.field),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.leaf,
      inactiveTrackColor: p.surfaceAlt,
      thumbColor: p.leaf,
      overlayColor: p.leaf.withValues(alpha: 0.12),
      trackHeight: 6,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.leaf,
      linearTrackColor: p.surfaceAlt,
      circularTrackColor: p.surfaceAlt,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KoruRadius.field),
        side: KoruBorders.hairline(p.line),
      ),
      textStyle: TextStyle(fontSize: 14.5, color: p.ink),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? p.onAccent
            : p.surface,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? p.leaf
            : p.surfaceAlt,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.transparent
            : p.line,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: p.ink,
        borderRadius: BorderRadius.circular(KoruRadius.xs),
      ),
      textStyle: TextStyle(fontSize: 12, color: p.cream),
    ),
  );
}