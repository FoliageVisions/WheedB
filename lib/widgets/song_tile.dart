import 'package:flutter/material.dart';
import '../models/song.dart';

/// Actions available from the song three-dots menu.
enum SongTileAction { addToPlaylist, addToAlbum, removeFromPlaylist }

class SongTile extends StatelessWidget {
  final Song song;
  final VoidCallback? onTap;
  final VoidCallback? onFavoriteToggle;
  final void Function(SongTileAction action)? onMenuAction;
  final bool isPlaying;
  final bool showRemoveOption;
  final int? reorderIndex;

  const SongTile({super.key, required this.song, this.onTap, this.onFavoriteToggle, this.onMenuAction, this.isPlaying = false, this.showRemoveOption = false, this.reorderIndex});

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isImporting = song.importStatus == SongImportStatus.importing;
    final isFailed = song.importStatus == SongImportStatus.failed;
    final dimmed = isImporting || isFailed;

    final child = Container(
      decoration: isPlaying
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.6),
                width: 1.2,
              ),
            )
          : null,
      child: InkWell(
        onTap: dimmed ? null : onTap,
        borderRadius: isPlaying ? BorderRadius.circular(12) : null,
        // splashColor + highlightColor with short duration ensures the
        // 'pressed' highlight clears immediately after the tap ends.
        highlightColor: Colors.white.withValues(alpha: 0.05),
        splashFactory: InkSplash.splashFactory,
        child: Opacity(
        opacity: dimmed ? 0.5 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Album art placeholder with status overlay
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isFailed ? Icons.error_outline_rounded : Icons.music_note_rounded,
                        color: isFailed
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (isImporting)
                      Positioned.fill(
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              // Title + artist + audio info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isFailed ? 'Import failed' : song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isFailed
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (!isImporting) ...[
                      const SizedBox(height: 2),
                      Text(
                        song.audioInfoLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Favorite heart + duration
              if (onFavoriteToggle != null) ...[
                GestureDetector(
                  onTap: onFavoriteToggle,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Icon(
                      song.isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
              // Duration or status indicator
              if (isImporting)
                Text(
                  '…',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Text(
                  _formatDuration(song.duration),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              // Three-dots menu
              if (onMenuAction != null && !dimmed)
                SizedBox(
                  width: 28,
                  height: 28,
                  child: PopupMenuButton<SongTileAction>(
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: theme.colorScheme.onSurfaceVariant,
                      size: 18,
                    ),
                    color: const Color(0xFF1E1E1E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onSelected: onMenuAction,
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: SongTileAction.addToPlaylist,
                        child: Row(
                          children: [
                            Icon(Icons.playlist_add_rounded,
                                color: theme.colorScheme.primary, size: 20),
                            const SizedBox(width: 10),
                            Text('Add to Playlist',
                                style: TextStyle(
                                    color: theme.colorScheme.onSurface)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: SongTileAction.addToAlbum,
                        child: Row(
                          children: [
                            Icon(Icons.album_rounded,
                                color: theme.colorScheme.tertiary, size: 20),
                            const SizedBox(width: 10),
                            Text('Add to Album',
                                style: TextStyle(
                                    color: theme.colorScheme.onSurface)),
                          ],
                        ),
                      ),
                      if (showRemoveOption)
                        PopupMenuItem(
                          value: SongTileAction.removeFromPlaylist,
                          child: Row(
                            children: [
                              Icon(Icons.remove_circle_outline_rounded,
                                  color: theme.colorScheme.error, size: 20),
                              const SizedBox(width: 10),
                              Text('Remove',
                                  style: TextStyle(
                                      color: theme.colorScheme.error)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
    );

    if (reorderIndex != null) {
      return ReorderableDelayedDragStartListener(
        index: reorderIndex!,
        child: child,
      );
    }
    return child;
  }
}
