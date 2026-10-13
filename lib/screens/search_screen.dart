import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/track.dart';
import '../services/app_settings.dart';
import '../services/audio_controller.dart';
import '../services/song_catalog_service.dart';
import '../widgets/track_tile.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.settings, required this.audio});
  final AppSettings settings;
  final AudioController audio;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController controller = TextEditingController();
  String query = '';
  bool favoritesOnly = false;
  bool _onlineMode = false;
  bool _onlineLoading = false;
  bool _hasOnlineSearched = false;
  String? _onlineError;
  List<Track> _onlineResults = const <Track>[];
  Timer? _queryDebounce;
  int _searchGeneration = 0;

  void _queueQuery(String value) {
    _queryDebounce?.cancel();
    _queryDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() => query = value.trim());
    });
  }

  void _setOnlineMode(bool online) {
    if (_onlineMode == online) return;
    setState(() {
      _onlineMode = online;
      _onlineError = null;
    });
    if (online && controller.text.trim().length >= 2) {
      _searchOnline(controller.text);
    }
  }

  Future<void> _searchOnline([String? rawQuery]) async {
    final term = (rawQuery ?? controller.text).trim();
    if (term.length < 2) {
      setState(() {
        query = term;
        _onlineResults = const <Track>[];
        _onlineError = 'Введи хотя бы два символа для поиска.';
        _onlineLoading = false;
      });
      return;
    }

    final generation = ++_searchGeneration;
    setState(() {
      _onlineMode = true;
      query = term;
      _onlineLoading = true;
      _hasOnlineSearched = true;
      _onlineError = null;
    });

    try {
      final results = await SongCatalogService.search(term);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _onlineResults = results;
        _onlineLoading = false;
      });
    } on SongCatalogException catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _onlineResults = const <Track>[];
        _onlineError = error.message;
        _onlineLoading = false;
      });
    } catch (_) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _onlineResults = const <Track>[];
        _onlineError = 'Не удалось выполнить поиск. Проверь интернет и попробуй снова.';
        _onlineLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _searchGeneration++;
    _queryDebounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.audio,
        builder: (context, _) {
          final normalizedQuery = query.toLowerCase();
          final List<Track> visibleTracks;
          if (normalizedQuery.isEmpty) {
            visibleTracks = favoritesOnly
                ? widget.audio.library.where((track) => widget.audio.favoriteIds.contains(track.id)).toList(growable: false)
                : widget.audio.library.reversed.take(6).toList(growable: false);
          } else {
            visibleTracks = widget.audio.library.where((track) {
              final matchesQuery = widget.audio.searchableText(track).contains(normalizedQuery);
              return matchesQuery && (!favoritesOnly || widget.audio.favoriteIds.contains(track.id));
            }).toList(growable: false);
          }

          return CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Поиск', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      Text(
                        _onlineMode ? 'Ищи треки в онлайн-каталоге.' : 'Найди любой трек в своей коллекции.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 18),
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: const <ButtonSegment<bool>>[
                          ButtonSegment<bool>(value: false, icon: Icon(Icons.library_music_rounded), label: Text('Моя музыка')),
                          ButtonSegment<bool>(value: true, icon: Icon(Icons.public_rounded), label: Text('Онлайн-каталог')),
                        ],
                        selected: <bool>{_onlineMode},
                        onSelectionChanged: (selection) => _setOnlineMode(selection.first),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: controller,
                        autofocus: false,
                        onChanged: _queueQuery,
                        onSubmitted: (value) {
                          if (_onlineMode) {
                            _searchOnline(value);
                          } else {
                            _queryDebounce?.cancel();
                            setState(() => query = value.trim());
                          }
                        },
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search_rounded),
                          hintText: _onlineMode ? 'Песня или исполнитель' : 'Название или исполнитель',
                          suffixIcon: _onlineMode
                              ? IconButton(onPressed: () => _searchOnline(controller.text), tooltip: 'Искать онлайн', icon: const Icon(Icons.search_rounded))
                              : (query.isEmpty
                                  ? null
                                  : IconButton(
                                      onPressed: () {
                                        _queryDebounce?.cancel();
                                        controller.clear();
                                        setState(() => query = '');
                                      },
                                      icon: const Icon(Icons.close_rounded),
                                    )),
                        ),
                      ),
                      const SizedBox(height: 22),
                    ],
                  ),
                ),
              ),
              if (_onlineMode) ..._onlineSlivers(context) else ..._localSlivers(context, visibleTracks),
            ],
          );
        },
      );

  List<Widget> _localSlivers(BuildContext context, List<Track> visibleTracks) => <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (query.isEmpty) ...[
                  Text('Попробуй поискать', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(label: const Text('Избранное'), selected: favoritesOnly, onSelected: (value) => setState(() => favoritesOnly = value)),
                      ActionChip(label: const Text('Вся библиотека'), onPressed: () => setState(() => favoritesOnly = false)),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  query.isNotEmpty && visibleTracks.isNotEmpty ? 'Результаты · ${visibleTracks.length}' : (favoritesOnly ? 'Избранное' : 'Недавно добавлено'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
        if (query.isNotEmpty && visibleTracks.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 44, 24, 30),
              child: _Message(icon: Icons.search_off_rounded, title: 'Ничего не найдено', body: 'Проверь название или переключись на онлайн-каталог.'),
            ),
          )
        else if (visibleTracks.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 30),
              child: _Message(icon: Icons.library_music_outlined, title: 'Библиотека пока пуста', body: 'Добавь аудиофайлы с устройства или найди музыку в онлайн-каталоге.'),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = visibleTracks[index];
                  return TrackTile(key: ValueKey(track.id), track: track, audio: widget.audio, settings: widget.settings);
                },
                childCount: visibleTracks.length,
              ),
            ),
          ),
      ];

  List<Widget> _onlineSlivers(BuildContext context) {
    final theme = Theme.of(context);
    if (_onlineLoading) {
      return <Widget>[
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator())),
        ),
      ];
    }
    if (_onlineError != null) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: _Message(icon: Icons.wifi_off_rounded, title: 'Поиск не выполнен', body: _onlineError!, action: _searchOnline),
        ),
      ];
    }
    if (query.trim().length < 2 || _onlineResults.isEmpty) {
      final tooShort = query.trim().length < 2;
      final notSearched = !_hasOnlineSearched;
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: _Message(
            icon: tooShort ? Icons.travel_explore_rounded : (notSearched ? Icons.search_rounded : Icons.search_off_rounded),
            title: tooShort ? 'Каталог музыки' : (notSearched ? 'Готов к поиску' : 'Совпадений не найдено'),
            body: tooShort
                ? 'Введи название песни или исполнителя и нажми поиск. Нужен интернет.'
                : (notSearched ? 'Нажми Enter или кнопку поиска, чтобы обратиться к каталогу.' : 'Попробуй другое название или напиши имя исполнителя.'),
            action: !tooShort ? _searchOnline : null,
          ),
        ),
      ];
    }

    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Apple Music / iTunes · ${_onlineResults.length}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Короткие предпрослушивания предоставлены iTunes. Полные треки открываются в музыкальном магазине Apple.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _OnlineTrackTile(track: _onlineResults[index], queue: _onlineResults, audio: widget.audio),
            childCount: _onlineResults.length,
          ),
        ),
      ),
    ];
  }
}

