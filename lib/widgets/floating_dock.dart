import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/app_page.dart';
import '../services/app_settings.dart';

/// A low-cost edge dock. The dock snaps to one of the four edges and is always
/// centred along that edge. A separate three-dot button opens secondary pages.
class FloatingDock extends StatefulWidget {
  const FloatingDock({
    super.key,
    required this.page,
    required this.settings,
    required this.onOpen,
    required this.onMore,
    this.allowDragging = true,
  });

  final AppPage page;
  final AppSettings settings;
  final ValueChanged<AppPage> onOpen;
  final VoidCallback onMore;
  /// Set false for touch-first platforms where the dock must stay fixed.
  final bool allowDragging;

  @override
  State<FloatingDock> createState() => _FloatingDockState();
}

class _FloatingDockState extends State<FloatingDock> {
  static const double _inset = 12;
  static const double _gap = 9;
  static const double _moreSize = 42;

  Offset? _dragOffset;
  DockEdge? _dragEdge;
  bool _dragging = false;
  bool _held = false;

  bool _isHorizontal(DockEdge edge) => edge == DockEdge.top || edge == DockEdge.bottom;

  Size _panelSize(DockEdge edge) {
    final horizontal = _isHorizontal(edge);
    // About 4 cm in logical-pixel terms. Keep the panel compact in either layout.
    return horizontal ? const Size(150, 62) : const Size(62, 150);
  }

  Size _groupSize(DockEdge edge) {
    final panel = _panelSize(edge);
    return _isHorizontal(edge)
        ? Size(panel.width + _gap + _moreSize, math.max(panel.height, _moreSize).toDouble())
        : Size(math.max(panel.width, _moreSize).toDouble(), panel.height + _gap + _moreSize);
  }

  Offset _positionFor(BuildContext context, BoxConstraints constraints, DockEdge edge) {
    final group = _groupSize(edge);
    final materialYou = widget.settings.style == OxygenStyle.materialYou;
    final inset = materialYou ? 0.0 : _inset;
    final safeBottom = !widget.allowDragging && edge == DockEdge.bottom
        ? MediaQuery.viewPaddingOf(context).bottom
        : 0.0;
    // Centre the complete dock group, including the separate three-dot button.
    return switch (edge) {
      DockEdge.left => Offset(inset, (constraints.maxHeight - group.height) / 2),
      DockEdge.right => Offset(constraints.maxWidth - group.width - inset, (constraints.maxHeight - group.height) / 2),
      DockEdge.top => Offset((constraints.maxWidth - group.width) / 2, inset),
      DockEdge.bottom => Offset((constraints.maxWidth - group.width) / 2, constraints.maxHeight - group.height - inset - safeBottom),
    };
  }

  Offset _clampOffset(Offset value, BoxConstraints constraints, Size size) {
    final maxX = math.max(0.0, constraints.maxWidth - size.width).toDouble();
    final maxY = math.max(0.0, constraints.maxHeight - size.height).toDouble();
    return Offset(value.dx.clamp(0.0, maxX).toDouble(), value.dy.clamp(0.0, maxY).toDouble());
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.settings,
        builder: (context, _) => Positioned.fill(
          child: LayoutBuilder(
          builder: (context, constraints) {
            final edge = widget.allowDragging ? (_dragEdge ?? widget.settings.dockEdge) : DockEdge.bottom;
            final panel = _panelSize(edge);
            final group = _groupSize(edge);
            final target = _positionFor(context, constraints, edge);
            final offset = _dragOffset ?? target;
            final horizontal = _isHorizontal(edge);
            final materialYou = widget.settings.style == OxygenStyle.materialYou;

            final dockContent = RepaintBoundary(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      width: panel.width,
                      height: panel.height,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: !widget.allowDragging || widget.settings.dockLocked
                            ? null
                            : (_) => setState(() {
                                  _dragging = true;
                                  _dragEdge = edge;
                                  _dragOffset = offset;
                                }),
                        onPanUpdate: !widget.allowDragging || widget.settings.dockLocked
                            ? null
                            : (details) => setState(() {
                                  _dragOffset = _clampOffset(
                                    (_dragOffset ?? offset) + details.delta,
                                    constraints,
                                    group,
                                  );
                                }),
                        onPanEnd: !widget.allowDragging || widget.settings.dockLocked ? null : (_) => _finishDrag(constraints),
                        onLongPressStart: (_) => setState(() => _held = true),
                        onLongPressEnd: (_) => setState(() => _held = false),
                        child: _DockSurface(
                          edge: edge,
                          page: widget.page,
                          settings: widget.settings,
                          held: _held,
                          onOpen: widget.onOpen,
                        ),
                      ),
                    ),
                    Positioned(
                      left: horizontal ? panel.width + _gap : (panel.width - _moreSize) / 2,
                      top: horizontal ? (panel.height - _moreSize) / 2 : panel.height + _gap,
                      width: _moreSize,
                      height: _moreSize,
                      child: _MoreButton(
                        style: widget.settings.style,
                        accent: widget.settings.accent,
                        onTap: widget.onMore,
                      ),
                    ),
                    if (widget.settings.dockLocked)
                      Positioned(
                        right: materialYou && edge == DockEdge.right ? panel.width + 4 : -2,
                        top: horizontal ? 4 : 7,
                        child: IgnorePointer(
                          child: Icon(Icons.push_pin_rounded, size: 12, color: Theme.of(context).colorScheme.primary.withValues(alpha: .82)),
                        ),
                      ),
                  ],
                ),
              );

