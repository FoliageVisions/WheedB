import 'package:flutter/material.dart';
import '../models/playlist.dart';

/// Represents where imported files should go.
class ImportDestination {
  /// Null means "General Library" (no specific playlist).
  final Playlist? playlist;
  const ImportDestination({this.playlist});
}

/// A bottom sheet that lets the user choose an import destination:
/// "General Library" or one of their manual playlists.
class ImportDestinationSheet extends StatelessWidget {
  final List<Playlist> playlists;

  const ImportDestinationSheet({super.key, required this.playlists});

  /// Shows the sheet and returns the chosen [ImportDestination], or null
  /// if the user dismissed without picking.
  static Future<ImportDestination?> show(
    BuildContext context, {
    required List<Playlist> playlists,
  }) {
    return showModalBottomSheet<ImportDestination>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ImportDestinationSheet(playlists: playlists),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Import to…',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // General Library option
            _DestinationTile(
              icon: Icons.library_music_rounded,
              label: 'General Library',
              subtitle: 'Songs appear in the Music tab',
              accentColor: theme.colorScheme.primary,
              onTap: () => Navigator.pop(
                context,
                const ImportDestination(),
              ),
            ),

            // Playlist options
            if (playlists.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'PLAYLISTS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              // Constrain height if many playlists
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (context, i) {
                    final pl = playlists[i];
                    return _DestinationTile(
                      icon: pl.icon,
                      label: pl.name,
                      subtitle: '${pl.songs.length} ${pl.songs.length == 1 ? 'song' : 'songs'}',
                      accentColor: theme.colorScheme.secondary,
                      onTap: () => Navigator.pop(
                        context,
                        ImportDestination(playlist: pl),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DestinationTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onTap;

  const _DestinationTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: accentColor, size: 22),
      ),
      title: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.4),
          fontSize: 12,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: Colors.white.withValues(alpha: 0.25),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      onTap: onTap,
    );
  }
}
