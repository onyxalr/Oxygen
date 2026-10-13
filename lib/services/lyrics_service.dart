import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/track.dart';

/// Lightweight LRCLIB client. Results and in-flight requests are cached so
/// reopening the lyrics panel does not create more network traffic.
class LyricsService {
  LyricsService._();

  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 20);

  static final Map<String, LyricsResult?> _cache = <String, LyricsResult?>{};
  static final Map<String, Future<LyricsResult?>> _inFlight = <String, Future<LyricsResult?>>{};
  static DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime _blockedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  static Future<void> _requestTail = Future<void>.value();

  static const String website = 'https://lrclib.net';
  static const String _version = '3.8.0';

  static Future<LyricsResult?> lookup(Track track) {
    final title = track.title.trim();
    // Imported local files currently do not include parsed artist metadata.
    final artist = track.artist.trim() == 'Локальный файл' ? '' : track.artist.trim();
    final key = '${title.toLowerCase()}\u0000${artist.toLowerCase()}';
    if (_cache.containsKey(key)) return Future<LyricsResult?>.value(_cache[key]);
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final future = _serialized(() => _fetch(title: title, artist: artist));
    _inFlight[key] = future;
    return future.then((result) {
      _cache[key] = result;
      // Keep the in-memory cache bounded for long-running player sessions.
      while (_cache.length > 80) {
        _cache.remove(_cache.keys.first);
      }
      return result;
    }).whenComplete(() => _inFlight.remove(key));
  }

  static Future<T> _serialized<T>(Future<T> Function() action) async {
    final completer = Completer<void>();
    final previous = _requestTail;
    _requestTail = completer.future;
    await previous;
    try {
      final now = DateTime.now();
      if (now.isBefore(_blockedUntil)) {
        await Future<void>.delayed(_blockedUntil.difference(now));
      }
      final elapsed = DateTime.now().difference(_lastRequestAt).inMilliseconds;
      if (elapsed < 300) {
        await Future<void>.delayed(Duration(milliseconds: 300 - elapsed));
      }
      _lastRequestAt = DateTime.now();
      return await action();
    } finally {
      completer.complete();
    }
  }

  static Future<LyricsResult?> _fetch({required String title, required String artist}) async {
    if (title.isEmpty) return null;

    final query = <String, String>{'q': artist.isEmpty ? title : '$title $artist'};
    final uri = Uri.https('lrclib.net', '/api/search', query);
    try {
      final request = await _client.getUrl(uri).timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'Oxygen/$_version (https://t.me/onyx_alr)');
      request.headers.set('Lrclib-Client', 'Oxygen/$_version (https://t.me/onyx_alr)');
      final response = await request.close().timeout(const Duration(seconds: 12));

      if (response.statusCode == HttpStatus.tooManyRequests) {
        final retryAfter = response.headers.value(HttpHeaders.retryAfterHeader);
        final retrySeconds = (int.tryParse(retryAfter ?? '') ?? 30).clamp(1, 300);
        _blockedUntil = DateTime.now().add(Duration(seconds: retrySeconds));
        await response.drain<void>();
        throw LyricsServiceException('Слишком много запросов. Сервис разблокирует поиск примерно через $retrySeconds сек.');
      }
      if (response.statusCode == HttpStatus.notFound) {
        await response.drain<void>();
        return null;
      }
      if (response.statusCode != HttpStatus.ok) {
        throw LyricsServiceException('Сервис текстов вернул HTTP ${response.statusCode}.');
      }

      final body = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 8));
      final json = jsonDecode(body);
      if (json is! List<dynamic>) return null;

      final candidates = json
          .whereType<Map<String, dynamic>>()
          .map(LyricsResult.fromJson)
          .where((item) => item.instrumental || item.hasLyrics)
          .toList(growable: false);
      if (candidates.isEmpty) return null;

      final normalizedTitle = _normalize(title);
      final normalizedArtist = _normalize(artist);
      if (normalizedTitle.isEmpty) return null;
      candidates.sort((a, b) => _score(b, normalizedTitle, normalizedArtist)
          .compareTo(_score(a, normalizedTitle, normalizedArtist)));
      final best = candidates.first;
      final score = _score(best, normalizedTitle, normalizedArtist);
      // Avoid displaying the lyrics of a similarly named but different track.
      if (score < (normalizedArtist.isEmpty ? 3 : 7)) return null;
      return best;
    } on LyricsServiceException {
      rethrow;
    } on TimeoutException {
      throw LyricsServiceException('Сервис текстов не ответил вовремя. Проверь интернет и повтори попытку.');
    } on SocketException {
      throw LyricsServiceException('Нет соединения с LRCLIB. Проверь интернет.');
    } on HandshakeException {
      throw LyricsServiceException('Не удалось установить защищённое соединение с сервисом текстов.');
    } on FormatException {
      throw LyricsServiceException('Сервис текстов вернул данные в неизвестном формате.');
    } catch (error) {
      throw LyricsServiceException('Не удалось загрузить текст: $error');
    }
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

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9а-яё]+', caseSensitive: false), '');
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
  });

  final int id;
  final String trackName;
  final String artistName;
  final String? albumName;
  final bool instrumental;
  final String? plainLyrics;
  final String? syncedLyrics;

  bool get hasLyrics =>
      plainLyrics?.trim().isNotEmpty == true || syncedLyrics?.trim().isNotEmpty == true;

  factory LyricsResult.fromJson(Map<String, dynamic> json) => LyricsResult(
        id: (json['id'] as num?)?.toInt() ?? 0,
        trackName: json['trackName'] as String? ?? json['name'] as String? ?? 'Без названия',
        artistName: json['artistName'] as String? ?? 'Неизвестный исполнитель',
        albumName: json['albumName'] as String?,
        instrumental: json['instrumental'] as bool? ?? false,
        plainLyrics: json['plainLyrics'] as String?,
        syncedLyrics: json['syncedLyrics'] as String?,
      );
}

class LyricsServiceException implements Exception {
  const LyricsServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}
