import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:miniaudio_player/miniaudio_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';

List<dynamic> _decodeTrackJson(String source) => jsonDecode(source) as List<dynamic>;
String _encodeTrackJson(List<Map<String, String>> tracks) => jsonEncode(tracks);

enum OxygenPlaybackState { stopped, playing, paused, completed }

@immutable
class PlaybackProgress {
  const PlaybackProgress({this.position = Duration.zero, this.duration = Duration.zero});
  final Duration position;
  final Duration duration;
  double get value => duration.inMilliseconds <= 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0).toDouble();
}

class AudioController extends ChangeNotifier {
  AudioController() {
    _engineReady = _initializeEngine();
    _subscriptions.add(_player.stream.playing.listen((playing) {
      if (playing) {
        state = OxygenPlaybackState.playing;
        if (_visualizerRequested) _startVisualizer();
      } else {
        _stopVisualizer();
        if (state != OxygenPlaybackState.completed && state != OxygenPlaybackState.stopped) {
          state = OxygenPlaybackState.paused;
        }
      }
      if (!_disposed) notifyListeners();
    }));
    _subscriptions.add(_player.stream.position.listen((value) {
      position = value;
      final now = DateTime.now();
      if (now.difference(_lastProgressPublish).inMilliseconds < 220) return;
      _lastProgressPublish = now;
      duration = _safeDuration(_player.state.duration, duration);
      playbackProgress.value = PlaybackProgress(position: position, duration: duration);
    }));
    _subscriptions.add(_player.stream.completed.listen((completed) {
      if (!completed || _disposed) return;
      state = OxygenPlaybackState.completed;
      _stopVisualizer();
      position = duration;
      playbackProgress.value = PlaybackProgress(position: position, duration: duration);
      notifyListeners();
      if (repeatOne) {
        unawaited(_restartCurrent());
      } else {
        unawaited(next());
      }
    }));
    unawaited(restoreLibrary());
  }

  final MiniaudioPlayer _player = MiniaudioPlayer();
  late final Future<void> _engineReady;
  final ValueNotifier<PlaybackProgress> playbackProgress = ValueNotifier<PlaybackProgress>(const PlaybackProgress());
  final ValueNotifier<double> volumeListenable = ValueNotifier<double>(0.82);
  /// Actual band energy provided by miniaudio DSP. Subscribed only while playing.
  final ValueNotifier<List<double>> visualizerBands = ValueNotifier<List<double>>(
    List<double>.filled(10, 0.035, growable: false),
  );
  StreamSubscription<dynamic>? _visualizerSubscription;
  bool _visualizerRequested = false;
  final List<Track> library = <Track>[];
  final Set<String> favoriteIds = <String>{};
  final List<Track> queue = <Track>[];
  final Map<String, String> _searchIndex = <String, String>{};
  final List<StreamSubscription<dynamic>> _subscriptions = <StreamSubscription<dynamic>>[];

