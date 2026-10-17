import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';

class LyricsService {
  LyricsService._();
  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 20);
  static final Map<String, LyricsResult?> _cache = <String, LyricsResult?>{};
  static final Map<String, Future<LyricsResult?>> _inFlight = <String, Future<LyricsResult?>>{};
  static DateTime _lastLrcRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime _blockedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  static Future<void> _requestTail = Future<void>.value();

  static const String website = 'https://lrclib.net';
  static const String _version = '4.2.4';
  static const String _musixmatchApiKeyKey = 'oxygen.api.musixmatchApiKey';

  static Future<String> getMusixmatchApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_musixmatchApiKeyKey)?.trim() ?? '';
  }

  static Future<void> saveMusixmatchApiKey(String value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value.trim().isEmpty) {
      await prefs.remove(_musixmatchApiKeyKey);
    } else {
      await prefs.setString(_musixmatchApiKeyKey, value.trim());
    }
    _cache.clear();
  }

  static Map<String, Uri> searchLinks(Track track) {
    final metadata = _cleanTrackMetadata(track);
    final title = metadata[0];
    final artist = metadata[1];
    final terms = [title, artist].where((item) => item.isNotEmpty).join(' ');
    final encodedTerms = terms.isEmpty ? title : terms;
    return <String, Uri>{
      'LRCLIB search': Uri.https('lrclib.net', '/search', <String, String>{'q': encodedTerms}),
      'Lyrics.ovh': Uri.https('lyrics.ovh', '/'),
      'LyricsPlus docs': Uri.https('github.com', '/ibratabian17/lyricsplus/blob/cookie/docs/endpoints.md'),
      'SimpMusic Lyrics API': Uri.https('api-lyrics.simpmusic.org', '/swagger-ui/'),
      'BetterLyrics API': Uri.https('lyrics-api-docs.boidu.dev', '/reference/get-lyrics'),
      'Genius': Uri.https('genius.com', '/search', <String, String>{'q': encodedTerms}),
      'Musixmatch': Uri.https('www.musixmatch.com', '/search', <String, String>{'q': encodedTerms}),
      'Lyrics.com': Uri.https('www.lyrics.com', '/serp.php', <String, String>{'st': encodedTerms, 'qtype': '2'}),
      'AZLyrics search': Uri.https('www.google.com', '/search', <String, String>{'q': 'site:azlyrics.com "$encodedTerms" lyrics'}),
      'Letras search': Uri.https('www.google.com', '/search', <String, String>{'q': 'site:letras.com "$encodedTerms" letra lyrics'}),
      'SongLyrics search': Uri.https('www.google.com', '/search', <String, String>{'q': 'site:songlyrics.com "$encodedTerms" lyrics'}),
      'LyricsTranslate search': Uri.https('www.google.com', '/search', <String, String>{'q': 'site:lyricstranslate.com "$encodedTerms" lyrics'}),
      'YouTube lyrics': Uri.https('www.youtube.com', '/results', <String, String>{'search_query': '$encodedTerms lyrics'}),
      'Spotify search': Uri.https('open.spotify.com', '/search', <String, String>{'q': '$encodedTerms lyrics'}),
      'Deezer search': Uri.https('www.deezer.com', '/search', <String, String>{'q': encodedTerms}),
      'Apple Music search': Uri.https('music.apple.com', '/search', <String, String>{'term': encodedTerms}),
      'Yandex Music search': Uri.https('music.yandex.com', '/search', <String, String>{'text': '$encodedTerms lyrics'}),
      'Bandcamp search': Uri.https('bandcamp.com', '/search', <String, String>{'q': '$encodedTerms lyrics'}),
      'SoundCloud search': Uri.https('soundcloud.com', '/search', <String, String>{'q': '$encodedTerms lyrics'}),
      'DuckDuckGo': Uri.https('duckduckgo.com', '/', <String, String>{'q': 'lyrics "$encodedTerms"'}),
      'Bing': Uri.https('www.bing.com', '/search', <String, String>{'q': 'lyrics "$encodedTerms"'}),
      'Google': Uri.https('www.google.com', '/search', <String, String>{'q': 'lyrics "$encodedTerms"'}),
    };
  }

  static List<String> _cleanTrackMetadata(Track track) {
    var title = _cleanTitle(track.title);
    var artist = _cleanArtist(track.artist);
    final split = RegExp(r'^(.{1,80}?)\s+[-–—|]\s+(.{2,})$').firstMatch(title);
    if (split != null) {
      final splitArtist = split.group(1)!.trim();
      final splitTitle = _cleanTitle(split.group(2)!);
      if (artist.isEmpty) {
        artist = splitArtist;
        title = splitTitle;
      } else if (_normalize(splitArtist) == _normalize(artist)) {
        title = splitTitle;
      }
    }
    if (artist.isNotEmpty) {
      final prefix = RegExp('^${RegExp.escape(artist)}\\s*[-–—:]\\s*', caseSensitive: false);
      title = title.replaceFirst(prefix, '').trim();
    }
    return <String>[title, artist];
  }

  static String _cleanTitle(String raw) {
    var value = raw.trim();
    value = value.replaceAll(RegExp(r'\s*[\(\[]\s*(?:official\s+)?(?:music\s+)?(?:video|audio|lyrics?|visuali[sz]er|hd|4k)(?:\s+[^)\]]*)?[)\]]', caseSensitive: false), ' ');
    value = value.replaceAll(RegExp(r'\s*[-–—|]\s*(?:official\s+)?(?:music\s+)?(?:video|audio|lyrics?|visuali[sz]er)\s*$', caseSensitive: false), ' ');
    value = value.replaceAll(RegExp(r'\s+(?:official\s+)?(?:music\s+)?(?:video|audio|lyrics?|visuali[sz]er)\s*$', caseSensitive: false), ' ');
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _cleanArtist(String raw) {
    final value = raw.trim();
    final normalized = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё]+', caseSensitive: false), ' ').trim();
    const providerNames = <String>{
      '', 'локальный файл', 'unknown artist', 'неизвестный исполнитель',
      'internet archive', 'internet archive contributors', 'audius',
      'soundcloud', 'spotify', 'youtube', 'youtube music', 'deezer',
      'wikimedia commons', 'jamendo', 'openverse', 'apple music', 'itunes',
      'archive org', 'archive.org', 'unknown', 'official', 'official video',
      'official audio', 'official music video', 'topic', 'audio', 'video',
      'lyrics', 'lyrics video', 'visualizer', 'visualiser', 'hd', '4k',
      'various artists', 'unknown creator',
    };
    if (providerNames.contains(normalized) || normalized.startsWith('internet archive ')) return '';
    return value;
  }

  static Future<LyricsResult?> lookup(Track track, {Duration? duration}) {
    final metadata = _cleanTrackMetadata(track);
    final title = metadata[0];
    final artist = metadata[1];
    final album = track.albumName?.trim() ?? '';
    final durationSeconds = (duration?.inSeconds ?? 0).clamp(0, 86400).toInt();
    final key = '${title.toLowerCase()}\u0000${artist.toLowerCase()}\u0000${album.toLowerCase()}\u0000$durationSeconds';
    if (_cache.containsKey(key)) return Future<LyricsResult?>.value(_cache[key]);
    final existing = _inFlight[key];
    if (existing != null) return existing;
    final future = _fetch(title: title, artist: artist, album: album, durationSeconds: durationSeconds);
    _inFlight[key] = future;
    return future.then((result) {
      // Cache only successful matches. Caching null here made the Retry button
      // return the same empty result without contacting any API again.
      if (result != null) {
        _cache[key] = result;
        while (_cache.length > 80) {
          _cache.remove(_cache.keys.first);
        }
      }
      return result;
    }).whenComplete(() => _inFlight.remove(key));
  }

  static Future<T> _serializedLrc<T>(Future<T> Function() action) async {
    final completer = Completer<void>();
    final previous = _requestTail;
    _requestTail = completer.future;
    await previous;
    try {
      final now = DateTime.now();
      if (now.isBefore(_blockedUntil)) {
        final waitSeconds = _blockedUntil.difference(now).inSeconds + 1;
        throw LyricsServiceException('LRCLIB временно недоступен или ограничил запросы. Повторная попытка примерно через $waitSeconds сек.; другие источники продолжают работать.');
      }
      final elapsed = DateTime.now().difference(_lastLrcRequestAt).inMilliseconds;
      if (elapsed < 350) await Future<void>.delayed(Duration(milliseconds: 350 - elapsed));
      _lastLrcRequestAt = DateTime.now();
      return await action();
    } finally {
      completer.complete();
    }
  }

  static Future<LyricsResult?> _fetch({
    required String title,
    required String artist,
    required String album,
    required int durationSeconds,
  }) async {
    if (title.trim().isEmpty) return null;
    final errors = <String>[];

    bool useful(LyricsResult? result) => result != null && (result.hasLyrics || result.instrumental);

    Future<LyricsResult?> attempt(String name, Future<LyricsResult?> Function() request) async {
      try {
        final result = await request();
        return useful(result) ? result : null;
      } catch (error) {
        errors.add('$name: ${_userError(error)}');
        return null;
      }
    }

    // Query independent services at the same time. A 503 from LRCLIB is not
    // allowed to block LyricsPlus/Lyrics.ovh; these APIs have separate hosts.
    final primary = <Future<LyricsResult?>>[];
    if (artist.isNotEmpty) {
      primary.add(attempt(
        'LyricsPlus',
        () => _fetchLyricsPlus(title, artist, album, durationSeconds).timeout(const Duration(seconds: 12)),
      ));
      primary.add(attempt(
        'Lyrics.ovh',
        () => _fetchLyricsOvh(title, artist).timeout(const Duration(seconds: 7)),
      ));
      primary.add(attempt(
        'Lyrics.ovh поиск',
        () => _fetchLyricsOvhSuggestions(title, artist).timeout(const Duration(seconds: 12)),
      ));
      primary.add(attempt(
        'SimpMusic Lyrics API',
        () => _fetchSimpMusic(title, artist, album).timeout(const Duration(seconds: 7)),
      ));
      primary.add(attempt(
        'BetterLyrics API',
        () => _fetchBetterLyrics(title, artist, album, durationSeconds).timeout(const Duration(seconds: 6)),
      ));
    } else {
      // Archive/video records often have no artist field. Resolve a title-only
      // result using LyricsPlus and the Lyrics.ovh/Deezer suggestion endpoint
      // before querying LRCLIB with weak metadata.
      primary.add(attempt(
        'LyricsPlus поиск по названию',
        () => _fetchLyricsPlus(title, '', album, durationSeconds).timeout(const Duration(seconds: 9)),
      ));
      primary.add(attempt(
        'Lyrics.ovh поиск',
        () => _fetchLyricsOvhSuggestions(title, '').timeout(const Duration(seconds: 12)),
      ));
      primary.add(attempt(
        'SimpMusic Lyrics API',
        () => _fetchSimpMusic(title, '', album).timeout(const Duration(seconds: 7)),
      ));
      primary.add(attempt(
        'BetterLyrics API',
        () => _fetchBetterLyrics(title, '', album, durationSeconds).timeout(const Duration(seconds: 6)),
      ));
    }

    final musixmatchKey = await getMusixmatchApiKey();
    if (musixmatchKey.isNotEmpty && artist.isNotEmpty) {
      primary.add(attempt(
        'Musixmatch API',
        () => _fetchMusixmatch(title, artist, musixmatchKey).timeout(const Duration(seconds: 8)),
      ));
    }

    if (primary.isNotEmpty) {
      final winner = Completer<LyricsResult?>();
      var pending = primary.length;
      for (final request in primary) {
        request.then((result) {
          if (useful(result) && !winner.isCompleted) winner.complete(result);
        }).whenComplete(() {
          pending--;
          if (pending == 0 && !winner.isCompleted) winner.complete(null);
        });
      }
      final first = await winner.future.timeout(const Duration(seconds: 13), onTimeout: () => null);
      if (useful(first)) return first;
    }

    // LRCLIB exact matching requires artist metadata and works best with duration.
    // `_serializedLrc` throttles requests and immediately skips while its cooldown
    // is active, preventing repeated 503s from hammering an unavailable service.
    if (artist.isNotEmpty && durationSeconds > 0) {
      try {
        final exact = await _serializedLrc(() => _fetchLrcLibExact(title, artist, album, durationSeconds));
        if (useful(exact)) return exact;
      } catch (error) {
        errors.add('LRCLIB exact: ${_userError(error)}');
      }
    }

    try {
      final lrc = await _serializedLrc(() => _fetchLrcLib(title, artist));
      if (useful(lrc)) return lrc;
    } catch (error) {
      errors.add('LRCLIB search: ${_userError(error)}');
    }

    if (errors.isNotEmpty) {
      final unique = errors.toSet().take(5).join(' · ');
      throw LyricsServiceException(
        'Текст не удалось получить ни из одного доступного API. LRCLIB может временно отвечать 503/429; Oxygen пробует LyricsPlus и Lyrics.ovh отдельно. $unique. Повтори запрос позже или открой один из внешних поисков.',
      );
    }
    return null;
  }

  static Future<LyricsResult?> _fetchLyricsPlus(String title, String artist, String album, int durationSeconds) async {
    const hosts = <String>[
      // Current commonly used mirrors. The service is community-operated, so
      // always fall through instead of treating one host as authoritative.
      'lyricsplus.prjktla.workers.dev',
      'lyricsplus-seven.vercel.app',
      'lyrics-plus-backend.vercel.app',
      'lyricsplus.atomix.one',
      'lyricsplus.prjktla.my.id',
    ];
    String? lastTemporaryStatus;
    Object? lastError;
    final searchHosts = artist.trim().isEmpty ? hosts.take(3) : hosts;
    final searchPaths = artist.trim().isEmpty
        ? const <String>['/v2/lyrics/get']
        : const <String>['/v2/lyrics/get', '/v1/lyrics/get'];
    final connectTimeout = artist.trim().isEmpty ? const Duration(seconds: 2) : const Duration(seconds: 3);
    final responseTimeout = artist.trim().isEmpty ? const Duration(seconds: 3) : const Duration(seconds: 4);
    for (final host in searchHosts) {
      final query = <String, String>{
        'title': title,
        if (artist.trim().isNotEmpty) 'artist': artist,
        if (album.isNotEmpty) 'album': album,
        if (durationSeconds > 0) 'duration': durationSeconds.toString(),
        'source': 'apple,musixmatch,spotify,qq,lyricsplus,musixmatch-word',
      };
      for (final apiPath in searchPaths) {
      try {
        final uri = Uri.https(host, apiPath, query);
        final request = await _client.getUrl(uri).timeout(connectTimeout);
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(HttpHeaders.userAgentHeader, 'Oxygen/$_version (https://t.me/onyx_alr)');
        request.headers.set('X-Client-Package', 'Oxygen <https://t.me/onyx_alr>');
        final response = await request.close().timeout(responseTimeout);
        if (response.statusCode == HttpStatus.notFound || response.statusCode == HttpStatus.noContent) {
          await response.drain<void>();
          continue;
        }
        if (response.statusCode == HttpStatus.tooManyRequests || response.statusCode >= 500) {
          lastTemporaryStatus = '$host HTTP ${response.statusCode}';
          await response.drain<void>();
          continue;
        }
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>();
          continue;
        }
        final body = await utf8.decoder.bind(response).join().timeout(responseTimeout);
        final decoded = jsonDecode(body);
        if (decoded is! Map<String, dynamic>) continue;
        final rawPayload = decoded['data'] ?? decoded['result'];
        final payload = rawPayload is Map<String, dynamic> ? rawPayload : decoded;
        final plainDirect = _firstString(payload, const ['plainLyrics', 'plain', 'lyricsText', 'text']);
        final syncedDirect = _firstString(payload, const ['syncedLyrics', 'synced', 'lrc', 'lyricsLrc']);
        final rawLyrics = payload['lyrics'] ?? payload['lines'] ?? payload['content'];
        String plain = plainDirect;
        String synced = syncedDirect;

        if (rawLyrics is String && plain.isEmpty && synced.isEmpty) {
          final candidate = rawLyrics.trim();
          if (RegExp(r'^\s*\[\d{1,2}:\d{2}(?:[.:]\d{1,3})?\]', multiLine: true).hasMatch(candidate)) {
            synced = candidate;
            plain = _stripLrcTimestamps(candidate);
          } else {
            plain = candidate;
          }
        } else if (rawLyrics is List<dynamic> && plain.isEmpty && synced.isEmpty) {
          final lineTexts = <String>[];
          final timedLines = <String>[];
          for (final item in rawLyrics) {
            final text = _lyricsLineText(item);
            if (text.isEmpty) continue;
            lineTexts.add(text);
            final timeMs = _lyricsTimeMs(item);
            if (timeMs != null && timeMs >= 0) {
              timedLines.add('[${_formatLrcTime(timeMs)}]$text');
            }
          }
          plain = lineTexts.join('\n');
          if (timedLines.length >= 2) synced = timedLines.join('\n');
        } else if (rawLyrics is Map<String, dynamic> && plain.isEmpty && synced.isEmpty) {
          final nested = rawLyrics['lines'] ?? rawLyrics['lyrics'];
          if (nested is List<dynamic>) {
            final lineTexts = <String>[];
            final timedLines = <String>[];
            for (final item in nested) {
              final text = _lyricsLineText(item);
              if (text.isEmpty) continue;
              lineTexts.add(text);
              final timeMs = _lyricsTimeMs(item);
              if (timeMs != null && timeMs >= 0) timedLines.add('[${_formatLrcTime(timeMs)}]$text');
            }
            plain = lineTexts.join('\n');
            if (timedLines.length >= 2) synced = timedLines.join('\n');
          }
        }

        // LyricsPlus v2 may return syncedLyrics as an array/object instead of a
        // string. Parse that field independently even when plainLyrics exists.
        if (synced.isEmpty) {
          final rawSynced = payload['syncedLyrics'] ?? payload['synced'] ?? payload['lrc'] ?? payload['lyricsLrc'];
          if (rawSynced is String) {
            final candidate = rawSynced.trim();
            if (RegExp(r'^\s*\[\d{1,2}:\d{2}(?:[.:]\d{1,3})?\]', multiLine: true).hasMatch(candidate)) {
              synced = candidate;
              if (plain.isEmpty) plain = _stripLrcTimestamps(candidate);
            }
          } else {
            final rawLines = rawSynced is List<dynamic>
                ? rawSynced
                : rawSynced is Map<String, dynamic>
                    ? (rawSynced['lines'] ?? rawSynced['lyrics'] ?? rawSynced['content'])
                    : null;
            if (rawLines is List<dynamic>) {
              final textLines = <String>[];
              final timedLines = <String>[];
              for (final item in rawLines) {
                final lineText = _lyricsLineText(item);
                if (lineText.isEmpty) continue;
                textLines.add(lineText);
                final timeMs = _lyricsTimeMs(item);
                if (timeMs != null && timeMs >= 0) timedLines.add('[${_formatLrcTime(timeMs)}]$lineText');
              }
              final joined = textLines.join('\n');
              if (joined.contains(RegExp(r'^\s*\[\d{1,2}:\d{2}', multiLine: true))) {
                synced = joined;
              } else if (timedLines.length >= 2) {
                synced = timedLines.join('\n');
              }
              if (plain.isEmpty && textLines.isNotEmpty) plain = textLines.join('\n');
            }
          }
        }

        final instrumental = payload['instrumental'] == true || payload['isInstrumental'] == true;
        if (!instrumental && plain.isEmpty && synced.isEmpty) continue;
        final metadata = payload['metadata'] is Map<String, dynamic>
            ? payload['metadata'] as Map<String, dynamic>
            : (decoded['metadata'] is Map<String, dynamic> ? decoded['metadata'] as Map<String, dynamic> : <String, dynamic>{});
        final provider = _firstString(metadata, const ['source', 'provider', 'engine']);
        return LyricsResult(
          id: int.tryParse(payload['id']?.toString() ?? '') ?? 0,
          trackName: _firstString(payload, const ['trackName', 'title', 'name']).isEmpty ? title : _firstString(payload, const ['trackName', 'title', 'name']),
          artistName: _firstString(payload, const ['artistName', 'artist']).isEmpty ? artist : _firstString(payload, const ['artistName', 'artist']),
          albumName: _firstString(payload, const ['albumName', 'album']).isEmpty ? (album.isEmpty ? null : album) : _firstString(payload, const ['albumName', 'album']),
          instrumental: instrumental,
          plainLyrics: plain.isEmpty ? null : plain,
          syncedLyrics: synced.isEmpty ? null : synced,
          sourceName: provider.isEmpty ? 'LyricsPlus · мульти-источник' : 'LyricsPlus · $provider',
          sourceUrl: Uri.https('github.com', '/ibratabian17/lyricsplus/blob/cookie/docs/endpoints.md').toString(),
        );
      } catch (error) {
        lastError = error;
      }
      }
    }
    if (lastTemporaryStatus != null) {
      throw LyricsServiceException('зеркала LyricsPlus временно недоступны ($lastTemporaryStatus)');
    }
    if (lastError is SocketException || lastError is TimeoutException) {
      throw const LyricsServiceException('LyricsPlus временно недоступен: превышено время ожидания или нет соединения.');
    }
    return null;
  }

  static Future<LyricsResult?> _fetchSimpMusic(String title, String artist, String album) async {
    final query = <String>[title.trim(), artist.trim()].where((item) => item.isNotEmpty).join(' ');
    if (query.isEmpty) return null;
    final uri = Uri.https('api-lyrics.simpmusic.org', '/v1/search', <String, String>{
      'q': query,
      'limit': '10',
    });
    final request = await _client.getUrl(uri).timeout(const Duration(seconds: 4));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, 'Oxygen/$_version (https://t.me/onyx_alr)');
    final response = await request.close().timeout(const Duration(seconds: 5));
    if (response.statusCode == HttpStatus.notFound || response.statusCode == HttpStatus.noContent) {
      await response.drain<void>();
      return null;
    }
    if (response.statusCode == HttpStatus.tooManyRequests || response.statusCode >= 500) {
      final status = response.statusCode;
      final retryAfter = response.headers.value(HttpHeaders.retryAfterHeader);
      await response.drain<void>();
      throw LyricsServiceException('SimpMusic Lyrics API временно недоступен (HTTP $status${retryAfter == null ? '' : ', повтор через $retryAfter сек.'}).');
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      return null;
    }
    final decoded = jsonDecode(await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 5)));
    dynamic rawItems = decoded;
    if (decoded is Map<String, dynamic>) rawItems = decoded['data'] ?? decoded['results'] ?? decoded['tracks'];
    if (rawItems is! List<dynamic>) return null;

    final candidates = <LyricsResult>[];
    for (final raw in rawItems) {
      if (raw is! Map<String, dynamic>) continue;
      final candidateTitle = _cleanTitle(_firstString(raw, const ['songTitle', 'trackName', 'title', 'name']));
      final candidateArtist = _cleanArtist(_firstString(raw, const ['artistName', 'artist', 'artist_name']));
      if (candidateTitle.isEmpty) continue;
      final plain = _firstString(raw, const ['plainLyric', 'plainLyrics', 'plain', 'lyricsText']);
      final synced = _decodeSyncedContent(raw['syncedLyrics'] ?? raw['syncedLyric'] ?? raw['synced'] ?? raw['lrc']);
      final bestPlain = plain.isNotEmpty ? plain : (synced.isEmpty ? '' : _stripLrcTimestamps(synced));
      if (bestPlain.trim().isEmpty && synced.trim().isEmpty) continue;
      candidates.add(LyricsResult(
        id: 0,
        trackName: candidateTitle,
        artistName: candidateArtist.isEmpty ? 'Неизвестный исполнитель' : candidateArtist,
        albumName: _firstString(raw, const ['albumName', 'album', 'album_name']).isEmpty
            ? (album.isEmpty ? null : album)
            : _firstString(raw, const ['albumName', 'album', 'album_name']),
        instrumental: false,
        plainLyrics: bestPlain.isEmpty ? null : bestPlain,
        syncedLyrics: synced.isEmpty ? null : synced,
        sourceName: 'SimpMusic Lyrics API',
        sourceUrl: Uri.https('api-lyrics.simpmusic.org', '/swagger-ui/').toString(),
      ));
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => _score(b, _normalize(title), _normalize(artist)).compareTo(_score(a, _normalize(title), _normalize(artist))));
    final best = candidates.first;
    final score = _score(best, _normalize(title), _normalize(artist));
    if (score < (artist.trim().isEmpty ? 3 : 7)) return null;
    return best;
  }

  static Future<LyricsResult?> _fetchBetterLyrics(String title, String artist, String album, int durationSeconds) async {
    // BetterLyrics may serve cached records without credentials and otherwise
    // return 401/503. Treat those as a normal fallback miss, not as fatal.
    if (title.trim().isEmpty || artist.trim().isEmpty) return null;
    final uri = Uri.https('lyrics-api.binimum.org', '/getLyrics', <String, String>{
      's': title,
      'a': artist,
      if (album.trim().isNotEmpty) 'al': album,
      if (durationSeconds >= 1 && durationSeconds <= 3600) 'd': durationSeconds.toString(),
    });
    final request = await _client.getUrl(uri).timeout(const Duration(seconds: 3));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, 'Oxygen/$_version (https://t.me/onyx_alr)');
    final response = await request.close().timeout(const Duration(seconds: 4));
    if (response.statusCode == HttpStatus.notFound ||
        response.statusCode == HttpStatus.unauthorized ||
        response.statusCode == HttpStatus.forbidden ||
        response.statusCode == HttpStatus.noContent) {
      await response.drain<void>();
      return null;
    }
    if (response.statusCode == HttpStatus.tooManyRequests || response.statusCode >= 500) {
      final status = response.statusCode;
      await response.drain<void>();
      throw LyricsServiceException('BetterLyrics временно недоступен (HTTP $status).');
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      return null;
    }
    final decoded = jsonDecode(await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 4)));
    if (decoded is! Map<String, dynamic>) return null;
    final payload = decoded['data'] is Map<String, dynamic> ? decoded['data'] as Map<String, dynamic> : decoded;
    final raw = _firstString(payload, const ['lyrics', 'ttml', 'plainLyrics', 'plainLyric', 'lrc']);
    if (raw.isEmpty) return null;
    final synced = _decodeSyncedContent(raw);
    final plain = synced.isNotEmpty ? _stripLrcTimestamps(synced) : _stripMarkup(raw);
    if (plain.trim().isEmpty) return null;
    return LyricsResult(
      id: 0,
      trackName: title,
      artistName: artist,
      albumName: album.isEmpty ? null : album,
      instrumental: false,
      plainLyrics: plain,
      syncedLyrics: synced.isEmpty ? null : synced,
      sourceName: 'BetterLyrics API',
      sourceUrl: Uri.https('lyrics-api-docs.boidu.dev', '/reference/get-lyrics').toString(),
    );
  }

  static String _decodeSyncedContent(dynamic value) {
    if (value is String) {
      final text = value.trim();
      if (RegExp(r'^\s*\[\d{1,2}:\d{2}(?:[.:]\d{1,3})?\]', multiLine: true).hasMatch(text)) return text;
      if (text.contains('<tt') || text.contains('<p') || text.contains('<span')) return _ttmlToLrc(text);
      return '';
    }
    if (value is Map<String, dynamic>) {
      final nested = value['lines'] ?? value['lyrics'] ?? value['content'] ?? value['syncedLyrics'];
      return _decodeSyncedContent(nested);
    }
    if (value is List<dynamic>) {
      final rawText = <String>[];
      final timedText = <String>[];
      for (final item in value) {
        final text = _lyricsLineText(item);
        if (text.isEmpty) continue;
        rawText.add(text);
        final time = _lyricsTimeMs(item);
        if (time != null && time >= 0) timedText.add('[${_formatLrcTime(time)}]$text');
      }
      final joined = rawText.join('\n');
      if (RegExp(r'^\s*\[\d{1,2}:\d{2}', multiLine: true).hasMatch(joined)) return joined;
      if (timedText.length >= 2) return timedText.join('\n');
    }
    return '';
  }

  static String _ttmlToLrc(String xml) {
    final output = <String>[];
    final pPattern = RegExp(r'<p\b([^>]*)>([\s\S]*?)</p>', caseSensitive: false);
    final spanPattern = RegExp(r'<span\b([^>]*)>([\s\S]*?)</span>', caseSensitive: false);
    final blocks = pPattern.allMatches(xml).toList(growable: false);
    final matches = blocks.isNotEmpty ? blocks : spanPattern.allMatches(xml).toList(growable: false);
    for (final match in matches) {
      final attributes = match.group(1) ?? '';
      final body = match.group(2) ?? '';
      final begin = RegExp(r'''\bbegin\s*=\s*["']([^"']+)["']''', caseSensitive: false).firstMatch(attributes)?.group(1);
      final millis = begin == null ? null : _parseTtmlTime(begin);
      final text = _stripMarkup(body).replaceAll(RegExp(r'\s+'), ' ').trim();
      if (millis != null && text.isNotEmpty) output.add('[${_formatLrcTime(millis)}]$text');
    }
    return output.length >= 2 ? output.join('\n') : '';
  }

  static int? _parseTtmlTime(String raw) {
    final value = raw.trim();
    if (value.endsWith('ms')) {
      return double.tryParse(value.substring(0, value.length - 2))
          ?.round()
          .clamp(0, 24 * 60 * 60 * 1000)
          .toInt();
    }
    if (value.endsWith('s') && !value.contains(':')) {
      final seconds = double.tryParse(value.substring(0, value.length - 1));
      return seconds == null ? null : (seconds * 1000).round();
    }
    final parts = value.split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    final seconds = double.tryParse(parts.last);
    final minutes = int.tryParse(parts[parts.length - 2]);
    final hours = parts.length == 3 ? int.tryParse(parts[0]) ?? 0 : 0;
    if (seconds == null || minutes == null) return null;
    return ((hours * 3600 + minutes * 60 + seconds) * 1000).round().clamp(0, 24 * 60 * 60 * 1000).toInt();
  }

  static String _stripMarkup(String raw) => raw
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(?:p|div|li)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n[ \t]+'), '\n')
      .trim();

  static String _firstString(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  static String _lyricsLineText(dynamic item) {
    if (item is String) return item.trim();
    if (item is! Map<String, dynamic>) return '';
    for (final key in const ['text', 'line', 'content', 'lyricsText']) {
      final value = item[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    final words = item['words'] ?? item['syllables'] ?? item['tokens'];
    if (words is String) return words.trim();
    if (words is List<dynamic>) {
      final segments = <String>[];
      for (final word in words) {
        if (word is String) {
          if (word.trim().isNotEmpty) segments.add(word.trim());
        } else if (word is Map<String, dynamic>) {
          final value = _firstString(word, const ['text', 'word', 'value', 'token']);
          if (value.isNotEmpty) segments.add(value);
        }
      }
      return segments.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    return '';
  }

  static int? _lyricsTimeMs(dynamic item) {
    if (item is! Map<String, dynamic>) return null;
    final value = item['startTimeMs'] ?? item['time'] ?? item['start'] ?? item['timestamp'] ?? item['startTime'];
    if (value is num) {
      // LyricsPlus v2 `time` and `startTimeMs` are millisecond based.
      return value.round().clamp(0, 24 * 60 * 60 * 1000).toInt();
    }
    if (value is String) {
      final lrc = RegExp(r'^(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?$').firstMatch(value.trim());
      if (lrc != null) {
        final minutes = int.tryParse(lrc.group(1)!) ?? 0;
        final seconds = int.tryParse(lrc.group(2)!) ?? 0;
        final fractionText = lrc.group(3) ?? '0';
        final fractionMs = int.tryParse(fractionText.padRight(3, '0').substring(0, 3)) ?? 0;
        return (minutes * 60 + seconds) * 1000 + fractionMs;
      }
      return int.tryParse(value.trim());
    }
    return null;
  }

  static String _formatLrcTime(int milliseconds) {
    final centiseconds = (milliseconds / 10).round();
    final minutes = (centiseconds ~/ 6000).toString().padLeft(2, '0');
    final seconds = ((centiseconds ~/ 100) % 60).toString().padLeft(2, '0');
    final fraction = (centiseconds % 100).toString().padLeft(2, '0');
    return '$minutes:$seconds.$fraction';
  }

  static String _stripLrcTimestamps(String value) => value
      .replaceAll(RegExp(r'\[\d{1,2}:\d{2}(?:[.:]\d{1,3})?\]'), '')
      .split('\n')
      .map((line) => line.trimRight())
      .where((line) => line.trim().isNotEmpty)
      .join('\n')
      .trim();

  static Future<LyricsResult?> _fetchMusixmatch(String title, String artist, String apiKey) async {
    final uri = Uri.https('api.musixmatch.com', '/ws/1.1/matcher.lyrics.get', <String, String>{
      'format': 'json',
      'q_track': title,
      'q_artist': artist,
      'apikey': apiKey,
    });
    final request = await _client.getUrl(uri).timeout(const Duration(seconds: 8));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, 'Oxygen/$_version lyrics client');
    final response = await request.close().timeout(const Duration(seconds: 12));
    if (response.statusCode == HttpStatus.notFound || response.statusCode == HttpStatus.noContent) {
      await response.drain<void>();
      return null;
    }
    if (response.statusCode == HttpStatus.tooManyRequests) {
      await response.drain<void>();
      throw const LyricsServiceException('Musixmatch ограничил запросы. Попробуй позже.');
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw LyricsServiceException('Musixmatch API вернул HTTP ${response.statusCode}. Проверь API key.');
    }
    final decoded = jsonDecode(await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 8)));
    if (decoded is! Map<String, dynamic>) return null;
    final message = decoded['message'];
    if (message is! Map<String, dynamic>) return null;
    final body = message['body'];
    if (body is! Map<String, dynamic>) return null;
    final lyrics = body['lyrics'];
    if (lyrics is! Map<String, dynamic>) return null;
    final plain = (lyrics['lyrics_body'] as String? ?? '').trim();
    if (plain.isEmpty) return null;
    return LyricsResult(
      id: int.tryParse(lyrics['lyrics_id']?.toString() ?? '') ?? 0,
      trackName: title,
      artistName: artist,
      instrumental: false,
      plainLyrics: plain,
      sourceName: 'Musixmatch API',
      sourceUrl: searchLinks(Track(path: '', title: title, artist: artist))['Musixmatch']!.toString(),
    );
  }

  static Future<LyricsResult?> _fetchLrcLibExact(String title, String artist, String album, int durationSeconds) async {
    final uri = Uri.https('lrclib.net', '/api/get', <String, String>{
      'track_name': title,
      'artist_name': artist,
      if (album.trim().isNotEmpty) 'album_name': album,
      if (durationSeconds >= 1 && durationSeconds <= 3600) 'duration': durationSeconds.toString(),
    });
    final request = await _client.getUrl(uri).timeout(const Duration(seconds: 5));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, 'Oxygen/$_version (https://t.me/onyx_alr)');
    final response = await request.close().timeout(const Duration(seconds: 6));
    if (response.statusCode == HttpStatus.notFound) {
      await response.drain<void>();
      return null;
    }
    if (response.statusCode == HttpStatus.tooManyRequests) {
      final retryAfter = response.headers.value(HttpHeaders.retryAfterHeader);
      final seconds = (int.tryParse(retryAfter ?? '') ?? 30).clamp(1, 300);
      _blockedUntil = DateTime.now().add(Duration(seconds: seconds));
      await response.drain<void>();
      throw LyricsServiceException('LRCLIB просит подождать примерно $seconds сек.');
    }
    if (response.statusCode != HttpStatus.ok) {
      final status = response.statusCode;
      final retryAfter = int.tryParse(response.headers.value(HttpHeaders.retryAfterHeader) ?? '');
      final cooldownSeconds = status >= 500 ? (retryAfter ?? 5).clamp(1, 60).toInt() : 0;
      if (cooldownSeconds > 0) _blockedUntil = DateTime.now().add(Duration(seconds: cooldownSeconds));
      await response.drain<void>();
      throw LyricsServiceException(status >= 500
          ? 'LRCLIB временно перегружен (HTTP $status). Другие источники продолжают работать; повторный запрос к LRCLIB через $cooldownSeconds сек.'
          : 'LRCLIB /api/get вернул HTTP $status.');
    }
    final decoded = jsonDecode(await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 8)));
    if (decoded is! Map<String, dynamic>) return null;
    final result = LyricsResult.fromJson(decoded, sourceName: 'LRCLIB (точное совпадение)', sourceUrl: website);
    return result.hasLyrics || result.instrumental ? result : null;
  }

  static Future<LyricsResult?> _fetchLrcLib(String title, String artist) async {
    final uri = Uri.https('lrclib.net', '/api/search', <String, String>{'q': artist.isEmpty ? title : '$title $artist'});
    final request = await _client.getUrl(uri).timeout(const Duration(seconds: 10));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, 'Oxygen/$_version (https://t.me/onyx_alr)');
    request.headers.set('Lrclib-Client', 'Oxygen/$_version (https://t.me/onyx_alr)');
    final response = await request.close().timeout(const Duration(seconds: 12));
    if (response.statusCode == HttpStatus.tooManyRequests) {
      final retryAfter = response.headers.value(HttpHeaders.retryAfterHeader);
      final seconds = (int.tryParse(retryAfter ?? '') ?? 30).clamp(1, 300);
      _blockedUntil = DateTime.now().add(Duration(seconds: seconds));
      await response.drain<void>();
      throw LyricsServiceException('LRCLIB просит подождать примерно $seconds сек.');
    }
    if (response.statusCode == HttpStatus.notFound) {
      await response.drain<void>();
      return null;
    }
    if (response.statusCode != HttpStatus.ok) {
      final status = response.statusCode;
      final retryAfter = int.tryParse(response.headers.value(HttpHeaders.retryAfterHeader) ?? '');
      final cooldownSeconds = status >= 500 ? (retryAfter ?? 5).clamp(1, 60).toInt() : 0;
      if (cooldownSeconds > 0) _blockedUntil = DateTime.now().add(Duration(seconds: cooldownSeconds));
      await response.drain<void>();
      throw LyricsServiceException(status >= 500
          ? 'LRCLIB временно перегружен (HTTP $status). Остальные сервисы доступны независимо; повторный запрос к LRCLIB через $cooldownSeconds сек.'
          : 'LRCLIB вернул HTTP $status.');
    }
    final body = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 8));
    final json = jsonDecode(body);
    if (json is! List<dynamic>) return null;
    final candidates = json.whereType<Map<String, dynamic>>()
        .map((item) => LyricsResult.fromJson(item, sourceName: 'LRCLIB', sourceUrl: website))
        .where((item) => item.instrumental || item.hasLyrics)
        .toList(growable: false);
    if (candidates.isEmpty) return null;
    final normalizedTitle = _normalize(title);
    final normalizedArtist = _normalize(artist);
    candidates.sort((a, b) => _score(b, normalizedTitle, normalizedArtist).compareTo(_score(a, normalizedTitle, normalizedArtist)));
    final best = candidates.first;
    if (_score(best, normalizedTitle, normalizedArtist) < (normalizedArtist.isEmpty ? 3 : 7)) return null;
    return best;
  }

  static Future<LyricsResult?> _fetchLyricsOvh(String title, String artist) async {
    final uri = Uri(pathSegments: <String>['v1', artist, title], scheme: 'https', host: 'api.lyrics.ovh');
    final request = await _client.getUrl(uri).timeout(const Duration(seconds: 5));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, 'Oxygen/$_version (https://t.me/onyx_alr)');
    final response = await request.close().timeout(const Duration(seconds: 6));
    if (response.statusCode == HttpStatus.notFound || response.statusCode == HttpStatus.noContent) {
      await response.drain<void>();
      return null;
    }
    if (response.statusCode == HttpStatus.tooManyRequests) {
      final retryAfter = response.headers.value(HttpHeaders.retryAfterHeader);
      await response.drain<void>();
      throw LyricsServiceException('Lyrics.ovh ограничил запросы (Retry-After: ${retryAfter ?? 'не указан'}).');
    }
    if (response.statusCode != HttpStatus.ok) {
      final status = response.statusCode;
      await response.drain<void>();
      if (status >= 500) throw LyricsServiceException('Lyrics.ovh временно недоступен (HTTP $status).');
      return null;
    }
    final decoded = jsonDecode(await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 5)));
    if (decoded is! Map<String, dynamic>) return null;
    final lyrics = (decoded['lyrics'] as String? ?? '').trim();
    if (lyrics.isEmpty) return null;
    return LyricsResult(
      id: 0,
      trackName: title,
      artistName: artist,
      instrumental: false,
      plainLyrics: lyrics,
      sourceName: 'Lyrics.ovh API',
      sourceUrl: Uri.https('lyrics.ovh', '/').toString(),
    );
  }

  static Future<LyricsResult?> _fetchLyricsOvhSuggestions(String query, String knownArtist) async {
    final cleanedQuery = _cleanTitle(query).trim();
    if (cleanedQuery.isEmpty) return null;

    final variants = <String>[cleanedQuery];
    final words = cleanedQuery.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList(growable: false);
    if (words.length >= 3) {
      final tail = words.sublist(words.length > 3 ? words.length - 3 : 0).join(' ');
      if (tail.toLowerCase() != cleanedQuery.toLowerCase()) variants.add(tail);
    }
    final transliterated = _latinToCyrillic(cleanedQuery);
    if (transliterated.trim().isNotEmpty && _normalize(transliterated) != _normalize(cleanedQuery)) {
      variants.add(transliterated);
    }
    final queryVariants = variants.toSet().take(3).toList(growable: false);
    final candidates = <String, ({String title, String artist, int score})>{};
    Object? lastRequestError;
    LyricsServiceException? lastHttpError;

    for (final variant in queryVariants) {
      try {
        final uri = Uri.parse('https://api.lyrics.ovh/suggest/${Uri.encodeComponent(variant)}');
        final request = await _client.getUrl(uri).timeout(const Duration(seconds: 4));
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(HttpHeaders.userAgentHeader, 'Oxygen/$_version (https://t.me/onyx_alr)');
        final response = await request.close().timeout(const Duration(seconds: 4));
        if (response.statusCode == HttpStatus.notFound || response.statusCode == HttpStatus.noContent) {
          await response.drain<void>();
          continue;
        }
        if (response.statusCode == HttpStatus.tooManyRequests || response.statusCode >= 500) {
          final status = response.statusCode;
          final retryAfter = response.headers.value(HttpHeaders.retryAfterHeader);
          await response.drain<void>();
          lastHttpError = LyricsServiceException(
            'Lyrics.ovh поиск временно недоступен (HTTP $status${retryAfter == null ? '' : ', Retry-After $retryAfter'}).',
          );
          continue;
        }
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>();
          continue;
        }
        final body = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 4));
        final decoded = jsonDecode(body);
        dynamic rawItems = decoded;
        if (decoded is Map<String, dynamic>) {
          rawItems = decoded['data'] ?? decoded['results'] ?? decoded['tracks'];
        }
        if (rawItems is! List<dynamic>) continue;

        final variantTokens = <String>{
          ..._lyricTokens(variant),
          ..._lyricTokens(_latinToCyrillic(variant)),
          ..._lyricTokens(cleanedQuery),
          ..._lyricTokens(_latinToCyrillic(cleanedQuery)),
        };
        for (final raw in rawItems) {
          if (raw is! Map<String, dynamic>) continue;
          final candidateTitle = _cleanTitle(_firstString(raw, const ['title', 'title_short', 'trackName', 'name']));
          final rawArtist = raw['artist'] ?? raw['artistName'];
          final candidateArtist = _cleanArtist(
            rawArtist is Map<String, dynamic>
                ? _firstString(rawArtist, const ['name', 'artistName', 'title'])
                : rawArtist is String
                    ? rawArtist
                    : _firstString(raw, const ['artistName', 'artist_name']),
          );
          if (candidateTitle.isEmpty || candidateArtist.isEmpty) continue;
          final candidateTokens = _lyricTokens(candidateTitle);
          if (candidateTokens.isEmpty) continue;
          final overlap = candidateTokens.intersection(variantTokens).length;
          if (overlap == 0) continue;
          final normalizedCandidateArtist = _normalize(candidateArtist);
          final normalizedKnownArtist = _normalize(knownArtist);
          var score = overlap * 10;
          if (_normalize(cleanedQuery).contains(_normalize(candidateTitle))) score += 5;
          if (normalizedKnownArtist.isNotEmpty) {
            if (normalizedCandidateArtist == normalizedKnownArtist ||
                normalizedCandidateArtist.contains(normalizedKnownArtist) ||
                normalizedKnownArtist.contains(normalizedCandidateArtist)) {
              score += 12;
            } else {
              score -= 8;
            }
          }
          final key = '$normalizedCandidateArtist|${_normalize(candidateTitle)}';
          final previous = candidates[key];
          if (previous == null || score > previous.score) {
            candidates[key] = (title: candidateTitle, artist: candidateArtist, score: score);
          }
        }
      } catch (error) {
        lastRequestError = error;
      }
      // If an API variant produced at least one decent two-word match, avoid extra requests.
      if (candidates.values.any((candidate) => candidate.score >= 20)) break;
    }

    final ranked = candidates.values.toList(growable: false)..sort((a, b) => b.score.compareTo(a.score));
    for (final candidate in ranked.take(2)) {
      try {
        final result = await _fetchLyricsOvh(candidate.title, candidate.artist).timeout(const Duration(seconds: 7));
        if (result == null || !result.hasLyrics) continue;
        return LyricsResult(
          id: result.id,
          trackName: candidate.title,
          artistName: candidate.artist,
          albumName: result.albumName,
          instrumental: result.instrumental,
          plainLyrics: result.plainLyrics,
          syncedLyrics: result.syncedLyrics,
          sourceName: 'Lyrics.ovh API · найдено через поиск',
          sourceUrl: result.sourceUrl,
        );
      } catch (error) {
        lastRequestError = error;
      }
    }

    if (candidates.isEmpty && lastHttpError != null) throw lastHttpError;
    if (candidates.isEmpty && lastRequestError != null &&
        (lastRequestError is SocketException || lastRequestError is TimeoutException || lastRequestError is HandshakeException)) {
      throw LyricsServiceException(_userError(lastRequestError));
    }
    return null;
  }

  static String _latinToCyrillic(String value) => value.replaceAllMapped(
        RegExp(r'shch|sch|yo|jo|zh|kh|ts|ch|sh|yu|ju|ya|ja|ye|je|a|b|v|g|d|e|z|i|j|k|l|m|n|o|p|r|s|t|u|f|h|c|y|w|q|x', caseSensitive: false),
        (match) => switch (match.group(0)!.toLowerCase()) {
          'shch' || 'sch' => 'щ',
          'yo' || 'jo' => 'ё',
          'zh' => 'ж',
          'kh' => 'х',
          'ts' => 'ц',
          'ch' => 'ч',
          'sh' => 'ш',
          'yu' || 'ju' => 'ю',
          'ya' || 'ja' => 'я',
          'ye' || 'je' => 'е',
          'a' => 'а', 'b' => 'б', 'v' => 'в', 'g' => 'г', 'd' => 'д',
          'e' => 'е', 'z' => 'з', 'i' => 'и', 'j' => 'й', 'k' => 'к',
          'l' => 'л', 'm' => 'м', 'n' => 'н', 'o' => 'о', 'p' => 'п',
          'r' => 'р', 's' => 'с', 't' => 'т', 'u' => 'у', 'f' => 'ф',
          'h' => 'х', 'c' => 'к', 'y' => 'ы', 'w' => 'в', 'q' => 'к',
          'x' => 'кс',
          _ => match.group(0)!,
        },
      );

  static String _userError(Object error) {
    if (error is LyricsServiceException) return error.message;
    if (error is TimeoutException) return 'время ожидания истекло';
    if (error is SocketException) return 'нет соединения с сервисами текстов';
    if (error is HandshakeException) return 'не удалось установить защищённое HTTPS-соединение';
    return error.toString();
  }

  static int _score(LyricsResult item, String title, String artist) {
    final candidateTitle = _normalize(item.trackName);
    final candidateArtist = _normalize(item.artistName);
    var score = 0;
    if (candidateTitle == title) {
      score += 6;
    } else if (candidateTitle.contains(title) || title.contains(candidateTitle)) {
      score += 3;
    } else {
      score -= 5;
    }
    if (artist.isNotEmpty) {
      if (candidateArtist == artist) {
        score += 5;
      } else if (candidateArtist.contains(artist) || artist.contains(candidateArtist)) {
        score += 2;
      } else {
        score -= 2;
      }
    }
    if (item.plainLyrics?.trim().isNotEmpty == true) score++;
    if (item.syncedLyrics?.trim().isNotEmpty == true) score++;
    return score;
  }

  static Set<String> _lyricTokens(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9а-яё]+', caseSensitive: false), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((token) => token.length > 1)
      .toSet();

  static String _normalize(String value) => value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё]+', caseSensitive: false), '');
}

