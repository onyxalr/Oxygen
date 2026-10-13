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
  }) {
    final dark = brightness == Brightness.dark;
    final seed = style == OxygenStyle.oxygen
        ? (dark ? const Color(0xFFF5F5F5) : const Color(0xFF17191D))
        : accent;
    final generated = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    final background = switch (style) {
      OxygenStyle.oxygen => dark ? const Color(0xFF090A0C) : const Color(0xFFF4F4F2),
      // Soft tonal backgrounds and layered surfaces inspired by Pixel UI.
      OxygenStyle.materialYou => dark ? const Color(0xFF101116) : const Color(0xFFF6F2FA),
      OxygenStyle.liquidGlass => dark ? const Color(0xFF080B12) : const Color(0xFFE6ECF4),
    };
    final surface = switch (style) {
      OxygenStyle.oxygen => dark ? const Color(0xFF151619) : const Color(0xFFFFFFFF),
      OxygenStyle.materialYou => dark ? const Color(0xFF1A1B22) : const Color(0xFFFFF7FF),
      OxygenStyle.liquidGlass => dark ? const Color(0xFF1B2330) : const Color(0xFFF8FBFF),
    };
    final elevatedSurface = switch (style) {
      OxygenStyle.oxygen => dark ? const Color(0xFF1D1F23) : const Color(0xFFEAEAE7),
      OxygenStyle.materialYou => dark ? const Color(0xFF262731) : const Color(0xFFECE6F3),
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
