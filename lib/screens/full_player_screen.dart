import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/track.dart';
import '../services/app_settings.dart';
import '../services/audio_controller.dart';
import 'lyrics_sheet.dart';

/// Full player. Playback progress has its own ValueNotifier, so audio position
/// updates repaint only the timeline and do not rebuild this entire screen.
class FullPlayerScreen extends StatelessWidget {
  const FullPlayerScreen({super.key, required this.audio, required this.settings});

  final AudioController audio;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: settings,
        builder: (context, _) => AnimatedBuilder(
          animation: audio,
          builder: (context, _) {
            final track = audio.current;
            if (track == null) {
              return Scaffold(
                appBar: AppBar(title: const Text('Плеер')),
                body: const Center(child: Text('Сначала выбери трек')),
              );
            }

            final scheme = Theme.of(context).colorScheme;
            return Scaffold(
              body: Stack(
                children: [
                  Positioned.fill(child: RepaintBoundary(child: _PlayerBackground(settings: settings))),
                  SafeArea(
                    child: Column(
                      children: [
                        _PlayerHeader(audio: audio, settings: settings),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final desktop = constraints.maxWidth >= 850;
                              if (desktop) {
                                return Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 1180),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(30, 14, 30, 18),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Expanded(
                                            flex: 5,
                                            child: Center(
                                              child: ConstrainedBox(
                                                constraints: const BoxConstraints(maxWidth: 440),
                                                child: _AlbumArt(
                                                  settings: settings,
                                                  isPlaying: audio.isPlaying,
                                                  track: track,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 42),
                                          Expanded(
                                            flex: 6,
                                            child: SingleChildScrollView(
                                              padding: const EdgeInsets.symmetric(vertical: 8),
                                              child: _PlayerControls(audio: audio, settings: settings),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }

                              final artSide = (constraints.maxWidth - 44).clamp(160.0, 350.0).toDouble();
                              return SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 520),
                                    child: Column(
                                      children: [
                                        SizedBox(
                                          width: artSide,
                                          child: _AlbumArt(settings: settings, isPlaying: audio.isPlaying, track: track),
                                        ),
                                        const SizedBox(height: 26),
                                        _PlayerControls(audio: audio, settings: settings),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        _VolumeStrip(audio: audio),
                        if (audio.lastError != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                            child: Text(
                              audio.lastError!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: scheme.error),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
}

class _PlayerBackground extends StatelessWidget {
  const _PlayerBackground({required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (settings.style == OxygenStyle.oxygen) {
      return ColoredBox(color: Theme.of(context).scaffoldBackgroundColor);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-.72, -.88),
          radius: 1.25,
          colors: settings.style == OxygenStyle.liquidGlass
              ? [
                  settings.accent.withValues(alpha: settings.reducedEffects ? .11 : .20),
                  Theme.of(context).scaffoldBackgroundColor,
                  const Color(0xFF111B2B),
                ]
              : [
                  scheme.primaryContainer.withValues(alpha: .55),
                  Theme.of(context).scaffoldBackgroundColor,
                  Theme.of(context).scaffoldBackgroundColor,
                ],
        ),
      ),
    );
  }
}

class _PlayerHeader extends StatelessWidget {
  const _PlayerHeader({required this.audio, required this.settings});
  final AudioController audio;
  final AppSettings settings;

  void _showLyrics(BuildContext context) {
    final track = audio.current;
    if (track == null) return;
    final liquid = settings.style == OxygenStyle.liquidGlass;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: liquid ? Colors.transparent : Theme.of(context).colorScheme.surface,
      builder: (_) => LyricsSheet(settings: settings, track: track),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      child: Row(
        children: [
          IconButton.filledTonal(
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Свернуть плеер',
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
          ),
          const Spacer(),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'СЕЙЧАС ИГРАЕТ',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.7,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 3),
              Text(
                settings.style == OxygenStyle.materialYou ? 'Oxygen · Player' : 'Из твоей библиотеки',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const Spacer(),
          if (audio.current?.storeUrl != null)
            IconButton(
              tooltip: 'Открыть в Apple Music',
              onPressed: () async {
                final url = audio.current?.storeUrl;
                if (url != null) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.open_in_new_rounded),
            ),
          IconButton(
            tooltip: 'Текст песни',
            onPressed: () => _showLyrics(context),
            icon: const Icon(Icons.lyrics_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Вид и режимы',
            onSelected: (value) {
              switch (value) {
                case 'shuffle':
                  audio.toggleShuffle();
                  break;
                case 'repeat':
                  audio.toggleRepeatOne();
                  break;
                case 'visualizer':
                  settings.setPlayerVisualizer(!settings.playerVisualizer);
                  break;
                case 'wave':
                  settings.setWaveformTimeline(!settings.waveformTimeline);
                  break;
              }
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem<String>(value: 'shuffle', checked: audio.shuffle, child: const Text('Перемешивание')),
              CheckedPopupMenuItem<String>(value: 'repeat', checked: audio.repeatOne, child: const Text('Повтор трека')),
              CheckedPopupMenuItem<String>(value: 'visualizer', checked: settings.playerVisualizer, child: const Text('Индикатор воспроизведения')),
              CheckedPopupMenuItem<String>(value: 'wave', checked: settings.waveformTimeline, child: const Text('Волнистая шкала')),
            ],
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
    );
  }
}

class _AlbumArt extends StatelessWidget {
  const _AlbumArt({required this.settings, required this.isPlaying, required this.track});
  final AppSettings settings;
  final bool isPlaying;
  final Track track;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final material = settings.style == OxygenStyle.materialYou;
    final glass = settings.style == OxygenStyle.liquidGlass;
    final radius = material ? 34.0 : glass ? 30.0 : 20.0;

    return RepaintBoundary(
      child: AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: material
                    ? [scheme.primaryContainer, scheme.secondaryContainer, scheme.tertiaryContainer]
                    : glass
                        ? [settings.accent.withValues(alpha: .84), const Color(0xFF314865), const Color(0xFF111B2B)]
                        : [scheme.onSurface, scheme.surfaceContainerHighest, scheme.surface],
              ),
              border: glass ? Border.all(color: Colors.white.withValues(alpha: .48), width: 1.2) : null,
              boxShadow: !settings.reducedEffects && glass
                  ? [BoxShadow(color: settings.accent.withValues(alpha: .16), blurRadius: 18, offset: const Offset(0, 8))]
                  : null,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final side = constraints.maxWidth;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (track.artworkUrl != null) ...[
                      Positioned.fill(
                        child: Image.network(
                          track.artworkUrl!,
                          fit: BoxFit.cover,
                          cacheWidth: (side * 2).round(),
                          errorBuilder: (_, __, ___) => ColoredBox(color: scheme.surfaceContainerHighest, child: Icon(Icons.album_rounded, size: side * .45, color: scheme.onSurfaceVariant)),
                        ),
                      ),
                      if (track.isRemote)
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: DecoratedBox(
                              decoration: BoxDecoration(color: Colors.black.withValues(alpha: .62), borderRadius: BorderRadius.circular(14)),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                child: Text('iTunes Preview', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                              ),
                            ),
                          ),
                        ),
                    ] else if (material) ...[
                      Positioned(
                        right: side * .10,
                        top: side * .11,
                        child: Transform.rotate(
                          angle: .16,
                          child: Container(
                            width: side * .37,
                            height: side * .37,
                            decoration: BoxDecoration(
                              color: scheme.tertiary.withValues(alpha: .70),
                              borderRadius: BorderRadius.circular(side * .13),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: side * .12,
                        bottom: side * .12,
                        child: Container(
                          width: side * .23,
                          height: side * .23,
                          decoration: BoxDecoration(
                            color: scheme.secondary.withValues(alpha: .60),
                            borderRadius: BorderRadius.circular(side * .08),
                          ),
                        ),
                      ),
                      Center(
                        child: Container(
                          width: side * .45,
                          height: side * .45,
                          decoration: BoxDecoration(
                            color: scheme.surface.withValues(alpha: .66),
                            borderRadius: BorderRadius.circular(side * .15),
                            border: Border.all(color: Colors.white.withValues(alpha: .36)),
                          ),
                          child: Icon(Icons.graphic_eq_rounded, size: side * .25, color: scheme.onSurface),
                        ),
                      ),
                      Positioned(
                        left: side * .10,
                        top: side * .10,
                        child: Text(
                          'OXYGEN',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: scheme.onSurface.withValues(alpha: .72),
                                letterSpacing: 2.1,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                    ] else if (glass) ...[
                      Positioned(
                        left: -side * .18,
                        top: -side * .10,
                        child: Container(
                          width: side * .80,
                          height: side * .80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(colors: [Colors.white.withValues(alpha: .32), Colors.white.withValues(alpha: .015)]),
                            border: Border.all(color: Colors.white.withValues(alpha: .22)),
                          ),
                        ),
                      ),
                      Positioned(
                        right: side * .10,
                        top: side * .13,
                        child: Container(
                          width: side * .15,
                          height: side * .15,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: .14),
                            border: Border.all(color: Colors.white.withValues(alpha: .50)),
                          ),
                        ),
                      ),
                      Center(
                        child: Container(
                          width: side * .48,
                          height: side * .48,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(side * .18),
                            border: Border.all(color: Colors.white.withValues(alpha: .44)),
                          ),
                          child: Icon(Icons.graphic_eq_rounded, size: side * .26, color: Colors.white),
                        ),
                      ),
                    ] else ...[
                      Center(child: Icon(Icons.graphic_eq_rounded, size: side * .46, color: scheme.surface)),
                      Positioned(left: side * .12, bottom: side * .11, child: Text('OXYGEN / LOCAL PLAYER', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.surface, letterSpacing: 1.3))),
                    ],
                    if (settings.playerVisualizer && isPlaying)
                      Positioned(
                        right: 18,
                        bottom: 18,
                        child: settings.animations && !settings.reducedEffects
                            ? const _PlayingIndicator()
                            : Icon(Icons.equalizer_rounded, color: material ? scheme.onPrimaryContainer : Colors.white.withValues(alpha: .9), size: 28),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayingIndicator extends StatefulWidget {
  const _PlayingIndicator();
  @override
  State<_PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<_PlayingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 32,
        height: 28,
        child: CustomPaint(painter: _BarsPainter(_controller, Colors.white)),
      );
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.animation, this.color) : super(repaint: animation);
  final Animation<double> animation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const count = 4;
    final barWidth = 4.0;
    final gap = (size.width - count * barWidth) / (count * 2 - 2);
    for (var i = 0; i < count; i++) {
      final phase = animation.value * math.pi * 2 + i * .92;
      final h = 7 + 17 * ((math.sin(phase) + 1) / 2);
      final left = i * (barWidth + gap * 2);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, size.height - h, barWidth, h),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter oldDelegate) => color != oldDelegate.color;
}

class _PlayerControls extends StatelessWidget {
  const _PlayerControls({required this.audio, required this.settings});
  final AudioController audio;
  final AppSettings settings;

  String _time(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = value.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final track = audio.current;
    if (track == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final material = settings.style == OxygenStyle.materialYou;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.7,
                        ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: audio.favoriteIds.contains(track.id) ? 'Убрать из избранного' : 'В избранное',
              onPressed: () => audio.toggleFavorite(track),
              icon: Icon(
                audio.favoriteIds.contains(track.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: audio.favoriteIds.contains(track.id) ? const Color(0xFFFF6E97) : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _PlaybackTimeline(audio: audio, settings: settings, formatTime: _time),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final showJumpButtons = constraints.maxWidth >= 420;
            final compactControls = constraints.maxWidth < 360;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  visualDensity: compactControls ? VisualDensity.compact : VisualDensity.standard,
                  onPressed: audio.toggleShuffle,
                  tooltip: 'Перемешивание',
                  color: audio.shuffle ? scheme.primary : scheme.onSurfaceVariant,
                  icon: const Icon(Icons.shuffle_rounded),
                ),
                IconButton(
                  visualDensity: compactControls ? VisualDensity.compact : VisualDensity.standard,
                  onPressed: audio.previous,
                  tooltip: 'Предыдущий трек',
                  icon: const Icon(Icons.skip_previous_rounded, size: 32),
                ),
                if (showJumpButtons)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => audio.seek(audio.position - const Duration(seconds: 10)),
                    tooltip: 'Назад на 10 секунд',
                    icon: const Icon(Icons.replay_10_rounded, size: 25),
                  ),
                _PlayButton(audio: audio, materialYou: material, compact: compactControls),
                if (showJumpButtons)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => audio.seek(audio.position + const Duration(seconds: 10)),
                    tooltip: 'Вперёд на 10 секунд',
                    icon: const Icon(Icons.forward_10_rounded, size: 25),
                  ),
                IconButton(
                  visualDensity: compactControls ? VisualDensity.compact : VisualDensity.standard,
                  onPressed: audio.next,
                  tooltip: 'Следующий трек',
                  icon: const Icon(Icons.skip_next_rounded, size: 32),
                ),
                IconButton(
                  visualDensity: compactControls ? VisualDensity.compact : VisualDensity.standard,
                  onPressed: audio.toggleRepeatOne,
                  tooltip: 'Повтор одного трека',
                  color: audio.repeatOne ? scheme.primary : scheme.onSurfaceVariant,
                  icon: const Icon(Icons.repeat_one_rounded),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _PlayerActionChip(
              icon: Icons.queue_music_rounded,
              label: 'Очередь · ${audio.queue.length}',
              onPressed: () => _showQueue(context),
            ),
            _PlayerActionChip(
              icon: Icons.equalizer_rounded,
              label: 'Эквалайзер',
              onPressed: () => _showEqualizer(context),
            ),
            _SleepTimerButton(audio: audio),
            _BalanceButton(audio: audio),
          ],
        ),
        if (audio.busy) ...[
          const SizedBox(height: 14),
          const LinearProgressIndicator(minHeight: 2),
        ],
        const SizedBox(height: 12),
        Text(
          'Локальное воспроизведение · ${audio.queue.isEmpty ? 0 : audio.queue.length} треков в очереди',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  void _showQueue(BuildContext context) {
    final queuedTracks = List<Track>.from(audio.queue);
    final currentId = audio.current?.id;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Очередь воспроизведения', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text('${queuedTracks.length} треков', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: queuedTracks.isEmpty
                    ? const Center(child: Text('Очередь пока пуста'))
                    : ListView.separated(
                        itemCount: queuedTracks.length,
                        separatorBuilder: (context, index) => const Divider(height: 1, indent: 72),
                        itemBuilder: (context, index) {
                          final item = queuedTracks[index];
                          final active = item.id == currentId;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: active ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHigh,
                              child: Icon(active ? Icons.graphic_eq_rounded : Icons.music_note_rounded),
                            ),
                            title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(item.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: active ? const Icon(Icons.volume_up_rounded) : Text('${index + 1}', style: Theme.of(context).textTheme.labelMedium),
                            selected: active,
                            onTap: () {
                              Navigator.pop(sheetContext);
                              audio.playTrack(item, from: queuedTracks);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEqualizer(BuildContext context) {
    const profiles = <String, List<double>>{
      'Ровный': [0, 0, 0, 0, 0],
      'Бас': [6, 4, 1, 0, -1],
      'Рок': [4, 2, -1, 3, 5],
      'Вокал': [-2, 0, 4, 3, 1],
      'Электро': [4, 2, 0, 3, 4],
    };
    final bands = List<double>.from(settings.equalizerBands);
    var selectedProfile = profiles.containsKey(settings.equalizerPreset) ? settings.equalizerPreset : 'Пользовательский';
    const labels = <String>['60 Hz', '250 Hz', '1 kHz', '4 kHz', '16 kHz'];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Эквалайзер', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 5),
                  Text(
                    'Профили хранятся в Oxygen. В текущей сборке они пока не меняют сам звуковой сигнал: для настоящего эквалайзера нужен DSP-аудиомодуль.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.35),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in profiles.entries)
                        ChoiceChip(
                          label: Text(entry.key),
                          selected: selectedProfile == entry.key,
                          onSelected: (selected) async {
                            if (!selected) return;
                            setSheetState(() {
                              selectedProfile = entry.key;
                              for (var i = 0; i < bands.length; i++) {
                                bands[i] = entry.value[i];
                              }
                            });
                            await settings.setEqualizerPreset(entry.key);
                            await settings.setEqualizerBands(bands);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < labels.length; i++)
                    Row(
                      children: [
                        SizedBox(width: 58, child: Text(labels[i], style: Theme.of(context).textTheme.labelMedium)),
                        Expanded(
                          child: Slider(
                            min: -8,
                            max: 8,
                            divisions: 32,
                            value: bands[i].clamp(-8.0, 8.0).toDouble(),
                            label: '${bands[i].toStringAsFixed(1)} dB',
                            onChanged: (value) => setSheetState(() {
                              bands[i] = value;
                              selectedProfile = 'Пользовательский';
                            }),
                            onChangeEnd: (_) async {
                              await settings.setEqualizerPreset(selectedProfile);
                              await settings.setEqualizerBands(bands);
                            },
                          ),
                        ),
                        SizedBox(width: 42, child: Text('${bands[i] > 0 ? '+' : ''}${bands[i].toStringAsFixed(1)}', textAlign: TextAlign.end)),
                      ],
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        setSheetState(() {
                          for (var i = 0; i < bands.length; i++) {
                            bands[i] = 0;
                          }
                          selectedProfile = 'Ровный';
                        });
                        await settings.setEqualizerPreset('Ровный');
                        await settings.setEqualizerBands(bands);
                      },
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Сбросить'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaybackTimeline extends StatefulWidget {
  const _PlaybackTimeline({required this.audio, required this.settings, required this.formatTime});
  final AudioController audio;
  final AppSettings settings;
  final String Function(Duration) formatTime;

  @override
  State<_PlaybackTimeline> createState() => _PlaybackTimelineState();
}

class _PlaybackTimelineState extends State<_PlaybackTimeline> {
  double? _dragValue;

  Future<void> _commitSeek(double value, Duration duration) async {
    final target = Duration(milliseconds: (duration.inMilliseconds * value.clamp(0.0, 1.0)).round());
    try {
      await widget.audio.seek(target);
    } catch (_) {
      // The UI remains responsive when the backend cannot seek a source.
    } finally {
      if (mounted) setState(() => _dragValue = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final useWave = widget.settings.style == OxygenStyle.materialYou && widget.settings.waveformTimeline;
    return ValueListenableBuilder<PlaybackProgress>(
      valueListenable: widget.audio.playbackProgress,
      builder: (context, playback, _) {
        final value = (_dragValue ?? playback.value).clamp(0.0, 1.0).toDouble();
        final scheme = Theme.of(context).colorScheme;
        return Column(
          children: [
            if (useWave)
              LayoutBuilder(
                builder: (context, constraints) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) => _commitSeek(
                    constraints.maxWidth <= 0 ? 0 : details.localPosition.dx / constraints.maxWidth,
                    playback.duration,
                  ),
                  onHorizontalDragStart: (details) => setState(() {
                    _dragValue = constraints.maxWidth <= 0 ? 0 : (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0).toDouble();
                  }),
                  onHorizontalDragUpdate: (details) => setState(() {
                    _dragValue = constraints.maxWidth <= 0 ? 0 : (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0).toDouble();
                  }),
                  onHorizontalDragEnd: (_) => _commitSeek(_dragValue ?? value, playback.duration),
                  child: SizedBox(
                    width: double.infinity,
                    height: 34,
                    child: CustomPaint(
                      painter: _WaveTimelinePainter(
                        progress: value,
                        played: scheme.primary,
                        unplayed: scheme.onSurfaceVariant.withValues(alpha: .30),
                      ),
                    ),
                  ),
                ),
              )
            else
              Slider(
                value: value,
                min: 0,
                max: 1,
                onChanged: (next) => setState(() => _dragValue = next),
                onChangeEnd: (next) => _commitSeek(next, playback.duration),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(widget.formatTime(_dragValue == null ? playback.position : Duration(milliseconds: (playback.duration.inMilliseconds * _dragValue!).round())), style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  Text(widget.formatTime(playback.duration), style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WaveTimelinePainter extends CustomPainter {
  const _WaveTimelinePainter({required this.progress, required this.played, required this.unplayed});
  final double progress;
  final Color played;
  final Color unplayed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final center = size.height / 2;
    final path = Path()..moveTo(0, center);
    // Fewer line segments produce the same visual impression with less work
    // on each throttled playback-progress tick.
    const segments = 52;
    for (var i = 1; i <= segments; i++) {
      final x = size.width * i / segments;
      final y = center + math.sin((x / size.width) * math.pi * 16) * 3.1;
      path.lineTo(x, y);
    }
    final basePaint = Paint()..color = unplayed..style = PaintingStyle.stroke..strokeWidth = 2.2..strokeCap = StrokeCap.round;
    final activePaint = Paint()..color = played..style = PaintingStyle.stroke..strokeWidth = 2.8..strokeCap = StrokeCap.round;
    canvas.drawPath(path, basePaint);
    final activeWidth = (size.width * progress.clamp(0.0, 1.0)).toDouble();
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, activeWidth, size.height));
    canvas.drawPath(path, activePaint);
    canvas.restore();
    final head = Offset(activeWidth, center);
    canvas.drawCircle(head, 5, Paint()..color = played);
    canvas.drawCircle(head, 2, Paint()..color = Colors.white.withValues(alpha: .92));
  }

  @override
  bool shouldRepaint(covariant _WaveTimelinePainter oldDelegate) =>
      progress != oldDelegate.progress || played != oldDelegate.played || unplayed != oldDelegate.unplayed;
}

class _PlayerActionChip extends StatelessWidget {
  const _PlayerActionChip({required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ActionChip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
      );
}

class _SleepTimerButton extends StatelessWidget {
  const _SleepTimerButton({required this.audio});
  final AudioController audio;

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
        tooltip: 'Таймер сна',
        onSelected: (minutes) => audio.setSleepTimer(minutes == 0 ? null : minutes),
        itemBuilder: (context) => [
          const PopupMenuItem<int>(value: 0, child: Text('Отключить таймер')),
          for (final minutes in <int>[15, 30, 45, 60]) PopupMenuItem<int>(value: minutes, child: Text('$minutes минут')),
        ],
        child: Chip(
          avatar: const Icon(Icons.bedtime_outlined, size: 18),
          label: Text(audio.sleepTimerMinutes == null ? 'Таймер' : '${audio.sleepTimerMinutes} мин'),
          visualDensity: VisualDensity.compact,
        ),
      );
}

class _BalanceButton extends StatelessWidget {
  const _BalanceButton({required this.audio});
  final AudioController audio;

  String _label(double value) {
    if (value.abs() < .01) return 'Баланс';
    return value < 0 ? 'L ${(-value * 100).round()}%' : 'R ${(value * 100).round()}%';
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<double>(
        tooltip: 'Стереобаланс',
        onSelected: audio.setBalance,
        itemBuilder: (context) => const [
          PopupMenuItem<double>(value: -1, child: Text('Только левый канал')),
          PopupMenuItem<double>(value: -.5, child: Text('L · 50%')),
          PopupMenuItem<double>(value: 0, child: Text('По центру')),
          PopupMenuItem<double>(value: .5, child: Text('R · 50%')),
          PopupMenuItem<double>(value: 1, child: Text('Только правый канал')),
        ],
        child: Chip(
          avatar: const Icon(Icons.graphic_eq_rounded, size: 18),
          label: Text(_label(audio.balance)),
          visualDensity: VisualDensity.compact,
        ),
      );
}

class _VolumeStrip extends StatelessWidget {
  const _VolumeStrip({required this.audio});
  final AudioController audio;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 3, 18, 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 740),
            child: ValueListenableBuilder<double>(
              valueListenable: audio.volumeListenable,
              builder: (context, volume, _) => Row(
                children: [
                  Icon(Icons.volume_down_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20),
                  Expanded(child: Slider(value: volume, onChanged: audio.setVolume)),
                  Icon(Icons.volume_up_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20),
                  const SizedBox(width: 8),
                  SizedBox(width: 38, child: Text('${(volume * 100).round()}%', textAlign: TextAlign.end, style: Theme.of(context).textTheme.labelMedium)),
                ],
              ),
            ),
          ),
        ),
      );
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.audio, required this.materialYou, this.compact = false});
  final AudioController audio;
  final bool materialYou;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 56.0 : materialYou ? 70.0 : 66.0;
    return SizedBox(
      width: size,
      height: size,
      child: FilledButton(
        onPressed: audio.togglePlay,
        style: FilledButton.styleFrom(shape: const CircleBorder(), padding: EdgeInsets.zero),
        child: Icon(
          audio.busy ? Icons.hourglass_top_rounded : audio.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 36,
        ),
      ),
    );
  }
}
