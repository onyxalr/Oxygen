import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import '../services/app_settings.dart';
import '../widgets/glass_surface.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.settings, required this.onOpenAbout});
  final AppSettings settings;
  final VoidCallback onOpenAbout;

  static const _colors = <Color>[
    Color(0xFFB6A7FF),
    Color(0xFF9CCBFF),
    Color(0xFF78E0CD),
    Color(0xFFFFB7C5),
    Color(0xFFFFC58A),
    Color(0xFFA8D88D),
    Color(0xFF8AB4F8),
    Color(0xFFE9E5EF),
  ];

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: settings,
        builder: (context, _) {
          final isMaterialYou = settings.style == OxygenStyle.materialYou;
          return ListView(
            padding: const EdgeInsets.fromLTRB(26, 22, 26, 34),
            children: [
              Text(
                'Настройки',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.9,
                    ),
              ),
              const SizedBox(height: 7),
              Text(
                'Сделай Oxygen похожим на твоё устройство.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 28),
              _SectionTitle(
                title: 'Внешний вид',
                subtitle: 'Выбери одну из трёх отдельных дизайн-систем.',
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth > 900 ? 3 : 1;
                  if (columns == 1) {
                    return Column(
                      children: [
                        for (final style in OxygenStyle.values) ...[
                          _StylePreviewCard(
                            settings: settings,
                            style: style,
                            onTap: () => settings.setStyle(style),
                          ),
                          if (style != OxygenStyle.values.last) const SizedBox(height: 10),
                        ],
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < OxygenStyle.values.length; i++) ...[
                        Expanded(
                          child: _StylePreviewCard(
                            settings: settings,
                            style: OxygenStyle.values[i],
                            onTap: () => settings.setStyle(OxygenStyle.values[i]),
                            compact: true,
                          ),
                        ),
                        if (i < OxygenStyle.values.length - 1) const SizedBox(width: 12),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 28),
              _SectionTitle(
                title: isMaterialYou ? 'Цветовая палитра Pixel' : 'Акцентный цвет',
                subtitle: settings.style == OxygenStyle.oxygen
                    ? 'Влияет на второстепенные состояния и индикаторы.'
                    : isMaterialYou
                        ? 'Основной цвет формирует тон всей палитры Material You.'
                        : 'Акцент подсвечивает элементы стеклянного интерфейса.',
              ),
              const SizedBox(height: 14),
              GlassSurface(
                settings: settings,
                radius: settings.style == OxygenStyle.materialYou ? 30 : 22,
                blur: 3,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: settings.accent,
                            borderRadius: BorderRadius.circular(settings.style == OxygenStyle.materialYou ? 17 : 14),
                          ),
                          child: Icon(
                            Icons.palette_outlined,
                            color: settings.accent.computeLuminance() > .55 ? Colors.black : Colors.white,
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Текущий оттенок', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                              const SizedBox(height: 3),
                              Text(_hex(settings.accent), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: _colors
                          .map(
                            (color) => _ColorDot(
                              color: color,
                              selected: settings.accent.toARGB32() == color.toARGB32(),
                              onTap: () => settings.setAccent(color),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                ),
              ),
              if (defaultTargetPlatform != TargetPlatform.android) ...[
              const SizedBox(height: 26),
              _SectionTitle(
                title: 'Плавающая навигация',
                subtitle: 'Расположи dock так, как удобно тебе.',
              ),
              const SizedBox(height: 14),
              GlassSurface(
                settings: settings,
                radius: settings.style == OxygenStyle.materialYou ? 28 : 22,
                blur: 0,
                padding: const EdgeInsets.all(18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(settings.style == OxygenStyle.materialYou ? 16 : 14),
                      ),
                      child: Icon(Icons.open_with_rounded, color: Theme.of(context).colorScheme.onPrimaryContainer),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Перетаскивай к любому краю', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 5),
                          Text(
                            settings.style == OxygenStyle.liquidGlass
                                ? 'Зажми панель, чтобы увидеть мягкое свечение. Перетащи её влево, вправо, вверх или вниз — позиция сохранится.'
                                : 'Перетащи панель к левому, правому, верхнему или нижнему краю. Oxygen запомнит её положение.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.45),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              GlassSurface(
                settings: settings,
                radius: settings.style == OxygenStyle.materialYou ? 26 : 20,
                blur: 0,
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.dockLocked,
                  onChanged: settings.setDockLocked,
                  title: const Text('Закрепить док'),
                  subtitle: const Text('Панель останется у выбранного края и не будет перетаскиваться.'),
                  secondary: const Icon(Icons.push_pin_outlined),
                ),
              ),
              const SizedBox(height: 26),
              ],
              _SectionTitle(
                title: 'Поведение',
                subtitle: 'Настройки сохраняются автоматически.',
              ),
              const SizedBox(height: 14),
              GlassSurface(
                settings: settings,
                radius: settings.style == OxygenStyle.materialYou ? 30 : 22,
                blur: 2.5,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Режим оформления', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 11),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<OxygenBrightness>(
                        segments: const [
                          ButtonSegment(value: OxygenBrightness.dark, icon: Icon(Icons.dark_mode_rounded), label: Text('Тёмная')),
                          ButtonSegment(value: OxygenBrightness.light, icon: Icon(Icons.light_mode_rounded), label: Text('Светлая')),
                          ButtonSegment(value: OxygenBrightness.system, icon: Icon(Icons.settings_brightness_rounded), label: Text('Система')),
                        ],
                        selected: {settings.brightness},
                        onSelectionChanged: (value) => settings.setBrightness(value.first),
                        showSelectedIcon: false,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: settings.animations,
                      onChanged: settings.setAnimations,
                      title: const Text('Анимации интерфейса'),
                      subtitle: const Text('Отключи, если нужен максимально отзывчивый интерфейс.'),
                      secondary: const Icon(Icons.animation_rounded),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: settings.compact,
                      onChanged: settings.setCompact,
                      title: const Text('Компактный список'),
                      subtitle: const Text('Показывать больше треков на экране.'),
                      secondary: const Icon(Icons.view_agenda_outlined),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: settings.reducedEffects,
                      onChanged: settings.setReducedEffects,
                      title: const Text('Лёгкие эффекты'),
                      subtitle: const Text('Меньше размытия и теней — плавнее на слабых ПК.'),
                      secondary: const Icon(Icons.speed_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              _SectionTitle(title: 'О приложении'),
              const SizedBox(height: 14),
              GlassSurface(
                settings: settings,
                radius: settings.style == OxygenStyle.materialYou ? 30 : 22,
                blur: 2,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.graphic_eq_rounded, color: Theme.of(context).colorScheme.onPrimary),
                  ),
                  title: const Text('Oxygen Music', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Версия 3.9.0 · создатели и дополнительные функции'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: onOpenAbout,
                ),
              ),
            ],
          );
        },
      );

  static String _hex(Color color) => '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
}

class _StylePreviewCard extends StatelessWidget {
  const _StylePreviewCard({required this.settings, required this.style, required this.onTap, this.compact = false});
  final AppSettings settings;
  final OxygenStyle style;
  final VoidCallback onTap;
  final bool compact;

  String get title => switch (style) {
        OxygenStyle.oxygen => 'Oxygen',
        OxygenStyle.materialYou => 'Material You',
        OxygenStyle.liquidGlass => 'Liquid Glass',
      };

  String get description => switch (style) {
        OxygenStyle.oxygen => 'Чёрно-белый минимализм и чистая типографика.',
        OxygenStyle.materialYou => 'Тональные поверхности и округлые формы в духе Pixel.',
        OxygenStyle.liquidGlass => 'Стеклянные панели, контуры и мягкие блики.',
      };

  IconData get icon => switch (style) {
        OxygenStyle.oxygen => Icons.circle_outlined,
        OxygenStyle.materialYou => Icons.palette_rounded,
        OxygenStyle.liquidGlass => Icons.blur_on_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final selected = settings.style == style;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isOxygen = style == OxygenStyle.oxygen;
    final isMaterialYou = style == OxygenStyle.materialYou;
    final Color previewBase = isOxygen
        ? (dark ? const Color(0xFF111214) : const Color(0xFFF5F5F3))
        : isMaterialYou
            ? (dark ? const Color(0xFF20212B) : const Color(0xFFF0EAF8))
            : (dark ? const Color(0xFF111B2B) : const Color(0xFFD9E5F2));
    final Color previewAccent = isOxygen ? (dark ? Colors.white : const Color(0xFF222222)) : (isMaterialYou ? settings.accent : const Color(0xFF9DD7FF));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(style == OxygenStyle.materialYou ? 30 : 22),
        child: AnimatedContainer(
          duration: settings.animations ? const Duration(milliseconds: 170) : Duration.zero,
          padding: EdgeInsets.all(compact ? 12 : 15),
          decoration: BoxDecoration(
            color: selected ? Theme.of(context).colorScheme.primary.withValues(alpha: .06) : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(style == OxygenStyle.materialYou ? 30 : 22),
            border: Border.all(
              color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
              width: selected ? 1.6 : 1,
            ),
            boxShadow: selected ? [BoxShadow(color: previewAccent.withValues(alpha: .10), blurRadius: 18, offset: const Offset(0, 5))] : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ThemePreview(base: previewBase, accent: previewAccent, style: style, compact: compact),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                  if (selected) Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary, size: 20),
                ],
              ),
              const SizedBox(height: 5),
              Text(description, maxLines: compact ? 3 : 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.35)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.base, required this.accent, required this.style, required this.compact});
  final Color base;
  final Color accent;
  final OxygenStyle style;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final glass = style == OxygenStyle.liquidGlass;
    final materialYou = style == OxygenStyle.materialYou;
    final radius = materialYou ? 22.0 : (glass ? 19.0 : 12.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        height: compact ? 105 : 126,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: base,
          gradient: glass ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [base, const Color(0xFF3A526E)]) : null,
          border: Border.all(color: glass ? Colors.white.withValues(alpha: .4) : accent.withValues(alpha: .15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(width: 22, height: 22, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(materialYou ? 9 : 6))),
              const SizedBox(width: 7),
              Container(width: 48, height: 5, decoration: BoxDecoration(color: (glass ? Colors.white : accent).withValues(alpha: .7), borderRadius: BorderRadius.circular(10))),
              const Spacer(),
              Icon(Icons.more_horiz_rounded, size: 16, color: glass ? Colors.white70 : accent),
            ]),
            const SizedBox(height: 10),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: glass ? Colors.white.withValues(alpha: .12) : accent.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(materialYou ? 16 : 10),
                        border: glass ? Border.all(color: Colors.white.withValues(alpha: .22)) : null,
                      ),
                      child: Center(child: Icon(Icons.graphic_eq_rounded, size: 24, color: glass ? Colors.white : accent)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(width: double.infinity, height: 6, decoration: BoxDecoration(color: (glass ? Colors.white : accent).withValues(alpha: .70), borderRadius: BorderRadius.circular(6))),
                        const SizedBox(height: 6),
                        Container(width: 52, height: 4, decoration: BoxDecoration(color: (glass ? Colors.white : accent).withValues(alpha: .35), borderRadius: BorderRadius.circular(6))),
                        const Spacer(),
                        Align(alignment: Alignment.centerRight, child: Container(width: 28, height: 20, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(materialYou ? 10 : 7)))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ],
      );
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: selected ? 43 : 37,
          height: selected ? 43 : 37,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Theme.of(context).colorScheme.onSurface : Colors.white.withValues(alpha: .7),
              width: selected ? 3 : 1,
            ),
            boxShadow: selected ? [BoxShadow(color: color.withValues(alpha: .35), blurRadius: 13)] : null,
          ),
          child: selected ? Icon(Icons.check_rounded, color: color.computeLuminance() > .55 ? Colors.black : Colors.white) : null,
        ),
      );
}
