import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/track.dart';
import '../services/app_settings.dart';
import '../services/audio_controller.dart';
import '../services/song_catalog_service.dart';
import '../widgets/glass_surface.dart';
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
                                                child: _AnimatedAlbumArt(settings: settings, isPlaying: audio.isPlaying, track: track, audio: audio),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 42),
                                          Expanded(
                                            flex: 6,
                                            child: SingleChildScrollView(
                                              padding: const EdgeInsets.symmetric(vertical: 8),
                                              child: GlassSurface(
                                                settings: settings,
                                                radius: settings.style == OxygenStyle.materialYou ? 32 : 28,
                                                blur: settings.style == OxygenStyle.liquidGlass && !settings.reducedEffects && constraints.maxWidth >= 850 ? 4.6 : 0,
                                                padding: const EdgeInsets.all(24),
                                                child: _PlayerControls(audio: audio, settings: settings),
                                              ),
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
                                          child: _AnimatedAlbumArt(settings: settings, isPlaying: audio.isPlaying, track: track, audio: audio),
                                        ),
                                        const SizedBox(height: 22),
                                        GlassSurface(
                                          settings: settings,
                                          radius: settings.style == OxygenStyle.materialYou ? 32 : 28,
                                          blur: settings.style == OxygenStyle.liquidGlass && !settings.reducedEffects && constraints.maxWidth >= 850 ? 4.6 : 0,
                                          padding: const EdgeInsets.all(20),
                                          child: _PlayerControls(audio: audio, settings: settings),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        _VolumeStrip(audio: audio, settings: settings),
                        if (audio.busy && audio.statusMessage != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2)),
                              const SizedBox(width: 9),
                              Flexible(child: Text(audio.statusMessage!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall)),
                            ]),
                          ),
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
                        if (audio.lastError != null && audio.current != null && audio.state == OxygenPlaybackState.stopped)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                FilledButton.tonalIcon(
                                  onPressed: audio.playCurrent,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Повторить'),
                                ),
                                if (!audio.current!.isRemote)
                                  OutlinedButton.icon(
                                    onPressed: audio.locateCurrentAudioFile,
                                    icon: const Icon(Icons.folder_open_rounded),
                                    label: const Text('Найти файл заново'),
                                  ),
                              ],
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
    final glass = settings.style == OxygenStyle.liquidGlass;
    final material = settings.style == OxygenStyle.materialYou;
    final stops = glass
        ? <Color>[
            settings.accent.withValues(alpha: settings.reducedEffects ? .09 : .18),
            const Color(0xFF182333),
            Theme.of(context).scaffoldBackgroundColor,
          ]
        : material
            ? <Color>[
                scheme.primaryContainer.withValues(alpha: .44),
                scheme.surface,
                Theme.of(context).scaffoldBackgroundColor,
              ]
            : <Color>[
                Theme.of(context).scaffoldBackgroundColor,
                Theme.of(context).scaffoldBackgroundColor,
                Theme.of(context).scaffoldBackgroundColor,
              ];
    return AnimatedContainer(
      duration: settings.animations ? const Duration(milliseconds: 420) : Duration.zero,
      curve: Curves.easeInOutCubic,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        gradient: RadialGradient(
          center: const Alignment(-.76, -.92),
          radius: 1.35,
          stops: const [0.0, 0.52, 1.0],
          colors: stops,
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: settings.style == OxygenStyle.liquidGlass ? Colors.transparent : Theme.of(context).colorScheme.surface,
      builder: (_) => LyricsSheet(settings: settings, track: track, audio: audio),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final track = audio.current;
    final material = settings.style == OxygenStyle.materialYou;
    final liquid = settings.style == OxygenStyle.liquidGlass;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: GlassSurface(
        settings: settings,
        radius: material ? 28 : liquid ? 26 : 18,
        blur: liquid && !settings.reducedEffects ? 4.6 : 0,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(
          children: [
            IconButton.filledTonal(
              onPressed: () => Navigator.of(context).maybePop(),
              tooltip: 'Свернуть плеер',
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'СЕЙЧАС ИГРАЕТ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.5, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(audio.isPlaying ? Icons.graphic_eq_rounded : Icons.music_note_rounded, size: 14, color: scheme.primary),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'Воспроизведение',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (track?.storeUrl != null)
              IconButton(
                tooltip: 'Открыть страницу трека',
                onPressed: () async {
                  final raw = audio.current?.storeUrl;
                  final url = raw == null ? null : Uri.tryParse(raw);
                  if (url != null) await launchUrl(url, mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.open_in_new_rounded),
              ),
            IconButton(tooltip: 'Текст песни', onPressed: () => _showLyrics(context), icon: const Icon(Icons.lyrics_outlined)),
            PopupMenuButton<String>(
              tooltip: 'Вид и режимы',
              onSelected: (value) {
                switch (value) {
                  case 'shuffle': audio.toggleShuffle(); break;
                  case 'repeat': audio.toggleRepeatOne(); break;
                  case 'visualizer': settings.setPlayerVisualizer(!settings.playerVisualizer); break;
                }
              },
              itemBuilder: (context) => [
                CheckedPopupMenuItem<String>(value: 'shuffle', checked: audio.shuffle, child: const Text('Перемешивание')),
                CheckedPopupMenuItem<String>(value: 'repeat', checked: audio.repeatOne, child: const Text('Повтор трека')),
                CheckedPopupMenuItem<String>(value: 'visualizer', checked: settings.playerVisualizer, child: const Text('Индикатор воспроизведения')),
              ],
              icon: const Icon(Icons.more_horiz_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedAlbumArt extends StatelessWidget {
  const _AnimatedAlbumArt({required this.settings, required this.isPlaying, required this.track, required this.audio});
  final AppSettings settings;
  final bool isPlaying;
  final Track track;
  final AudioController audio;

  @override
  Widget build(BuildContext context) {
    final duration = settings.animations
        ? const Duration(milliseconds: 260)
        : Duration.zero;
    return AnimatedScale(
      scale: isPlaying && settings.animations ? 1.012 : 1.0,
      duration: settings.animations ? const Duration(milliseconds: 420) : Duration.zero,
      curve: Curves.easeOutCubic,
      child: AnimatedSwitcher(
        duration: duration,
        reverseDuration: duration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: Tween<double>(begin: .965, end: 1).animate(animation), child: child),
        ),
        child: _AlbumArt(key: ValueKey<String>(track.id), settings: settings, isPlaying: isPlaying, track: track, audio: audio),
      ),
    );
  }
}

class _AlbumArt extends StatelessWidget {
  const _AlbumArt({super.key, required this.settings, required this.isPlaying, required this.track, required this.audio});
  final AppSettings settings;
  final bool isPlaying;
  final Track track;
  final AudioController audio;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final material = settings.style == OxygenStyle.materialYou;
    final glass = settings.style == OxygenStyle.liquidGlass;
    final radius = material ? 28.0 : glass ? 24.0 : 12.0;

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
                          errorBuilder: (_, _, _) => ColoredBox(color: scheme.surfaceContainerHighest, child: Icon(Icons.album_rounded, size: side * .45, color: scheme.onSurfaceVariant)),
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
                    ],
                    if (track.artworkUrl == null)
                      Positioned.fill(child: _ArtworkResolver(track: track)),
                    if (settings.playerVisualizer && isPlaying)
                      Positioned(
                        right: 18,
                        bottom: 18,
                        child: _PlayingIndicator(
                          audio: audio,
                          color: material ? scheme.onPrimaryContainer : Colors.white.withValues(alpha: .96),
                        ),
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

class _ArtworkResolver extends StatefulWidget {
  const _ArtworkResolver({required this.track});
  final Track track;

  @override
  State<_ArtworkResolver> createState() => _ArtworkResolverState();
}

class _ArtworkResolverState extends State<_ArtworkResolver> {
  late Future<String?> _future;

  @override
  void initState() {
    super.initState();
    _future = SongCatalogService.lookupArtwork(widget.track);
  }

  @override
  void didUpdateWidget(covariant _ArtworkResolver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _future = SongCatalogService.lookupArtwork(widget.track);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
        future: _future,
        builder: (context, snapshot) {
          final url = snapshot.data;
          if (url == null || url.isEmpty) return const SizedBox.expand();
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
            child: Image.network(
              url,
              key: ValueKey<String>(url),
              fit: BoxFit.cover,
              cacheWidth: 900,
              errorBuilder: (_, _, _) => const SizedBox.expand(),
            ),
          );
        },
      );
}

class _PlayingIndicator extends StatefulWidget {
  const _PlayingIndicator({required this.audio, required this.color});
  final AudioController audio;
  final Color color;

  @override
  State<_PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<_PlayingIndicator> {
  @override
  void initState() {
    super.initState();
    widget.audio.setVisualizerEnabled(true);
  }

  @override
  void didUpdateWidget(covariant _PlayingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audio != widget.audio) {
      oldWidget.audio.setVisualizerEnabled(false);
      widget.audio.setVisualizerEnabled(true);
    }
  }

  @override
  void dispose() {
    widget.audio.setVisualizerEnabled(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<double>>(
        valueListenable: widget.audio.visualizerBands,
        builder: (context, bands, _) => SizedBox(
          width: 48,
          height: 34,
          child: CustomPaint(painter: _SpectrumPainter(bands, widget.color)),
        ),
      );
}

class _SpectrumPainter extends CustomPainter {
  const _SpectrumPainter(this.bands, this.color);
  final List<double> bands;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    final count = bands.length.clamp(4, 10);
    final barWidth = (size.width / (count * 1.85)).clamp(2.0, 4.0).toDouble();
    final gap = (size.width - count * barWidth) / (count - 1);
    final paint = Paint()..color = color..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final raw = i < bands.length ? bands[i] : .04;
      final amplitude = raw.clamp(0.0, 1.0).toDouble();
      final barHeight = 5.0 + amplitude * (size.height - 6.0);
      final x = i * (barWidth + gap) + barWidth / 2;
      canvas.drawLine(Offset(x, size.height), Offset(x, size.height - barHeight), paint..strokeWidth = barWidth);
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) {
    if (oldDelegate.color != color || oldDelegate.bands.length != bands.length) {
      return true;
    }
    for (var index = 0; index < bands.length; index++) {
      if (oldDelegate.bands[index] != bands[index]) {
        return true;
      }
    }
    return false;
  }
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
    if (track == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final material = settings.style == OxygenStyle.materialYou;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: settings.animations ? const Duration(milliseconds: 260) : Duration.zero,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0, .04), end: Offset.zero).animate(animation),
                    child: child,
                  ),
                ),
                child: Column(
                  key: ValueKey<String>(track.id),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.8,
                            height: 1.02,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
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
        _PlaybackTimeline(audio: audio, formatTime: _time),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final compactControls = constraints.maxWidth < 390;
            final side = compactControls ? 40.0 : 46.0;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  constraints: BoxConstraints.tightFor(width: side, height: side),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: audio.toggleShuffle,
                  tooltip: 'Перемешивание',
                  color: audio.shuffle ? scheme.primary : scheme.onSurfaceVariant,
                  icon: const Icon(Icons.shuffle_rounded, size: 20),
                ),
                SizedBox(width: compactControls ? 0 : 4),
                IconButton(
                  constraints: BoxConstraints.tightFor(width: side, height: side),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: audio.previous,
                  tooltip: 'Предыдущий трек',
                  icon: const Icon(Icons.skip_previous_rounded, size: 29),
                ),
                SizedBox(width: compactControls ? 2 : 8),
                _PlayButton(audio: audio, materialYou: material, compact: compactControls),
                SizedBox(width: compactControls ? 2 : 8),
                IconButton(
                  constraints: BoxConstraints.tightFor(width: side, height: side),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: audio.next,
                  tooltip: 'Следующий трек',
                  icon: const Icon(Icons.skip_next_rounded, size: 29),
                ),
                SizedBox(width: compactControls ? 0 : 4),
                IconButton(
                  constraints: BoxConstraints.tightFor(width: side, height: side),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: audio.toggleRepeatOne,
                  tooltip: 'Повтор одного трека',
                  color: audio.repeatOne ? scheme.primary : scheme.onSurfaceVariant,
                  icon: const Icon(Icons.repeat_one_rounded, size: 20),
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
              settings: settings,
              icon: Icons.replay_10_rounded,
              label: '−10 сек',
              onPressed: () { audio.seek(audio.position - const Duration(seconds: 10)); },
            ),
            _PlayerActionChip(
              settings: settings,
              icon: Icons.forward_10_rounded,
              label: '+10 сек',
              onPressed: () { audio.seek(audio.position + const Duration(seconds: 10)); },
            ),
            _PlayerActionChip(
              settings: settings,
              icon: Icons.queue_music_rounded,
              label: 'Очередь · ${audio.queue.length}',
              onPressed: () => _showQueue(context),
            ),
            _PlayerActionChip(
              settings: settings,
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
          '${audio.queue.isEmpty ? 0 : audio.queue.length} треков в очереди · ${audio.isPlaying ? 'воспроизводится' : audio.state == OxygenPlaybackState.paused ? 'на паузе' : 'готов к воспроизведению'}',
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
      'Ровный': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      'Бас': [5, 5, 4, 3, 1, 0, 0, -1, -1, -2],
      'Рок': [4, 3, 2, 0, -1, 1, 3, 4, 4, 3],
      'Вокал': [-3, -2, -1, 2, 4, 4, 3, 2, 1, 0],
      'Электро': [4, 3, 1, 0, -1, 1, 3, 4, 3, 2],
      'Классика': [3, 2, 1, 0, -1, -1, 0, 2, 3, 4],
      'Джаз': [4, 2, 1, 2, -1, -1, 0, 1, 3, 4],
      'Подкаст': [-4, -2, 1, 3, 4, 4, 2, 0, -1, -2],
    };
    final bands = List<double>.from(settings.equalizerBands);
    while (bands.length < 10) { bands.add(0); }
    var selectedProfile = profiles.containsKey(settings.equalizerPreset) ? settings.equalizerPreset : 'Пользовательский';
    var eqEnabled = audio.equalizerEnabled;
    var limiter = audio.limiterEnabled;
    var reverb = audio.reverbEnabled;
    var reverbMix = audio.reverbMix;
    var spatial = audio.spatializerEnabled;
    var spatialWidth = audio.spatializerWidth;
    var mono = audio.monoDownmix;
    var preamp = audio.preampDb;
    var rate = audio.playbackRate;
    var pitch = audio.pitch;
    const labels = <String>['31 Hz', '63 Hz', '125 Hz', '250 Hz', '500 Hz', '1 kHz', '2 kHz', '4 kHz', '8 kHz', '16 kHz'];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: settings.style == OxygenStyle.liquidGlass ? Colors.transparent : null,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 18 + MediaQuery.viewInsetsOf(context).bottom),
            child: SingleChildScrollView(
              child: GlassSurface(
                settings: settings,
                radius: settings.style == OxygenStyle.liquidGlass ? 28 : 24,
                blur: settings.style == OxygenStyle.liquidGlass && !settings.reducedEffects ? 4.6 : 0,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: Text('Звук и эквалайзер', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900))),
                      IconButton(tooltip: 'Сбросить всё', onPressed: () async {
                        const flat = <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
                        setSheetState(() { for (var i = 0; i < 10; i++) { bands[i] = 0; } selectedProfile = 'Ровный'; preamp = 0; rate = 1; pitch = 1; });
                        await audio.setEqualizerBands(flat);
                        await settings.setEqualizerPreset('Ровный');
                        await settings.setEqualizerBands(flat);
                        await audio.setPreamp(0);
                        await audio.setPlaybackRate(1);
                        await audio.setPitch(1);
                      }, icon: const Icon(Icons.restart_alt_rounded)),
                    ]),
                    Text('Нативная обработка аудио: EQ, лимитер, реверберация и расширение стерео.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 14),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Эквалайзер'),
                      subtitle: const Text('10 полос · −12…+12 дБ'),
                      value: eqEnabled,
                      onChanged: (value) async { setSheetState(() => eqEnabled = value); await audio.setEqualizerEnabled(value); },
                    ),
                    AnimatedOpacity(
                      opacity: eqEnabled ? 1 : .42,
                      duration: settings.animations ? const Duration(milliseconds: 160) : Duration.zero,
                      child: IgnorePointer(
                        ignoring: !eqEnabled,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(
                            height: 88,
                            width: double.infinity,
                            child: CustomPaint(painter: _EqualizerCurvePainter(values: bands, color: Theme.of(context).colorScheme.primary, gridColor: Theme.of(context).dividerColor)),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              for (final entry in profiles.entries)
                                ChoiceChip(
                                  label: Text(entry.key),
                                  selected: selectedProfile == entry.key,
                                  onSelected: (selected) async {
                                    if (!selected) {
                                      return;
                                    }
                                    setSheetState(() { selectedProfile = entry.key; for (var i = 0; i < 10; i++) { bands[i] = entry.value[i]; } });
                                    await audio.setEqualizerBands(bands);
                                    await settings.setEqualizerPreset(entry.key);
                                    await settings.setEqualizerBands(bands);
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          for (var i = 0; i < labels.length; i++)
                            Row(children: [
                              SizedBox(width: 58, child: Text(labels[i], style: Theme.of(context).textTheme.labelMedium)),
                              Expanded(child: Slider(
                                min: -12, max: 12, divisions: 48,
                                value: bands[i].clamp(-12.0, 12.0).toDouble(),
                                label: '${bands[i].toStringAsFixed(1)} dB',
                                onChanged: (value) { setSheetState(() { bands[i] = value; selectedProfile = 'Пользовательский'; }); audio.previewEqualizerBands(bands); },
                                onChangeEnd: (_) async { await audio.setEqualizerBands(bands); await settings.setEqualizerPreset(selectedProfile); await settings.setEqualizerBands(bands); },
                              )),
                              SizedBox(width: 46, child: Text('${bands[i] > 0 ? '+' : ''}${bands[i].toStringAsFixed(1)} dB', textAlign: TextAlign.end, style: Theme.of(context).textTheme.labelSmall)),
                            ]),
                        ]),
                      ),
                    ),
                    const Divider(height: 24),
                    Text('Обработка', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('Лимитер'), subtitle: const Text('Уменьшает резкие пики громкости'), value: limiter, onChanged: (value) async { setSheetState(() => limiter = value); await audio.setLimiterEnabled(value); }),
                    SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('Комнатная реверберация'), value: reverb, onChanged: (value) async { setSheetState(() => reverb = value); await audio.setReverb(enabled: value, mix: reverbMix); }),
                    if (reverb) ...[
                      Row(children: [const SizedBox(width: 76, child: Text('Влажность')), Expanded(child: Slider(min: 0, max: .55, divisions: 22, value: reverbMix.clamp(0.0, .55).toDouble(), label: '${(reverbMix * 100).round()}%', onChanged: (v) => setSheetState(() => reverbMix = v), onChangeEnd: (v) => audio.setReverb(enabled: true, mix: v))), Text('${(reverbMix * 100).round()}%')]),
                    ],
                    SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('Широкое стерео'), value: spatial, onChanged: (value) async { setSheetState(() => spatial = value); await audio.setSpatializer(enabled: value, width: spatialWidth); }),
                    if (spatial) ...[
                      Row(children: [const SizedBox(width: 76, child: Text('Ширина')), Expanded(child: Slider(min: 1, max: 1.8, divisions: 16, value: spatialWidth.clamp(1.0, 1.8).toDouble(), label: spatialWidth.toStringAsFixed(2), onChanged: (v) => setSheetState(() => spatialWidth = v), onChangeEnd: (v) => audio.setSpatializer(enabled: true, width: v))), Text(spatialWidth.toStringAsFixed(2))]),
                    ],
                    SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('Моно'), subtitle: const Text('Смешать левый и правый каналы'), value: mono, onChanged: (value) async { setSheetState(() => mono = value); await audio.setMonoDownmix(value); }),
                    Row(children: [const SizedBox(width: 82, child: Text('Preamp')), Expanded(child: Slider(min: -6, max: 6, divisions: 48, value: preamp.clamp(-6.0, 6.0).toDouble(), label: '${preamp.toStringAsFixed(1)} dB', onChanged: (v) => setSheetState(() => preamp = v), onChangeEnd: audio.setPreamp)), SizedBox(width: 44, child: Text('${preamp.toStringAsFixed(1)} dB'))]),
                    const Divider(height: 24),
                    Text('Воспроизведение', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    Row(children: [const SizedBox(width: 82, child: Text('Скорость')), Expanded(child: Slider(min: .5, max: 2, divisions: 30, value: rate.clamp(.5, 2.0).toDouble(), label: '${rate.toStringAsFixed(2)}×', onChanged: (v) => setSheetState(() => rate = v), onChangeEnd: audio.setPlaybackRate)), SizedBox(width: 50, child: Text('${rate.toStringAsFixed(2)}×'))]),
                    Row(children: [const SizedBox(width: 82, child: Text('Высота тона')), Expanded(child: Slider(min: .5, max: 2, divisions: 30, value: pitch.clamp(.5, 2.0).toDouble(), label: '${pitch.toStringAsFixed(2)}×', onChanged: (v) => setSheetState(() => pitch = v), onChangeEnd: audio.setPitch)), SizedBox(width: 50, child: Text('${pitch.toStringAsFixed(2)}×'))]),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

}


