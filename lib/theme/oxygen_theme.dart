import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/app_settings.dart';

/// Three deliberately different visual systems used throughout Oxygen.
///
/// `liquidGlass` uses layered translucent surfaces and restrained blur;
/// `materialYou` uses tonal surfaces, pill controls and generous Pixel-like
/// geometry; `oxygen` keeps the interface monochrome and minimal.
class OxygenTheme {
  static ThemeData build({
    required Brightness brightness,
    required OxygenStyle style,
    required Color accent,
    bool materialMonochrome = false,
  }) {
    final dark = brightness == Brightness.dark;
    final monochromeMaterialYou = style == OxygenStyle.materialYou && materialMonochrome;
    final seed = style == OxygenStyle.oxygen
        ? (dark ? const Color(0xFFF5F5F5) : const Color(0xFF17191D))
        : monochromeMaterialYou
            ? const Color(0xFF808080)
            : accent;
    final generated = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    final background = switch (style) {
      OxygenStyle.oxygen => dark ? const Color(0xFF090A0C) : const Color(0xFFF4F4F2),
      // Soft tonal backgrounds and layered surfaces inspired by Pixel UI.
      OxygenStyle.materialYou => monochromeMaterialYou
          ? (dark ? const Color(0xFF101010) : const Color(0xFFF4F4F4))
          : (dark ? const Color(0xFF101116) : const Color(0xFFF6F2FA)),
      OxygenStyle.liquidGlass => dark ? const Color(0xFF080B12) : const Color(0xFFE6ECF4),
    };
    final surface = switch (style) {
      OxygenStyle.oxygen => dark ? const Color(0xFF151619) : const Color(0xFFFFFFFF),
      OxygenStyle.materialYou => monochromeMaterialYou
          ? (dark ? const Color(0xFF1C1C1C) : const Color(0xFFFFFFFF))
          : (dark ? const Color(0xFF1A1B22) : const Color(0xFFFFF7FF)),
      OxygenStyle.liquidGlass => dark ? const Color(0xFF1B2330) : const Color(0xFFF8FBFF),
    };
    final elevatedSurface = switch (style) {
      OxygenStyle.oxygen => dark ? const Color(0xFF1D1F23) : const Color(0xFFEAEAE7),
      OxygenStyle.materialYou => monochromeMaterialYou
          ? (dark ? const Color(0xFF292929) : const Color(0xFFE7E7E7))
          : (dark ? const Color(0xFF262731) : const Color(0xFFECE6F3)),
      OxygenStyle.liquidGlass => dark ? const Color(0xFF222D3D) : const Color(0xFFEFF4FA),
    };
    final radius = switch (style) {
      OxygenStyle.oxygen => 14.0,
      OxygenStyle.materialYou => 28.0,
      OxygenStyle.liquidGlass => 24.0,
    };

    final ColorScheme scheme;
    if (style == OxygenStyle.oxygen) {
      scheme = generated.copyWith(
        primary: dark ? const Color(0xFFF4F4F4) : const Color(0xFF1B1C1F),
        onPrimary: dark ? const Color(0xFF161719) : Colors.white,
        secondary: dark ? const Color(0xFFB8BBC2) : const Color(0xFF565961),
        surface: surface,
      );
    } else if (style == OxygenStyle.materialYou && monochromeMaterialYou) {
      // Material You monochrome: all tonal roles remain achromatic in light and dark mode.
      scheme = generated.copyWith(
        primary: dark ? const Color(0xFFEAEAEA) : const Color(0xFF252525),
        onPrimary: dark ? const Color(0xFF222222) : Colors.white,
        primaryContainer: dark ? const Color(0xFF383838) : const Color(0xFFE5E5E5),
        onPrimaryContainer: dark ? const Color(0xFFF4F4F4) : const Color(0xFF222222),
        secondary: dark ? const Color(0xFFC7C7C7) : const Color(0xFF4C4C4C),
        onSecondary: dark ? const Color(0xFF252525) : Colors.white,
        secondaryContainer: dark ? const Color(0xFF303030) : const Color(0xFFE9E9E9),
        onSecondaryContainer: dark ? const Color(0xFFEFEFEF) : const Color(0xFF292929),
        tertiary: dark ? const Color(0xFFD8D8D8) : const Color(0xFF595959),
        onTertiary: dark ? const Color(0xFF292929) : Colors.white,
        tertiaryContainer: dark ? const Color(0xFF414141) : const Color(0xFFEFEFEF),
        onTertiaryContainer: dark ? const Color(0xFFF1F1F1) : const Color(0xFF292929),
        error: dark ? const Color(0xFFE0E0E0) : const Color(0xFF666666),
        onError: dark ? const Color(0xFF222222) : Colors.white,
        errorContainer: dark ? const Color(0xFF3A3A3A) : const Color(0xFFE8E8E8),
        onErrorContainer: dark ? const Color(0xFFF2F2F2) : const Color(0xFF2B2B2B),
        surface: surface,
        onSurface: dark ? const Color(0xFFF1F1F1) : const Color(0xFF202020),
        onSurfaceVariant: dark ? const Color(0xFFC3C3C3) : const Color(0xFF565656),
        surfaceTint: dark ? const Color(0xFFEAEAEA) : const Color(0xFF333333),
        outline: const Color(0xFF777777),
        outlineVariant: dark ? const Color(0xFF484848) : const Color(0xFFD0D0D0),
        inverseSurface: dark ? const Color(0xFFEAEAEA) : const Color(0xFF303030),
        onInverseSurface: dark ? const Color(0xFF252525) : const Color(0xFFF4F4F4),
        inversePrimary: dark ? const Color(0xFF444444) : const Color(0xFFC6C6C6),
      );
    } else if (style == OxygenStyle.materialYou) {
      scheme = generated.copyWith(surface: surface, primary: accent);
    } else {
      scheme = generated.copyWith(
        surface: surface,
        primary: accent,
        secondary: generated.tertiary,
      );
    }

    final outline = dark
        ? Colors.white.withValues(alpha: style == OxygenStyle.liquidGlass ? .16 : .09)
        : Colors.black.withValues(alpha: style == OxygenStyle.liquidGlass ? .10 : .08);
    final controlRadius = style == OxygenStyle.materialYou ? 24.0 : (style == OxygenStyle.liquidGlass ? 22.0 : 12.0);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      cardColor: surface,
      dividerColor: outline,
      visualDensity: VisualDensity.standard,
      splashFactory: InkRipple.splashFactory,
      textTheme: Typography.material2021().black.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: style == OxygenStyle.materialYou,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: style == OxygenStyle.materialYou
            ? scheme.secondaryContainer
            : scheme.primary.withValues(alpha: style == OxygenStyle.liquidGlass ? .18 : .10),
        selectedIconTheme: IconThemeData(
          color: style == OxygenStyle.materialYou ? scheme.onSecondaryContainer : scheme.primary,
        ),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        backgroundColor: style == OxygenStyle.liquidGlass
            ? surface.withValues(alpha: dark ? .78 : .88)
            : style == OxygenStyle.materialYou
                ? surface
                : background,
        surfaceTintColor: Colors.transparent,
        indicatorColor: style == OxygenStyle.materialYou
            ? scheme.secondaryContainer
            : scheme.primary.withValues(alpha: .12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: style == OxygenStyle.materialYou ? scheme.surfaceTint : Colors.transparent,
        elevation: style == OxygenStyle.materialYou ? 1 : 0,
        shadowColor: Colors.black.withValues(alpha: .12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: outline),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: style == OxygenStyle.liquidGlass
            ? surface.withValues(alpha: dark ? .52 : .72)
            : style == OxygenStyle.materialYou
                ? elevatedSurface
                : surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(controlRadius)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(controlRadius)),
          side: BorderSide(color: outline),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        thumbColor: scheme.primary,
        inactiveTrackColor: scheme.primary.withValues(alpha: .23),
        trackHeight: style == OxygenStyle.materialYou ? 4 : 3,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
    );
  }
}
