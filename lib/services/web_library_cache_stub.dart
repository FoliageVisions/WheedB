import '../models/song.dart';

/// No-op stub used on native platforms where IndexedDB is unavailable.
class WebLibraryCache {
  static final instance = WebLibraryCache._();
  WebLibraryCache._();

  Future<List<Song>> loadSongs() async => [];
  Future<void> saveSongs(List<Song> songs) async {}
}
