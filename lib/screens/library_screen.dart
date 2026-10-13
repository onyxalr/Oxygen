import 'dart:async';

import 'package:flutter/material.dart';
import '../services/app_settings.dart';
import '../services/audio_controller.dart';
import '../widgets/track_tile.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.settings, required this.audio, required this.favoritesOnly, required this.onImport});
  final AppSettings settings;
  final AudioController audio;
  final bool favoritesOnly;
  final VoidCallback onImport;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController controller = TextEditingController();
  String query = '';
  Timer? _queryDebounce;

  void _queueQuery(String value) {
    _queryDebounce?.cancel();
    _queryDebounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => query = value.trim());
    });
  }

  @override
  void dispose() {
    _queryDebounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.audio,
        builder: (context, _) {
          final source = widget.favoritesOnly
              ? widget.audio.library.where((track) => widget.audio.favoriteIds.contains(track.id))
              : widget.audio.library;
          final normalizedQuery = query.trim().toLowerCase();
          final tracks = source
              .where((track) => widget.audio.searchableText(track).contains(normalizedQuery))
              .toList(growable: false);

          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.favoritesOnly ? 'Избранное' : 'Моя музыка', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Text('${tracks.length} ${_trackWord(tracks.length)}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controller,
                              onChanged: _queueQuery,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search_rounded),
                                hintText: 'Найти трек в библиотеке',
                                suffixIcon: query.isEmpty
                                    ? null
                                    : IconButton(
                                        onPressed: () {
                                          _queryDebounce?.cancel();
                                          controller.clear();
                                          setState(() => query = '');
                                        },
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.tonalIcon(onPressed: widget.onImport, icon: const Icon(Icons.add_rounded), label: const Text('Добавить')),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              if (tracks.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
                  sliver: SliverToBoxAdapter(child: _EmptyState(favorites: widget.favoritesOnly, onImport: widget.onImport)),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final track = tracks[index];
                        return TrackTile(
                          key: ValueKey(track.id),
                          track: track,
                          audio: widget.audio,
                          settings: widget.settings,
                          index: index,
                          onRemove: widget.favoritesOnly ? null : () => widget.audio.removeTrack(track),
                        );
                      },
                      childCount: tracks.length,
                    ),
                  ),
                ),
            ],
          );
        },
      );

  String _trackWord(int count) {
    final lastTwo = count % 100;
    final last = count % 10;
    if (lastTwo >= 11 && lastTwo <= 14) return 'треков';
    if (last == 1) return 'трек';
    if (last >= 2 && last <= 4) return 'трека';
    return 'треков';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.favorites, required this.onImport});
  final bool favorites;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 58),
        child: Column(
          children: [
            Icon(favorites ? Icons.favorite_border_rounded : Icons.library_music_outlined, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(favorites ? 'Избранное пока пусто' : 'Библиотека пока пуста', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(favorites ? 'Отмечай сердечком треки, к которым хочешь вернуться.' : 'Добавь аудиофайлы с компьютера, чтобы начать слушать.', textAlign: TextAlign.center),
            if (!favorites) ...[
              const SizedBox(height: 18),
              FilledButton.icon(onPressed: onImport, icon: const Icon(Icons.add_rounded), label: const Text('Импортировать аудио')),
            ],
          ],
        ),
      );
}
