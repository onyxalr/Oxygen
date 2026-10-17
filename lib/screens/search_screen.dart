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
  bool _remoteLoading = false;
  List<Track> _remoteResults = const <Track>[];
  Timer? _queryDebounce;
  int _searchGeneration = 0;

  void _queueQuery(String value) {
    final term = value.trim();
    _queryDebounce?.cancel();
    // Immediately invalidate a previous response and update local results.
    _searchGeneration++;
    setState(() {
      query = term;
      _remoteResults = const <Track>[];
      _remoteLoading = term.length >= 2;
    });
    if (term.length < 2) return;
    _queryDebounce = Timer(const Duration(milliseconds: 750), () => _searchEverywhere(term));
  }

  Future<void> _searchEverywhere([String? rawQuery]) async {
    _queryDebounce?.cancel();
    final term = (rawQuery ?? controller.text).trim();
    if (term.length < 2) return;
    final generation = ++_searchGeneration;
    setState(() {
      query = term;
      _remoteLoading = true;
    });
    try {
      final results = await SongCatalogService.searchAll(term);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _remoteResults = results;
        _remoteLoading = false;
      });
    } catch (_) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _remoteResults = const <Track>[];
        _remoteLoading = false;
      });
    }
  }

  Future<void> _configureSearchApis() async {
    final credentials = await SongCatalogService.getApiCredentials();
    if (!mounted) return;

    final spotify = TextEditingController(text: credentials.spotifyAccessToken);
    final soundCloud = TextEditingController(text: credentials.soundCloudAccessToken);
    final youtube = TextEditingController(text: credentials.youtubeApiKey);

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Источники поиска'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Oxygen автоматически объединяет результаты SoundCloud, Spotify, YouTube и Deezer в одном поиске. Выбирать сервис для каждого трека не нужно. Для Spotify и SoundCloud нужен действующий токен API, для YouTube — ключ API; без них соответствующий поиск будет пропущен.',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: spotify,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Spotify access token',
                    helperText: 'Временный токен каталога. Не публикуй его в GitHub.',
                    prefixIcon: Icon(Icons.music_note_rounded),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _openUrl('https://developer.spotify.com/documentation/web-api'),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Документация Spotify API'),
                  ),
                ),
                TextField(
                  controller: soundCloud,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'SoundCloud OAuth access token',
                    helperText: 'Нужен токен приложения, которому разрешён API-доступ.',
                    prefixIcon: Icon(Icons.graphic_eq_rounded),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _openUrl('https://developers.soundcloud.com/docs/api/guide'),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Документация SoundCloud API'),
                  ),
                ),
                TextField(
                  controller: youtube,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'YouTube Data API key',
                    helperText: 'В Google Cloud включи YouTube Data API v3.',
                    prefixIcon: Icon(Icons.smart_display_rounded),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _openUrl('https://console.cloud.google.com/apis/library/youtube.googleapis.com'),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Настроить YouTube API'),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Значения сохраняются только в локальных настройках Oxygen. Spotify и SoundCloud access tokens обычно временные и могут истекать; если поиск перестал работать, обнови токен. Не публикуй ключи и токены в GitHub.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () {
              spotify.clear();
              soundCloud.clear();
              youtube.clear();
            },
            child: const Text('Очистить поля'),
          ),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Сохранить')),
        ],
      ),
    );

    if (save == true) {
      await SongCatalogService.saveApiCredentials(
        spotifyAccessToken: spotify.text,
        soundCloudAccessToken: soundCloud.text,
        youtubeApiKey: youtube.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Настройки источников сохранены.')));
        if (query.trim().length >= 2) await _searchEverywhere(query);
      }
    }
    spotify.dispose();
    soundCloud.dispose();
    youtube.dispose();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось открыть ссылку.')));
      }
    }
  }


  List<Widget> _localSlivers(BuildContext context, List<Track> visibleTracks) => <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (query.isEmpty) ...[
                  Text('Моя музыка', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('Избранное'),
                        selected: favoritesOnly,
                        onSelected: (value) => setState(() => favoritesOnly = value),
                      ),
                      ActionChip(label: const Text('Вся библиотека'), onPressed: () => setState(() => favoritesOnly = false)),
                    ],
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  Text('В моей библиотеке · ${visibleTracks.length}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ],
            ),
          ),
        ),
        if (query.isNotEmpty && visibleTracks.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 12, 24, 18),
              child: Text('В локальной библиотеке совпадений нет. Ниже идут результаты музыкальных сервисов.'),
            ),
          )
        else if (visibleTracks.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: _Message(
                icon: Icons.library_music_outlined,
                title: 'Библиотека пока пуста',
                body: 'Добавь музыку с устройства — онлайн-источники будут показаны ниже при поиске.',
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
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

  List<Widget> _internetSlivers(BuildContext context) {
    final theme = Theme.of(context);
    final queryIsReady = query.trim().length >= 2;
    if (!queryIsReady) {
      return <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
          sliver: SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: .45)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.travel_explore_rounded, color: theme.colorScheme.primary, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Поиск сразу в нескольких источниках', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Text(
                          'Поиск автоматически объединяет результаты SoundCloud, Spotify, YouTube и Deezer. Источник вручную выбирать не нужно. Для некоторых сервисов требуется действующий API-токен или ключ.',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(24, 2, 24, 10),
        sliver: SliverToBoxAdapter(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'В интернете${_remoteResults.isEmpty ? '' : ' · ${_remoteResults.length}'}',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (_remoteLoading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
        ),
      ),
      if (_remoteResults.isNotEmpty && SongCatalogService.lastSearchIssues.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Часть API недоступна: ${SongCatalogService.lastSearchIssues.take(3).join(' · ')}',
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                TextButton(
                  onPressed: _configureSearchApis,
                  child: const Text('Настроить'),
                ),
              ],
            ),
          ),
        ),
      if (_remoteLoading && _remoteResults.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 4, 24, 18),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        ),
      if (!_remoteLoading && _remoteResults.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Совпадений пока нет. Проверь интернет и API-доступ в настройках поиска. Oxygen автоматически проверяет все настроенные сервисы — выбирать источник вручную не нужно.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                if (SongCatalogService.lastSearchIssues.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final issue in SongCatalogService.lastSearchIssues.take(4))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $issue', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.error)),
                    ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: _configureSearchApis,
                    icon: const Icon(Icons.key_rounded),
                    label: const Text('Настроить API-доступ'),
                  ),
                ],
              ],
            ),
          ),
        ),
      if (_remoteResults.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _OnlineTrackTile(
                key: ValueKey(_remoteResults[index].id),
                track: _remoteResults[index],
                queue: _remoteResults,
                audio: widget.audio,
              ),
              childCount: _remoteResults.length,
            ),
          ),
        ),
    ];
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
          final normalizedQuery = query.trim().toLowerCase();
          final visibleTracks = widget.audio.library.where((track) {
            if (favoritesOnly && !widget.audio.favoriteIds.contains(track.id)) {
              return false;
            }
            if (normalizedQuery.isEmpty) return true;
            return widget.audio.searchableText(track).contains(normalizedQuery);
          }).toList(growable: false);

          final theme = Theme.of(context);
          return CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Поиск',
                        style: theme.textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Одна строка для твоей музыки',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controller,
                              onChanged: _queueQuery,
                              onSubmitted: (value) => _searchEverywhere(value),
                              textInputAction: TextInputAction.search,
                              autocorrect: false,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search_rounded),
                                hintText: 'Трек, исполнитель или альбом',
                                suffixIcon: query.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Очистить поиск',
                                        onPressed: () {
                                          controller.clear();
                                          _queueQuery('');
                                        },
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: 'API и источники поиска',
                            onPressed: _configureSearchApis,
                            icon: const Icon(Icons.tune_rounded),
                          ),
                          if (query.trim().length >= 2) ...[
                            const SizedBox(width: 4),
                            IconButton.filledTonal(
                              tooltip: 'Повторить поиск',
                              onPressed: _remoteLoading
                                  ? null
                                  : () => _searchEverywhere(query),
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              ..._localSlivers(context, visibleTracks),
              ..._internetSlivers(context),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          );
        },
      );

}

