import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';

enum SongCatalogProvider { soundCloud, spotify, youtube, deezer }

class SongCatalogService {
  SongCatalogService._();

  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 25);
  static final Map<String, List<Track>> _cache = <String, List<Track>>{};
  static final Map<String, Future<List<Track>>> _inFlight = <String, Future<List<Track>>>{};
  static final Map<SongCatalogProvider, String> _lastProviderStatus = <SongCatalogProvider, String>{};

  /// Only returns configuration/network errors. Ordinary empty search results
  /// are intentionally omitted so the UI does not nag on normal no-match cases.
  static List<String> get lastSearchIssues => SongCatalogProvider.values
      .where((provider) {
        final status = _lastProviderStatus[provider] ?? '';
        return status.startsWith('Не настроен') || status.startsWith('Ошибка');
      })
      .map((provider) => '${_providerLabel(provider)}: ${_lastProviderStatus[provider]}')
      .toList(growable: false);

  static String _providerLabel(SongCatalogProvider provider) => switch (provider) {
        SongCatalogProvider.soundCloud => 'SoundCloud',
        SongCatalogProvider.spotify => 'Spotify',
        SongCatalogProvider.youtube => 'YouTube',
        SongCatalogProvider.deezer => 'Deezer',
      };
  static const String _spotifyTokenKey = 'oxygen.api.spotifyAccessToken';
  static const String _soundCloudTokenKey = 'oxygen.api.soundCloudAccessToken';
  static const String _youtubeApiKeyKey = 'oxygen.api.youtubeApiKey';
  static Future<SearchApiCredentials> getApiCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    return SearchApiCredentials(
      spotifyAccessToken: (prefs.getString(_spotifyTokenKey) ?? '').trim(),
      soundCloudAccessToken: (prefs.getString(_soundCloudTokenKey) ?? '').trim(),
      youtubeApiKey: (prefs.getString(_youtubeApiKeyKey) ?? '').trim(),
    );
  }

  static Future<void> saveApiCredentials({
    required String spotifyAccessToken,
    required String soundCloudAccessToken,
    required String youtubeApiKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    Future<void> putOrRemove(String key, String value) async {
      final cleaned = value.trim();
      if (cleaned.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, cleaned);
      }
    }

    await putOrRemove(_spotifyTokenKey, spotifyAccessToken);
    await putOrRemove(_soundCloudTokenKey, soundCloudAccessToken);
    await putOrRemove(_youtubeApiKeyKey, youtubeApiKey);
    await prefs.remove('oxygen.api.jamendoClientId'); // discard the old, no longer supported provider setting
    _cache.clear();
  }

  /// Uses artwork supplied by the selected provider. No extra catalog is queried.
  static Future<String?> lookupArtwork(Track track) async => _https(track.artworkUrl);

  /// Queries only SoundCloud, Spotify, YouTube and Deezer.
  /// APIs requiring credentials are skipped until a user configures them.
  static Future<List<Track>> searchAll(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.length < 2) return const <Track>[];

    final credentials = await getApiCredentials();
    final providers = SongCatalogProvider.values;
    // Every configured provider is queried automatically. There is no provider
    // picker per search or per track; an auth/configuration problem is retained
    // for the UI instead of being silently turned into an empty result.
    final batches = await Future.wait(providers.map((provider) async {
      final missingCredential = switch (provider) {
        SongCatalogProvider.spotify when !credentials.hasSpotify => 'Не настроен API-доступ: добавь действующий Spotify access token в настройках поиска.',
        SongCatalogProvider.soundCloud when !credentials.hasSoundCloud => 'Не настроен API-доступ: добавь действующий SoundCloud OAuth token в настройках поиска.',
        SongCatalogProvider.youtube when !credentials.hasYouTube => 'Не настроен API-доступ: добавь YouTube Data API key в настройках поиска.',
        _ => null,
      };
      if (missingCredential != null) {
        _lastProviderStatus[provider] = missingCredential;
        return const <Track>[];
      }
      try {
        final results = await search(query, provider: provider).timeout(const Duration(seconds: 10));
        _lastProviderStatus[provider] = results.isEmpty ? 'Совпадений нет' : 'Найдено ${results.length}';
        return results;
      } catch (error) {
        _lastProviderStatus[provider] = 'Ошибка: ${error.toString().replaceFirst('SongCatalogException: ', '')}';
        return const <Track>[];
      }
    }));

    final merged = <String, Track>{};
    for (final batch in batches) {
      for (final track in batch) {
        final title = _normalise(track.title);
        final artist = _normalise(track.artist);
        if (title.isEmpty) continue;
        final key = '$title|$artist';
        final previous = merged[key];
        if (previous == null || _isPreferredResult(track, previous)) {
          merged[key] = track;
        }
      }
    }
    final result = merged.values.toList(growable: true);
    // Keep results that Oxygen can open locally/through an authorized direct
    // media URL first. Service-only metadata remains available below them.
    result.sort((left, right) {
      final playable = (left.externalOnly ? 1 : 0).compareTo(right.externalOnly ? 1 : 0);
      if (playable != 0) return playable;
      final artwork = (left.artworkUrl == null ? 1 : 0).compareTo(right.artworkUrl == null ? 1 : 0);
      return artwork;
    });
    return List<Track>.unmodifiable(result);
  }

  static int _sourcePriority(Track track) => switch (track.sourceName.toLowerCase()) {
        'soundcloud' => 0,
        'deezer' => 1,
        'spotify' => 2,
        'youtube' || 'youtube music / video' => 3,
        _ => 4,
      };

  static bool _isPreferredResult(Track candidate, Track previous) {
    if (candidate.externalOnly != previous.externalOnly) return !candidate.externalOnly;
    final candidatePriority = _sourcePriority(candidate);
    final previousPriority = _sourcePriority(previous);
    if (candidatePriority != previousPriority) return candidatePriority < previousPriority;
    if (candidate.artworkUrl != null && previous.artworkUrl == null) return true;
    return false;
  }

  static String _normalise(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\([^)]*\)'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9а-яё]+', caseSensitive: false), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  static Future<List<Track>> search(
    String rawQuery, {
    SongCatalogProvider provider = SongCatalogProvider.deezer,
  }) async {
    final query = rawQuery.trim();
    if (query.length < 2) return const <Track>[];
    final key = '${provider.name}:${query.toLowerCase()}';
    if (_cache.containsKey(key)) return _cache[key]!;
    final active = _inFlight[key];
    if (active != null) return active;
    final future = switch (provider) {
      SongCatalogProvider.soundCloud => _searchSoundCloud(query),
      SongCatalogProvider.spotify => _searchSpotify(query),
      SongCatalogProvider.youtube => _searchYouTube(query),
      SongCatalogProvider.deezer => _searchDeezer(query),
    };
    _inFlight[key] = future;
    try {
      final results = await future;
      // Don't negative-cache empty responses: public APIs sometimes return a
      // transient empty/error result and the user must be able to retry.
      if (results.isNotEmpty) {
        _cache[key] = List<Track>.unmodifiable(results);
        while (_cache.length > 60) {
          _cache.remove(_cache.keys.first);
        }
      } else {
        _cache.remove(key);
      }
      return results;
    } finally {
      _inFlight.remove(key);
    }
  }

  static Future<Map<String, dynamic>> _getJson(Uri uri, String source, {Map<String, String> headers = const <String, String>{}}) async {
    final request = await _client.getUrl(uri).timeout(const Duration(seconds: 7));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, 'Oxygen/4.2.2 (cross-platform music player)');
    headers.forEach((name, value) => request.headers.set(name, value));
    final response = await request.close().timeout(const Duration(seconds: 9));
    if (response.statusCode == HttpStatus.tooManyRequests) {
      final retryAfter = response.headers.value(HttpHeaders.retryAfterHeader);
      await response.drain<void>();
      throw SongCatalogException('$source ограничил частоту запросов. Подожди ${retryAfter ?? 'немного'} и попробуй снова.');
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw SongCatalogException('$source вернул HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 12)));
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is List<dynamic>) return <String, dynamic>{'data': decoded};
    throw SongCatalogException('$source вернул неизвестный формат данных.');
  }

  static Future<List<Track>> _searchDeezer(String query) async {
    try {
      final uri = Uri.https('api.deezer.com', '/search', <String, String>{'q': query, 'limit': '10'});
      final json = await _getJson(uri, 'Deezer');
      final items = json['data'];
      if (items is! List<dynamic>) return const <Track>[];
      final tracks = <Track>[];
      for (final raw in items) {
        if (raw is! Map<String, dynamic>) continue;
        final title = (raw['title'] as String? ?? '').trim();
        final id = raw['id']?.toString() ?? '';
        if (title.isEmpty || id.isEmpty) continue;
        final artist = raw['artist'] is Map<String, dynamic> ? raw['artist'] as Map<String, dynamic> : <String, dynamic>{};
        final album = raw['album'] is Map<String, dynamic> ? raw['album'] as Map<String, dynamic> : <String, dynamic>{};
        final url = _https(raw['link'] as String?) ?? 'https://www.deezer.com/track/$id';
        tracks.add(Track(
          path: url,
          title: title,
          artist: (artist['name'] as String? ?? 'Deezer').trim(),
          albumName: album['title'] as String?,
          artworkUrl: _https(album['cover_xl'] as String? ?? album['cover_big'] as String? ?? album['cover_medium'] as String?),
          storeUrl: url,
          sourceName: 'Deezer',
          externalOnly: true,
        ));
      }
      return tracks;
    } catch (error) {
      // Let the aggregator isolate this source and avoid caching transient failures.
      throw SongCatalogException('Deezer сейчас недоступен: $error');
    }
  }

  static Future<List<Track>> _searchSpotify(String query) async {
    final token = (await getApiCredentials()).spotifyAccessToken;
    if (token.isEmpty) return const <Track>[];
    try {
      final uri = Uri.https('api.spotify.com', '/v1/search', <String, String>{
        'q': query,
        'type': 'track',
        'limit': '8',
      });
      final cleanedToken = token.startsWith('Bearer ') ? token.substring(7).trim() : token;
      final json = await _getJson(uri, 'Spotify', headers: <String, String>{'Authorization': 'Bearer $cleanedToken'});
      final tracksNode = json['tracks'];
      final items = tracksNode is Map<String, dynamic> ? tracksNode['items'] : null;
      if (items is! List<dynamic>) return const <Track>[];
      final tracks = <Track>[];
      for (final raw in items) {
        if (raw is! Map<String, dynamic>) continue;
        final title = (raw['name'] as String? ?? '').trim();
        if (title.isEmpty) continue;
        final artists = raw['artists'] is List<dynamic> ? raw['artists'] as List<dynamic> : const <dynamic>[];
        final artistNames = artists.whereType<Map<String, dynamic>>().map((entry) => entry['name']).whereType<String>().toList();
        final album = raw['album'] is Map<String, dynamic> ? raw['album'] as Map<String, dynamic> : <String, dynamic>{};
        final images = album['images'] is List<dynamic> ? album['images'] as List<dynamic> : const <dynamic>[];
        String? imageUrl;
        if (images.isNotEmpty && images.first is Map<String, dynamic>) {
          imageUrl = _https((images.first as Map<String, dynamic>)['url'] as String?);
        }
        final urls = raw['external_urls'] is Map<String, dynamic> ? raw['external_urls'] as Map<String, dynamic> : <String, dynamic>{};
        final url = _https(urls['spotify'] as String?);
        if (url == null) continue;
        tracks.add(Track(
          path: url,
          title: title,
          artist: artistNames.isEmpty ? 'Spotify' : artistNames.join(', '),
          albumName: album['name'] as String?,
          artworkUrl: imageUrl,
          storeUrl: url,
          sourceName: 'Spotify',
          externalOnly: true,
        ));
      }
      return tracks;
    } catch (error) {
      throw SongCatalogException('Spotify сейчас недоступен или access token истёк: $error');
    }
  }

  static Future<List<Track>> _searchSoundCloud(String query) async {
    final token = (await getApiCredentials()).soundCloudAccessToken;
    if (token.isEmpty) return const <Track>[];
    try {
      final uri = Uri.https('api.soundcloud.com', '/tracks', <String, String>{
        'q': query,
        'limit': '8',
        'access': 'playable',
        'linked_partitioning': 'true',
      });
      final auth = token.startsWith('OAuth ') || token.startsWith('Bearer ') ? token : 'OAuth $token';
      final json = await _getJson(uri, 'SoundCloud', headers: <String, String>{'Authorization': auth});
      final items = json['collection'] ?? json['data'];
      if (items is! List<dynamic>) return const <Track>[];
      final tracks = <Track>[];
      for (final raw in items) {
        if (raw is! Map<String, dynamic>) continue;
        final title = (raw['title'] as String? ?? '').trim();
        final url = _https(raw['permalink_url'] as String?);
        if (title.isEmpty || url == null) continue;
        final user = raw['user'] is Map<String, dynamic> ? raw['user'] as Map<String, dynamic> : <String, dynamic>{};
        tracks.add(Track(
          path: url,
          title: title,
          artist: (user['username'] as String? ?? 'SoundCloud').trim(),
          artworkUrl: _https(raw['artwork_url'] as String?),
          storeUrl: url,
          sourceName: 'SoundCloud',
          externalOnly: true,
        ));
      }
      return tracks;
    } catch (error) {
      throw SongCatalogException('SoundCloud API сейчас недоступен: $error');
    }
  }

  static Future<List<Track>> _searchYouTube(String query) async {
    final key = (await getApiCredentials()).youtubeApiKey;
    if (key.isEmpty) return const <Track>[];
    try {
      final uri = Uri.https('www.googleapis.com', '/youtube/v3/search', <String, String>{
        'part': 'snippet',
        'type': 'video',
        'videoCategoryId': '10',
        'maxResults': '8',
        'q': query,
        'key': key,
      });
      final json = await _getJson(uri, 'YouTube');
      final items = json['items'];
      if (items is! List<dynamic>) return const <Track>[];
      final tracks = <Track>[];
      for (final raw in items) {
        if (raw is! Map<String, dynamic>) continue;
        final idObject = raw['id'] is Map<String, dynamic> ? raw['id'] as Map<String, dynamic> : <String, dynamic>{};
        final videoId = (idObject['videoId'] as String? ?? '').trim();
        final snippet = raw['snippet'] is Map<String, dynamic> ? raw['snippet'] as Map<String, dynamic> : <String, dynamic>{};
        final title = (snippet['title'] as String? ?? '').trim();
        if (videoId.isEmpty || title.isEmpty) continue;
        final thumbnails = snippet['thumbnails'] is Map<String, dynamic> ? snippet['thumbnails'] as Map<String, dynamic> : <String, dynamic>{};
        final thumb = thumbnails['high'] is Map<String, dynamic> ? thumbnails['high'] as Map<String, dynamic> : (thumbnails['default'] is Map<String, dynamic> ? thumbnails['default'] as Map<String, dynamic> : <String, dynamic>{});
        final url = 'https://www.youtube.com/watch?v=${Uri.encodeComponent(videoId)}';
        tracks.add(Track(
          path: url,
          title: title,
          artist: (snippet['channelTitle'] as String? ?? 'YouTube').trim(),
          artworkUrl: _https(thumb['url'] as String?),
          storeUrl: url,
          sourceName: 'YouTube Music / video',
          externalOnly: true,
        ));
      }
      return tracks;
    } catch (error) {
      throw SongCatalogException('YouTube API сейчас недоступен или API key неверен: $error');
    }
  }

  static String? _https(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasAuthority) return null;
    if (uri.scheme == 'https') return uri.toString();
    if (uri.scheme == 'http') return uri.replace(scheme: 'https').toString();
    return null;
  }
}

class SearchApiCredentials {
  const SearchApiCredentials({
    required this.spotifyAccessToken,
    required this.soundCloudAccessToken,
    required this.youtubeApiKey,
  });

  final String spotifyAccessToken;
  final String soundCloudAccessToken;
  final String youtubeApiKey;

  bool get hasSpotify => spotifyAccessToken.isNotEmpty;
  bool get hasSoundCloud => soundCloudAccessToken.isNotEmpty;
  bool get hasYouTube => youtubeApiKey.isNotEmpty;
}

class SongCatalogException implements Exception {
  const SongCatalogException(this.message);
  final String message;
  @override
  String toString() => message;
}
