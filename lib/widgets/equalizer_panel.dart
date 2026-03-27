import 'package:flutter/material.dart';
import '../models/audio_settings.dart';

/// 10-band graphic equalizer panel (31 Hz – 16 kHz, ±12 dB).
class EqualizerPanel extends StatelessWidget {
  final AudioSettings settings;

  const EqualizerPanel({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final bands = settings.eqBands;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    '10-BAND EQUALIZER',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: settings.resetEqualizer,
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ),

            // dB scale labels + sliders
            SizedBox(
              height: 220,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    // dB axis labels
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('+12', style: _axisStyle(theme)),
                        Text('0', style: _axisStyle(theme)),
                        Text('-12', style: _axisStyle(theme)),
                      ],
                    ),
                    const SizedBox(width: 4),

                    // Band sliders
                    ...List.generate(10, (i) {
                      return Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              child: RotatedBox(
                                quarterTurns: 3,
                                child: SliderTheme(
                                  data: SliderThemeData(
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 6,
                                    ),
                                    overlayShape:
                                        const RoundSliderOverlayShape(
                                      overlayRadius: 12,
                                    ),
                                    activeTrackColor:
                                        theme.colorScheme.primary,
                                    inactiveTrackColor: theme
                                        .colorScheme.onSurface
                                        .withValues(alpha: 0.15),
                                    thumbColor: theme.colorScheme.primary,
                                  ),
                                  child: Slider(
                                    value: bands[i],
                                    min: -12,
                                    max: 12,
                                    onChanged: (v) =>
                                        settings.setEqBand(i, v),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              AudioSettings.bandLabels[i],
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  TextStyle? _axisStyle(ThemeData theme) => theme.textTheme.labelSmall
      ?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 10);
}
