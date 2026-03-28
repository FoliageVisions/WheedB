import 'package:flutter/material.dart';
import '../main.dart' show appFontNotifier;
import '../models/audio_settings.dart';
import 'equalizer_panel.dart';

/// Full-screen bottom sheet containing all playback options.
class OptionsMenuSheet extends StatelessWidget {
  final AudioSettings settings;

  const OptionsMenuSheet({super.key, required this.settings});

  /// Show the sheet from any context.
  static void show(BuildContext context, AudioSettings settings) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OptionsMenuSheet(settings: settings),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListenableBuilder(
            listenable: settings,
            builder: (context, _) {
              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Title
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Text(
                      'OPTIONS',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),

                  // ── PLAYBACK section ──
                  _sectionHeader(theme, 'PLAYBACK',
                      'Seamless transition between tracks'),

                  _toggleTile(
                    theme,
                    icon: Icons.playlist_play_rounded,
                    title: 'Gapless Playback',
                    subtitle: 'Eliminate silence between tracks',
                    value: settings.gaplessPlayback,
                    onChanged: (v) => settings.gaplessPlayback = v,
                  ),

                  _toggleTile(
                    theme,
                    icon: Icons.graphic_eq_rounded,
                    title: 'Waveform Visualization',
                    subtitle: 'Show live audio waveform during playback',
                    value: settings.waveformVisualization,
                    onChanged: (v) => settings.waveformVisualization = v,
                  ),

                  const SizedBox(height: 8),

                  // ── AUDIO PROCESSING section ──
                  _sectionHeader(theme, 'AUDIO PROCESSING',
                      'Fine-tune your listening experience'),

                  _toggleTile(
                    theme,
                    icon: Icons.equalizer_rounded,
                    title: '10-Band Equalizer',
                    subtitle: '31 Hz – 16 kHz, ±12 dB per band',
                    value: settings.equalizerEnabled,
                    onChanged: (v) => settings.equalizerEnabled = v,
                  ),

                  // Equalizer panel (shown when enabled)
                  if (settings.equalizerEnabled)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: EqualizerPanel(settings: settings),
                    ),

                  const SizedBox(height: 4),

                  _toggleTile(
                    theme,
                    icon: Icons.swap_horiz_rounded,
                    title: 'Crossfade Mixing',
                    subtitle: 'Blend the end of one track into the next',
                    value: settings.crossfadeEnabled,
                    onChanged: (v) => settings.crossfadeEnabled = v,
                  ),

                  // Crossfade duration picker (shown when enabled)
                  if (settings.crossfadeEnabled) _crossfadeSlider(theme),

                  const SizedBox(height: 8),

                  // ── SORTING section ──
                  _sectionHeader(theme, 'SORTING', 'Organize your library'),

                  _sortOption(
                    theme,
                    category: 'CHRONOLOGICAL – DATE MODIFIED',
                    description: 'Newest First',
                  ),
                  _sortOption(
                    theme,
                    category: 'ALPHABETICAL – TITLE',
                    description: 'A → Z by track name',
                  ),
                  _sortOption(
                    theme,
                    category: 'ALPHABETICAL – ARTIST',
                    description: 'A → Z by performing artist',
                  ),
                  _sortOption(
                    theme,
                    category: 'DURATION – LENGTH',
                    description: 'Longest tracks first',
                  ),

                  const SizedBox(height: 8),

                  // ── FONT section ──
                  _sectionHeader(theme, 'APPEARANCE',
                      'Change the app typeface'),

                  _fontOption(
                    theme,
                    fontName: 'System Default',
                    fontValue: '',
                  ),
                  _fontOption(
                    theme,
                    fontName: 'Courier Prime',
                    fontValue: 'Courier Prime',
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  // ── Helper builders ───────────────────────────────────────────────────

  Widget _sectionHeader(ThemeData theme, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
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
    );
  }

  Widget _toggleTile(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _crossfadeSlider(ThemeData theme) {
    final options = AudioSettings.crossfadeOptions;
    final currentIndex =
        options.indexOf(settings.crossfadeDurationSeconds).clamp(0, options.length - 1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                'Crossfade Duration: ${settings.crossfadeDurationSeconds}s',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          Slider(
            value: currentIndex.toDouble(),
            min: 0,
            max: (options.length - 1).toDouble(),
            divisions: options.length - 1,
            label: '${options[currentIndex]}s',
            onChanged: (v) {
              settings.crossfadeDurationSeconds = options[v.round()];
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: options
                .map((s) => Text(
                      '${s}s',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _sortOption(
    ThemeData theme, {
    required String category,
    required String description,
  }) {
    return InkWell(
      onTap: () {
        // TODO: apply sort
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              category,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fontOption(
    ThemeData theme, {
    required String fontName,
    required String fontValue,
  }) {
    final isSelected = appFontNotifier.value == fontValue;
    return InkWell(
      onTap: () {
        appFontNotifier.value = fontValue;
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 22,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                fontName,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: isSelected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}