class _OnlineTrackTile extends StatelessWidget {
  const _OnlineTrackTile({required this.track, required this.queue, required this.audio});
  final Track track;
  final List<Track> queue;
  final AudioController audio;

  Future<void> _openStore() async {
    final url = track.storeUrl;
    if (url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = audio.current?.id == track.id;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: active ? scheme.secondaryContainer.withValues(alpha: .55) : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: active ? scheme.primary.withValues(alpha: .35) : scheme.outlineVariant.withValues(alpha: .4)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 58,
                      height: 58,
                      child: track.artworkUrl == null
                          ? ColoredBox(color: scheme.surfaceContainerHighest, child: const Icon(Icons.music_note_rounded))
                          : Image.network(
                              track.artworkUrl!,
                              fit: BoxFit.cover,
                              cacheWidth: 116,
                              errorBuilder: (_, __, ___) => ColoredBox(color: scheme.surfaceContainerHighest, child: const Icon(Icons.music_note_rounded)),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        if (track.albumName?.isNotEmpty == true) ...[
                          const SizedBox(height: 2),
                          Text(track.albumName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    tooltip: active && audio.isPlaying ? 'Пауза' : 'Предпрослушать',
                    onPressed: () => active ? audio.togglePlay() : audio.playTrack(track, from: queue),
                    icon: Icon(active && audio.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text('Предпрослушивание предоставлено iTunes', style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                  TextButton.icon(
                    onPressed: track.storeUrl == null ? null : _openStore,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Apple Music'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body, this.action});
  final IconData icon;
  final String title;
  final String body;
  final Future<void> Function()? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 46, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 12),
                Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 7),
                Text(body, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                if (action != null) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(onPressed: action, icon: const Icon(Icons.refresh_rounded), label: const Text('Повторить')),
                ],
              ],
            ),
          ),
        ),
      );
}
