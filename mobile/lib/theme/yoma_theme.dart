import 'package:flutter/material.dart';

/// Design tokens: the Stitch design system "Clinical Field Resilience"
/// (`docs/design/stitch/design-system/DESIGN.md`). Every colour in the app comes from
/// here; no hex values anywhere else in `lib/`.
///
/// Brand roles: primary (actions, Emergency referral, active and focus states, timeline
/// markers), secondary (secondary emphasis, selected chips), tertiary (links, information,
/// pulse rings in lighter tints), neutral (text, dark cards and strips). Greys and tints
/// are the ones the design system names. Triage colours ([TriageColors]) are for the risk
/// level and emergency/destructive actions only.
abstract final class YomaColors {
  // Brand (design system overrides).
  static const primary = Color(0xFF0F2744);
  static const secondary = Color(0xFF1B3B6F);
  static const tertiary = Color(0xFF2C5E8A);
  static const neutral = Color(0xFF0B192C);
  static const onPrimary = Color(0xFFFFFFFF);

  // Tonal scale (design system).
  static const primaryPressed = Color(0xFF001229); // tonal "primary"
  static const primaryContainer = Color(0xFFE7EEFF); // "surface-container"
  static const containerLow = Color(0xFFF0F3FF); // "surface-container-low"
  static const secondaryTint = Color(0xFFD8E2FF); // "secondary-fixed": selected chips
  static const tertiaryTint = Color(0xFF9CCBFD); // "tertiary-fixed-dim": pulse rings
  static const onDark = Color(0xFFEBF1FF); // "inverse-on-surface": muted text on neutral
  static const outline = Color(0xFF74777E);
  static const outlineVariant = Color(0xFFC4C6CE);
  static const onSurface = Color(0xFF0E1C2F);

  // Surfaces and slate greys named in the design system.
  static const canvas = Color(0xFFF9F9FF); // "background"
  static const surface = Color(0xFFFFFFFF);
  static const panel = Color(0xFFF1F5F9);
  static const line = Color(0xFFE2E8F0);
  static const border = Color(0xFFCBD5E1);
  static const slate600 = Color(0xFF475569);
  static const slate700 = Color(0xFF334155);

  // Error (design system "error"): failures and destructive actions, not risk level.
  static const error = Color(0xFFBA1A1A);

  // Names the screens already use, mapped onto the design system.
  static const brand = primary;
  static const brandPressed = primaryPressed;
  static const brandTint = primaryContainer;
  static const navy = neutral; // dark cards and strips
  static const grey100 = panel;
  static const grey200 = line;
  static const grey300 = border;
  static const grey400 = outlineVariant; // decorative dots only, never text
  static const grey500 = outline; // large text and borders only (4.48:1 on white)
  static const grey600 = slate600;
  static const grey700 = slate700;
  static const grey800 = onSurface;
  static const grey900 = neutral;
  // Notices that are not a risk level (retries, sync): tertiary, never amber.
  static const warning = tertiary;
  static const caution = tertiary;
  static const danger = error;
}

/// RED / AMBER / GREEN (design system triage values), for the MOEWS risk level and for
/// emergency or destructive actions only.
abstract final class TriageColors {
  static const red = Color(0xFFC5221F); // white text 5.80:1
  static const amber = Color(0xFFB45309); // white text 5.02:1
  static const green = Color(0xFF15803D); // white text 5.02:1
  static const onRed = YomaColors.onPrimary;
  static const onAmber = YomaColors.onPrimary;
  static const onGreen = YomaColors.onPrimary;

  // Incomplete: grey card with a dashed border.
  static const incompleteFill = YomaColors.panel;
  static const incompleteBorder = YomaColors.outline; // non-text, 4.48:1 on white
  static const onIncomplete = YomaColors.neutral;
}

abstract final class YomaSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// Screen side gutter.
  static const gutter = 16.0;
}

abstract final class YomaRadii {
  static const sm = 8.0;
  static const md = 12.0; // buttons, inputs, chips, small cards
  static const lg = 16.0; // large cards
  static const pill = 999.0;
}

abstract final class YomaSizes {
  /// Smallest tap target anywhere.
  static const minTap = 48.0;
  static const primaryButton = 56.0;
  static const chip = 52.0;
  static const chipLarge = 58.0; // the referral form's emergency types
}

abstract final class YomaShadows {
  /// Tailwind shadow-sm.
  static const sm = [
    BoxShadow(color: Color(0x0D0B192C), blurRadius: 2, offset: Offset(0, 1)), // neutral 5%
  ];

  /// Tailwind shadow-md, for risk cards and the primary call to action.
  static const md = [
    BoxShadow(color: Color(0x140B192C), blurRadius: 6, offset: Offset(0, 4), spreadRadius: -1),
    BoxShadow(color: Color(0x0F0B192C), blurRadius: 4, offset: Offset(0, 2), spreadRadius: -2),
  ];
}

/// Bundled as an app asset (see pubspec.yaml); never fetched at runtime.
const yomaFontFamily = 'AtkinsonHyperlegibleNext';

