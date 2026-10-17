import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/track.dart';
import '../services/app_settings.dart';
import '../services/audio_controller.dart';
import '../services/lyrics_service.dart';
import '../widgets/glass_surface.dart';

class LyricsSheet extends StatefulWidget {
  const LyricsSheet({super.key, required this.settings, required this.track, required this.audio});

  final AppSettings settings;
  final Track track;
  final AudioController audio;

  @override
  State<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<LyricsSheet> {
  LyricsResult? _result;
  String? _error;
  bool _loading = true;
  bool _preferSynced = false;

  @override
  void initState() {
    super.initState();
    _loadLyrics();
  }

  Future<void> _loadLyrics() async {
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await LyricsService.lookup(widget.track, duration: widget.audio.duration);
      if (!mounted) return;
      setState(() {
        _result = result;
        _preferSynced = result?.plainLyrics?.trim().isNotEmpty != true &&
            result?.syncedLyrics?.trim().isNotEmpty == true;
        _loading = false;
      });
    } on LyricsServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить текст песни.';
        _loading = false;
      });
    }
  }

  String? get _displayLyrics {
    final result = _result;
    if (result == null || result.instrumental) return null;
    final raw = _preferSynced && result.syncedLyrics?.trim().isNotEmpty == true
        ? result.syncedLyrics!
        : (result.plainLyrics?.trim().isNotEmpty == true
            ? result.plainLyrics!
            : result.syncedLyrics ?? '');
    // Remove only the LRC timestamps; preserve the actual lyric lines and breaks.
    return raw
        .replaceAll(RegExp(r'\[\d{1,2}:\d{2}(?:[.:]\d{1,3})?\]'), '')
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .join('\n')
        .trim();
  }

  Future<void> _openUrl(Uri uri) async {
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть сайт в браузере.')),
      );
    }
  }

  Future<void> _openWebsite() async {
    final resultUrl = _result?.sourceUrl;
    final fallbacks = LyricsService.searchLinks(widget.track);
    final fallbackUrl = fallbacks['Google'] ?? fallbacks['LRCLIB search'] ?? Uri.parse(LyricsService.website);
    final parsedResultUrl = resultUrl == null ? null : Uri.tryParse(resultUrl);
    await _openUrl(parsedResultUrl ?? fallbackUrl);
  }

  Future<void> _copyLyrics() async {
    final text = _displayLyrics;
    if (text == null || text.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось скопировать текст.')));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Текст скопирован')),
    );
  }

  Future<void> _configureMusixmatch() async {
    final controller = TextEditingController(text: await LyricsService.getMusixmatchApiKey());
    if (!mounted) { controller.dispose(); return; }
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Musixmatch API'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Необязательный дополнительный источник. Нужен собственный API key; он сохраняется только в локальных настройках Oxygen.'),
            const SizedBox(height: 12),
            TextField(controller: controller, obscureText: true, autocorrect: false, decoration: const InputDecoration(labelText: 'API key')),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => launchUrl(Uri.parse('https://developer.musixmatch.com/'), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new_rounded), label: const Text('Документация API'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, ''), child: const Text('Удалить ключ')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Сохранить')),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || value == null) return;
    await LyricsService.saveMusixmatchApiKey(value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value.isEmpty ? 'Ключ Musixmatch удалён.' : 'Ключ Musixmatch сохранён.')));
    if (value.isNotEmpty) await _loadLyrics();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final syncedAvailable = _result?.syncedLyrics?.trim().isNotEmpty == true;
    final lyrics = _displayLyrics;
    final height = MediaQuery.sizeOf(context).height;

    return SizedBox(
      height: height * .86,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        child: GlassSurface(
          settings: settings,
          radius: settings.style == OxygenStyle.liquidGlass ? 34 : 28,
          blur: 0,
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.lyrics_rounded, color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Текст песни', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        Text(
                          widget.track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(onPressed: _configureMusixmatch, tooltip: 'Подключить Musixmatch API', icon: const Icon(Icons.key_rounded)),
                  IconButton(onPressed: _openWebsite, tooltip: 'Открыть источник текста', icon: const Icon(Icons.open_in_new_rounded)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _result == null ? widget.track.artist : '${_result!.artistName}${_result!.albumName?.isNotEmpty == true ? ' · ${_result!.albumName}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  if (syncedAvailable && _result?.plainLyrics?.trim().isNotEmpty == true)
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment<bool>(value: false, label: Text('Обычный')),
                        ButtonSegment<bool>(value: true, label: Text('LRC')),
                      ],
                      selected: <bool>{_preferSynced},
                      onSelectionChanged: (selection) => setState(() => _preferSynced = selection.first),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Автопоиск одновременно проверяет независимые API. Если LRCLIB вернул 503/429, Oxygen включает паузу для этого сервиса и продолжает поиск через LyricsPlus/Lyrics.ovh. Повтор не кэширует ошибку. Musixmatch подключается при наличии собственного API-ключа.',
                style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 6),
                dense: true,
                title: Text('Другие источники текста (${LyricsService.searchLinks(widget.track).length})', style: theme.textTheme.labelLarge),
                children: [
                  Wrap(
                    spacing: 7,
                    runSpacing: 4,
                    children: [
                      for (final entry in LyricsService.searchLinks(widget.track).entries)
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(entry.key),
                          onPressed: () => _openUrl(entry.value),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 14), Text('Ищем текст песни…')]))
                    : _error != null
                        ? _MessageState(icon: Icons.wifi_off_rounded, title: 'Не получилось загрузить', message: _error!, actionLabel: 'Повторить', onAction: _loadLyrics)
                        : _result == null
                            ? _MessageState(icon: Icons.lyrics_outlined, title: 'Текст не найден', message: 'Текст не найден в доступных API. Для видео с неверными метаданными попробуй название только песни и исполнителя либо открой дополнительный поиск ниже.', actionLabel: 'Повторить поиск', onAction: _loadLyrics)
                            : _result!.instrumental
                                ? const _MessageState(icon: Icons.piano_rounded, title: 'Инструментальная запись', message: 'Для этого трека текст не предусмотрен.')
                                : (lyrics == null || lyrics.isEmpty)
                                    ? const _MessageState(icon: Icons.lyrics_outlined, title: 'Текст отсутствует', message: 'Источник нашёл запись, но текст недоступен.')
                                    : SelectionArea(
                                        child: _preferSynced && _result!.syncedLyrics?.trim().isNotEmpty == true
                                            ? _SyncedLyricsPane(audio: widget.audio, source: _result!.syncedLyrics!, theme: theme)
                                            : ListView(
                                                padding: const EdgeInsets.fromLTRB(2, 8, 2, 24),
                                                children: [
                                                  Text(lyrics, style: theme.textTheme.bodyLarge?.copyWith(height: 1.7, fontSize: 16)),
                                                  const SizedBox(height: 20),
                                                  Text('Источник: ${_result!.sourceName}', style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                                                ],
                                              ),
                                      ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: lyrics == null || lyrics.isEmpty ? null : _copyLyrics,
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Копировать текст'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _openWebsite,
                      icon: const Icon(Icons.language_rounded),
                      label: const Text('Источник текста'),
                    ),
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

class _TimedLyricLine {
  const _TimedLyricLine(this.time, this.text);
  final Duration time;
  final String text;
}

class _SyncedLyricsPane extends StatefulWidget {
  const _SyncedLyricsPane({required this.audio, required this.source, required this.theme});
  final AudioController audio;
  final String source;
  final ThemeData theme;

  @override
  State<_SyncedLyricsPane> createState() => _SyncedLyricsPaneState();
}

class _SyncedLyricsPaneState extends State<_SyncedLyricsPane> {
  final ScrollController _scrollController = ScrollController();
  int _lastActive = -1;
  late final List<_TimedLyricLine> _parsedLines = _parseLines(widget.source);

  List<_TimedLyricLine> _parseLines(String source) {
    final result = <_TimedLyricLine>[];
    final pattern = RegExp(r'^\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\](.*)$');
    for (final raw in source.split('\n')) {
      final match = pattern.firstMatch(raw.trim());
      if (match == null) continue;
      final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
      final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
      final fraction = match.group(3) ?? '0';
      final millis = fraction.length >= 3 ? int.tryParse(fraction.substring(0, 3)) ?? 0 : (int.tryParse(fraction) ?? 0) * (fraction.length == 1 ? 100 : 10);
      final text = (match.group(4) ?? '').trim();
      if (text.isEmpty) continue;
      result.add(_TimedLyricLine(Duration(minutes: minutes, seconds: seconds, milliseconds: millis), text));
    }
    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  }

  @override
  void dispose() { _scrollController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final lines = _parsedLines;
    if (lines.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(8),
        children: [Text(widget.source, style: widget.theme.textTheme.bodyLarge?.copyWith(height: 1.6))],
      );
    }
    return ValueListenableBuilder<PlaybackProgress>(
      valueListenable: widget.audio.playbackProgress,
      builder: (context, progress, _) {
        var active = -1;
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].time <= progress.position) {
            active = i;
          } else {
            break;
          }
        }
        if (active >= 0 && active != _lastActive) {
          _lastActive = active;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_scrollController.hasClients) {
              return;
            }
            final target = (active * 54.0).clamp(0.0, _scrollController.position.maxScrollExtent).toDouble();
            _scrollController.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
          });
        }
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(2, 12, 2, 26),
          itemCount: lines.length + 1,
          itemBuilder: (context, index) {
            if (index == lines.length) {
              return Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text('Синхронизированный текст · ${lines.length} строк', style: widget.theme.textTheme.labelSmall),
              );
            }
            final line = lines[index];
            final selected = index == active;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              padding: EdgeInsets.symmetric(vertical: selected ? 10 : 7, horizontal: selected ? 10 : 4),
              decoration: BoxDecoration(color: selected ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .64) : Colors.transparent, borderRadius: BorderRadius.circular(14)),
              child: Text(line.text, style: widget.theme.textTheme.bodyLarge?.copyWith(height: 1.45, fontSize: selected ? 19 : 16, fontWeight: selected ? FontWeight.w800 : FontWeight.w500, color: selected ? Theme.of(context).colorScheme.onPrimaryContainer : Theme.of(context).colorScheme.onSurfaceVariant)),
            );
          },
        );
      },
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.icon, required this.title, required this.message, this.actionLabel, this.onAction});

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 42, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 12),
                Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 7),
                Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.45)),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 16),
                  FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
                ],
              ],
            ),
          ),
        ),
      );
}