  Track? current;
  OxygenPlaybackState state = OxygenPlaybackState.stopped;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  double volume = 0.82;
  double balance = 0;
  List<double> equalizerBands = List<double>.filled(10, 0, growable: false);
  bool shuffle = false;
  bool repeatOne = false;
  bool busy = false;
  String? lastError;
  String? statusMessage;
  int? sleepTimerMinutes;
  bool equalizerEnabled = true;
  bool limiterEnabled = true;
  bool reverbEnabled = false;
  double reverbMix = 0.18;
  bool spatializerEnabled = false;
  double spatializerWidth = 1.20;
  bool monoDownmix = false;
  double preampDb = 0.0;
  double playbackRate = 1.0;
  double pitch = 1.0;
  int _queueIndex = -1;
  int _startGeneration = 0;
  bool _disposed = false;
  bool _hasOpenedSource = false;
  Timer? _sleepTimer;
  Timer? _eqDebounce;
  Timer? _volumeDebounce;
  DateTime _lastProgressPublish = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _startQueue = Future<void>.value();
  static const String _balancePrefsKey = 'oxygen.player.stereoBalance';
  static const String _eqBandsKey = 'oxygen.player.eqBands';
  static const String _eqEnabledKey = 'oxygen.player.eqEnabled';
  static const String _limiterEnabledKey = 'oxygen.player.limiterEnabled';
  static const String _reverbEnabledKey = 'oxygen.player.reverbEnabled';
  static const String _reverbMixKey = 'oxygen.player.reverbMix';
  static const String _spatializerEnabledKey = 'oxygen.player.spatializerEnabled';
  static const String _spatializerWidthKey = 'oxygen.player.spatializerWidth';
  static const String _monoKey = 'oxygen.player.mono';
  static const String _preampKey = 'oxygen.player.preampDb';
  static const String _rateKey = 'oxygen.player.rate';
  static const String _pitchKey = 'oxygen.player.pitch';
  static const int _maxRemoteAudioBytes = 512 * 1024 * 1024;
  static final HttpClient _mediaClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 35);
  static const Set<String> _supportedExtensions = <String>{
    '.mp3', '.mp2', '.mp1', '.wav', '.bwf', '.rifx', '.w64', '.rf64',
    '.flac', '.ogg', '.oga', '.opus', '.m4a', '.aac', '.aif', '.aiff', '.aifc',
  };

  bool get isPlaying => state == OxygenPlaybackState.playing;
  bool get hasTrack => current != null;
  double get progress => duration.inMilliseconds <= 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0).toDouble();

  Duration _safeDuration(Duration value, Duration fallback) => value > Duration.zero ? value : fallback;

  void setVisualizerEnabled(bool enabled) {
    _visualizerRequested = enabled;
    if (!enabled || !isPlaying) {
      _stopVisualizer();
    } else {
      _startVisualizer();
    }
  }

  void _startVisualizer() {
    if (_disposed || !_visualizerRequested || _visualizerSubscription != null) return;
    try {
      _visualizerSubscription = _player.stream.visualizer.listen((sample) {
        if (_disposed) return;
        try {
          final next = <double>[
            sample.hz31, sample.hz63, sample.hz125, sample.hz250, sample.hz500,
            sample.hz1k, sample.hz2k, sample.hz4k, sample.hz8k, sample.hz16k,
          ].map((value) => (value as num).toDouble().abs().clamp(0.0, 1.0).toDouble())
              .toList(growable: false);
          visualizerBands.value = next;
        } catch (_) {
          // Keep the player functional if a native visualizer sample is partial.
        }
      }, onError: (_) {});
    } catch (_) {
      // The analyzer is optional; playback and DSP remain available if a backend
      // cannot expose visualizer data on a particular platform.
    }
  }

  void _stopVisualizer({bool reset = true}) {
    final active = _visualizerSubscription;
    _visualizerSubscription = null;
    if (active != null) unawaited(active.cancel());
    if (reset && !_disposed) {
      visualizerBands.value = List<double>.filled(10, 0.035, growable: false);
    }
  }

  Future<void> _initializeEngine() async {
    final prefs = await SharedPreferences.getInstance();
    balance = (prefs.getDouble(_balancePrefsKey) ?? 0.0).clamp(-1.0, 1.0).toDouble();
    final savedBands = prefs.getStringList(_eqBandsKey);
    if (savedBands != null && savedBands.isNotEmpty) {
      final oldValues = savedBands.map((value) => double.tryParse(value) ?? 0).toList(growable: false);
      if (oldValues.length == 10) {
        equalizerBands = oldValues.map((value) => value.clamp(-12.0, 12.0).toDouble()).toList(growable: false);
      } else if (oldValues.length == 5) {
        equalizerBands = List<double>.generate(10, (index) => oldValues[index ~/ 2].clamp(-12.0, 12.0).toDouble(), growable: false);
      }
    }
    equalizerEnabled = prefs.getBool(_eqEnabledKey) ?? true;
    limiterEnabled = prefs.getBool(_limiterEnabledKey) ?? true;
    reverbEnabled = prefs.getBool(_reverbEnabledKey) ?? false;
    reverbMix = (prefs.getDouble(_reverbMixKey) ?? 0.18).clamp(0.0, 0.55).toDouble();
    spatializerEnabled = prefs.getBool(_spatializerEnabledKey) ?? false;
    spatializerWidth = (prefs.getDouble(_spatializerWidthKey) ?? 1.20).clamp(1.0, 1.8).toDouble();
    monoDownmix = prefs.getBool(_monoKey) ?? false;
    preampDb = (prefs.getDouble(_preampKey) ?? 0.0).clamp(-6.0, 6.0).toDouble();
    playbackRate = (prefs.getDouble(_rateKey) ?? 1.0).clamp(0.5, 2.0).toDouble();
    pitch = (prefs.getDouble(_pitchKey) ?? 1.0).clamp(0.5, 2.0).toDouble();
    await _player.action.setVolume(volume);
    await _player.action.setBalance(balance);
    // Do not send DSP commands before a decoder is open. Several native audio
    // backends only bind their processing graph after open(); _start reapplies
    // the entire persisted chain immediately after opening a file.
  }

  Future<void> _applyDsp() async {
    final failures = <String>[];
    Future<void> apply(String label, Future<void> Function() action) async {
      try {
        await action();
      } catch (error) {
        failures.add('$label: $error');
      }
    }

    final activeBands = equalizerEnabled ? equalizerBands : List<double>.filled(10, 0, growable: false);
    await apply('Эквалайзер', () => _player.action.setEqualizer(_makeEqualizer(activeBands)));
    await apply('Лимитер', () => _player.action.setLimiter(limiterEnabled));
    final wet = reverbEnabled ? reverbMix : 0.0;
    await apply('Реверберация', () => _player.action.configureReverb(
      roomSize: 0.52,
      damping: 0.48,
      wet: wet,
      dry: 1.0 - wet,
      width: 1.0,
      enabled: reverbEnabled,
    ));
    await apply('Стерео', () => _player.action.setSpatializer(enabled: spatializerEnabled, width: spatializerWidth));
    await apply('Моно', () => _player.action.setMono(monoDownmix));
    await apply('Предусиление', () => _player.action.setPreamp(preampDb));
    await apply('Скорость', () => _player.action.setRate(playbackRate));
    await apply('Высота тона', () => _player.action.setPitch(pitch));

    // A DSP capability failure should not stop otherwise playable audio.
    lastError = failures.isEmpty
        ? null
        : 'Трек играет, но некоторые эффекты не применились: ${failures.join(' · ')}';
  }

  Equalizer _makeEqualizer(List<double> bands) => Equalizer(
        hz31: _band(bands, 0),
        hz63: _band(bands, 1),
        hz125: _band(bands, 2),
        hz250: _band(bands, 3),
        hz500: _band(bands, 4),
        hz1k: _band(bands, 5),
        hz2k: _band(bands, 6),
        hz4k: _band(bands, 7),
        hz8k: _band(bands, 8),
        hz16k: _band(bands, 9),
      );

  double _band(List<double> values, int index) =>
      (index < values.length ? values[index] : 0).clamp(-12.0, 12.0).toDouble();

  static String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static String _extensionOf(String rawPath) {
    final uri = Uri.tryParse(rawPath);
    final path = uri != null && uri.hasAuthority ? uri.path : rawPath;
    final fileName = path.split(RegExp(r'[/\\]')).last;
    final dot = fileName.lastIndexOf('.');
    if (dot < 0) return '';
    return fileName.substring(dot).toLowerCase();
  }

  static String _normalizeLocalPath(String rawPath) {
    final uri = Uri.tryParse(rawPath);
    if (uri != null && uri.scheme.toLowerCase() == 'file') {
      try {
        return uri.toFilePath(windows: Platform.isWindows);
      } catch (_) {
        return rawPath;
      }
    }
    return rawPath;
  }

  static Future<Directory>? _cacheDirectoryFuture;

  static Future<Directory> _cacheDirectory() => _cacheDirectoryFuture ??= _createCacheDirectory();

  static Future<Directory> _createCacheDirectory() async {
    final directory = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}oxygen_audio_cache');
    if (!await directory.exists()) await directory.create(recursive: true);
    // The remote cache is temporary: remove only stale generated cache files,
    // never user music. This prevents old downloads from growing indefinitely.
    try {
      final now = DateTime.now();
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File || entity.path.endsWith('.part')) continue;
        try {
          final stat = await entity.stat();
          if (now.difference(stat.modified) > const Duration(days: 10)) {
            await entity.delete();
          }
        } catch (_) {
          // A file may be in use; leave it alone.
        }
      }
    } catch (_) {
      // Cache pruning is optional and must never block playback.
    }
    return directory;
  }

  Future<String> _preparePlayablePath(Track track) async {
    if (track.isRemote) return _downloadRemoteAudio(track.path);

    final normalizedPath = _normalizeLocalPath(track.path);
    final file = File(normalizedPath);
    if (!await file.exists()) {
      throw FileSystemException('Файл не найден. Возможно, его переместили или удалили. Добавь его в библиотеку заново.', normalizedPath);
    }
    final extension = _extensionOf(normalizedPath);
    if (!_supportedExtensions.contains(extension)) {
      throw FormatException('Формат $extension не поддерживается аудиодвижком. Поддерживаются MP3, WAV, FLAC, OGG, OPUS, M4A, AAC и AIFF.');
    }
    return file.absolute.path;
  }

  static String _extensionFromMime(String mime) {
    final value = mime.toLowerCase().split(';').first.trim();
    const mapping = <String, String>{
      'audio/mpeg': '.mp3',
      'audio/mp3': '.mp3',
      'audio/mp2': '.mp2',
      'audio/wav': '.wav',
      'audio/wave': '.wav',
      'audio/x-wav': '.wav',
      'audio/vnd.wave': '.wav',
      'audio/flac': '.flac',
      'audio/x-flac': '.flac',
      'audio/ogg': '.ogg',
      'application/ogg': '.ogg',
      'audio/opus': '.opus',
      'audio/aac': '.aac',
      'audio/mp4': '.m4a',
      'audio/x-m4a': '.m4a',
      'audio/aiff': '.aiff',
      'audio/x-aiff': '.aiff',
    };
    return mapping[value] ?? '';
  }

  static Future<File?> _findCachedRemoteFile(Directory directory, String prefix) async {
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File || !entity.uri.pathSegments.last.startsWith(prefix) || entity.path.endsWith('.part')) continue;
        if (!_supportedExtensions.contains(_extensionOf(entity.path))) continue;
        try {
          if (await entity.length() > 128) return entity.absolute;
        } catch (_) {
          // Ignore a cache file that was deleted by another process.
        }
      }
    } catch (_) {
      // Cache lookup is an optimization only.
    }
    return null;
  }

  Future<String> _downloadRemoteAudio(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http') || !uri.hasAuthority) {
      throw const FormatException('Источник вернул некорректную ссылку на аудио.');
    }

    final directory = await _cacheDirectory();
    // Version the cache namespace so entries previously saved with a guessed
    // .mp3 extension cannot poison a redirect URL returning AAC/FLAC/etc.
    final prefix = 'remote_${_stableHash(rawUrl)}_v4_';
    final cached = await _findCachedRemoteFile(directory, prefix);
    if (cached != null) return cached.path;

    final request = await _mediaClient.getUrl(uri).timeout(const Duration(seconds: 15));
    request.followRedirects = true;
    request.maxRedirects = 8;
    request.headers.set(HttpHeaders.userAgentHeader, 'Oxygen/4.0 audio-cache');
    request.headers.set(HttpHeaders.acceptHeader, 'audio/*,application/octet-stream;q=0.9,*/*;q=0.5');
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw HttpException('Источник аудио вернул HTTP ${response.statusCode}. Ссылка могла устареть или трек недоступен.', uri: uri);
    }

    final contentType = response.headers.contentType?.mimeType.toLowerCase() ?? '';
    if (contentType.contains('text/html') || contentType.contains('application/json') || contentType.contains('text/plain')) {
      await response.drain<void>();
      throw HttpException('Вместо аудио источник вернул страницу или текст. Выбери другую запись или источник.', uri: uri);
    }
    if (response.contentLength > _maxRemoteAudioBytes) {
      await response.drain<void>();
      throw HttpException('Файл превышает лимит кэша 512 МБ.', uri: uri);
    }

    final finalUri = response.redirects.isNotEmpty ? response.redirects.last.location : uri;
    final mimeExtension = _extensionFromMime(contentType);
    final finalUrlExtension = _extensionOf(finalUri.toString());
    final originalUrlExtension = _extensionOf(uri.toString());
    final extension = _supportedExtensions.contains(mimeExtension)
        ? mimeExtension
        : (_supportedExtensions.contains(finalUrlExtension)
            ? finalUrlExtension
            : (_supportedExtensions.contains(originalUrlExtension) ? originalUrlExtension : '.mp3'));
    final target = File('${directory.path}${Platform.pathSeparator}$prefix$extension');
    final partial = File('${target.path}.part');
    if (await partial.exists()) {
      try { await partial.delete(); } catch (_) {}
    }

    final sink = partial.openWrite();
    var received = 0;
    var closed = false;
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 50))) {
        received += chunk.length;
        if (received > _maxRemoteAudioBytes) {
          throw HttpException('Файл превысил лимит кэша 512 МБ.', uri: uri);
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      closed = true;
      if (received <= 128) {
        throw HttpException('Источник отдал пустой или слишком маленький аудиофайл.', uri: uri);
      }
      final sample = await partial.openRead(0, 96).fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
      final prefixText = utf8.decode(sample, allowMalformed: true).trimLeft().toLowerCase();
      if (prefixText.startsWith('<!doctype html') || prefixText.startsWith('<html') || prefixText.startsWith('{"error"')) {
        throw HttpException('Источник вернул страницу ошибки вместо аудиофайла.', uri: uri);
      }
      final renamed = await partial.rename(target.path);
      if (!await renamed.exists() || await renamed.length() <= 128) {
        throw HttpException('Не удалось сохранить аудиофайл в кэш.', uri: uri);
      }
      return renamed.absolute.path;
    } catch (_) {
      if (!closed) {
        try { await sink.close(); } catch (_) {}
      }
      if (await partial.exists()) {
        try { await partial.delete(); } catch (_) {}
      }
      rethrow;
    }
  }

  Future<String> _makeSafeLocalCopy(String rawPath) async {
    final sourcePath = _normalizeLocalPath(rawPath);
    final source = File(sourcePath);
    if (!await source.exists()) return sourcePath;
    final stat = await source.stat();
    if (stat.size <= 0 || stat.size > _maxRemoteAudioBytes) return source.absolute.path;
    final extension = _extensionOf(sourcePath);
    if (!_supportedExtensions.contains(extension)) return source.absolute.path;
    final cache = await _cacheDirectory();
    final signature = '${source.absolute.path}|${stat.size}|${stat.modified.millisecondsSinceEpoch}';
    final copy = File('${cache.path}${Platform.pathSeparator}local_${_stableHash(signature)}$extension');
    if (!await copy.exists() || (await copy.length()) != stat.size) {
      await source.copy(copy.path);
    }
    return copy.path;
  }

  Future<void> restoreLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    final rawTracks = prefs.getString('oxygen.library');
    final rawFavorites = prefs.getStringList('oxygen.favorites') ?? const <String>[];
    try {
      await _engineReady;
    } catch (error) {
      lastError = 'Не удалось инициализировать аудиодвижок: $error';
    }
    if (rawTracks != null) {
      try {
        final decoded = rawTracks.length >= 256 * 1024
            ? await compute(_decodeTrackJson, rawTracks)
            : jsonDecode(rawTracks) as List<dynamic>;
        library.addAll(decoded
            .map((item) => Track.fromJson(Map<String, dynamic>.from(item as Map)))
            .where((track) => track.path.isNotEmpty));
      } catch (_) {
        // Ignore corrupt legacy library data so the app still opens.
      }
    }
    favoriteIds.addAll(rawFavorites);
    if (!_disposed) notifyListeners();
  }

  String searchableText(Track track) => _searchIndex.putIfAbsent(
        track.id,
        () => '${track.title} ${track.artist} ${track.fileName}'.toLowerCase(),
      );

  Future<void> _saveLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    final snapshot = library.map((track) => track.toJson()).toList(growable: false);
    final encoded = snapshot.length >= 1000 ? await compute(_encodeTrackJson, snapshot) : jsonEncode(snapshot);
    await prefs.setString('oxygen.library', encoded);
    await prefs.setStringList('oxygen.favorites', favoriteIds.toList(growable: false));
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('oxygen.favorites', favoriteIds.toList(growable: false));
  }

  Future<int> importAudio() async {
    lastError = null;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
      dialogTitle: 'Добавить музыку в Oxygen',
    );
    if (result == null) return 0;
    var added = 0;
    final knownPaths = library.map((track) => track.path).toSet();
    for (final file in result.files) {
      final path = file.path;
      if (path == null || path.isEmpty || !knownPaths.add(path)) continue;
      final rawName = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      final track = Track(path: path, title: rawName.isEmpty ? file.name : rawName);
      library.add(track);
      _searchIndex[track.id] = '${track.title} ${track.artist} ${track.fileName}'.toLowerCase();
      added++;
    }
    if (added > 0) {
      await _saveLibrary();
      if (!_disposed) notifyListeners();
    }
    return added;
  }

  Future<void> locateCurrentAudioFile() async {
    final oldTrack = current;
    if (oldTrack == null || oldTrack.isRemote) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
      dialogTitle: 'Найти файл для «${oldTrack.title}»',
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.single.path;
    if (path == null || path.isEmpty) {
      lastError = 'Не удалось получить путь к выбранному файлу.';
      if (!_disposed) notifyListeners();
      return;
    }
    final replacement = Track(
      path: path,
      title: oldTrack.title == 'Локальный файл' ? picked.files.single.name.replaceFirst(RegExp(r'\.[^.]+$'), '') : oldTrack.title,
      artist: oldTrack.artist,
      artworkUrl: oldTrack.artworkUrl,
      storeUrl: oldTrack.storeUrl,
      albumName: oldTrack.albumName,
      sourceName: 'Локальная музыка',
    );
    for (var i = 0; i < library.length; i++) {
      if (library[i].id == oldTrack.id) library[i] = replacement;
    }
    for (var i = 0; i < queue.length; i++) {
      if (queue[i].id == oldTrack.id) queue[i] = replacement;
    }
    _searchIndex.remove(oldTrack.id);
    _searchIndex[replacement.id] = '${replacement.title} ${replacement.artist} ${replacement.fileName}'.toLowerCase();
    current = replacement;
    await _saveLibrary();
    if (!_disposed) notifyListeners();
    await _start(replacement);
  }

  Future<void> playTrack(Track track, {List<Track>? from}) async {
    final source = from ?? (track.isRemote ? <Track>[track] : library);
    queue
      ..clear()
      ..addAll(source);
    _queueIndex = queue.indexWhere((item) => item.id == track.id);
    if (_queueIndex < 0) {
      queue.insert(0, track);
      _queueIndex = 0;
    }
    await _start(track);
  }

  Future<void> _start(Track track) {
    final generation = ++_startGeneration;
    busy = true;
    lastError = null;
    statusMessage = track.isRemote ? 'Загружаем аудио…' : 'Открываем аудиофайл…';
    current = track;
    position = Duration.zero;
    duration = Duration.zero;
    state = OxygenPlaybackState.stopped;
    playbackProgress.value = const PlaybackProgress();
    notifyListeners();
    _startQueue = _startQueue.catchError((_) {}).then((_) async {
      if (generation != _startGeneration || _disposed) return;
      try {
        await _engineReady;
        if (_hasOpenedSource) {
          try {
            await _player.action.stop();
          } finally {
            _hasOpenedSource = false;
          }
        }
        if (generation != _startGeneration) return;
        final playablePath = await _preparePlayablePath(track);
        if (generation != _startGeneration) return;
        statusMessage = 'Применяем аудиоэффекты…';
        if (!_disposed) notifyListeners();

        final preparedFile = File(playablePath);
        if (!await preparedFile.exists()) {
          throw FileSystemException('Аудиофайл после подготовки не найден. Повтори поиск или выбери файл заново.', playablePath);
        }
        final preparedStat = await preparedFile.stat();
        if (preparedStat.size <= 128) {
          throw FileSystemException('Аудиофайл пустой или повреждён.', playablePath);
        }
        try {
          await _player.action.open(preparedFile.absolute.path, autoPlay: true);
        } catch (firstError) {
          // Retry both local and downloaded sources from a short, plain cache
          // path. This helps native decoders on Windows with Unicode/long paths.
          final safePath = await _makeSafeLocalCopy(preparedFile.path);
          if (safePath == preparedFile.path || !await File(safePath).exists()) {
            throw FileSystemException('Аудиодвижок не открыл файл: $firstError', preparedFile.path);
          }
          try {
            await _player.action.open(File(safePath).absolute.path, autoPlay: true);
          } catch (retryError) {
            throw FileSystemException(
              'Файл скачан и существует, но аудиодвижок не смог его декодировать. Первая попытка: $firstError; повтор: $retryError',
              safePath,
            );
          }
        }
        _hasOpenedSource = true;
        if (generation != _startGeneration) {
          await _player.action.stop();
          return;
        }
        // Some native backends reset DSP state when a new decoder is opened,
        // so the complete processing chain is deliberately applied afterwards.
        await _applyDsp();
        await _player.action.setVolume(volume);
        await _player.action.setBalance(balance);
        duration = _safeDuration(_player.state.duration, duration);
        position = Duration.zero;
        state = OxygenPlaybackState.playing;
        statusMessage = null;
      } catch (error) {
        if (generation == _startGeneration) {
          final detail = error.toString();
          _hasOpenedSource = false;
          _stopVisualizer();
          if (detail.contains('Файл не найден') || detail.contains('Аудиофайл после подготовки не найден')) {
            lastError = 'Локальный файл не найден. Возможно, его переместили или диск отключён. Нажми «Найти файл заново», чтобы указать новое расположение.';
          } else if (detail.contains('Audio file not found') || detail.contains('не смог его декодировать')) {
            lastError = 'Аудиодвижок не распознал содержимое файла. Возможно, ссылка ведёт не на аудио или файл повреждён. Попробуй другой источник или выбери файл заново. Подробности: $detail';
          } else if (error is FileSystemException) {
            lastError = 'Не удалось прочитать файл или сохранить его в кэш: ${error.message}';
          } else {
            lastError = 'Не удалось открыть аудио: $error';
          }
          statusMessage = null;
          state = OxygenPlaybackState.stopped;
        }
      } finally {
        if (generation == _startGeneration && !_disposed) {
          busy = false;
          statusMessage = null;
          playbackProgress.value = PlaybackProgress(position: position, duration: duration);
          notifyListeners();
        }
      }
    });
    return _startQueue;
  }

  Future<void> togglePlay() async {
    if (current == null) {
      if (library.isNotEmpty) await playTrack(library.first);
      return;
    }
    try {
      await _engineReady;
      if (isPlaying) {
        await _player.action.pause();
        state = OxygenPlaybackState.paused;
      } else if (state == OxygenPlaybackState.stopped || state == OxygenPlaybackState.completed) {
        await _start(current!);
      } else {
        await _player.action.play();
        state = OxygenPlaybackState.playing;
      }
    } catch (error) {
      lastError = 'Ошибка воспроизведения: $error';
      notifyListeners();
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _restartCurrent() async {
    final track = current;
    if (track == null) return;
    try {
      await _player.action.seek(Duration.zero);
      await _player.action.play();
      state = OxygenPlaybackState.playing;
      position = Duration.zero;
      playbackProgress.value = PlaybackProgress(position: position, duration: duration);
      if (!_disposed) notifyListeners();
    } catch (_) {
      await _start(track);
    }
  }

  Future<void> playCurrent() async {
    final track = current;
    if (track != null) await _start(track);
  }

  Future<void> next() async {
    if (queue.isEmpty) return;
    if (shuffle && queue.length > 1) {
      var nextIndex = DateTime.now().microsecondsSinceEpoch % (queue.length - 1);
      if (nextIndex >= _queueIndex) nextIndex++;
      _queueIndex = nextIndex;
    } else {
      _queueIndex++;
      if (_queueIndex >= queue.length) {
        _queueIndex = 0;
        await _player.action.stop();
        state = OxygenPlaybackState.stopped;
        position = Duration.zero;
        playbackProgress.value = PlaybackProgress(position: position, duration: duration);
        if (!_disposed) notifyListeners();
        return;
      }
    }
    await _start(queue[_queueIndex]);
  }

  Future<void> previous() async {
    if (position > const Duration(seconds: 3)) {
      await _player.action.seek(Duration.zero);
      return;
    }
    if (queue.isEmpty) return;
    _queueIndex = _queueIndex <= 0 ? queue.length - 1 : _queueIndex - 1;
    await _start(queue[_queueIndex]);
  }

  Future<void> setBalance(double value) async {
    balance = value.clamp(-1.0, 1.0).toDouble();
    try {
      await _engineReady;
      await _player.action.setBalance(balance);
      lastError = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_balancePrefsKey, balance);
    } catch (error) {
      lastError = 'Не удалось изменить стереобаланс: $error';
    }
    if (!_disposed) notifyListeners();
  }

  /// Apply a live EQ update while dragging; native DSP updates are coalesced.
  void previewEqualizerBands(List<double> values) {
    equalizerBands = List<double>.generate(10, (index) => _band(values, index), growable: false);
    _eqDebounce?.cancel();
    final snapshot = equalizerEnabled
        ? List<double>.from(equalizerBands)
        : List<double>.filled(10, 0, growable: false);
    _eqDebounce = Timer(const Duration(milliseconds: 60), () async {
      if (!_hasOpenedSource) return;
      try {
        await _engineReady;
        await _player.action.setEqualizer(_makeEqualizer(snapshot));
      } catch (error) {
        lastError = 'Не удалось применить эквалайзер: $error';
        if (!_disposed) notifyListeners();
      }
    });
  }

  Future<void> setEqualizerBands(List<double> values) async {
    equalizerBands = List<double>.generate(10, (index) => _band(values, index), growable: false);
    _eqDebounce?.cancel();
    await _engineReady;
    try {
      if (_hasOpenedSource) {
        final activeBands = equalizerEnabled ? equalizerBands : List<double>.filled(10, 0, growable: false);
        await _player.action.setEqualizer(_makeEqualizer(activeBands));
      }
      lastError = null;
    } catch (error) {
      // Keep the player and dialog responsive; surface DSP failures in the UI
      // instead of throwing through Slider.onChangeEnd callbacks.
      lastError = 'Не удалось применить эквалайзер: $error';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> setEqualizerEnabled(bool enabled) async {
    equalizerEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_eqEnabledKey, enabled);
    try {
      await _engineReady;
      if (_hasOpenedSource) {
        final values = enabled ? equalizerBands : List<double>.filled(10, 0, growable: false);
        await _player.action.setEqualizer(_makeEqualizer(values));
      }
      lastError = null;
    } catch (error) {
      lastError = 'Не удалось переключить эквалайзер: $error';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> setLimiterEnabled(bool enabled) async {
    limiterEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_limiterEnabledKey, enabled);
    try {
      await _engineReady;
      if (_hasOpenedSource) await _player.action.setLimiter(enabled);
      lastError = null;
    } catch (error) {
      lastError = 'Не удалось переключить лимитер: $error';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> setReverb({required bool enabled, double? mix}) async {
    reverbEnabled = enabled;
    if (mix != null) reverbMix = mix.clamp(0.0, 0.55).toDouble();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reverbEnabledKey, reverbEnabled);
    await prefs.setDouble(_reverbMixKey, reverbMix);
    try {
      await _engineReady;
      if (_hasOpenedSource) {
        final wet = reverbEnabled ? reverbMix : 0.0;
        await _player.action.configureReverb(
          roomSize: 0.52,
          damping: 0.48,
          wet: wet,
          dry: 1.0 - wet,
          width: 1.0,
          enabled: reverbEnabled,
        );
      }
      lastError = null;
    } catch (error) {
      lastError = 'Не удалось изменить реверберацию: $error';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> setSpatializer({required bool enabled, double? width}) async {
    spatializerEnabled = enabled;
    if (width != null) spatializerWidth = width.clamp(1.0, 1.8).toDouble();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_spatializerEnabledKey, spatializerEnabled);
    await prefs.setDouble(_spatializerWidthKey, spatializerWidth);
    try {
      await _engineReady;
      if (_hasOpenedSource) await _player.action.setSpatializer(enabled: spatializerEnabled, width: spatializerWidth);
      lastError = null;
    } catch (error) {
      lastError = 'Не удалось изменить пространственный звук: $error';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> setMonoDownmix(bool enabled) async {
    monoDownmix = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_monoKey, enabled);
    try {
      await _engineReady;
      if (_hasOpenedSource) await _player.action.setMono(enabled);
      lastError = null;
    } catch (error) {
      lastError = 'Не удалось переключить моно: $error';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> setPreamp(double value) async {
    preampDb = value.clamp(-6.0, 6.0).toDouble();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_preampKey, preampDb);
    try {
      await _engineReady;
      if (_hasOpenedSource) await _player.action.setPreamp(preampDb);
      lastError = null;
    } catch (error) {
      lastError = 'Не удалось изменить предусиление: $error';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> setPlaybackRate(double value) async {
    playbackRate = value.clamp(0.5, 2.0).toDouble();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_rateKey, playbackRate);
    try {
      await _engineReady;
      if (_hasOpenedSource) await _player.action.setRate(playbackRate);
      lastError = null;
    } catch (error) {
      lastError = 'Не удалось изменить скорость воспроизведения: $error';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> setPitch(double value) async {
    pitch = value.clamp(0.5, 2.0).toDouble();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_pitchKey, pitch);
    try {
      await _engineReady;
      if (_hasOpenedSource) await _player.action.setPitch(pitch);
      lastError = null;
    } catch (error) {
      lastError = 'Не удалось изменить высоту тона: $error';
    }
    if (!_disposed) notifyListeners();
  }

  void setSleepTimer(int? minutes) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepTimerMinutes = minutes == null || minutes <= 0 ? null : minutes;
    if (sleepTimerMinutes != null) {
      _sleepTimer = Timer(Duration(minutes: sleepTimerMinutes!), () async {
        try {
          await _player.action.pause();
          state = OxygenPlaybackState.paused;
        } catch (error) {
          lastError = 'Не удалось остановить воспроизведение по таймеру: $error';
        }
        sleepTimerMinutes = null;
        _sleepTimer = null;
        if (!_disposed) notifyListeners();
      });
    }
    notifyListeners();
  }

  Future<void> seek(Duration value) async {
    final maxMs = duration.inMilliseconds;
    final safeMs = value.inMilliseconds.clamp(0, maxMs > 0 ? maxMs : value.inMilliseconds).toInt();
    await _player.action.seek(Duration(milliseconds: safeMs));
    position = Duration(milliseconds: safeMs);
    playbackProgress.value = PlaybackProgress(position: position, duration: duration);
  }

  Future<void> setVolume(double value) async {
    final nextValue = value.clamp(0.0, 1.0).toDouble();
    if ((nextValue - volume).abs() < 0.002) return;
    volume = nextValue;
    volumeListenable.value = nextValue;
    _volumeDebounce?.cancel();
    _volumeDebounce = Timer(const Duration(milliseconds: 40), () async {
      try {
        await _player.action.setVolume(volume);
      } catch (error) {
        lastError = 'Не удалось изменить громкость: $error';
        if (!_disposed) notifyListeners();
      }
    });
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    notifyListeners();
  }

  void toggleRepeatOne() {
    repeatOne = !repeatOne;
    notifyListeners();
  }

  Future<void> toggleFavorite(Track track) async {
    if (!favoriteIds.add(track.id)) favoriteIds.remove(track.id);
    await _saveFavorites();
    if (!_disposed) notifyListeners();
  }

  Future<void> removeTrack(Track track) async {
    library.removeWhere((item) => item.id == track.id);
    favoriteIds.remove(track.id);
    _searchIndex.remove(track.id);
    if (current?.id == track.id) {
      await _player.action.stop();
      current = null;
      state = OxygenPlaybackState.stopped;
      position = Duration.zero;
      duration = Duration.zero;
      playbackProgress.value = const PlaybackProgress();
    }
    queue.removeWhere((item) => item.id == track.id);
    await _saveLibrary();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sleepTimer?.cancel();
    _eqDebounce?.cancel();
    _volumeDebounce?.cancel();
    _startGeneration++;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _stopVisualizer(reset: false);
    playbackProgress.dispose();
    volumeListenable.dispose();
    visualizerBands.dispose();
    unawaited(_player.dispose());
    super.dispose();
  }
}
