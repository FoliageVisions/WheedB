import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Visual style for the spinning disc.
enum DiscType { cd, vinyl }

/// A spinning disc that displays album art, switchable between CD and Vinyl
/// looks.
///
/// * Rotation **decelerates** over ~600 ms when [isPlaying] becomes false,
///   giving a heavy, physical feel instead of snapping to a stop.
/// * The disc visual is wrapped in a [RepaintBoundary] so the 60 fps rotation
///   doesn't dirty the rest of the WheedB widget tree.
/// * [DiscType] can be switched at any time via the parent; only the static
///   disc child rebuilds — the animation controller is untouched.
class RotatingDiscPlayer extends StatefulWidget {
  /// Controls whether the disc is spinning.
  final bool isPlaying;

  /// CD or Vinyl appearance.
  final DiscType discType;

  /// Album art to clip into the center of the disc.
  /// Accepts a file path, asset path, or network URL.
  final ImageProvider? albumArt;

  /// Outer diameter of the disc. Defaults to 200.
  final double size;

  const RotatingDiscPlayer({
    super.key,
    required this.isPlaying,
    this.discType = DiscType.vinyl,
    this.albumArt,
    this.size = 200,
  });

  @override
  State<RotatingDiscPlayer> createState() => _RotatingDiscPlayerState();
}