class _EqualizerCurvePainter extends CustomPainter {
  const _EqualizerCurvePainter({required this.values, required this.color, required this.gridColor});
  final List<double> values;
  final Color color;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    final grid = Paint()..color = gridColor.withValues(alpha: .45)..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final points = <Offset>[];
    for (var i = 0; i < 10; i++) {
      final x = size.width * i / 9;
      final db = (i < values.length ? values[i] : 0).clamp(-12.0, 12.0).toDouble();
      final y = size.height * (1 - (db + 12) / 24);
      points.add(Offset(x, y));
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final midX = (previous.dx + current.dx) / 2;
      path.quadraticBezierTo(previous.dx + (midX - previous.dx) * .65, previous.dy, midX, (previous.dy + current.dy) / 2);
      path.quadraticBezierTo(midX + (current.dx - midX) * .35, current.dy, current.dx, current.dy);
    }
    final glow = Paint()..color = color.withValues(alpha: .08)..style = PaintingStyle.stroke..strokeWidth = 4..strokeCap = StrokeCap.round..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    final line = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, glow);
    canvas.drawPath(path, line);
    for (final point in points) {
      canvas.drawCircle(point, 2.2, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _EqualizerCurvePainter oldDelegate) {
    if (oldDelegate.color != color || oldDelegate.gridColor != gridColor || oldDelegate.values.length != values.length) {
      return true;
    }
    for (var i = 0; i < values.length; i++) { if (oldDelegate.values[i] != values[i]) return true; }
    return false;
  }
}

