import 'package:flutter/material.dart';
import '../services/app_settings.dart';
import '../services/audio_controller.dart';
import '../widgets/glass_surface.dart';
import '../widgets/track_tile.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.settings, required this.audio, required this.onOpenLibrary, required this.onOpenFavorites, required this.onImport, required this.onOpenPlayer});
  final AppSettings settings;
  final AudioController audio;
  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenFavorites;
  final VoidCallback onImport;
  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: audio, builder: (context, _) {
    final greeting = DateTime.now().hour < 12 ? 'Доброе утро' : DateTime.now().hour < 18 ? 'Добрый день' : 'Добрый вечер';
    final recent = audio.library.reversed.take(5).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(26, 22, 26, 30), children: [
      Text(greeting, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 4),
      Text('Твоя волна.\nТвой ритм.', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900, height: 1.02, letterSpacing: -1.4)),
      const SizedBox(height: 24),
      _HeroCard(settings: settings, audio: audio, onImport: onImport, onOpenPlayer: onOpenPlayer),
      const SizedBox(height: 30),
      Row(children: [Expanded(child: Text('Недавно добавлено', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))), TextButton(onPressed: onOpenLibrary, child: const Text('Вся библиотека'))]),
      const SizedBox(height: 10),
      if (recent.isEmpty) _EmptyLibrary(settings: settings, onImport: onImport) else ...recent.map((track) => TrackTile(track: track, audio: audio, settings: settings)),
      const SizedBox(height: 28),
      Text('Быстрый доступ', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth > 780 ? 3 : constraints.maxWidth > 480 ? 2 : 1;
        return GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: columns, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: columns == 1 ? 3.8 : 2.3, children: [
          _QuickCard(icon: Icons.library_music_rounded, title: 'Моя музыка', subtitle: '${audio.library.length} треков', onTap: onOpenLibrary),
          _QuickCard(icon: Icons.favorite_rounded, title: 'Избранное', subtitle: '${audio.favoriteIds.length} треков', onTap: onOpenFavorites),
          _QuickCard(icon: Icons.add_rounded, title: 'Добавить музыку', subtitle: 'MP3, FLAC, WAV и другие', onTap: onImport),
        ]);
      }),
    ]);
  });
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.settings, required this.audio, required this.onImport, required this.onOpenPlayer});
  final AppSettings settings;
  final AudioController audio;
  final VoidCallback onImport;
  final VoidCallback onOpenPlayer;
  @override
  Widget build(BuildContext context) => GlassSurface(
        settings: settings,
        radius: settings.style == OxygenStyle.materialYou ? 34 : (settings.style == OxygenStyle.liquidGlass ? 30 : 18),
        blur: settings.style == OxygenStyle.liquidGlass ? 5.0 : 0,
        padding: const EdgeInsets.all(24),
        child: LayoutBuilder(builder: (context, constraints) {
          final narrow = constraints.maxWidth < 520;
          final materialYou = settings.style == OxygenStyle.materialYou;
          final liquid = settings.style == OxygenStyle.liquidGlass;
          final scheme = Theme.of(context).colorScheme;
          final details = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: .14), borderRadius: BorderRadius.circular(30)),
              child: Text('OXYGEN PLAYER', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 1.6)),
            ),
            const SizedBox(height: 18),
            Text(audio.current?.title ?? 'Музыка без границ', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Text(audio.current != null ? 'Продолжай слушать то, что нравится.' : 'Собери коллекцию, которая звучит именно как ты.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            Wrap(spacing: 10, runSpacing: 8, children: [
              FilledButton.icon(onPressed: audio.current != null ? onOpenPlayer : onImport, icon: Icon(audio.current != null ? Icons.play_arrow_rounded : Icons.add_rounded), label: Text(audio.current != null ? 'Открыть плеер' : 'Добавить треки')),
              if (audio.current != null) OutlinedButton.icon(onPressed: audio.togglePlay, icon: Icon(audio.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded), label: Text(audio.isPlaying ? 'Пауза' : 'Слушать')),
            ]),
          ]);
          final artColors = settings.style == OxygenStyle.oxygen
              ? [scheme.onSurface, scheme.surfaceContainerHighest, scheme.surface]
              : materialYou
                  ? [settings.accent, scheme.secondaryContainer, scheme.tertiaryContainer]
                  : [settings.accent.withValues(alpha: .92), const Color(0xFF526C91), const Color(0xFF111C2D)];
          final artForeground = materialYou
              ? (settings.accent.computeLuminance() > .55 ? Colors.black : Colors.white)
              : liquid ? Colors.white : scheme.onSurface;
          final artwork = Container(
            width: narrow ? double.infinity : constraints.maxWidth * .28,
            height: narrow ? 150 : 200,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(materialYou ? 30 : (liquid ? 26 : 16)),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: artColors),
              border: liquid ? Border.all(color: Colors.white.withValues(alpha: .38)) : null,
              boxShadow: liquid && !settings.reducedEffects ? [BoxShadow(color: settings.accent.withValues(alpha: .12), blurRadius: 14, offset: const Offset(0, 5))] : null,
            ),
            child: Stack(alignment: Alignment.center, children: [
              if (liquid) ...[
                Positioned(left: -18, top: -32, child: Container(width: 170, height: 170, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: .24), width: 1.2), gradient: RadialGradient(colors: [Colors.white.withValues(alpha: .22), Colors.white.withValues(alpha: .015)])))),
                Positioned(right: 18, top: 18, child: Container(width: 52, height: 52, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .12), border: Border.all(color: Colors.white.withValues(alpha: .42))))),
                Positioned(left: 24, bottom: 18, child: Container(width: 74, height: 3, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .56), borderRadius: BorderRadius.circular(4)))),
              ] else if (materialYou) ...[
                Positioned(right: 15, top: 17, child: Transform.rotate(angle: .18, child: Container(width: 68, height: 68, decoration: BoxDecoration(color: scheme.tertiary.withValues(alpha: .32), borderRadius: BorderRadius.circular(25))))),
                Positioned(left: 20, bottom: 17, child: Container(width: 48, height: 48, decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .17), borderRadius: BorderRadius.circular(18)))),
              ] else ...[
                Positioned(right: 18, top: 18, child: Icon(Icons.circle_outlined, size: 44, color: artForeground.withValues(alpha: .23))),
              ],
              Icon(Icons.graphic_eq_rounded, size: 78, color: artForeground.withValues(alpha: .94)),
              Positioned(right: 14, bottom: 14, child: Icon(liquid ? Icons.blur_on_rounded : materialYou ? Icons.auto_awesome_rounded : Icons.graphic_eq_rounded, size: 23, color: artForeground.withValues(alpha: .68))),
            ]),
          );
          if (narrow) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [details, const SizedBox(height: 24), artwork]);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: details), const SizedBox(width: 22), artwork]);
        }),
      );
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.settings, required this.onImport});
  final AppSettings settings;
  final VoidCallback onImport;
  @override
  Widget build(BuildContext context) => GlassSurface(settings: settings, padding: const EdgeInsets.all(24), child: Column(children: [Icon(Icons.library_music_outlined, size: 38, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 10), Text('Здесь пока тихо', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 5), const Text('Добавь локальные аудиофайлы — и Oxygen соберёт их в твою библиотеку.', textAlign: TextAlign.center), const SizedBox(height: 14), FilledButton.icon(onPressed: onImport, icon: const Icon(Icons.add_rounded), label: const Text('Импортировать музыку'))]));
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(20), child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [Container(width: 44, height: 44, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: .13), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: Theme.of(context).colorScheme.primary)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)]))]))));
}