class _RotatingDiscPlayerState extends State<RotatingDiscPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinCtrl;

  /// Tracks the instantaneous rotation angle across repeated cycles and
  /// deceleration stops so the disc never jumps.
  double _currentAngle = 0;
  bool _decelerating = false;

  // ── Deceleration tuning ────────────────────────────────────────────
  static const _decelDuration = Duration(milliseconds: 600);
  static const _decelCurve = Curves.easeOutCubic;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(vsync: this);
    if (widget.isPlaying) _startSpin();
  }

  @override
  void didUpdateWidget(covariant RotatingDiscPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Play state changed.
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _startSpin();
      } else {
        _decelerate();
      }
    }
    // DiscType or art changed — no animation work needed; the child param
    // of AnimatedBuilder handles it via the key on the disc widget.
  }

  /// Begin continuous rotation from the current angle.
  void _startSpin() {
    _decelerating = false;
    _spinCtrl.stop();

    // Animate from currentAngle → currentAngle + 2π, then repeat.
    final startAngle = _currentAngle % (2 * math.pi);
    _spinCtrl
      ..duration = const Duration(seconds: 4)
      ..removeStatusListener(_onSpinStatus); // avoid duplicates
    _spinCtrl.addStatusListener(_onSpinStatus);

    _currentAngle = startAngle;
    _spinCtrl.value = 0;
    _spinCtrl.repeat();
  }

  void _onSpinStatus(AnimationStatus status) {
    // Keep _currentAngle in sync when a full cycle completes.
    if (status == AnimationStatus.completed) {
      _currentAngle += 2 * math.pi;
    }
  }

  /// Smoothly decelerate to a stop over [_decelDuration].
  void _decelerate() {
    if (_decelerating) return;
    _decelerating = true;

    // Snapshot where we are right now.
    final startAngle = _rotationAngle;
    _spinCtrl.removeStatusListener(_onSpinStatus);
    _spinCtrl.stop();

    // A small extra coast: 15 % of a full turn.
    const coastFraction = 0.15;
    final endAngle = startAngle + 2 * math.pi * coastFraction;

    _spinCtrl.duration = _decelDuration;
    // Map controller 0→1 to startAngle→endAngle via the curve.
    _currentAngle = startAngle;
    _spinCtrl.value = 0;

    _spinCtrl.addListener(_decelTick);
    _spinCtrl.animateTo(1.0, curve: _decelCurve).whenCompleteOrCancel(() {
      _spinCtrl.removeListener(_decelTick);
      _currentAngle = endAngle;
      _decelerating = false;
    });
  }

  void _decelTick() {
    // Handled in the build via _rotationAngle.
  }

  /// The angle the disc should display right now.
  double get _rotationAngle {
    if (_decelerating) {
      final startAngle = _currentAngle;
      const coastFraction = 0.15;
      final endAngle = startAngle + 2 * math.pi * coastFraction;
      return startAngle + (endAngle - startAngle) * _spinCtrl.value;
    }
    return _currentAngle + _spinCtrl.value * 2 * math.pi;
  }

  @override
  void dispose() {
    _spinCtrl.removeStatusListener(_onSpinStatus);
    _spinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _spinCtrl,
        builder: (_, _) {
          final angle = _rotationAngle;
          return Transform.rotate(
            angle: angle,
            child: RepaintBoundary(
              child: _buildDisc(angle),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDisc(double currentAngle) {
    return widget.discType == DiscType.vinyl
        ? _VinylDisc(
            key: const ValueKey(DiscType.vinyl),
            size: widget.size,
            albumArt: widget.albumArt,
            rotationAngle: currentAngle,
          )
        : _CdDisc(
            key: const ValueKey(DiscType.cd),
            size: widget.size,
            albumArt: widget.albumArt,
          );
  }
}

// ── Vinyl disc ───────────────────────────────────────────────────────

class _VinylDisc extends StatelessWidget {
  final double size;
  final ImageProvider? albumArt;

  /// Current rotation angle — used to counter-rotate the specular highlight
  /// so it stays fixed in screen-space while the disc spins beneath it.
  final double rotationAngle;

  const _VinylDisc({
    super.key,
    required this.size,
    this.albumArt,
    required this.rotationAngle,
  });

  @override
  Widget build(BuildContext context) {
    final artSize = size * 0.42;
    final holeSize = size * 0.06;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Base disc body + painted grooves
          CustomPaint(
            size: Size.square(size),
            painter: VinylGroovePainter(),
          ),

          // Label area (album art) — ClipRRect is cheaper than Container
          // clip during continuous rotation transforms.
          ClipRRect(
            borderRadius: BorderRadius.circular(artSize / 2),
            child: Container(
              width: artSize,
              height: artSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2A2A2A),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
              child: albumArt != null
                  ? Image(
                      image: albumArt!,
                      fit: BoxFit.cover,
                      width: artSize,
                      height: artSize,
                      errorBuilder: (_, _, _) => _placeholderIcon(artSize),
                    )
                  : _placeholderIcon(artSize),
            ),
          ),

          // Center hole
          Container(
            width: holeSize,
            height: holeSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF121212),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 0.5,
              ),
            ),
          ),

          // Specular highlight — counter-rotated so it stays fixed on screen
          Transform.rotate(
            angle: -rotationAngle,
            child: IgnorePointer(
              child: CustomPaint(
                size: Size.square(size),
                painter: _SpecularHighlightPainter(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── VinylGroovePainter ───────────────────────────────────────────────
//
// Draws the dark vinyl body and dense concentric groove rings using
// Canvas for pixel-perfect control and efficient rendering.

class VinylGroovePainter extends CustomPainter {
  VinylGroovePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // ── 1. Dark vinyl base ──────────────────────────────────────────
    final basePaint = Paint()
      ..shader = RadialGradient(
        colors: const [
          Color(0xFF1A1A1A),
          Color(0xFF0D0D0D),
          Color(0xFF151515),
          Color(0xFF0A0A0A),
        ],
        stops: const [0.0, 0.4, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, basePaint);

    // ── 2. Concentric groove rings ──────────────────────────────────
    // Dense rings from 22% to 97% of the radius (~60 grooves).
    // Alternating opacity simulates the micro-ridges of a real record.
    final groovePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    const innerFrac = 0.22; // inside the label area
    const outerFrac = 0.97; // near the outer edge
    const grooveCount = 60;

    for (int i = 0; i <= grooveCount; i++) {
      final t = i / grooveCount;
      final r = radius * (innerFrac + (outerFrac - innerFrac) * t);

      // Every other ring is slightly brighter to mimic groove peaks/valleys.
      final alpha = i.isEven ? 0.045 : 0.025;
      groovePaint.color = Color.fromRGBO(255, 255, 255, alpha);
      canvas.drawCircle(center, r, groovePaint);
    }

    // ── 3. A few wider "band" separators (like the gaps between
    //       tracks on a real record) ─────────────────────────────────
    final bandPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color.fromRGBO(255, 255, 255, 0.06);

    for (final frac in const [0.40, 0.58, 0.76]) {
      canvas.drawCircle(center, radius * frac, bandPaint);
    }

    // ── 4. Outer rim edge highlight ─────────────────────────────────
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color.fromRGBO(255, 255, 255, 0.07);
    canvas.drawCircle(center, radius - 1, rimPaint);
  }

  /// Static painter — only repaints when the widget is reconstructed.
  @override
  bool shouldRepaint(VinylGroovePainter oldDelegate) => false;
}

// ── Specular highlight (stays fixed in screen-space) ─────────────────
//
// A white gradient "sweep" painted over the disc to simulate the reflective
// bar of light you see on a real vinyl record under a lamp. Because this
// painter's transform is counter-rotated by the disc's current angle, it
// appears stationary while the grooves spin beneath it.

class _SpecularHighlightPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Clip to the disc circle so the highlight doesn't bleed outside.
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));

    // A narrow sweep gradient from about 10 o'clock to 1 o'clock.
    const sweepStart = -math.pi / 3; // –60°
    const sweepEnd = math.pi / 6;    // +30°

    final highlightPaint = Paint()
      ..shader = SweepGradient(
        startAngle: sweepStart + math.pi,
        endAngle: sweepEnd + math.pi,
        colors: const [
          Color.fromRGBO(255, 255, 255, 0.0),
          Color.fromRGBO(255, 255, 255, 0.07),
          Color.fromRGBO(255, 255, 255, 0.13),
          Color.fromRGBO(255, 255, 255, 0.07),
          Color.fromRGBO(255, 255, 255, 0.0),
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, highlightPaint);
  }

  @override
  bool shouldRepaint(_SpecularHighlightPainter oldDelegate) => false;
}

// ── CD disc ──────────────────────────────────────────────────────────

class _CdDisc extends StatelessWidget {
  final double size;
  final ImageProvider? albumArt;

  const _CdDisc({super.key, required this.size, this.albumArt});

  @override
  Widget build(BuildContext context) {
    final rimWidth = size * 0.08;
    final artSize = size * 0.58;
    final holeSize = size * 0.08;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Silver outer rim — 45° linear gradient simulates light
          // hitting polycarbonate plastic.
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment(-0.7, -0.7), // ~top-left (45°)
                end: Alignment(0.7, 0.7),     // ~bottom-right
                colors: [
                  Color(0xFFFFFFFF),  // bright highlight
                  Color(0xFFE0E0E0),  // grey[300]
                  Color(0xFFBDBDBD),  // grey[400]
                  Color(0xFFE0E0E0),  // grey[300]
                  Color(0xFFFFFFFF),  // second highlight edge
                ],
                stops: [0.0, 0.25, 0.5, 0.75, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),

          // Iridescent rainbow sheen over the rim (subtle)
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [
                  Colors.transparent,
                  const Color(0x18A8C8E8), // blue tint
                  const Color(0x18E8D0F0), // purple tint
                  const Color(0x18C0E0C0), // green tint
                  const Color(0x18E8E0B0), // gold tint
                  Colors.transparent,
                ],
              ),
            ),
          ),

          // Inner reflective data surface
          Container(
            width: size - rimWidth * 2,
            height: size - rimWidth * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFEEEEEE),
                  const Color(0xFFD8D8D8),
                  const Color(0xFFE0E0E0),
                  const Color(0xFFCCCCCC),
                ],
                stops: const [0.0, 0.4, 0.7, 1.0],
              ),
            ),
          ),

          // Faint concentric track rings
          for (double frac in const [0.50, 0.60, 0.72])
            Container(
              width: size * frac,
              height: size * frac,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35),
                  width: 0.5,
                ),
              ),
            ),

          // Album art in center — ClipRRect is cheaper than Container
          // clip during continuous rotation transforms.
          ClipRRect(
            borderRadius: BorderRadius.circular(artSize / 2),
            child: Container(
              width: artSize,
              height: artSize,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFE0E0E0),
              ),
              child: albumArt != null
                  ? Image(
                      image: albumArt!,
                      fit: BoxFit.cover,
                      width: artSize,
                      height: artSize,
                      errorBuilder: (_, _, _) => _placeholderIcon(artSize),
                    )
                  : _placeholderIcon(artSize),
            ),
          ),

          // Center hole – transparent-looking
          Container(
            width: holeSize,
            height: holeSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.15),
                  Colors.white.withValues(alpha: 0.05),
                ],
              ),
              border: Border.all(
                color: Colors.grey.shade400,
                width: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared placeholder ───────────────────────────────────────────────

Widget _placeholderIcon(double size) {
  return Center(
    child: Icon(
      Icons.music_note_rounded,
      size: size * 0.4,
      color: Colors.white38,
    ),
  );
}
