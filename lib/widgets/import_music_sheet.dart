import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

/// A bottom sheet that presents the "Import Music" action.
/// Returns `true` if the user chose to import, `null` if dismissed.
class ImportMusicSheet extends StatelessWidget {
  const ImportMusicSheet({super.key});

  /// Shows the sheet and returns `true` when the user taps Import,
  /// or `null` if dismissed.
  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const ImportMusicSheet(),
    );
  }

  String get _platformLabel {
    if (kIsWeb) return 'browser';
    return defaultTargetPlatform == TargetPlatform.iOS
        ? 'iPhone'
        : defaultTargetPlatform == TargetPlatform.android
            ? 'Android device'
            : defaultTargetPlatform == TargetPlatform.macOS
                ? 'Mac'
                : defaultTargetPlatform == TargetPlatform.windows
                    ? 'Windows PC'
                    : defaultTargetPlatform == TargetPlatform.linux
                        ? 'Linux device'
                        : 'device';
  }

  IconData get _platformIcon {
    if (kIsWeb) return Icons.language_rounded;
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return Icons.apple_rounded;
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return Icons.laptop_windows_rounded;
    }
    return Icons.phone_android_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
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
                'Import Music',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 6),

            // Subtitle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Add music files from your $_platformLabel',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Import from device option
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_platformIcon, color: accent, size: 24),
              ),
              title: const Text(
                'Import from Device',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              subtitle: Text(
                'Select MP3, WAV, or FLAC files',
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
              onTap: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
  }
}
