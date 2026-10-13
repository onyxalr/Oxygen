import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/track.dart';

/// Apple/iTunes catalogue search. Results include catalog metadata and a
/// short streaming preview when Apple provides one; this is not full-song
/// streaming. Query results are cached and requests are rate-limited.
class SongCatalogService {
  SongCatalogService._();

  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 20);

  static final Map<String, List<Track>> _cache = <String, List<Track>>{};
  static final Map<String, Future<List<Track>>> _inFlight = <String, Future<List<Track>>>{};
  static DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
  static Future<void> _requestTail = Future<void>.value();

  static const String website = 'https://music.apple.com';

  static Future<List<Track>> search(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.length < 2) return const <Track>[];
    final key = query.toLowerCase();
    if (_cache.containsKey(key)) return _cache[key]!;
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final request = _serialized(() => _fetch(query));
    _inFlight[key] = request;
    try {
      final results = await request;
      _cache[key] = List<Track>.unmodifiable(results);
      while (_cache.length > 60) {
        _cache.remove(_cache.keys.first);
      }
      return results;
    } finally {
      _inFlight.remove(key);
    }
  }

  static Future<T> _serialized<T>(Future<T> Function() action) async {
    final completer = Completer<void>();
    final previous = _requestTail;
    _requestTail = completer.future;
    await previous;
    try {
      // Apple's public Search API recommends caching and limits request rate
      // to approximately 20 requests/minute, so leave a little over 3 seconds.
      final elapsed = DateTime.now().difference(_lastRequestAt).inMilliseconds;
      if (elapsed < 3100) {
        await Future<void>.delayed(Duration(milliseconds: 3100 - elapsed));
      }
      _lastRequestAt = DateTime.now();
      return await action();
    } finally {
      completer.complete();
    }
  }

  static Future<List<Track>> _fetch(String query) async {
    final uri = Uri.https('itunes.apple.com', '/search', <String, String>{
      'term': query,
      'entity': 'song',
      'limit': '25',
    });

    try {
      final request = await _client.getUrl(uri).timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'Oxygen/3.8 (music catalogue search)');
      final response = await request.close().timeout(const Duration(seconds: 12));

      if (response.statusCode == HttpStatus.tooManyRequests) {
        await response.drain<void>();
        throw const SongCatalogException('Каталог ограничил частоту запросов. Подожди немного и попробуй снова.');
      }
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw SongCatalogException('Каталог Apple вернул HTTP ${response.statusCode}.');
      }

      final body = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 8));
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> || decoded['results'] is! List<dynamic>) {
        throw const SongCatalogException('Каталог вернул неожиданный формат ответа.');
      }

      final tracks = <Track>[];
      for (final item in decoded['results'] as List<dynamic>) {
        if (item is! Map<String, dynamic>) continue;
        final preview = _secureUrl(item['previewUrl'] as String?);
        final title = (item['trackName'] as String? ?? '').trim();
        final artist = (item['artistName'] as String? ?? '').trim();
        if (preview == null || title.isEmpty || artist.isEmpty) continue;

        final artwork = _secureUrl(item['artworkUrl100'] as String?)
            ?.replaceFirst('100x100', '600x600');
        final storeUrl = _secureUrl(item['trackViewUrl'] as String?) ??
            _secureUrl(item['collectionViewUrl'] as String?);
        tracks.add(Track(
          path: preview,
          title: title,
          artist: artist,
          artworkUrl: artwork,
          storeUrl: storeUrl,
          albumName: item['collectionName'] as String?,
        ));
      }
      return tracks;
    } on SongCatalogException {
      rethrow;
    } on TimeoutException {
      throw const SongCatalogException('Каталог музыки не ответил вовремя. Проверь интернет.');
    } on SocketException {
      throw const SongCatalogException('Нет соединения с каталогом музыки. Проверь интернет.');
    } on HandshakeException {
      throw const SongCatalogException('Не удалось установить защищённое соединение с каталогом.');
    } on FormatException {
      throw const SongCatalogException('Не удалось разобрать ответ каталога музыки.');
    } catch (error) {
      throw SongCatalogException('Не удалось выполнить поиск песен: $error');
    }
  }

  static String? _secureUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasAuthority) return null;
    if (uri.scheme == 'https') return uri.toString();
    if (uri.scheme == 'http') return uri.replace(scheme: 'https').toString();
    return null;
  }
}

class SongCatalogException implements Exception {
  const SongCatalogException(this.message);
  final String message;
  @override
  String toString() => message;
}
