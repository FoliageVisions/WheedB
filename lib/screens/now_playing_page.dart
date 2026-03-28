import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../controllers/music_player_controller.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../widgets/song_tile.dart';

/// Full-screen "Now Playing" page with a spinning vinyl (lossless) or
/// CD (lossy) visualizer. The disc spins at 33⅓ RPM only while audio
/// is playing and pauses instantly when playback stops.
class NowPlayingPage extends StatefulWidget {
  final MusicPlayerController controller;
  final void Function(Song song, SongTileAction action)? onMenuAction;
  final Playlist? currentPlaylist;
  final void Function(Playlist playlist, Song song)? onRemoveFromPlaylist;
  final void Function(Song song)? onFavoriteToggle;

  const NowPlayingPage({super.key, required this.controller, this.onMenuAction, this.currentPlaylist, this.onRemoveFromPlaylist, this.onFavoriteToggle});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    // One full revolution every 1.8 seconds → ~33⅓ RPM.
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    widget.controller.addListener(_syncSpin);
    _syncSpin(); // kick-start if already playing
  }

  void _syncSpin() {
    if (widget.controller.isPlaying) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop(); // freezes at current angle — no jump
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncSpin);
    _spin.dispose();
    super.dispose();
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final song = widget.controller.currentSong;
          if (song == null) {
            // Nothing playing — pop back.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) Navigator.of(context).pop();
            });
            return const SizedBox.shrink();
          }

          final isLossless = song.isLossless;
          final position = widget.controller.position;
          final duration = widget.controller.duration;
          final remaining = widget.controller.remaining;
          final progress = duration.inMilliseconds > 0
              ? position.inMilliseconds / duration.inMilliseconds
              : 0.0;

          // Disc size: 70% of the narrower dimension, capped at 360.
          final discSize =
              (math.min(mq.size.width, mq.size.height) * 0.70).clamp(200.0, 360.0);

          return SafeArea(
            child: Column(
              children: [
                // ── Top bar ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        iconSize: 32,
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Spacer(),
                      Text(
                        'NOW PLAYING',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          letterSpacing: 1.8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      PopupMenuButton<SongTileAction>(
                        padding: EdgeInsets.zero,
                        iconSize: 24,
                        icon: Icon(
                          Icons.more_vert_rounded,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        color: const Color(0xFF1E1E1E),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onSelected: (action) {
                          if (action == SongTileAction.removeFromPlaylist) {
                            if (widget.currentPlaylist != null && widget.onRemoveFromPlaylist != null) {
                              widget.onRemoveFromPlaylist!(widget.currentPlaylist!, song);
                            }
                          } else if (widget.onMenuAction != null) {
                            widget.onMenuAction!(song, action);
                          }
                        },
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
                          if (widget.currentPlaylist != null && !widget.currentPlaylist!.isSmart)
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
                    ],
                  ),
                ),

                const Spacer(flex: 2),

                // ── Spinning disc ──
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _spin,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _spin.value * 2 * math.pi,
                        child: child,
                      );
                    },
                    child: SizedBox(
                      width: discSize,
                      height: discSize,
                      child: CustomPaint(
                        painter: isLossless
                            ? _VinylPainter(theme: theme, title: song.title, artist: song.artist)
                            : _CdPainter(theme: theme, title: song.title, artist: song.artist),
                        willChange: true,
                      ),
                    ),
                  ),
                ),

                const Spacer(flex: 1),

                // ── Song metadata ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              song.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (widget.onFavoriteToggle != null) ...[                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => widget.onFavoriteToggle!(song),
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  song.isFavorite
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  size: 22,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Quality badge
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            song.audioInfoLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                          if (song.isLossless) ...[
                            const SizedBox(width: 8),
                            _badge(theme, 'Lossless', theme.colorScheme.tertiary),
                          ],
                          if (song.isHiRes) ...[
                            const SizedBox(width: 6),
                            _badge(theme, 'Hi-Res', theme.colorScheme.primary),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 1),

                // ── Progress slider ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      SliderTheme(
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
                            widget.controller.seekTo(
                              Duration(
                                milliseconds:
                                    (v * duration.inMilliseconds).round(),
                              ),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _fmt(position),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontFeatures: [
                                  const FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            Text(
                              '-${_fmt(remaining)}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontFeatures: [
                                  const FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // ── Transport controls ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Shuffle
                      IconButton(
                        icon: const Icon(Icons.shuffle_rounded),
                        iconSize: 22,
                        color: widget.controller.shuffleEnabled
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.4),
                        onPressed: widget.controller.toggleShuffle,
                      ),
                      // Previous
                      IconButton(
                        icon: const Icon(Icons.skip_previous_rounded),
                        iconSize: 36,
                        color: theme.colorScheme.onSurface,
                        onPressed: widget.controller.handleBack,
                      ),
                      // Play/Pause — large
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primary,
                        ),
                        child: IconButton(
                          icon: Icon(
                            widget.controller.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                          iconSize: 36,
                          color: theme.colorScheme.onPrimary,
                          onPressed: widget.controller.togglePlayPause,
                        ),
                      ),
                      // Next
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded),
                        iconSize: 36,
                        color: theme.colorScheme.onSurface,
                        onPressed: widget.controller.skipNext,
                      ),
                      // Loop
                      IconButton(
                        icon: Icon(
                          widget.controller.loopMode == LoopMode.one
                              ? Icons.repeat_one_rounded
                              : Icons.repeat_rounded,
                        ),
                        iconSize: 22,
                        color: widget.controller.loopMode != LoopMode.off
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.4),
                        onPressed: widget.controller.cycleLoopMode,
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 1),
              ],
            ),
          );
        },
      ),
    );
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

