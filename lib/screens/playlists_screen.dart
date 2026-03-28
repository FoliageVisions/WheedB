import 'dart:io';
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../controllers/music_player_controller.dart';
import '../models/playlist.dart';
import '../models/smart_playlist_generator.dart';
import '../models/song.dart';
import '../widgets/song_tile.dart';
import 'playlist_detail_page.dart';

/// Actions available on each manual playlist tile's three-dots menu.
enum PlaylistCardAction { rename, addPicture, delete }

class PlaylistsScreen extends StatelessWidget {
  final List<Song> library;
  final List<Playlist> manualPlaylists;
  final void Function(List<Song> queue, int index)? onSongTap;
  final void Function(int oldIndex, int newIndex)? onPlaylistReorder;
  final void Function(Song song)? onFavoriteToggle;
  final void Function(Song song, SongTileAction action)? onMenuAction;
  final void Function(Playlist playlist, Song song)? onRemoveFromPlaylist;
  final Song? nowPlaying;
  final MusicPlayerController? controller;
  final void Function(String playlistName, PlaylistCardAction action)? onPlaylistCardAction;

  const PlaylistsScreen({
    super.key,
    required this.library,
    this.manualPlaylists = const [],
    this.onSongTap,
    this.onPlaylistReorder,
    this.onFavoriteToggle,
    this.onMenuAction,
    this.onRemoveFromPlaylist,
    this.nowPlaying,
    this.controller,
    this.onPlaylistCardAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final smartPlaylists = SmartPlaylistGenerator(library).generateAll();

    return CustomScrollView(
      slivers: [
        // ── Smart Playlists section header ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Smart Playlists',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),

        // ── Smart Playlist grid ──
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.65,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _SmartPlaylistCard(
                playlist: smartPlaylists[index],
                onSongTap: onSongTap,
                onFavoriteToggle: onFavoriteToggle,
                onMenuAction: onMenuAction,
                onRemoveFromPlaylist: onRemoveFromPlaylist,
                nowPlaying: nowPlaying,
                controller: controller,
              ),
              childCount: smartPlaylists.length,
            ),
          ),
        ),

        // ── Manual Playlists section header ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              'Your Playlists',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),

        // ── Manual playlist list or empty state ──
        if (manualPlaylists.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.library_music_rounded,
                      size: 48,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No playlists yet',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverReorderableList(
            itemCount: manualPlaylists.length,
            onReorder: (oldIndex, newIndex) {
              onPlaylistReorder?.call(oldIndex, newIndex);
            },
            proxyDecorator: (child, index, animation) {
              return AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  final elevation = lerpDouble(0, 6, animation.value)!;
                  return Material(
                    elevation: elevation,
                    color: Colors.transparent,
                    shadowColor: Colors.black54,
                    child: child,
                  );
                },
                child: child,
              );
            },
            itemBuilder: (context, index) {
              final pl = manualPlaylists[index];
              return ReorderableDelayedDragStartListener(
                key: ValueKey(pl.id ?? pl.name),
                index: index,
                child: _ManualPlaylistTile(
                  playlist: pl,
                  onSongTap: onSongTap,
                  onFavoriteToggle: onFavoriteToggle,
                  onMenuAction: onMenuAction,
                  onRemoveFromPlaylist: onRemoveFromPlaylist,
                  nowPlaying: nowPlaying,
                  controller: controller,
                  onPlaylistCardAction: onPlaylistCardAction,
                ),
              );
            },
          ),
      ],
    );
  }
}

// ── Smart playlist card widget ──────────────────────────────────────────

class _SmartPlaylistCard extends StatelessWidget {
  final Playlist playlist;
  final void Function(List<Song> queue, int index)? onSongTap;
  final void Function(Song song)? onFavoriteToggle;
  final void Function(Song song, SongTileAction action)? onMenuAction;
  final void Function(Playlist playlist, Song song)? onRemoveFromPlaylist;
  final Song? nowPlaying;
  final MusicPlayerController? controller;
  const _SmartPlaylistCard({required this.playlist, this.onSongTap, this.onFavoriteToggle, this.onMenuAction, this.onRemoveFromPlaylist, this.nowPlaying, this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final songCount = playlist.songs.length;

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PlaylistDetailPage(
                playlist: playlist,
                onSongTap: onSongTap,
                onFavoriteToggle: onFavoriteToggle,
                onMenuAction: onMenuAction,
                onRemoveFromPlaylist: onRemoveFromPlaylist,
                nowPlaying: nowPlaying,
                controller: controller,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                playlist.icon,
                color: theme.colorScheme.primary,
                size: 28,
              ),
              const Spacer(),
              Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$songCount ${songCount == 1 ? 'song' : 'songs'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Manual playlist row widget ──────────────────────────────────────────

class _ManualPlaylistTile extends StatelessWidget {
  final Playlist playlist;
  final void Function(List<Song> queue, int index)? onSongTap;
  final void Function(Song song)? onFavoriteToggle;
  final void Function(Song song, SongTileAction action)? onMenuAction;
  final void Function(Playlist playlist, Song song)? onRemoveFromPlaylist;
  final Song? nowPlaying;
  final MusicPlayerController? controller;
  final void Function(String playlistName, PlaylistCardAction action)? onPlaylistCardAction;
  const _ManualPlaylistTile({required this.playlist, this.onSongTap, this.onFavoriteToggle, this.onMenuAction, this.onRemoveFromPlaylist, this.nowPlaying, this.controller, this.onPlaylistCardAction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final songCount = playlist.songs.length;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlaylistDetailPage(
              playlist: playlist,
              onSongTap: onSongTap,
              onFavoriteToggle: onFavoriteToggle,
              onMenuAction: onMenuAction,
              onRemoveFromPlaylist: onRemoveFromPlaylist,
              nowPlaying: nowPlaying,
              controller: controller,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Cover art thumbnail or placeholder
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: playlist.coverArtPath != null && !kIsWeb
                    ? Image.file(
                        File(playlist.coverArtPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _playlistPlaceholder(theme),
                      )
                    : _playlistPlaceholder(theme),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$songCount ${songCount == 1 ? 'song' : 'songs'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 32,
              height: 32,
              child: PopupMenuButton<PlaylistCardAction>(
                padding: EdgeInsets.zero,
                iconSize: 20,
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 20,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
                color: const Color(0xFF1E1E1E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                offset: const Offset(0, 36),
                onSelected: (action) =>
                    onPlaylistCardAction?.call(playlist.name, action),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: PlaylistCardAction.rename,
                    child: Row(
                      children: [
                        Icon(Icons.edit_rounded,
                            size: 20,
                            color: theme.colorScheme.primary),
                        const SizedBox(width: 12),
                        const Text('Rename Playlist',
                            style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: PlaylistCardAction.addPicture,
                    child: Row(
                      children: [
                        Icon(Icons.image_rounded,
                            size: 20,
                            color: theme.colorScheme.secondary),
                        const SizedBox(width: 12),
                        const Text('Add Playlist Picture',
                            style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: PlaylistCardAction.delete,
                    child: Row(
                      children: [
                        const Icon(Icons.delete_rounded,
                            size: 20, color: Colors.redAccent),
                        const SizedBox(width: 12),
                        const Text('Delete Playlist',
                            style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playlistPlaceholder(ThemeData theme) {
    final hue = (playlist.name.hashCode % 360).abs().toDouble();
    return Container(
      color: HSLColor.fromAHSL(1, hue, 0.3, 0.15).toColor(),
      child: Icon(
        playlist.icon,
        color: Colors.white.withValues(alpha: 0.35),
        size: 28,
      ),
    );
  }
}
