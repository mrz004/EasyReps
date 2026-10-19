import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass.dart';

// Brand palette ("Fitness": Slate Blue, Fog, Aloe, Charcoal).
const Color SLATE_BLUE = Color(0xFF3D4F5A);
const Color FOG = Color(0xFFE2DECE);
const Color ALOE = Color(0xFF73795D);
const Color CHARCOAL = Color(0xFF2E2C26);

/// Muted terracotta for errors and exceeded limits (not in the palette, but
/// in its tone).
const Color TERRACOTTA = Color(0xFFA4483A);

/// Kept for code that refers to the brand colour generically.
const Color SEED_COLOR = SLATE_BLUE;

const double CARD_RADIUS = 16;
const double CONTROL_RADIUS = 14;

ColorScheme _lightScheme() => ColorScheme.fromSeed(seedColor: SLATE_BLUE).copyWith(
  primary: SLATE_BLUE,
  onPrimary: Colors.white,
  primaryContainer: const Color(0xFFD5DEE3),
  onPrimaryContainer: const Color(0xFF1C2A32),
  secondary: ALOE,
  onSecondary: Colors.white,
  secondaryContainer: const Color(0xFFDDE1CB),
  onSecondaryContainer: const Color(0xFF2B3020),
  tertiary: ALOE,
  onTertiary: Colors.white,
  surface: const Color(0xFFF4F1E8),
  onSurface: CHARCOAL,
  onSurfaceVariant: const Color(0xFF5C5A51),
  surfaceContainerLowest: const Color(0xFFFBF9F4),
  surfaceContainerLow: const Color(0xFFF1EEE4),
  surfaceContainer: const Color(0xFFECE8DD),
  surfaceContainerHigh: const Color(0xFFE6E2D5),
  surfaceContainerHighest: FOG,
  outline: const Color(0xFF8B877B),
  outlineVariant: const Color(0xFFD3CEBF),
  error: TERRACOTTA,
  onError: Colors.white,
  errorContainer: const Color(0xFFF3DAD3),
  onErrorContainer: const Color(0xFF5A1F15),
  inverseSurface: CHARCOAL,
  onInverseSurface: FOG,
);

ColorScheme _darkScheme() =>
    ColorScheme.fromSeed(seedColor: SLATE_BLUE, brightness: Brightness.dark).copyWith(
      primary: const Color(0xFFA9BDC9),
      onPrimary: const Color(0xFF1C2A32),
      primaryContainer: SLATE_BLUE,
      onPrimaryContainer: const Color(0xFFDDE6EB),
      secondary: const Color(0xFFB5BB98),
      onSecondary: const Color(0xFF2B3020),
      secondaryContainer: const Color(0xFF4C5240),
      onSecondaryContainer: const Color(0xFFE1E5CF),
      tertiary: const Color(0xFFB5BB98),
      onTertiary: const Color(0xFF2B3020),
      surface: CHARCOAL,
      onSurface: FOG,
      onSurfaceVariant: const Color(0xFFBDB8A8),
      surfaceContainerLowest: const Color(0xFF211F1A),
      surfaceContainerLow: const Color(0xFF34322B),
      surfaceContainer: const Color(0xFF3A3830),
      surfaceContainerHigh: const Color(0xFF423F37),
      surfaceContainerHighest: const Color(0xFF4A473E),
      outline: const Color(0xFF8F8A7C),
      outlineVariant: const Color(0xFF4F4C43),
      error: const Color(0xFFE29A8A),
      onError: const Color(0xFF4A170E),
      errorContainer: const Color(0xFF7A3226),
      onErrorContainer: const Color(0xFFF7DCD5),
      inverseSurface: FOG,
      onInverseSurface: CHARCOAL,
    );

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = dark ? _darkScheme() : _lightScheme();
  // Translucent "glass" surfaces over the page background (see glass.dart).
  final glassFill = dark
      ? Colors.white.withValues(alpha: 0.06)
      : Colors.white.withValues(alpha: 0.50);
  final glassBorder = dark
      ? Colors.white.withValues(alpha: 0.12)
      : Colors.white.withValues(alpha: 0.75);
  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(CONTROL_RADIUS),
  );
  const glassTransitions = GlassPageTransitionsBuilder();

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // Pages are transparent; GlassPageTransitionsBuilder paints the backdrop.
    scaffoldBackgroundColor: Colors.transparent,
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {for (final p in TargetPlatform.values) p: glassTransitions},
    ),
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      // The app bar is transparent, so pick status bar icons by theme.
      systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      // ThemeData text styles get their sizes only at runtime, so set it here.
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: glassFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CARD_RADIUS),
        side: BorderSide(color: glassBorder),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: glassFill,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    chipTheme: ChipThemeData(backgroundColor: glassFill),
    dialogTheme: DialogThemeData(backgroundColor: scheme.surfaceContainerLowest),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: scheme.surfaceContainerLowest),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: controlShape,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: controlShape,
        backgroundColor: glassFill,
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CARD_RADIUS),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Capitalises each word: "middle back" -> "Middle Back".
String titleCase(String text) => text
    .split(' ')
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
    .join(' ');
