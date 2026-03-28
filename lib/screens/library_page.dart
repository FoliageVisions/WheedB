import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import 'playlists_screen.dart';

/// The Library page that replaces the old standalone Playlists tab.
/// A [TabBar] at the top toggles between **Playlists** and **Albums**,
/// backed by a [TabBarView] for smooth swipeable transitions.
class LibraryPage extends StatefulWidget {
  final List<Song> library;
  final List<Playlist> manualPlaylists;
  final void Function(List<Song> queue, int index)? onSongTap;
  final Map<String, String> albumCoverArtPaths;
  final ValueChanged<int>? onTabChanged;

  const LibraryPage({
    super.key,
    required this.library,
    this.manualPlaylists = const [],
    this.onSongTap,
    this.albumCoverArtPaths = const {},
    this.onTabChanged,
  });

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      widget.onTabChanged?.call(_tabCtrl.index);
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedIdx = _tabCtrl.index;

    return Column(
      children: [
        // ── Toggle bar ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: TabBar(
              controller: _tabCtrl,
              indicator: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.28),
                    theme.colorScheme.primary.withValues(alpha: 0.14),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.all(3),
              dividerHeight: 0,
              labelColor: Colors.white,
              unselectedLabelColor:
                  theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              labelStyle: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                fontSize: 14,
              ),
              unselectedLabelStyle: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
                fontSize: 13,
              ),
              splashBorderRadius: BorderRadius.circular(11),
              tabs: [
                _buildTab(
                  icon: Icons.queue_music_rounded,
                  label: 'Playlists',
                  isSelected: selectedIdx == 0,
                  theme: theme,
                ),
                _buildTab(
                  icon: Icons.album_rounded,
                  label: 'Albums',
                  isSelected: selectedIdx == 1,
                  theme: theme,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        // ── Swipeable body ──
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              PlaylistsScreen(
                library: widget.library,
                manualPlaylists: widget.manualPlaylists,
                onSongTap: widget.onSongTap,
              ),
              _AlbumsGrid(
                library: widget.library,
                onSongTap: widget.onSongTap,
                coverArtPaths: widget.albumCoverArtPaths,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTab({
    required IconData icon,
    required String label,
    required bool isSelected,
    required ThemeData theme,
  }) {
    return Tab(
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
          fontSize: isSelected ? 14 : 13,
          letterSpacing: isSelected ? 0.5 : 0.2,
          color: isSelected
              ? Colors.white
              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      ),
    );
  }
}

// ── Albums grid ──────────────────────────────────────────────────────

class _AlbumsGrid extends StatelessWidget {
  final List<Song> library;
  final void Function(List<Song> queue, int index)? onSongTap;
  final Map<String, String> coverArtPaths;
  const _AlbumsGrid({
    required this.library,
    this.onSongTap,
    this.coverArtPaths = const {},
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Group songs by album name.
    final albumMap = <String, List<Song>>{};
    for (final song in library) {
      albumMap.putIfAbsent(song.album, () => []).add(song);
    }
    final albums = albumMap.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (albums.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.album_rounded,
              size: 56,
              color: Colors.white.withValues(alpha: 0.12),
            ),
            const SizedBox(height: 12),
            Text(
              'No albums yet',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.35),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 14,
        childAspectRatio: 0.78,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final entry = albums[index];
        final albumName = entry.key;
        final songs = entry.value;
        final artist = songs.first.artist;

        return Material(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            splashColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            highlightColor: theme.colorScheme.primary.withValues(alpha: 0.06),
            onTap: () {
              if (songs.isNotEmpty) {
                onSongTap?.call(songs, 0);
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Album art
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _AlbumArt(
                        albumName: albumName,
                        theme: theme,
                        localPath: coverArtPaths[albumName],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    albumName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$artist · ${songs.length} ${songs.length == 1 ? 'song' : 'songs'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontWeight: FontWeight.w500,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Album art widget that shows a local [File] image, a [CachedNetworkImage],
/// or falls back to a styled placeholder with a gradient and icon.
class _AlbumArt extends StatelessWidget {
  final String albumName;
  final ThemeData theme;
  final String? localPath;

  const _AlbumArt({
    required this.albumName,
    required this.theme,
    this.localPath,
  });

  @override
  Widget build(BuildContext context) {
    // Prefer local file (extracted cover art).
    if (localPath != null && localPath!.isNotEmpty && !kIsWeb) {
      return Image.file(
        File(localPath!),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }

    return _placeholder();
  }

  Widget _placeholder() {
    // Generate a deterministic hue from the album name for visual variety.
    final hue = (albumName.hashCode % 360).abs().toDouble();
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            HSLColor.fromAHSL(1, hue, 0.35, 0.18).toColor(),
            HSLColor.fromAHSL(1, (hue + 40) % 360, 0.25, 0.10).toColor(),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 36,
          color: Colors.white.withValues(alpha: 0.25),
        ),
      ),
    );
  }
}