/// Type scale from the Result design's Tailwind config.
abstract final class YomaType {
  static const headlineLg = TextStyle(fontSize: 26, height: 34 / 26, fontWeight: FontWeight.w700);
  static const headlineMd = TextStyle(fontSize: 22, height: 30 / 22, fontWeight: FontWeight.w700);
  static const headlineSm = TextStyle(fontSize: 19, height: 26 / 19, fontWeight: FontWeight.w600);
  static const bodyLg = TextStyle(fontSize: 18, height: 28 / 18, fontWeight: FontWeight.w400);
  static const bodyMd = TextStyle(fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w400);
  static const bodySm = TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500);
  static const labelLg = TextStyle(fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w700);
  static const labelMd = TextStyle(fontSize: 14, height: 18 / 14, fontWeight: FontWeight.w600);
  static const labelSm = TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w700);
}

TextTheme _textTheme() {
  const ink = YomaColors.grey900;
  return const TextTheme(
    headlineMedium: YomaType.headlineLg,
    headlineSmall: YomaType.headlineMd,
    titleLarge: YomaType.headlineSm,
    titleMedium: TextStyle(fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w600),
    titleSmall: YomaType.labelMd,
    bodyLarge: YomaType.bodyMd,
    bodyMedium: YomaType.bodySm,
    bodySmall: TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500),
    labelLarge: YomaType.labelLg,
    labelMedium: YomaType.labelMd,
    labelSmall: YomaType.labelSm,
  ).apply(fontFamily: yomaFontFamily, bodyColor: ink, displayColor: ink);
}

const _buttonShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(YomaRadii.md)),
);

ThemeData buildYomaTheme() {
  final text = _textTheme();
  final scheme = ColorScheme.fromSeed(
    seedColor: YomaColors.brand,
    brightness: Brightness.light,
  ).copyWith(
    primary: YomaColors.brand,
    onPrimary: YomaColors.onPrimary,
    secondary: YomaColors.secondary,
    tertiary: YomaColors.tertiary,
    onSecondary: YomaColors.onPrimary,
    error: YomaColors.error,
    onError: YomaColors.onPrimary,
    surface: YomaColors.surface,
    onSurface: YomaColors.grey900,
    onSurfaceVariant: YomaColors.grey600,
    outline: YomaColors.grey300,
    outlineVariant: YomaColors.grey200,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: yomaFontFamily,
    textTheme: text,
    scaffoldBackgroundColor: YomaColors.canvas,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: AppBarTheme(
      backgroundColor: YomaColors.surface,
      foregroundColor: YomaColors.grey900,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: YomaType.headlineMd.copyWith(
        fontFamily: yomaFontFamily,
        fontSize: 20,
        height: 28 / 20,
        color: YomaColors.grey900,
      ),
      shape: const Border(bottom: BorderSide(color: YomaColors.grey100)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, YomaSizes.primaryButton)),
        shape: const WidgetStatePropertyAll(_buttonShape),
        textStyle: WidgetStatePropertyAll(text.labelLarge),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20)),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return YomaColors.grey200;
          if (states.contains(WidgetState.pressed)) return YomaColors.brandPressed;
          return YomaColors.brand;
        }),
        // grey600 on grey200 is 6.1:1; the design's grey500 would be 3.9:1.
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled) ? YomaColors.grey600 : YomaColors.onPrimary),
        elevation: const WidgetStatePropertyAll(0),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, YomaSizes.minTap)),
        shape: const WidgetStatePropertyAll(_buttonShape),
        textStyle: WidgetStatePropertyAll(text.labelMedium),
        backgroundColor: const WidgetStatePropertyAll(YomaColors.surface),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled) ? YomaColors.grey600 : YomaColors.secondary),
        side: WidgetStateProperty.resolveWith((states) => BorderSide(
              color:
                  states.contains(WidgetState.disabled) ? YomaColors.grey200 : YomaColors.secondary,
              width: 2,
            )),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(YomaSizes.minTap, YomaSizes.minTap)),
        shape: const WidgetStatePropertyAll(_buttonShape),
        textStyle: WidgetStatePropertyAll(text.labelMedium),
        foregroundColor: const WidgetStatePropertyAll(YomaColors.tertiary), // links
      ),
    ),
    iconButtonTheme: const IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(YomaSizes.minTap, YomaSizes.minTap)),
      ),
    ),
    cardTheme: const CardThemeData(
      color: YomaColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(YomaRadii.md)),
        side: BorderSide(color: YomaColors.grey200),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: YomaColors.canvas,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: text.bodyLarge?.copyWith(color: YomaColors.grey600),
      floatingLabelStyle: text.bodyMedium?.copyWith(color: YomaColors.brand),
      hintStyle: text.bodyLarge?.copyWith(color: YomaColors.grey500),
      helperStyle: text.bodySmall?.copyWith(color: YomaColors.grey600),
      errorStyle: text.bodySmall?.copyWith(color: YomaColors.error, fontWeight: FontWeight.w600),
      border: _inputBorder(YomaColors.grey300),
      enabledBorder: _inputBorder(YomaColors.grey300),
      disabledBorder: _inputBorder(YomaColors.grey200),
      focusedBorder: _inputBorder(YomaColors.brand, width: 2),
      errorBorder: _inputBorder(YomaColors.error),
      focusedErrorBorder: _inputBorder(YomaColors.error, width: 2),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: YomaColors.brand,
      selectionHandleColor: YomaColors.brand,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? YomaColors.brand : null),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: YomaColors.brand),
    dividerTheme: const DividerThemeData(color: YomaColors.grey200, space: 24),
    listTileTheme: const ListTileThemeData(iconColor: YomaColors.grey600),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: YomaColors.navy,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

OutlineInputBorder _inputBorder(Color color, {double width = 1}) => OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(YomaRadii.md)),
      borderSide: BorderSide(color: color, width: width),
    );
