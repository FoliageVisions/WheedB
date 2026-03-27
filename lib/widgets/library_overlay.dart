import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The two creation types the Library overlay supports.
enum LibraryCreateType { playlist, album }

/// A modal overlay triggered by the Library tab.
///
/// Phase 1 – shows two options: "Create Playlist" / "Create Album".
/// Phase 2 – transitions to a sleek text-input section for the chosen type.
class LibraryOverlay extends StatefulWidget {
  /// Called when the user submits a new name.
  /// Return a [Future] so the overlay can show a brief loading state.
  final Future<void> Function(LibraryCreateType type, String name)? onCreate;

  const LibraryOverlay({super.key, this.onCreate});

  /// Show the overlay as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    Future<void> Function(LibraryCreateType type, String name)? onCreate,
  }) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => LibraryOverlay(onCreate: onCreate),
    );
  }

  @override
  State<LibraryOverlay> createState() => _LibraryOverlayState();
}

class _LibraryOverlayState extends State<LibraryOverlay>
    with SingleTickerProviderStateMixin {
  LibraryCreateType? _selectedType;
  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();
  bool _saving = false;

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeIn = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _selectType(LibraryCreateType type) {
    HapticFeedback.selectionClick();
    setState(() => _selectedType = type);
    _animCtrl.forward(from: 0);
    // Auto-focus the text field after the transition starts.
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _nameFocus.requestFocus();
    });
  }

  void _cancel() {
    HapticFeedback.lightImpact();
    if (_selectedType != null) {
      // Go back to the option picker.
      _animCtrl.reverse().then((_) {
        if (mounted) {
          setState(() {
            _selectedType = null;
            _nameController.clear();
          });
        }
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _selectedType == null || _saving) return;
    HapticFeedback.mediumImpact();

    setState(() => _saving = true);
    try {
      await widget.onCreate?.call(_selectedType!, name);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 4),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                if (_selectedType == null) _buildOptionPicker(theme),
                if (_selectedType != null) _buildInputSection(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Phase 1: Option picker ─────────────────────────────────────────

  Widget _buildOptionPicker(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'CREATE NEW',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 20),
          _OptionCard(
            icon: Icons.queue_music_rounded,
            label: 'Create Playlist',
            subtitle: 'A collection of your favourite tracks',
            color: theme.colorScheme.primary,
            theme: theme,
            onTap: () => _selectType(LibraryCreateType.playlist),
          ),
          const SizedBox(height: 12),
          _OptionCard(
            icon: Icons.album_rounded,
            label: 'Create Album',
            subtitle: 'Group tracks into an album',
            color: theme.colorScheme.tertiary,
            theme: theme,
            onTap: () => _selectType(LibraryCreateType.album),
          ),
        ],
      ),
    );
  }

  // ── Phase 2: Sleek input section ───────────────────────────────────

  Widget _buildInputSection(ThemeData theme) {
    final isPlaylist = _selectedType == LibraryCreateType.playlist;
    final accent =
        isPlaylist ? theme.colorScheme.primary : theme.colorScheme.tertiary;
    final label = isPlaylist ? 'Playlist Name' : 'Album Name';
    final heading = isPlaylist ? 'NEW PLAYLIST' : 'NEW ALBUM';

    return FadeTransition(
      opacity: _fadeIn,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Heading with icon
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isPlaylist
                      ? Icons.queue_music_rounded
                      : Icons.album_rounded,
                  color: accent,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  heading,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Text field
            TextField(
              controller: _nameController,
              focusNode: _nameFocus,
              textCapitalization: TextCapitalization.words,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: TextStyle(color: accent.withValues(alpha: 0.8)),
                filled: true,
                fillColor:
                    theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: accent, width: 1.5),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 20),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.onSurfaceVariant,
                      side: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _nameController,
                    builder: (_, value, _) {
                      final enabled =
                          value.text.trim().isNotEmpty && !_saving;
                      return FilledButton(
                        onPressed: enabled ? _submit : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          disabledBackgroundColor:
                              accent.withValues(alpha: 0.25),
                          foregroundColor: theme.colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _saving
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.onPrimary,
                                ),
                              )
                            : const Text('Create'),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Option card used in Phase 1 ──────────────────────────────────────

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final ThemeData theme;
  final VoidCallback onTap;

  const _OptionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        splashColor: color.withValues(alpha: 0.15),
        highlightColor: color.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
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
      ),
    );
  }
}
