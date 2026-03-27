import 'dart:io';

import 'package:flutter/material.dart';
import '../models/playlist.dart';
import '../models/smart_playlist_generator.dart';
import '../models/song.dart';

class PlaylistsScreen extends StatelessWidget {
  final List<Song> library;
  final List<Playlist> manualPlaylists;
  final void Function(List<Song> queue, int index)? onSongTap;

  const PlaylistsScreen({
    super.key,
    required this.library,
    this.manualPlaylists = const [],
    this.onSongTap,
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
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final pl = manualPlaylists[index];
                return _ManualPlaylistTile(
                  playlist: pl,
                  onSongTap: onSongTap,
                );
              },
              childCount: manualPlaylists.length,
            ),
          ),
      ],
    );
  }
}

// ── Smart playlist card widget ──────────────────────────────────────────

class _SmartPlaylistCard extends StatelessWidget {
  final Playlist playlist;
  final void Function(List<Song> queue, int index)? onSongTap;
  const _SmartPlaylistCard({required this.playlist, this.onSongTap});

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
          if (playlist.songs.isNotEmpty) {
            onSongTap?.call(playlist.songs, 0);
          }
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
  const _ManualPlaylistTile({required this.playlist, this.onSongTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final songCount = playlist.songs.length;

    return InkWell(
      onTap: () {
        if (playlist.songs.isNotEmpty) {
          onSongTap?.call(playlist.songs, 0);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Cover art thumbnail or placeholder
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 48,
                height: 48,
                child: playlist.coverArtPath != null
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
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant,
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
        size: 24,
      ),
    );
  }
}
