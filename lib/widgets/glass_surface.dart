import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/app_settings.dart';

/// Shared surface primitive. Blur is intentionally capped to keep lists and
/// navigation responsive on integrated GPUs; most UI surfaces need only tint
/// and edge highlights to read as glass.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    required this.settings,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.blur = 4,
    this.tint,
    this.border = true,
  });

  final Widget child;
  final AppSettings settings;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final Color? tint;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final isGlass = settings.style == OxygenStyle.liquidGlass;
    final isMaterialYou = settings.style == OxygenStyle.materialYou;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final base = tint ?? Theme.of(context).cardColor;
    // Only explicitly marked, small hero surfaces may sample the backdrop.
    // Keep the sigma low: high-radius blur is disproportionately expensive on
    // integrated GPUs and tends to make clipped corners look dirty.
    // Reduced-effects mode never samples the backdrop: this is substantially
    // cheaper on older iGPUs and avoids edge halos while still keeping the tint.
    final safeBlur = isGlass && blur >= 4.5 && !settings.reducedEffects
        ? blur.clamp(0.0, 2.0).toDouble()
        : 0.0;
    final transitionDuration = settings.animations
        ? const Duration(milliseconds: 220)
        : Duration.zero;
    final adjustedRadius = isGlass ? (radius + 3).clamp(0.0, 36.0).toDouble() : radius;
    final radiusValue = BorderRadius.circular(adjustedRadius);

    if (!isGlass) {
      return Container(
        decoration: BoxDecoration(
          color: base,
          borderRadius: radiusValue,
          border: border ? Border.all(color: Theme.of(context).dividerColor) : null,
          boxShadow: isMaterialYou && !settings.reducedEffects
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? .055 : .02),
                    blurRadius: 5,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: radiusValue,
          clipBehavior: Clip.antiAlias,
          child: Padding(padding: padding, child: child),
        ),
      );
    }

    final glassFill = base.withValues(alpha: dark ? .42 : .57);
    final glassSurface = AnimatedContainer(
      duration: transitionDuration,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: radiusValue,
        boxShadow: settings.reducedEffects
            ? const <BoxShadow>[]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? .12 : .035),
                  blurRadius: 9,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: radiusValue,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            if (safeBlur > 0)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: safeBlur,
                    sigmaY: safeBlur,
                    tileMode: TileMode.clamp,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            Positioned.fill(
              child: AnimatedContainer(
                duration: transitionDuration,
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: glassFill,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: dark ? .16 : .42),
                      Colors.white.withValues(alpha: dark ? .035 : .10),
                      scheme.primary.withValues(alpha: dark ? .03 : .055),
                    ],
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
            if (border)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radiusValue,
                      border: Border.all(color: Colors.white.withValues(alpha: dark ? .20 : .44), width: 1),
                    ),
                  ),
                ),
              ),
            if (border)
              Positioned(
                left: adjustedRadius * .8,
                right: adjustedRadius * .8,
                top: 1,
                child: IgnorePointer(
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: .02),
                          Colors.white.withValues(alpha: dark ? .32 : .72),
                          Colors.white.withValues(alpha: .02),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
    // Cache low-cost tint/edge surfaces as a separate layer. When backdrop
    // sampling is active, keep it outside a repaint boundary so the blur stays
    // live relative to the content behind it.
    return safeBlur == 0 ? RepaintBoundary(child: glassSurface) : glassSurface;
  }
}
