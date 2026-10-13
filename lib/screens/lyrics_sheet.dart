import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/track.dart';
import '../services/app_settings.dart';
import '../services/lyrics_service.dart';
import '../widgets/glass_surface.dart';

class LyricsSheet extends StatefulWidget {
  const LyricsSheet({super.key, required this.settings, required this.track});

  final AppSettings settings;
  final Track track;

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
    });
    try {
      final result = await LyricsService.lookup(widget.track);
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

  Future<void> _openWebsite() async {
    var opened = false;
    try {
      opened = await launchUrl(Uri.parse(LyricsService.website), mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть сайт в браузере.')),
      );
    }
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
                  IconButton(onPressed: _openWebsite, tooltip: 'Открыть сайт LRCLIB', icon: const Icon(Icons.open_in_new_rounded)),
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
                'Для поиска название трека и исполнитель отправляются в LRCLIB.',
                style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 14), Text('Ищем текст песни…')]))
                    : _error != null
                        ? _MessageState(icon: Icons.wifi_off_rounded, title: 'Не получилось загрузить', message: _error!, actionLabel: 'Повторить', onAction: _loadLyrics)
                        : _result == null
                            ? _MessageState(icon: Icons.lyrics_outlined, title: 'Текст не найден', message: 'Для этой записи нет подходящего текста в LRCLIB. Можно открыть сайт и поискать вручную.', actionLabel: 'Повторить поиск', onAction: _loadLyrics)
                            : _result!.instrumental
                                ? const _MessageState(icon: Icons.piano_rounded, title: 'Инструментальная запись', message: 'Для этого трека текст не предусмотрен.')
                                : (lyrics == null || lyrics.isEmpty)
                                    ? const _MessageState(icon: Icons.lyrics_outlined, title: 'Текст отсутствует', message: 'Источник нашёл запись, но текст недоступен.')
                                    : SelectionArea(
                                        child: ListView(
                                          padding: const EdgeInsets.fromLTRB(2, 8, 2, 24),
                                          children: [
                                            Text(
                                              lyrics,
                                              style: theme.textTheme.bodyLarge?.copyWith(height: 1.7, fontSize: 16),
                                            ),
                                            const SizedBox(height: 20),
                                            Text('Источник: LRCLIB', style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
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
                      label: const Text('Сайт LRCLIB'),
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