class _OnlineTrackTile extends StatelessWidget {
  const _OnlineTrackTile({super.key, required this.track, required this.queue, required this.audio});
  final Track track;
  final List<Track> queue;
  final AudioController audio;

  Future<void> _openStore() async {
    final raw = track.storeUrl ?? (track.externalOnly ? track.path : null);
    final uri = raw == null ? null : Uri.tryParse(raw);
    if (uri == null || !uri.hasAuthority) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = !track.externalOnly && audio.current?.id == track.id;
    final playableQueue = queue.where((item) => !item.externalOnly).toList(growable: false);
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
                              errorBuilder: (context, error, stack) => ColoredBox(
                                color: scheme.surfaceContainerHighest,
                                child: const Icon(Icons.music_note_rounded),
                              ),
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
                  if (!track.externalOnly)
                    IconButton.filledTonal(
                      tooltip: active && audio.isPlaying ? 'Пауза' : 'Воспроизвести',
                      onPressed: () {
                        if (active) {
                          audio.togglePlay();
                        } else {
                          audio.playTrack(track, from: playableQueue);
                        }
                      },
                      icon: Icon(active && audio.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              if (track.externalOnly)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: track.storeUrl == null ? null : _openStore,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Открыть'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

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
              ],
            ),
          ),
        ),
      );
}