// ══════════════════════════════════════════════════════════════════════════
//  Custom painters for the spinning disc visuals
// ══════════════════════════════════════════════════════════════════════════

/// Classic vinyl record: black disc, fine grooves, coloured label.
class _VinylPainter extends CustomPainter {
  final ThemeData theme;
  final String title;
  final String artist;
  _VinylPainter({required this.theme, required this.title, required this.artist});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // ── Outer disc (black vinyl) ──
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = const Color(0xFF1A1A1A),
    );

    // ── Subtle grooves ──
    final groovePaint = Paint()
      ..color = const Color(0xFF2A2A2A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (double r = radius * 0.35; r < radius * 0.92; r += 3.5) {
      canvas.drawCircle(center, r, groovePaint);
    }

    // ── Sheen highlight (reflective arc) ──
    final sheenPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        radius: 0.8,
        colors: [
          Colors.white.withValues(alpha: 0.06),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, sheenPaint);

    // ── Centre label ──
    final labelRadius = radius * 0.28;
    final labelPaint = Paint()
      ..color = theme.colorScheme.tertiary.withValues(alpha: 0.85);
    canvas.drawCircle(center, labelRadius, labelPaint);

    // Inner label ring
    canvas.drawCircle(
      center,
      labelRadius * 0.7,
      Paint()
        ..color = theme.colorScheme.tertiary.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // ── Label text (title + artist) ──
    _drawLabelText(canvas, center, labelRadius, spindle: radius * 0.03);

    // ── Spindle hole ──
    canvas.drawCircle(
      center,
      radius * 0.03,
      Paint()..color = const Color(0xFF0A0A0A),
    );
  }

  void _drawLabelText(Canvas canvas, Offset center, double labelRadius, {required double spindle}) {
    // Available width is ~70% of label diameter to keep text inside the circle.
    final maxWidth = labelRadius * 1.3;
    // Place title above center, artist below — both stay above/below spindle.
    final titleFontSize = (labelRadius * 0.22).clamp(6.0, 14.0);
    final artistFontSize = (labelRadius * 0.17).clamp(5.0, 11.0);
    final gap = spindle + 2; // clearance from the spindle hole

    // Title (above center)
    final titleSpan = TextSpan(
      text: title,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.9),
        fontSize: titleFontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    );
    final titlePainter = TextPainter(
      text: titleSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '\u2026',
    )..layout(maxWidth: maxWidth);
    titlePainter.paint(
      canvas,
      Offset(
        center.dx - titlePainter.width / 2,
        center.dy - gap - titlePainter.height,
      ),
    );

    // Artist (below center)
    final artistSpan = TextSpan(
      text: artist,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.65),
        fontSize: artistFontSize,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
      ),
    );
    final artistPainter = TextPainter(
      text: artistSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '\u2026',
    )..layout(maxWidth: maxWidth);
    artistPainter.paint(
      canvas,
      Offset(
        center.dx - artistPainter.width / 2,
        center.dy + gap,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _VinylPainter old) =>
      theme.colorScheme.tertiary != old.theme.colorScheme.tertiary ||
      title != old.title ||
      artist != old.artist;
}

