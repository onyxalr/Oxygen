import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum OxygenStyle { oxygen, materialYou, liquidGlass }
enum OxygenBrightness { dark, light, system }
enum DockEdge { left, right, top, bottom }

class AppSettings extends ChangeNotifier {
  /// Separate invalidation channels keep theme construction out of routine UI changes.
  final ValueNotifier<int> themeRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> dockRevision = ValueNotifier<int>(0);

  static const _styleKey = 'oxygen.style';
  static const _brightnessKey = 'oxygen.brightness';
  static const _accentKey = 'oxygen.accent';
  static const _animationsKey = 'oxygen.animations';
  static const _compactKey = 'oxygen.compact';
  static const _dockEdgeKey = 'oxygen.dock.edge';
  static const _dockAlignmentKey = 'oxygen.dock.alignment';
  static const _playlistsKey = 'oxygen.playlists.names';
  static const _dockLockedKey = 'oxygen.dock.locked';
  static const _reducedEffectsKey = 'oxygen.reducedEffects';
  static const _experimentalKey = 'oxygen.experimental.unlocked';
  static const _visualizerKey = 'oxygen.player.visualizer';
  static const _waveformKey = 'oxygen.player.waveform';
  static const _eqPresetKey = 'oxygen.player.eqPreset';
  static const _eqBandsKey = 'oxygen.player.eqBands';

  OxygenStyle style = OxygenStyle.oxygen;
  OxygenBrightness brightness = OxygenBrightness.dark;
  Color accent = const Color(0xFFB6A7FF);
  bool animations = true;
  bool compact = false;
  bool loaded = false;
  DockEdge dockEdge = DockEdge.left;
  double dockAlignment = .5;
  List<String> playlistNames = <String>[];
  bool dockLocked = false;
  bool reducedEffects = true;
  bool experimentalFeaturesUnlocked = false;
  bool playerVisualizer = true;
  bool waveformTimeline = true;
  String equalizerPreset = 'Ровный';
  List<double> equalizerBands = List<double>.filled(10, 0, growable: false);

  ThemeMode get themeMode => switch (brightness) {
        OxygenBrightness.dark => ThemeMode.dark,
        OxygenBrightness.light => ThemeMode.light,
        OxygenBrightness.system => ThemeMode.system,
      };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final styleIndex = prefs.getInt(_styleKey) ?? 0;
    final brightnessIndex = prefs.getInt(_brightnessKey) ?? 0;
    style = OxygenStyle.values[styleIndex.clamp(0, OxygenStyle.values.length - 1).toInt()];
    brightness = OxygenBrightness.values[brightnessIndex.clamp(0, OxygenBrightness.values.length - 1).toInt()];
    accent = Color(prefs.getInt(_accentKey) ?? 0xFFB6A7FF);
    animations = prefs.getBool(_animationsKey) ?? true;
    compact = prefs.getBool(_compactKey) ?? false;
    final edgeIndex = prefs.getInt(_dockEdgeKey) ?? DockEdge.left.index;
    dockEdge = DockEdge.values[edgeIndex.clamp(0, DockEdge.values.length - 1).toInt()];
    dockAlignment = (prefs.getDouble(_dockAlignmentKey) ?? .5).clamp(0.0, 1.0).toDouble();
    playlistNames = prefs.getStringList(_playlistsKey) ?? <String>[];
    dockLocked = prefs.getBool(_dockLockedKey) ?? false;
    reducedEffects = prefs.getBool(_reducedEffectsKey) ?? true;
    experimentalFeaturesUnlocked = prefs.getBool(_experimentalKey) ?? false;
    playerVisualizer = prefs.getBool(_visualizerKey) ?? true;
    waveformTimeline = prefs.getBool(_waveformKey) ?? true;
    equalizerPreset = prefs.getString(_eqPresetKey) ?? 'Ровный';
    final savedBands = prefs.getStringList(_eqBandsKey);
    if (savedBands != null && (savedBands.length == 5 || savedBands.length == 10)) {
      final parsed = savedBands.map((value) => double.tryParse(value) ?? 0).toList(growable: false);
      equalizerBands = parsed.length == 10
          ? parsed.map((value) => value.clamp(-12.0, 12.0).toDouble()).toList(growable: false)
          : List<double>.generate(10, (index) => parsed[index ~/ 2].clamp(-12.0, 12.0).toDouble(), growable: false);
    }
    loaded = true;
    themeRevision.value++;
    dockRevision.value++;
    notifyListeners();
  }

  Future<void> setStyle(OxygenStyle value) async {
    style = value;
    themeRevision.value++;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt(_styleKey, value.index);
  }

  Future<void> setBrightness(OxygenBrightness value) async {
    brightness = value;
    themeRevision.value++;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt(_brightnessKey, value.index);
  }

  Future<void> setAccent(Color value) async {
    accent = value;
    themeRevision.value++;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt(_accentKey, value.toARGB32());
  }

  Future<void> setAnimations(bool value) async {
    animations = value;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_animationsKey, value);
  }

  Future<void> setCompact(bool value) async {
    compact = value;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_compactKey, value);
  }

  Future<void> setDockPosition(DockEdge edge, double alignment) async {
    dockEdge = edge;
    dockAlignment = alignment.clamp(0.0, 1.0).toDouble();
    dockRevision.value++;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dockEdgeKey, edge.index);
    await prefs.setDouble(_dockAlignmentKey, dockAlignment);
  }


  Future<void> setDockLocked(bool value) async {
    dockLocked = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dockLockedKey, value);
  }

  Future<void> setReducedEffects(bool value) async {
    reducedEffects = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reducedEffectsKey, value);
  }

  Future<void> unlockExperimentalFeatures() async {
    if (experimentalFeaturesUnlocked) return;
    experimentalFeaturesUnlocked = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_experimentalKey, true);
  }

  Future<void> setPlayerVisualizer(bool value) async {
    playerVisualizer = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_visualizerKey, value);
  }

  Future<void> setWaveformTimeline(bool value) async {
    waveformTimeline = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_waveformKey, value);
  }

  Future<void> setEqualizerPreset(String value) async {
    equalizerPreset = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_eqPresetKey, value);
  }

  Future<void> setEqualizerBands(List<double> values) async {
    equalizerBands = List<double>.generate(
      10,
      (index) => (index < values.length ? values[index] : 0).clamp(-12.0, 12.0).toDouble(),
      growable: false,
    );
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_eqBandsKey, equalizerBands.map((value) => value.toStringAsFixed(2)).toList(growable: false));
  }

  Future<void> addPlaylist(String name) async {
    final clean = name.trim();
    if (clean.isEmpty || playlistNames.any((item) => item.toLowerCase() == clean.toLowerCase())) return;
    playlistNames = <String>[...playlistNames, clean];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_playlistsKey, playlistNames);
  }

  Future<void> removePlaylist(String name) async {
    playlistNames = playlistNames.where((item) => item != name).toList(growable: false);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_playlistsKey, playlistNames);
  }

  @override
  void dispose() {
    themeRevision.dispose();
    dockRevision.dispose();
    super.dispose();
  }
}
