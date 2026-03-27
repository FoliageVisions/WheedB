import 'package:flutter/material.dart';
import 'song.dart';

/// A playlist — either smart (auto-generated) or manual (user-created).
class Playlist {
  final int? id;
  final String name;
  final IconData icon;
  final List<Song> songs;
  final bool isSmart;

  /// Local file path to the extracted cover art image, if available.
  final String? coverArtPath;

  /// True when the user has manually chosen a cover image.
  /// Auto-extraction will not override a manual pick.
  final bool isManualCover;

  const Playlist({
    this.id,
    required this.name,
    required this.icon,
    required this.songs,
    this.isSmart = false,
    this.coverArtPath,
    this.isManualCover = false,
  });
}