class _PlaybackTimeline extends StatefulWidget {
  const _PlaybackTimeline({required this.audio, required this.formatTime});
  final AudioController audio;
  final String Function(Duration) formatTime;

  @override
  State<_PlaybackTimeline> createState() => _PlaybackTimelineState();
}

class _PlaybackTimelineState extends State<_PlaybackTimeline> {
  double? _dragValue;

  Future<void> _commitSeek(double value, Duration duration) async {
    if (duration.inMilliseconds <= 0) {
      if (mounted) setState(() => _dragValue = null);
      return;
    }
    final target = Duration(
      milliseconds: (duration.inMilliseconds * value.clamp(0.0, 1.0)).round(),
    );
    try {
      await widget.audio.seek(target);
    } catch (_) {
      // Keep the controls responsive if the source cannot seek.
    } finally {
      if (mounted) setState(() => _dragValue = null);
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<PlaybackProgress>(
        valueListenable: widget.audio.playbackProgress,
        builder: (context, playback, _) {
          final value = (_dragValue ?? playback.value).clamp(0.0, 1.0).toDouble();
          final scheme = Theme.of(context).colorScheme;
          final canSeek = playback.duration.inMilliseconds > 0;
          final shownPosition = _dragValue == null
              ? playback.position
              : Duration(milliseconds: (playback.duration.inMilliseconds * _dragValue!).round());

          return Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: scheme.primary,
                  inactiveTrackColor: scheme.onSurfaceVariant.withValues(alpha: .24),
                  thumbColor: scheme.primary,
                  overlayColor: scheme.primary.withValues(alpha: .12),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  trackShape: const RoundedRectSliderTrackShape(),
                ),
                child: Slider(
                  value: value,
                  min: 0,
                  max: 1,
                  onChanged: canSeek ? (next) => setState(() => _dragValue = next) : null,
                  onChangeEnd: canSeek ? (next) => _commitSeek(next, playback.duration) : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.formatTime(shownPosition),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    Text(
                      widget.formatTime(playback.duration),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
}

class _PlayerActionChip extends StatelessWidget {
  const _PlayerActionChip({required this.settings, required this.icon, required this.label, required this.onPressed});
  final AppSettings settings;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final material = settings.style == OxygenStyle.materialYou;
    final liquid = settings.style == OxygenStyle.liquidGlass;
    return ActionChip(
      avatar: Icon(icon, size: 18, color: scheme.primary),
      label: Text(label),
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      backgroundColor: scheme.surfaceContainerHigh.withValues(alpha: liquid ? .34 : material ? .90 : .60),
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: liquid ? .40 : .55)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(material ? 18 : liquid ? 18 : 13)),
      elevation: 0,
      pressElevation: settings.reducedEffects ? 0 : 1.5,
    );
  }
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
    if (value.abs() < .01) {
      return 'Баланс';
    }
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
  const _VolumeStrip({required this.audio, required this.settings});
  final AudioController audio;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 3, 18, 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 740),
            child: GlassSurface(
              settings: settings,
              radius: settings.style == OxygenStyle.materialYou ? 24 : 19,
              blur: settings.style == OxygenStyle.liquidGlass && !settings.reducedEffects ? 4.6 : 0,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
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
    final size = compact ? 54.0 : materialYou ? 72.0 : 68.0;
    return SizedBox(
      width: size,
      height: size,
      child: FilledButton(
        onPressed: audio.togglePlay,
        style: FilledButton.styleFrom(shape: const CircleBorder(), padding: EdgeInsets.zero),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 170),
          transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: FadeTransition(opacity: animation, child: child)),
          child: Icon(
            audio.busy ? Icons.hourglass_top_rounded : audio.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            key: ValueKey<String>(audio.busy ? 'busy' : audio.isPlaying ? 'pause' : 'play'),
            size: 36,
          ),
        ),
      ),
    );
  }
}
