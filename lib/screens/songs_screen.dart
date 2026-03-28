import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import '../models/song.dart';
import '../widgets/song_tile.dart';

class SongsScreen extends StatefulWidget {
  final List<Song> songs;
  final void Function(List<Song> queue, int index)? onSongTap;
  final void Function(int oldIndex, int newIndex)? onReorder;
  final void Function(Song song)? onFavoriteToggle;
  final void Function(Song song, SongTileAction action)? onMenuAction;
  final Song? nowPlaying;

  const SongsScreen({
    super.key,
    required this.songs,
    this.onSongTap,
    this.onReorder,
    this.onFavoriteToggle,
    this.onMenuAction,
    this.nowPlaying,
  });

  @override
  State<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends State<SongsScreen> {
  late SongSearchIndex _searchIndex;
  late List<Song> _filtered;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchIndex = SongSearchIndex(widget.songs);
    _filtered = widget.songs;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didUpdateWidget(covariant SongsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Rebuild search index only when the list identity changes (add/remove).
    if (!identical(widget.songs, oldWidget.songs)) {
      _searchIndex = SongSearchIndex(widget.songs);
    }
    // Always re-filter to pick up in-place song updates (e.g. importStatus).
    _filtered = _searchIndex.search(_searchController.text);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _filtered = _searchIndex.search(_searchController.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CustomScrollView(
      slivers: [
        // ── Search header ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                hintText: 'Search songs…',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                suffixIcon: ListenableBuilder(
                  listenable: _searchController,
                  builder: (_, _) {
                    if (_searchController.text.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      onPressed: _searchController.clear,
                    );
                  },
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.45),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),

        // ── Song list or empty state ──
        if (_filtered.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.search_off_rounded,
                    size: 56,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No songs found',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          SliverReorderableList(
            itemCount: _filtered.length,
            onReorder: (oldIndex, newIndex) {
              widget.onReorder?.call(oldIndex, newIndex);
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
              final song = _filtered[index];
              return RepaintBoundary(
                key: ValueKey(song.fileName),
                child: SongTile(
                  song: song,
                  reorderIndex: index,
                  isPlaying: identical(song, widget.nowPlaying),
                  onTap: () {
                    widget.onSongTap?.call(_filtered, index);
                  },
                  onFavoriteToggle: widget.onFavoriteToggle != null
                      ? () => widget.onFavoriteToggle!(song)
                      : null,
                  onMenuAction: widget.onMenuAction != null
                      ? (action) => widget.onMenuAction!(song, action)
                      : null,
                ),
              );
            },
          ),
      ],
    );
  }
}