class LyricsResult {
  const LyricsResult({
    required this.id,
    required this.trackName,
    required this.artistName,
    required this.instrumental,
    this.albumName,
    this.plainLyrics,
    this.syncedLyrics,
    this.sourceName = 'LRCLIB',
    this.sourceUrl = 'https://lrclib.net',
  });
  final int id;
  final String trackName;
  final String artistName;
  final String? albumName;
  final bool instrumental;
  final String? plainLyrics;
  final String? syncedLyrics;
  final String sourceName;
  final String sourceUrl;
  bool get hasLyrics => plainLyrics?.trim().isNotEmpty == true || syncedLyrics?.trim().isNotEmpty == true;

  factory LyricsResult.fromJson(Map<String, dynamic> json, {String sourceName = 'LRCLIB', String sourceUrl = 'https://lrclib.net'}) => LyricsResult(
        id: (json['id'] as num?)?.toInt() ?? 0,
        trackName: json['trackName'] as String? ?? json['name'] as String? ?? 'Без названия',
        artistName: json['artistName'] as String? ?? 'Неизвестный исполнитель',
        albumName: json['albumName'] as String?,
        instrumental: json['instrumental'] as bool? ?? false,
        plainLyrics: json['plainLyrics'] as String?,
        syncedLyrics: json['syncedLyrics'] as String?,
        sourceName: sourceName,
        sourceUrl: sourceUrl,
      );
}

class LyricsServiceException implements Exception {
  const LyricsServiceException(this.message);
  final String message;
  @override
  String toString() => message;
}
