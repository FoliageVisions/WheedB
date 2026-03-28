import 'package:flutter/material.dart';
import '../controllers/music_player_controller.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../widgets/playback_bar.dart';
import '../widgets/song_tile.dart';

/// Shows the songs inside a playlist (smart or manual).
class PlaylistDetailPage extends StatelessWidget {
  final Playlist playlist;
  final void Function(List<Song> queue, int index)? onSongTap;
  final void Function(Song song)? onFavoriteToggle;
  final void Function(Song song, SongTileAction action)? onMenuAction;
  final void Function(Playlist playlist, Song song)? onRemoveFromPlaylist;
  final Song? nowPlaying;
  final MusicPlayerController? controller;

  const PlaylistDetailPage({
    super.key,
    required this.playlist,
    this.onSongTap,
    this.onFavoriteToggle,
    this.onMenuAction,
    this.onRemoveFromPlaylist,
    this.nowPlaying,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final songs = playlist.songs;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          playlist.name,
          style: theme.textTheme.titleLarge?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: songs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          playlist.icon,
                          size: 56,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No songs yet',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListenableBuilder(
                    listenable: controller ?? const _NoOpListenable(),
                    builder: (context, _) {
                      final playing = controller?.currentSong;
                      return ListView.builder(
                        itemCount: songs.length,
                        itemBuilder: (context, index) {
                          final song = songs[index];
                          return SongTile(
                            song: song,
                            isPlaying: identical(song, playing),
                            showRemoveOption: !playlist.isSmart,
                            onTap: () => onSongTap?.call(songs, index),
                            onFavoriteToggle: onFavoriteToggle != null
                                ? () => onFavoriteToggle!(song)
                                : null,
                            onMenuAction: (action) {
                              if (action == SongTileAction.removeFromPlaylist) {
                                onRemoveFromPlaylist?.call(playlist, song);
                              } else {
                                onMenuAction?.call(song, action);
                              }
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
          if (controller != null)
            RepaintBoundary(
              child: PlaybackBar(
                controller: controller!,
                onSongMenuAction: onMenuAction,
                currentPlaylist: playlist.isSmart ? null : playlist,
                onRemoveFromPlaylist: onRemoveFromPlaylist,
                onFavoriteToggle: onFavoriteToggle,
              ),
            ),
        ],
      ),
    );
  }
}

class _NoOpListenable implements Listenable {
  const _NoOpListenable();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}
