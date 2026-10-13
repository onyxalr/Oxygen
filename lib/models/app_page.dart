import 'package:flutter/material.dart';

enum AppPage {
  home,
  search,
  explore,
  library,
  favorites,
  playlists,
  social,
  settings,
  about,
}

extension AppPageInfo on AppPage {
  String get title => switch (this) {
        AppPage.home => 'Главная',
        AppPage.search => 'Поиск',
        AppPage.explore => 'Обзор',
        AppPage.library => 'Моя музыка',
        AppPage.favorites => 'Избранное',
        AppPage.playlists => 'Плейлисты',
        AppPage.social => 'Социальное',
        AppPage.settings => 'Настройки',
        AppPage.about => 'О приложении',
      };

  IconData get icon => switch (this) {
        AppPage.home => Icons.home_rounded,
        AppPage.search => Icons.search_rounded,
        AppPage.explore => Icons.explore_rounded,
        AppPage.library => Icons.library_music_rounded,
        AppPage.favorites => Icons.favorite_rounded,
        AppPage.playlists => Icons.queue_music_rounded,
        AppPage.social => Icons.people_alt_rounded,
        AppPage.settings => Icons.tune_rounded,
        AppPage.about => Icons.info_outline_rounded,
      };
}