            return Stack(clipBehavior: Clip.none, children: [
              AnimatedPositioned(
                duration: _dragging || !widget.settings.animations || widget.settings.reducedEffects ? Duration.zero : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                left: offset.dx,
                top: offset.dy,
                width: group.width,
                height: group.height,
                child: dockContent,
              ),
            ]);
          },
          ),
        ),
      );

  Future<void> _finishDrag(BoxConstraints constraints) async {
    final oldEdge = _dragEdge ?? widget.settings.dockEdge;
    final group = _groupSize(oldEdge);
    final current = _clampOffset(
      _dragOffset ?? _positionFor(context, constraints, oldEdge),
      constraints,
      group,
    );
    final distances = <(DockEdge, double)>[
      (DockEdge.left, current.dx),
      (DockEdge.right, constraints.maxWidth - current.dx - group.width),
      (DockEdge.top, current.dy),
      (DockEdge.bottom, constraints.maxHeight - current.dy - group.height),
    ];
    distances.sort((a, b) => a.$2.compareTo(b.$2));
    final edge = distances.first.$1;

    setState(() {
      _dragging = false;
      _held = false;
      _dragEdge = edge;
      // Immediately centre on the selected edge; the dock never stays mid-screen.
      _dragOffset = _positionFor(context, constraints, edge);
    });
    await widget.settings.setDockPosition(edge, .5);
    if (!mounted) return;
    setState(() {
      _dragEdge = null;
      _dragOffset = null;
    });
  }
}

class _DockSurface extends StatelessWidget {
  const _DockSurface({required this.edge, required this.page, required this.settings, required this.held, required this.onOpen});

  final DockEdge edge;
  final AppPage page;
  final AppSettings settings;
  final bool held;
  final ValueChanged<AppPage> onOpen;

  bool get horizontal => edge == DockEdge.top || edge == DockEdge.bottom;
  bool get liquid => settings.style == OxygenStyle.liquidGlass;
  bool get materialYou => settings.style == OxygenStyle.materialYou;

