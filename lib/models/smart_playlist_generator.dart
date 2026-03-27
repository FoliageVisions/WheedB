import 'package:flutter/material.dart';
import 'playlist.dart';
import 'song.dart';

/// Generates the four smart playlists from a full song library.
class SmartPlaylistGenerator {
  final List<Song> _library;

  SmartPlaylistGenerator(this._library);

  /// Songs added in the last 14 days, newest first.
  Playlist recentlyAdded() {
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    final songs = _library
        .where((s) => s.dateAdded.isAfter(cutoff))
        .toList()
      ..sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    return Playlist(
      name: 'Recently Added',
      icon: Icons.schedule_rounded,
      songs: songs,
      isSmart: true,
    );
  }

  /// Top songs ranked by play count (minimum 1 play).
  Playlist mostPlayed() {
    final songs = _library
        .where((s) => s.playCount > 0)
        .toList()
      ..sort((a, b) => b.playCount.compareTo(a.playCount));
    return Playlist(
      name: 'Most Played',
      icon: Icons.trending_up_rounded,
      songs: songs,
      isSmart: true,
    );
  }

  /// All songs the user has marked as favourite.
  Playlist favoritesMix() {
    final songs = _library.where((s) => s.isFavorite).toList();
    return Playlist(
      name: 'Favorites Mix',
      icon: Icons.favorite_rounded,
      songs: songs,
      isSmart: true,
    );
  }

  /// FLAC / lossless / Hi-Res audio (sample rate > 48 kHz).
  Playlist highQuality() {
    final songs = _library.where((s) => s.isHighQuality).toList();
    return Playlist(
      name: 'High Quality',
      icon: Icons.high_quality_rounded,
      songs: songs,
      isSmart: true,
    );
  }

  /// All four smart playlists in display order.
  List<Playlist> generateAll() => [
        recentlyAdded(),
        mostPlayed(),
        favoritesMix(),
        highQuality(),
      ];
}
