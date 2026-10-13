import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';

List<dynamic> _decodeTrackJson(String source) => jsonDecode(source) as List<dynamic>;

String _encodeTrackJson(List<Map<String, String>> tracks) => jsonEncode(tracks);

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
    // Track state changes are relatively rare; progress uses its own notifier below.
    _player.onPlayerStateChanged.listen((value) {
      if (state == value) return;
      state = value;
      notifyListeners();
    });
    _player.onPositionChanged.listen((value) {
      position = value;
      // Position events arrive often. Publish a UI frame at most four times
      // per second; controls and the current position still stay accurate.
      final now = DateTime.now();
      if (now.difference(_lastProgressPublish).inMilliseconds < 250) return;
      _lastProgressPublish = now;
      playbackProgress.value = PlaybackProgress(position: position, duration: duration);
    });
    _player.onDurationChanged.listen((value) {
      if (duration == value) return;
      duration = value;
      _lastProgressPublish = DateTime.now();
      playbackProgress.value = PlaybackProgress(position: position, duration: duration);
    });
    _player.onPlayerComplete.listen((_) {
      if (repeatOne) {
        playCurrent();
      } else {
        next();
      }
    });
    restoreLibrary();
  }

  final AudioPlayer _player = AudioPlayer();
  final ValueNotifier<PlaybackProgress> playbackProgress =
      ValueNotifier<PlaybackProgress>(const PlaybackProgress());
  final ValueNotifier<double> volumeListenable = ValueNotifier<double>(0.82);
  final List<Track> library = [];
  final Set<String> favoriteIds = {};
  final List<Track> queue = [];
  Track? current;
  PlayerState state = PlayerState.stopped;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  double volume = 0.82;
  bool shuffle = false;
  bool repeatOne = false;
  bool busy = false;
  String? lastError;
  int _queueIndex = -1;
  Timer? _sleepTimer;
  Timer? _volumeDebounce;
  Future<void> _startQueue = Future<void>.value();
  int _startGeneration = 0;
  DateTime _lastProgressPublish = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<String, String> _searchIndex = <String, String>{};
  int? sleepTimerMinutes;
  double balance = 0.0;
  static const String _balancePrefsKey = 'oxygen.player.stereoBalance';

  bool get isPlaying => state == PlayerState.playing;
  bool get hasTrack => current != null;
  double get progress => duration.inMilliseconds <= 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0).toDouble();

  Future<void> restoreLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    final rawTracks = prefs.getString('oxygen.library');
    final rawFavorites = prefs.getStringList('oxygen.favorites') ?? const <String>[];
    balance = (prefs.getDouble(_balancePrefsKey) ?? 0.0).clamp(-1.0, 1.0).toDouble();
    try {
      await _player.setBalance(balance);
    } catch (_) {
      // Some output devices initialise lazily; the next balance change retries.
    }
    if (rawTracks != null) {
      try {
        final decoded = rawTracks.length >= 256 * 1024
            ? await compute(_decodeTrackJson, rawTracks)
            : jsonDecode(rawTracks) as List<dynamic>;
        // Do not stat every audio file during startup. On very large libraries
        // that adds thousands of disk calls before the library becomes usable.
        // Large JSON payloads are parsed off the UI isolate; files are validated
        // lazily when playback starts instead.
        library.addAll(decoded
            .map((item) => Track.fromJson(Map<String, dynamic>.from(item as Map)))
            .where((track) => track.path.isNotEmpty));
      } catch (_) {
        // Invalid old data is ignored; the player remains usable.
      }
    }
    favoriteIds.addAll(rawFavorites);
    notifyListeners();
  }

  String searchableText(Track track) => _searchIndex.putIfAbsent(
        track.id,
        () => '${track.title} ${track.artist} ${track.fileName}'.toLowerCase(),
      );

  Future<void> _saveLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    final snapshot = library.map((track) => track.toJson()).toList(growable: false);
    final encoded = snapshot.length >= 1000
        ? await compute(_encodeTrackJson, snapshot)
        : jsonEncode(snapshot);
    await prefs.setString('oxygen.library', encoded);
    await prefs.setStringList('oxygen.favorites', favoriteIds.toList());
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('oxygen.favorites', favoriteIds.toList());
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
      notifyListeners();
    }
    return added;
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
    current = track;
    position = Duration.zero;
    duration = Duration.zero;
    playbackProgress.value = const PlaybackProgress();
    notifyListeners();

    // Serialize commands to the native player. Rapid clicks used to let two
    // stop/setSource/resume sequences interleave and could start the wrong file.
    _startQueue = _startQueue.catchError((_) {}).then((_) async {
      if (generation != _startGeneration) return;
      try {
        if (!track.isRemote && !await File(track.path).exists()) {
          if (generation == _startGeneration) {
            lastError = 'Файл больше не найден: ${track.fileName}';
            state = PlayerState.stopped;
          }
          return;
        }
        await _player.stop();
        if (generation != _startGeneration) return;
        await _player.setSource(track.isRemote ? UrlSource(track.path) : DeviceFileSource(track.path));
        if (generation != _startGeneration) return;
        await _player.setVolume(volume);
        await _player.setBalance(balance);
        await _player.resume();
      } catch (error) {
        if (generation == _startGeneration) {
          lastError = 'Не удалось открыть аудио: $error';
          state = PlayerState.stopped;
        }
      } finally {
        if (generation == _startGeneration) {
          busy = false;
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
      if (isPlaying) {
        await _player.pause();
      } else {
        if (state == PlayerState.stopped && position == Duration.zero) {
          await playCurrent();
          return;
        }
        if (state == PlayerState.completed || position >= duration && duration > Duration.zero) {
          await _player.seek(Duration.zero);
        }
        await _player.resume();
      }
    } catch (error) {
      lastError = 'Ошибка воспроизведения: $error';
      notifyListeners();
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
        if (!repeatOne) {
          await _player.stop();
          state = PlayerState.stopped;
          position = Duration.zero;
          playbackProgress.value = PlaybackProgress(position: position, duration: duration);
          notifyListeners();
          return;
        }
      }
    }
    await _start(queue[_queueIndex]);
  }

  Future<void> previous() async {
    if (position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }
    if (queue.isEmpty) return;
    _queueIndex = (_queueIndex - 1) < 0 ? queue.length - 1 : _queueIndex - 1;
    await _start(queue[_queueIndex]);
  }


  Future<void> setBalance(double value) async {
    balance = value.clamp(-1.0, 1.0).toDouble();
    try {
      await _player.setBalance(balance);
      lastError = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_balancePrefsKey, balance);
    } catch (error) {
      lastError = 'Не удалось изменить стереобаланс: $error';
    }
    notifyListeners();
  }

  void setSleepTimer(int? minutes) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepTimerMinutes = minutes == null || minutes <= 0 ? null : minutes;
    if (sleepTimerMinutes != null) {
      _sleepTimer = Timer(Duration(minutes: sleepTimerMinutes!), () async {
        try {
          await _player.pause();
          state = PlayerState.paused;
        } catch (error) {
          lastError = 'Не удалось остановить воспроизведение по таймеру: $error';
        }
        sleepTimerMinutes = null;
        _sleepTimer = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  Future<void> seek(Duration value) async {
    final maxMs = duration.inMilliseconds;
    final safeMs = value.inMilliseconds.clamp(0, maxMs > 0 ? maxMs : value.inMilliseconds).toInt();
    await _player.seek(Duration(milliseconds: safeMs));
  }

  Future<void> setVolume(double value) async {
    final nextValue = value.clamp(0.0, 1.0).toDouble();
    if ((nextValue - volume).abs() < 0.002) return;
    volume = nextValue;
    volumeListenable.value = nextValue;
    // UI responds immediately while native volume calls are coalesced during
    // slider drags (especially helpful on slower Windows audio backends).
    _volumeDebounce?.cancel();
    _volumeDebounce = Timer(const Duration(milliseconds: 45), () async {
      try {
        await _player.setVolume(volume);
      } catch (error) {
        lastError = 'Не удалось изменить громкость: $error';
        notifyListeners();
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
    notifyListeners();
  }

  Future<void> removeTrack(Track track) async {
    library.removeWhere((item) => item.id == track.id);
    favoriteIds.remove(track.id);
    _searchIndex.remove(track.id);
    if (current?.id == track.id) {
      await _player.stop();
      current = null;
      state = PlayerState.stopped;
      position = Duration.zero;
      duration = Duration.zero;
      playbackProgress.value = const PlaybackProgress();
    }
    queue.removeWhere((item) => item.id == track.id);
    await _saveLibrary();
    notifyListeners();
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _volumeDebounce?.cancel();
    _startGeneration++;
    playbackProgress.dispose();
    volumeListenable.dispose();
    _player.dispose();
    super.dispose();
  }
}
