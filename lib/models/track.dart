import 'dart:io';

class Track {
  const Track({
    required this.path,
    required this.title,
    this.artist = 'Локальный файл',
    this.artworkUrl,
    this.storeUrl,
    this.albumName,
  });

  /// Local file path, or a remote preview URL for catalogue results.
  final String path;
  final String title;
  final String artist;
  final String? artworkUrl;
  final String? storeUrl;
  final String? albumName;

  bool get isRemote {
    final uri = Uri.tryParse(path);
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http');
  }

  String get id => path;
  String get fileName => isRemote ? title : path.split(Platform.pathSeparator).last;

  Map<String, String> toJson() {
    final result = <String, String>{'path': path, 'title': title, 'artist': artist};
    if (artworkUrl != null) result['artworkUrl'] = artworkUrl!;
    if (storeUrl != null) result['storeUrl'] = storeUrl!;
    if (albumName != null) result['albumName'] = albumName!;
    return result;
  }

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        path: json['path'] as String? ?? '',
        title: json['title'] as String? ?? 'Без названия',
        artist: json['artist'] as String? ?? 'Локальный файл',
        artworkUrl: json['artworkUrl'] as String?,
        storeUrl: json['storeUrl'] as String?,
        albumName: json['albumName'] as String?,
      );
}
