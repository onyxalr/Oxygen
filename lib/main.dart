import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/app_page.dart';
import 'screens/full_player_screen.dart';
import 'screens/about_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'services/app_settings.dart';
import 'services/audio_controller.dart';
import 'theme/oxygen_theme.dart';
import 'widgets/glass_surface.dart';
import 'widgets/floating_dock.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OxygenApp());
}

class OxygenApp extends StatefulWidget {
  const OxygenApp({super.key});
  @override
  State<OxygenApp> createState() => _OxygenAppState();
}

class _OxygenAppState extends State<OxygenApp> {
  final AppSettings settings = AppSettings();
  final AudioController audio = AudioController();

  @override
  void initState() {
    super.initState();
    settings.load();
  }

  @override
  void dispose() {
    settings.dispose();
    audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: settings.themeRevision,
    builder: (context, _) => MaterialApp(
      title: 'Oxygen',
      debugShowCheckedModeBanner: false,
      theme: OxygenTheme.build(
        brightness: Brightness.light,
        style: settings.style,
        accent: settings.accent,
      ),
      darkTheme: OxygenTheme.build(
        brightness: Brightness.dark,
        style: settings.style,
        accent: settings.accent,
      ),
      themeMode: settings.themeMode,
      home: OxygenShell(settings: settings, audio: audio),
    ),
  );
}

class OxygenShell extends StatefulWidget {
  const OxygenShell({super.key, required this.settings, required this.audio});
  final AppSettings settings;
  final AudioController audio;

  @override
  State<OxygenShell> createState() => _OxygenShellState();
}

class _OxygenShellState extends State<OxygenShell> {
  AppPage page = AppPage.home;

  void open(AppPage next) {
    if (page == next) return;
    setState(() => page = next);
  }