  BorderRadius _radius() {
    if (!materialYou) return BorderRadius.circular(999);
    return switch (edge) {
      DockEdge.left => const BorderRadius.only(topLeft: Radius.circular(5), bottomLeft: Radius.circular(5), topRight: Radius.circular(22), bottomRight: Radius.circular(22)),
      DockEdge.right => const BorderRadius.only(topRight: Radius.circular(5), bottomRight: Radius.circular(5), topLeft: Radius.circular(22), bottomLeft: Radius.circular(22)),
      DockEdge.top => const BorderRadius.only(topLeft: Radius.circular(5), topRight: Radius.circular(5), bottomLeft: Radius.circular(22), bottomRight: Radius.circular(22)),
      DockEdge.bottom => const BorderRadius.only(bottomLeft: Radius.circular(5), bottomRight: Radius.circular(5), topLeft: Radius.circular(22), topRight: Radius.circular(22)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = _radius();
    final panelFill = liquid
        ? (Theme.of(context).brightness == Brightness.dark ? const Color(0xB91D2635) : const Color(0xCFEAF1F9))
        : materialYou
            ? scheme.surfaceContainerHigh
            : scheme.surface;

    final buttons = <(AppPage, String)>[
      (AppPage.home, 'Главная'),
      (AppPage.search, 'Поиск'),
      (AppPage.library, 'Музыка'),
    ];
    Widget inside = Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontal ? 5 : 4, vertical: horizontal ? 4 : 5),
      child: Flex(
        direction: horizontal ? Axis.horizontal : Axis.vertical,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final item in buttons)
            Expanded(
              child: _DockButton(
                icon: item.$1.icon,
                label: item.$2,
                selected: page == item.$1,
                style: settings.style,
                animations: settings.animations,
                onTap: () => onOpen(item.$1),
              ),
            ),
        ],
      ),
    );

    // Dock pages are connected directly from button callbacks below; the
    // callback is supplied through an inherited closure in the stateful host.
    // _DockButton itself only supplies semantics/ink animation.
    final outerShadow = settings.reducedEffects
        ? const <BoxShadow>[]
        : [
            BoxShadow(
              color: liquid ? settings.accent.withValues(alpha: held ? .24 : .075) : Colors.black.withValues(alpha: materialYou ? .10 : .07),
              blurRadius: held ? 16 : (liquid ? 12 : 7),
              spreadRadius: held ? .4 : 0,
              offset: const Offset(0, 3),
            ),
          ];
    // Keep the panel itself shadow-free. The shadow is painted once by the
    // outer AnimatedContainer; previously it was duplicated inside the clip.
    final decoration = BoxDecoration(
      color: panelFill,
      borderRadius: radius,
      border: Border.all(color: liquid ? Colors.white.withValues(alpha: held ? .64 : .24) : scheme.outlineVariant.withValues(alpha: .42)),
    );

    Widget surface = Container(decoration: decoration, child: inside);
    if (liquid) {
      surface = ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!settings.reducedEffects)
              BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: const SizedBox.expand(),
              ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? .13 : .48),
                    Colors.white.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? .035 : .13),
                    settings.accent.withValues(alpha: .035),
                  ],
                ),
              ),
            ),
            surface,
            Positioned(
              top: 1,
              left: horizontal ? 12 : 1,
              right: horizontal ? 12 : 1,
              child: IgnorePointer(
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    gradient: LinearGradient(colors: [Colors.white.withValues(alpha: .02), Colors.white.withValues(alpha: held ? .82 : .36), Colors.white.withValues(alpha: .02)]),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return AnimatedContainer(
      duration: settings.animations ? const Duration(milliseconds: 130) : Duration.zero,
      decoration: BoxDecoration(borderRadius: radius, boxShadow: outerShadow),
      child: Material(color: Colors.transparent, borderRadius: radius, clipBehavior: Clip.antiAlias, child: surface),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.style,
    required this.animations,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final OxygenStyle style;
  final bool animations;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final materialYou = style == OxygenStyle.materialYou;
    final liquid = style == OxygenStyle.liquidGlass;
    final iconColor = selected
        ? (liquid ? scheme.onSurface : materialYou ? scheme.primary : scheme.onSurface)
        : scheme.onSurfaceVariant;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(materialYou ? 17 : 999),
          child: Center(
            child: AnimatedScale(
              scale: selected && !materialYou ? 1.04 : 1,
              duration: animations ? const Duration(milliseconds: 120) : Duration.zero,
              child: Icon(icon, size: selected ? 23 : 21, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.style, required this.accent, required this.onTap});
  final OxygenStyle style;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glass = style == OxygenStyle.liquidGlass;
    return Tooltip(
      message: 'Ещё',
      child: Material(
        color: glass ? scheme.surface.withValues(alpha: .70) : scheme.surfaceContainerHigh,
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: glass ? Colors.white.withValues(alpha: .35) : scheme.outlineVariant.withValues(alpha: .45)),
              boxShadow: glass ? [BoxShadow(color: accent.withValues(alpha: .10), blurRadius: 8)] : null,
            ),
            child: Icon(Icons.more_horiz_rounded, color: scheme.onSurface, size: 24),
          ),
        ),
      ),
    );
  }
}
