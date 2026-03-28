import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../controllers/music_player_controller.dart';
import '../models/song.dart';

/// Persistent playback control bar displayed at the bottom of the screen.
class PlaybackBar extends StatelessWidget {
  final MusicPlayerController controller;

  const PlaybackBar({super.key, required this.controller});

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final song = controller.currentSong;
        if (song == null) return const SizedBox.shrink();

        final theme = Theme.of(context);
        final position = controller.position;
        final duration = controller.duration;
        final remaining = controller.remaining;
        final progress =
            duration.inMilliseconds > 0
                ? position.inMilliseconds / duration.inMilliseconds
                : 0.0;

        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Progress slider ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      // Elapsed time
                      SizedBox(
                        width: 42,
                        child: Text(
                          _fmt(position),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFeatures: [const FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14,
                            ),
                            activeTrackColor: theme.colorScheme.primary,
                            inactiveTrackColor:
                                theme.colorScheme.onSurface.withValues(alpha: 0.15),
                            thumbColor: theme.colorScheme.primary,
                          ),
                          child: Slider(
                            value: progress.clamp(0.0, 1.0),
                            onChanged: (v) {
                              controller.seekTo(
                                Duration(
                                  milliseconds:
                                      (v * duration.inMilliseconds).round(),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      // Remaining time (countdown)
                      SizedBox(
                        width: 46,
                        child: Text(
                          '-${_fmt(remaining)}',
                          textAlign: TextAlign.end,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFeatures: [const FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Song info + controls ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      // Song metadata column
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Audio info label
                                Text(
                                  song.audioInfoLabel,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // ── Quality badges ──
                            _QualityBadges(song: song),
                          ],
                        ),
                      ),

                      const SizedBox(width: 8),

                      // ── Transport buttons ──
                      _ShuffleRepeatButton(
                        icon: Icons.shuffle_rounded,
                        isActive: controller.shuffleEnabled,
                        onPressed: controller.toggleShuffle,
                        tooltip: 'Shuffle',
                        activeColor: theme.colorScheme.primary,
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_previous_rounded),
                        iconSize: 28,
                        color: theme.colorScheme.onSurface,
                        onPressed: controller.handleBack,
                        tooltip: 'Tap: restart · Double-tap: previous',
                      ),
                      IconButton(
                        icon: Icon(
                          controller.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                        iconSize: 36,
                        color: theme.colorScheme.onSurface,
                        onPressed: controller.togglePlayPause,
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded),
                        iconSize: 28,
                        color: theme.colorScheme.onSurface,
                        onPressed: controller.skipNext,
                      ),
                      _ShuffleRepeatButton(
                        icon: controller.loopMode == LoopMode.one
                            ? Icons.repeat_one_rounded
                            : Icons.repeat_rounded,
                        isActive: controller.loopMode != LoopMode.off,
                        onPressed: controller.cycleLoopMode,
                        tooltip: switch (controller.loopMode) {
                          LoopMode.off => 'Repeat: off',
                          LoopMode.all => 'Repeat: all',
                          LoopMode.one => 'Repeat: one',
                        },
                        activeColor: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Lossless / Hi-Res badge row ─────────────────────────────────────────

class _QualityBadges extends StatelessWidget {
  final Song song;
  const _QualityBadges({required this.song});

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[];
    final theme = Theme.of(context);

    if (song.isLossless) {
      badges.add(_badge(theme, 'Lossless', theme.colorScheme.tertiary));
    }
    if (song.isHiRes) {
      badges.add(_badge(theme, 'Hi-Res', theme.colorScheme.primary));
    }

    if (badges.isEmpty) return const SizedBox.shrink();

    return Wrap(spacing: 6, children: badges);
  }

  Widget _badge(ThemeData theme, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          height: 1.2,
        ),
      ),
    );
  }
}

// ── Shuffle / Repeat toggle button ──────────────────────────────────────

class _ShuffleRepeatButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onPressed;
  final String tooltip;
  final Color activeColor;

  const _ShuffleRepeatButton({
    required this.icon,
    required this.isActive,
    required this.onPressed,
    required this.tooltip,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inactiveColor =
        theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? activeColor.withValues(alpha: 0.15)
                  : Colors.transparent,
            ),
            child: Icon(
              icon,
              size: 18,
              color: isActive ? activeColor : inactiveColor,
            ),
          ),
        ),
      ),
    );
  }
}