/// Shiny compact disc: reflective rainbow shimmer, data track, center hole.
class _CdPainter extends CustomPainter {
  final ThemeData theme;
  final String title;
  final String artist;
  _CdPainter({required this.theme, required this.title, required this.artist});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // ── Silver disc base ──
    final basePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFE8E8E8),
          const Color(0xFFD0D0D0),
          const Color(0xFFB8B8B8),
          const Color(0xFFD4D4D4),
        ],
        stops: const [0.0, 0.4, 0.75, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, basePaint);

    // ── Rainbow iridescence (sweep gradient) ──
    final iridescentPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.purple.withValues(alpha: 0.12),
          Colors.blue.withValues(alpha: 0.14),
          Colors.cyan.withValues(alpha: 0.12),
          Colors.green.withValues(alpha: 0.10),
          Colors.yellow.withValues(alpha: 0.10),
          Colors.orange.withValues(alpha: 0.12),
          Colors.red.withValues(alpha: 0.12),
          Colors.purple.withValues(alpha: 0.12),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, iridescentPaint);

    // ── Data track rings ──
    final trackPaint = Paint()
      ..color = const Color(0xFFC0C0C0).withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.4;
    for (double r = radius * 0.35; r < radius * 0.90; r += 2.0) {
      canvas.drawCircle(center, r, trackPaint);
    }

    // ── Specular highlight ──
    final specularPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.35),
        radius: 0.6,
        colors: [
          Colors.white.withValues(alpha: 0.30),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, specularPaint);

    // ── Outer rim ──
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..color = const Color(0xFF999999)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // ── Centre transparent ring ──
    final hubRadius = radius * 0.22;
    canvas.drawCircle(
      center,
      hubRadius,
      Paint()..color = const Color(0xFF404040),
    );
    // Hub ring
    canvas.drawCircle(
      center,
      hubRadius,
      Paint()
        ..color = const Color(0xFF888888)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // ── CD-Text (title + artist in lead-in area) ──
    _drawCdText(canvas, center, hubRadius, spindle: radius * 0.04);

    // ── Spindle hole ──
    canvas.drawCircle(
      center,
      radius * 0.04,
      Paint()..color = const Color(0xFF1A1A1A),
    );
  }

  void _drawCdText(Canvas canvas, Offset center, double hubRadius, {required double spindle}) {
    final maxWidth = hubRadius * 1.3;
    final titleFontSize = (hubRadius * 0.20).clamp(5.0, 12.0);
    final artistFontSize = (hubRadius * 0.16).clamp(4.0, 10.0);
    final gap = spindle + 2;

    // Title (above center)
    final titleSpan = TextSpan(
      text: title,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.75),
        fontSize: titleFontSize,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );
    final titlePainter = TextPainter(
      text: titleSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '\u2026',
    )..layout(maxWidth: maxWidth);
    titlePainter.paint(
      canvas,
      Offset(
        center.dx - titlePainter.width / 2,
        center.dy - gap - titlePainter.height,
      ),
    );

    // Artist (below center)
    final artistSpan = TextSpan(
      text: artist,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.55),
        fontSize: artistFontSize,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
      ),
    );
    final artistPainter = TextPainter(
      text: artistSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '\u2026',
    )..layout(maxWidth: maxWidth);
    artistPainter.paint(
      canvas,
      Offset(
        center.dx - artistPainter.width / 2,
        center.dy + gap,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _CdPainter old) =>
      title != old.title || artist != old.artist;
}
