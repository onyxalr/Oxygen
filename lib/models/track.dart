class Track {
  const Track({
    required this.path,
    required this.title,
    this.artist = 'Локальный файл',
    this.artworkUrl,
    this.storeUrl,
    this.albumName,
    this.sourceName = 'Локальная музыка',
    this.externalOnly = false,
  });

  /// Local file path or a full-length remote audio stream/download URL.
  final String path;
  final String title;
  final String artist;
  final String? artworkUrl;
  final String? storeUrl;
  final String? albumName;
  final String sourceName;

  /// True when the source offers metadata/search but does not expose a direct
  /// audio stream that Oxygen is allowed to play. These results open the
  /// provider's official page instead of being passed to the audio engine.
  final bool externalOnly;

  bool get isRemote {
    final uri = Uri.tryParse(path);
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http');
  }

  String get id => path;
  String get fileName => isRemote ? title : path.split(RegExp(r'[/\\]')).last;

  Map<String, String> toJson() {
    final result = <String, String>{
      'path': path,
      'title': title,
      'artist': artist,
      'sourceName': sourceName,
      'externalOnly': externalOnly.toString(),
    };
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
        sourceName: json['sourceName'] as String? ?? 'Локальная музыка',
        externalOnly: json['externalOnly'] == true || json['externalOnly'] == 'true',
      );
}
