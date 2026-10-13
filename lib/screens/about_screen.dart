import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_settings.dart';
import '../widgets/glass_surface.dart';

enum _AboutTab { creators, extras }

/// About stays inside Oxygen's normal page navigation. The easter egg unlocks
/// inline content instead of launching a second window or another app.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  _AboutTab _tab = _AboutTab.creators;
  int _titleTaps = 0;
  int _orbitScore = 0;

  Future<void> _tapAboutTitle() async {
    if (widget.settings.experimentalFeaturesUnlocked) {
      setState(() => _titleTaps = 3);
      return;
    }
    final next = (_titleTaps + 1).clamp(0, 3).toInt();
    setState(() => _titleTaps = next);
    if (next >= 3) {
      await widget.settings.unlockExperimentalFeatures();
      if (!mounted) return;
      setState(() => _tab = _AboutTab.extras);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Секрет Oxygen открыт. Дополнительные функции доступны!')),
      );
    }
  }

  Future<void> _copyCreator() async {
    await Clipboard.setData(const ClipboardData(text: '@onyx_alr'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('@onyx_alr скопирован в буфер обмена')),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.settings,
        builder: (context, _) {
          final settings = widget.settings;
          final scheme = Theme.of(context).colorScheme;
          final unlocked = settings.experimentalFeaturesUnlocked;
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 34),
            children: [
              InkWell(
                onTap: _tapAboutTitle,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('О приложении', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -.8)),
                      const SizedBox(height: 5),
                      Text('Oxygen Music · версия 3.5.1', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
                      if (!unlocked && _titleTaps > 0) ...[
                        const SizedBox(height: 7),
                        Text(
                          'Секрет почти рядом — нажми ещё ${3 - _titleTaps} ${_titleTaps == 2 ? 'раз' : 'раза'} по заголовку.',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
                        ),
                      ],
                      if (unlocked) ...[
                        const SizedBox(height: 7),
                        Text('Секретный режим активирован ✦', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w800)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SegmentedButton<_AboutTab>(
                segments: const [
                  ButtonSegment(value: _AboutTab.creators, label: Text('Создатели'), icon: Icon(Icons.people_alt_outlined)),
                  ButtonSegment(value: _AboutTab.extras, label: Text('Доп. функции'), icon: Icon(Icons.auto_awesome_outlined)),
                ],
                selected: {_tab},
                showSelectedIcon: false,
                onSelectionChanged: (value) => setState(() => _tab = value.first),
              ),
              const SizedBox(height: 16),
              if (_tab == _AboutTab.creators) ...[
                GlassSurface(
                  settings: settings,
                  radius: settings.style == OxygenStyle.materialYou ? 28 : 22,
                  blur: 0,
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(settings.style == OxygenStyle.materialYou ? 18 : 15)),
                          child: Icon(Icons.person_rounded, size: 28, color: scheme.onPrimaryContainer),
                        ),
                        const SizedBox(width: 13),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Создатель', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.onSurfaceVariant)),
                          const SizedBox(height: 3),
                          Text('ONYX', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                        ])),
                      ]),
                      const SizedBox(height: 15),
                      Text('Разработка Oxygen', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 5),
                      Text('Идеи, дизайн и сборка музыкального плеера.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _copyCreator,
                        icon: const Icon(Icons.send_rounded),
                        label: const Text('@onyx_alr · Telegram'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GlassSurface(
                  settings: settings,
                  radius: settings.style == OxygenStyle.materialYou ? 26 : 20,
                  blur: 0,
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Icon(Icons.info_outline_rounded, color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Oxygen — локальный музыкальный плеер. Твоя музыка остаётся в твоей библиотеке.', style: Theme.of(context).textTheme.bodyMedium)),
                  ]),
                ),
              ] else ...[
                if (!unlocked)
                  GlassSurface(
                    settings: settings,
                    radius: settings.style == OxygenStyle.materialYou ? 28 : 22,
                    blur: 0,
                    padding: const EdgeInsets.all(22),
                    child: Column(children: [
                      Icon(Icons.lock_outline_rounded, size: 38, color: scheme.primary),
                      const SizedBox(height: 12),
                      Text('Дополнительные функции закрыты', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                      const SizedBox(height: 6),
                      Text('Нажми по заголовку «О приложении» три раза. Подсказка появится прямо под ним.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    ]),
                  )
                else ...[
                  GlassSurface(
                    settings: settings,
                    radius: settings.style == OxygenStyle.materialYou ? 28 : 22,
                    blur: 0,
                    padding: const EdgeInsets.fromLTRB(13, 4, 13, 4),
                    child: Column(children: [
                      SwitchListTile(
                        value: settings.playerVisualizer,
                        onChanged: settings.setPlayerVisualizer,
                        secondary: const Icon(Icons.equalizer_rounded),
                        title: const Text('Визуализатор плеера'),
                        subtitle: const Text('Небольшая анимация во время воспроизведения.'),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        value: settings.waveformTimeline,
                        onChanged: settings.setWaveformTimeline,
                        secondary: const Icon(Icons.waves_rounded),
                        title: const Text('Волновая шкала'),
                        subtitle: const Text('Волнистый прогресс в стиле Android.'),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        value: settings.reducedEffects,
                        onChanged: settings.setReducedEffects,
                        secondary: const Icon(Icons.speed_rounded),
                        title: const Text('Приоритет производительности'),
                        subtitle: const Text('Уменьшает дорогие эффекты размытия.'),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Text('СЕКРЕТНАЯ МИНИ-ИГРА', style: Theme.of(context).textTheme.labelMedium?.copyWith(letterSpacing: 1.4, fontWeight: FontWeight.w800, color: scheme.primary)),
                  const SizedBox(height: 9),
                  GlassSurface(
                    settings: settings,
                    radius: settings.style == OxygenStyle.materialYou ? 28 : 22,
                    blur: 0,
                    padding: const EdgeInsets.all(20),
                    child: Column(children: [
                      Text('Oxygen Orbit', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 5),
                      Text('Поймай заряд кислорода. Сколько сможешь собрать?', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 18),
                      InkWell(
                        onTap: () => setState(() => _orbitScore++),
                        customBorder: const CircleBorder(),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          width: 104,
                          height: 104,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(colors: [settings.accent.withValues(alpha: .96), settings.accent.withValues(alpha: .20)]),
                            border: Border.all(color: scheme.primary.withValues(alpha: .55), width: 2),
                            boxShadow: settings.reducedEffects ? null : [BoxShadow(color: settings.accent.withValues(alpha: .32), blurRadius: 20)],
                          ),
                          child: Icon(_orbitScore % 5 == 4 ? Icons.bolt_rounded : Icons.bubble_chart_rounded, size: 45, color: settings.accent.computeLuminance() > .55 ? Colors.black : Colors.white),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('Заряды: $_orbitScore', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      TextButton.icon(onPressed: () => setState(() => _orbitScore = 0), icon: const Icon(Icons.refresh_rounded), label: const Text('Заново')),
                    ]),
                  ),
                ],
              ],
            ],
          );
        },
      );
}