  Future<void> _import() async {
    final count = await widget.audio.importAudio();
    if (!mounted) return;
    if (count > 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Добавлено треков: $count')));
    } else if (widget.audio.lastError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(widget.audio.lastError!)));
    }
  }

  EdgeInsets _dockReservedSpace(BuildContext context) {
    // Android gets a fixed bottom dock: dragging to the edges is desktop-only.
    if (Theme.of(context).platform == TargetPlatform.android) {
      return const EdgeInsets.only(bottom: 88);
    }
    return switch (widget.settings.dockEdge) {
      DockEdge.left => const EdgeInsets.only(left: 82),
      DockEdge.right => const EdgeInsets.only(right: 82),
      DockEdge.top => const EdgeInsets.only(top: 78),
      DockEdge.bottom => const EdgeInsets.only(bottom: 78),
    };
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final content = _pageContent();
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.settings.style == OxygenStyle.liquidGlass)
            const _AmbientBackground(),
          ValueListenableBuilder<int>(
            valueListenable: widget.settings.dockRevision,
            builder: (context, _, child) => SafeArea(
              child: AnimatedPadding(
                duration:
                    widget.settings.animations &&
                        !widget.settings.reducedEffects
                    ? const Duration(milliseconds: 160)
                    : Duration.zero,
                curve: Curves.easeOutCubic,
                padding: _dockReservedSpace(context),
                child: child,
              ),
            ),
            child: Column(
              children: [
                if (wide)
                  _DesktopToolbar(
                    page: page,
                    settings: widget.settings,
                    onImport: _import,
                    onOpenSearch: () => open(AppPage.search),
                  )
                else
                  _MobileHeader(
                    page: page,
                    settings: widget.settings,
                    onMenu: () => _showMenu(context),
                    onImport: _import,
                  ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      wide ? 8 : 0,
                      0,
                      wide ? 12 : 0,
                      0,
                    ),
                    child: AnimatedSwitcher(
                      duration:
                          widget.settings.animations &&
                              !widget.settings.reducedEffects
                          ? const Duration(milliseconds: 160)
                          : Duration.zero,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(.006, .008),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: KeyedSubtree(key: ValueKey(page), child: content),
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: widget.settings,
                  builder: (context, _) => _MiniPlayer(
                    audio: widget.audio,
                    settings: widget.settings,
                    onExpand: _openFullPlayer,
                  ),
                ),
              ],
            ),
          ),
          FloatingDock(
            page: page,
            settings: widget.settings,
            onOpen: open,
            onMore: () => _showMenu(context),
            allowDragging: Theme.of(context).platform != TargetPlatform.android,
          ),
        ],
      ),
    );
  }

  Widget _pageContent() => switch (page) {
    AppPage.home => HomeScreen(
      settings: widget.settings,
      audio: widget.audio,
      onOpenLibrary: () => open(AppPage.library),
      onOpenFavorites: () => open(AppPage.favorites),
      onImport: _import,
      onOpenPlayer: _openFullPlayer,
    ),
    AppPage.search => SearchScreen(
      settings: widget.settings,
      audio: widget.audio,
    ),
    AppPage.explore => _ExploreScreen(
      settings: widget.settings,
      audio: widget.audio,
      onImport: _import,
      onOpenFavorites: () => open(AppPage.favorites),
      onOpenLibrary: () => open(AppPage.library),
      onOpenPlayer: _openFullPlayer,
    ),
    AppPage.library => LibraryScreen(
      settings: widget.settings,
      audio: widget.audio,
      favoritesOnly: false,
      onImport: _import,
    ),
    AppPage.favorites => LibraryScreen(
      settings: widget.settings,
      audio: widget.audio,
      favoritesOnly: true,
      onImport: _import,
    ),
    AppPage.playlists => _PlaylistsScreen(
      settings: widget.settings,
      audio: widget.audio,
    ),
    AppPage.social => _SocialScreen(
      settings: widget.settings,
      audio: widget.audio,
    ),
    AppPage.settings => SettingsScreen(
      settings: widget.settings,
      onOpenAbout: () => open(AppPage.about),
    ),
    AppPage.about => AboutScreen(settings: widget.settings),
  };

  void _openFullPlayer() {
    if (widget.audio.current == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            FullPlayerScreen(audio: widget.audio, settings: widget.settings),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    final liquid = widget.settings.style == OxygenStyle.liquidGlass;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: !liquid,
      isScrollControlled: true,
      backgroundColor: liquid
          ? Colors.transparent
          : Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
          child: GlassSurface(
            settings: widget.settings,
            radius: liquid ? 30 : 28,
            blur: 0,
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (liquid) ...[
                  Container(
                    width: 34,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ],
                for (final item in const <AppPage>[
                  AppPage.explore,
                  AppPage.favorites,
                  AppPage.playlists,
                  AppPage.social,
                  AppPage.settings,
                  AppPage.about,
                ])
                  ListTile(
                    leading: Icon(item.icon),
                    title: Text(item.title),
                    selected: item == page,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      open(item);
                    },
                  ),
                const Divider(height: 8),
                if (Theme.of(context).platform != TargetPlatform.android)
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    secondary: Icon(
                      widget.settings.dockLocked
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_outlined,
                    ),
                    title: const Text('Закрепить док'),
                    subtitle: const Text('Запретить перетаскивание панели'),
                    value: widget.settings.dockLocked,
                    onChanged: (value) async {
                      await widget.settings.setDockLocked(value);
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.add_rounded),
                  title: const Text('Импортировать музыку'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _import();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _pageTitle(AppPage page) => page.title;

class _DesktopToolbar extends StatelessWidget {
  const _DesktopToolbar({
    required this.page,
    required this.settings,
    required this.onImport,
    required this.onOpenSearch,
  });
  final AppPage page;
  final AppSettings settings;
  final VoidCallback onImport;
  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context) {
    final liquid = settings.style == OxygenStyle.liquidGlass;
    final materialYou = settings.style == OxygenStyle.materialYou;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 12, 10),
      child: GlassSurface(
        settings: settings,
        radius: liquid ? 25 : (materialYou ? 30 : 16),
        blur: liquid ? 5.0 : 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _pageTitle(page),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    liquid
                        ? 'A little space for your sound'
                        : materialYou
                        ? 'Музыка в твоём стиле'
                        : 'Oxygen Music',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: onOpenSearch,
              icon: const Icon(Icons.search_rounded, size: 19),
              label: const Text('Поиск'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text('Добавить треки'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileHeader extends StatelessWidget {
  const _MobileHeader({
    required this.page,
    required this.settings,
    required this.onMenu,
    required this.onImport,
  });
  final AppPage page;
  final AppSettings settings;
  final VoidCallback onMenu;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final materialYou = settings.style == OxygenStyle.materialYou;
    final liquid = settings.style == OxygenStyle.liquidGlass;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onMenu,
            tooltip: 'Ещё',
            icon: const Icon(Icons.more_horiz_rounded),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              _pageTitle(page),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          if (materialYou)
            IconButton.filledTonal(
              onPressed: onImport,
              tooltip: 'Добавить музыку',
              icon: const Icon(Icons.add_rounded),
            )
          else
            IconButton(
              onPressed: onImport,
              tooltip: 'Добавить музыку',
              icon: Icon(
                liquid ? Icons.add_rounded : Icons.file_upload_outlined,
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({
    required this.audio,
    required this.settings,
    required this.onExpand,
  });
  final AudioController audio;
  final AppSettings settings;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: audio,
    builder: (context, _) {
      final track = audio.current;
      if (track == null) return const SizedBox(height: 7);
      final liquid = settings.style == OxygenStyle.liquidGlass;
      final radius = settings.style == OxygenStyle.materialYou
          ? 27.0
          : (liquid ? 22.0 : 15.0);
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 5, 12, 7),
        child: GlassSurface(
          settings: settings,
          radius: radius,
          blur: liquid ? 5.0 : 0,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              InkWell(
                onTap: onExpand,
                borderRadius: BorderRadius.circular(13),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        settings.accent,
                        settings.accent.withValues(alpha: .24),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(
                      settings.style == OxygenStyle.materialYou ? 16 : 12,
                    ),
                  ),
                  child: Icon(
                    Icons.graphic_eq_rounded,
                    color: settings.accent.computeLuminance() > .55
                        ? Colors.black
                        : Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: onExpand,
                  borderRadius: BorderRadius.circular(9),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (MediaQuery.sizeOf(context).width > 520) ...[
                IconButton(
                  onPressed: audio.previous,
                  tooltip: 'Предыдущий',
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
                IconButton(
                  onPressed: audio.togglePlay,
                  tooltip: audio.isPlaying ? 'Пауза' : 'Воспроизвести',
                  icon: Icon(
                    audio.busy
                        ? Icons.hourglass_top_rounded
                        : audio.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 27,
                  ),
                ),
                IconButton(
                  onPressed: audio.next,
                  tooltip: 'Следующий',
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ] else
                IconButton.filledTonal(
                  onPressed: audio.togglePlay,
                  tooltip: audio.isPlaying ? 'Пауза' : 'Воспроизвести',
                  icon: Icon(
                    audio.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _ExploreScreen extends StatelessWidget {
  const _ExploreScreen({
    required this.settings,
    required this.audio,
    required this.onImport,
    required this.onOpenFavorites,
    required this.onOpenLibrary,
    required this.onOpenPlayer,
  });
  final AppSettings settings;
  final AudioController audio;
  final VoidCallback onImport;
  final VoidCallback onOpenFavorites;
  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(26, 22, 26, 30),
    children: [
      Text(
        'Обзор',
        style: Theme.of(context).textTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -.8,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Твоя коллекция — без алгоритмов и лишнего шума.',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 24),
      LayoutBuilder(
        builder: (context, constraints) {
          final count = constraints.maxWidth > 760
              ? 3
              : (constraints.maxWidth > 480 ? 2 : 1);
          return GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: count,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: count == 1 ? 3.1 : 1.35,
            children: [
              _ExploreCard(
                settings: settings,
                icon: Icons.library_music_rounded,
                title: 'Твоя библиотека',
                subtitle: '${audio.library.length} треков',
                onTap: onOpenLibrary,
              ),
              _ExploreCard(
                settings: settings,
                icon: Icons.favorite_rounded,
                title: 'Избранное',
                subtitle: '${audio.favoriteIds.length} сохранено',
                onTap: onOpenFavorites,
              ),
              _ExploreCard(
                settings: settings,
                icon: Icons.graphic_eq_rounded,
                title: 'Сейчас играет',
                subtitle: audio.current?.title ?? 'Запусти первый трек',
                onTap: onOpenPlayer,
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 24),
      GlassSurface(
        settings: settings,
        radius: settings.style == OxygenStyle.materialYou ? 32 : 24,
        blur: 4,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Твоя музыка. Твой ритм.',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              'Oxygen воспроизводит локальные аудиофайлы. Импортируй любимые треки и управляй своей коллекцией без онлайн-каталогов.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Импортировать аудио'),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ExploreCard extends StatelessWidget {
  const _ExploreCard({
    required this.settings,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final AppSettings settings;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = settings.style == OxygenStyle.materialYou
        ? 28.0
        : (settings.style == OxygenStyle.liquidGlass ? 24.0 : 14.0);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(
                icon,
                size: 29,
                color: Theme.of(context).colorScheme.primary,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground();

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          gradient: RadialGradient(
            center: const Alignment(-.82, -.92),
            radius: 1.22,
            colors: [
              Theme.of(context).colorScheme.primary.withValues(alpha: .24),
              Theme.of(context).scaffoldBackgroundColor,
              const Color(0xFF18273B).withValues(alpha: .72),
            ],
            stops: const [0, .48, 1],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

class _PlaylistsScreen extends StatelessWidget {
  const _PlaylistsScreen({required this.settings, required this.audio});
  final AppSettings settings;
  final AudioController audio;

  Future<void> _createPlaylist(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Новый плейлист'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Например, вечерний вайб',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty)
      await settings.addPlaylist(name);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: settings,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
      children: [
        Text(
          'Плейлисты',
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -.8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Собери музыку под настроение.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => _createPlaylist(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Создать плейлист'),
          ),
        ),
        const SizedBox(height: 16),
        if (settings.playlistNames.isEmpty)
          GlassSurface(
            settings: settings,
            radius: settings.style == OxygenStyle.materialYou ? 30 : 23,
            blur: 0,
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(
                  Icons.queue_music_rounded,
                  size: 42,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  'Пока нет плейлистов',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Создай первый плейлист — он сохранится на этом устройстве.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else
          for (final name in settings.playlistNames)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: GlassSurface(
                settings: settings,
                radius: settings.style == OxygenStyle.materialYou ? 26 : 18,
                blur: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(
                          settings.style == OxygenStyle.materialYou ? 17 : 13,
                        ),
                      ),
                      child: Icon(
                        Icons.queue_music_rounded,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Локальный плейлист · ${audio.library.length} треков в библиотеке',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Удалить плейлист',
                      onPressed: () => settings.removePlaylist(name),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
              ),
            ),
      ],
    ),
  );
}

class _SocialScreen extends StatelessWidget {
  const _SocialScreen({required this.settings, required this.audio});
  final AppSettings settings;
  final AudioController audio;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: audio,
    builder: (context, _) {
      final current = audio.current;
      final scheme = Theme.of(context).colorScheme;
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
        children: [
          Text(
            'Социальное',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -.8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Поделись тем, что сейчас звучит у тебя.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 22),
          GlassSurface(
            settings: settings,
            radius: settings.style == OxygenStyle.materialYou ? 32 : 24,
            blur: 0,
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(
                      settings.style == OxygenStyle.materialYou ? 20 : 16,
                    ),
                  ),
                  child: Icon(
                    Icons.graphic_eq_rounded,
                    size: 28,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  current?.title ?? 'Твоя музыка — твоя история',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  current != null
                      ? 'Сейчас играет · ${current.artist}'
                      : 'Запусти трек, чтобы подготовить карточку прослушивания.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: current == null
                          ? null
                          : () async {
                              final text =
                                  'Слушаю «${current.title}»${current.artist.isNotEmpty ? ' — ${current.artist}' : ''} в Oxygen.';
                              await Clipboard.setData(
                                ClipboardData(text: text),
                              );
                              if (context.mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Текст скопирован — можно отправлять друзьям',
                                    ),
                                  ),
                                );
                            },
                      icon: const Icon(Icons.ios_share_rounded),
                      label: const Text('Поделиться треком'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text:
                                'Моя музыкальная библиотека Oxygen: ${audio.library.length} треков и ${audio.favoriteIds.length} избранных.',
                          ),
                        );
                        if (context.mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Музыкальная статистика скопирована',
                              ),
                            ),
                          );
                      },
                      icon: const Icon(Icons.content_copy_rounded),
                      label: const Text('Скопировать статистику'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SocialStat(
                  settings: settings,
                  icon: Icons.library_music_rounded,
                  value: '${audio.library.length}',
                  label: 'Треков',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SocialStat(
                  settings: settings,
                  icon: Icons.favorite_rounded,
                  value: '${audio.favoriteIds.length}',
                  label: 'Избранных',
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}

class _SocialStat extends StatelessWidget {
  const _SocialStat({
    required this.settings,
    required this.icon,
    required this.value,
    required this.label,
  });
  final AppSettings settings;
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => GlassSurface(
    settings: settings,
    radius: settings.style == OxygenStyle.materialYou ? 28 : 20,
    blur: 0,
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}
