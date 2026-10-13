import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/audio_controller.dart';
import '../services/app_settings.dart';

class TrackTile extends StatelessWidget {
  const TrackTile({super.key, required this.track, required this.audio, required this.settings, this.index, this.onRemove, this.playQueue});
  final Track track;
  final AudioController audio;
  final AppSettings settings;
  final int? index;
  final VoidCallback? onRemove;
  final List<Track>? playQueue;

  void _play() => audio.playTrack(track, from: playQueue);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = audio.current?.id == track.id;
    final favorite = audio.favoriteIds.contains(track.id);
    final compact = settings.compact;
    final materialYou = settings.style == OxygenStyle.materialYou;
    final liquid = settings.style == OxygenStyle.liquidGlass;
    final radius = materialYou ? 24.0 : (liquid ? 20.0 : 12.0);
    final activeFill = materialYou
        ? scheme.secondaryContainer.withValues(alpha: .72)
        : scheme.primary.withValues(alpha: liquid ? .13 : .075);

    final tileBody = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: _play,
        borderRadius: BorderRadius.circular(radius),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 5 : 8),
          child: Row(
            children: [
              _Cover(track: track, active: active, size: compact ? 40 : 46, settings: settings),
              if (index != null) ...[
                const SizedBox(width: 10),
                SizedBox(width: 24, child: Text('${index! + 1}'.padLeft(2, '0'), style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant))),
              ],
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
                    const SizedBox(height: 3),
                    Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              IconButton(
                tooltip: favorite ? 'Убрать из избранного' : 'В избранное',
                onPressed: () => audio.toggleFavorite(track),
                visualDensity: VisualDensity.compact,
                icon: Icon(favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: favorite ? const Color(0xFFFF6F91) : scheme.onSurfaceVariant, size: 21),
              ),
              if (onRemove != null)
                IconButton(tooltip: 'Удалить из библиотеки', onPressed: onRemove, visualDensity: VisualDensity.compact, icon: const Icon(Icons.close_rounded, size: 20)),
              IconButton(
                tooltip: active && audio.isPlaying ? 'Пауза' : 'Слушать',
                onPressed: () => active ? audio.togglePlay() : _play,
                visualDensity: VisualDensity.compact,
                style: materialYou && active ? IconButton.styleFrom(backgroundColor: scheme.primaryContainer, foregroundColor: scheme.onPrimaryContainer) : null,
                icon: Icon(active && audio.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 23),
              ),
            ],
          ),
        ),
      ),
    );
    final decoration = BoxDecoration(
      color: active ? activeFill : Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      border: liquid && active ? Border.all(color: Colors.white.withValues(alpha: .16)) : null,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 3 : 6),
      child: settings.animations && !settings.reducedEffects
          ? AnimatedContainer(duration: const Duration(milliseconds: 120), decoration: decoration, child: tileBody)
          : Container(decoration: decoration, child: tileBody),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.track, required this.active, required this.size, required this.settings});
  final Track track;
  final bool active;
  final double size;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final materialYou = settings.style == OxygenStyle.materialYou;
    final liquid = settings.style == OxygenStyle.liquidGlass;
    final scheme = Theme.of(context).colorScheme;
    final color = settings.style == OxygenStyle.oxygen ? scheme.onSurface : settings.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(materialYou ? size * .34 : (liquid ? size * .27 : size * .22)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: settings.style == OxygenStyle.oxygen
              ? [scheme.surfaceContainerHighest, scheme.surface]
              : [color.withValues(alpha: .96), color.withValues(alpha: .46), scheme.surfaceContainerHighest],
        ),
        border: liquid ? Border.all(color: Colors.white.withValues(alpha: .35)) : null,
        boxShadow: liquid && !settings.reducedEffects ? [BoxShadow(color: color.withValues(alpha: .09), blurRadius: 7, offset: const Offset(0, 2))] : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: track.artworkUrl != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  track.artworkUrl!,
                  fit: BoxFit.cover,
                  cacheWidth: (size * 2).round(),
                  errorBuilder: (_, __, ___) => Icon(Icons.music_note_rounded, color: scheme.onSurfaceVariant, size: size * .5),
                ),
                if (active)
                  DecoratedBox(
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: .24)),
                    child: Icon(Icons.graphic_eq_rounded, color: Colors.white, size: size * .5),
                  ),
              ],
            )
          : Icon(
              active ? Icons.graphic_eq_rounded : Icons.music_note_rounded,
              color: settings.style == OxygenStyle.oxygen ? (scheme.brightness == Brightness.dark ? Colors.white : Colors.black) : (color.computeLuminance() > .55 ? Colors.black : Colors.white),
              size: size * .5,
            ),
    );
  }
}
