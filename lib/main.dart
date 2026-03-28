import 'dart:io';
import 'dart:math' show min;
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'controllers/music_player_controller.dart';
import 'models/audio_settings.dart';
import 'models/playlist.dart';
import 'models/song.dart';
import 'screens/library_page.dart';
import 'screens/playlists_screen.dart';
import 'screens/songs_screen.dart';
import 'services/audio_metadata.dart';
import 'services/audio_prober.dart';
import 'services/database_helper.dart';
import 'services/cover_art_extractor.dart';
import 'services/device_music_scanner.dart';
import 'services/web_library_cache.dart';
import 'widgets/options_menu_sheet.dart';
import 'widgets/playback_bar.dart';
import 'widgets/song_tile.dart';

/// Global notifier for the app font family.
/// Empty string means system default; otherwise a Google Fonts family name.
final ValueNotifier<String> appFontNotifier = ValueNotifier<String>('');

/// Human-readable name for display.
String get appFontDisplayName =>
    appFontNotifier.value.isEmpty ? 'System Default' : appFontNotifier.value;

void main() {
  runApp(const WheedBApp());
}

class WheedBApp extends StatelessWidget {
  const WheedBApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: appFontNotifier,
      builder: (context, fontFamily, _) {
        final baseTheme = ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF121212),
          useMaterial3: true,
        );

        final themed = fontFamily.isEmpty
            ? baseTheme
            : baseTheme.copyWith(
                textTheme: GoogleFonts.getTextTheme(fontFamily, baseTheme.textTheme),
              );

        return MaterialApp(
          title: 'WheedB',
          debugShowCheckedModeBanner: false,
          theme: themed,
          home: const HomePage(),
        );
      },
    );
  }
}

/// Actions available from the Library three-dots menu.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentTab = 0;
  int _libraryTabIndex = 0;
  final _playback = MusicPlayerController();
  final _audioSettings = AudioSettings();
  final _scanner = DeviceMusicScanner();
  List<Song> _deviceSongs = [];
  List<Playlist> _manualPlaylists = [];
  Set<String> _manualAlbumNames = {};
  Map<String, String> _albumCoverArtPaths = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    if (!kIsWeb) {
      await _playback.init();

      final granted = await _scanner.requestPermission();
      if (granted) {
        final songs = await _scanner.scanAllSongs();
        setState(() {
          _deviceSongs = songs;
          _loading = false;
        });
        await _refreshPlaylists();
        return;
      }

      final playlists = await DatabaseHelper.instance.loadPlaylists();
      setState(() {
        _manualPlaylists = playlists;
        _loading = false;
      });
    } else {
      // Web: initialise the player (skip AudioService) and restore cached library.
      await _playback.init();
      final cachedSongs = await WebLibraryCache.instance.loadSongs();
      setState(() {
        _deviceSongs = cachedSongs;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _playback.dispose();
    _audioSettings.dispose();
    super.dispose();
  }

  void _playSong(List<Song> queue, int index) {
    _playback.playTrack(queue, index: index);
  }

  void _onSongReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final song = _deviceSongs.removeAt(oldIndex);
      _deviceSongs.insert(newIndex, song);
    });
    if (kIsWeb) {
      WebLibraryCache.instance.saveSongs(_deviceSongs);
    }
  }

  void _toggleFavorite(Song song) {
    final idx = _deviceSongs.indexWhere((s) => s.fileName == song.fileName);
    if (idx == -1) return;
    final updated = song.copyWith(isFavorite: !song.isFavorite);
    setState(() {
      _deviceSongs[idx] = updated;
    });
    // Keep the player's internal queue in sync so NowPlayingPage /
    // PlaybackBar heart icon reflects the change immediately.
    _playback.updateSong(updated);
    if (kIsWeb) {
      WebLibraryCache.instance.saveSongs(_deviceSongs);
    }
  }

  Future<void> _handleSongMenuAction(Song song, SongTileAction action) async {
    switch (action) {
      case SongTileAction.addToPlaylist:
        await _showAddToPlaylistSheet(song);
      case SongTileAction.addToAlbum:
        await _showAddToAlbumSheet(song);
      case SongTileAction.removeFromPlaylist:
        // Handled by _handleRemoveFromPlaylist via dedicated callback.
        break;
    }
  }

  Future<void> _handleRemoveFromPlaylist(Playlist playlist, Song song) async {
    if (playlist.id == null) return;
    await DatabaseHelper.instance.removeSongFromPlaylist(
      playlist.id!,
      song.fileName,
    );
    await _refreshPlaylists();
  }

  void _handleRemoveFromAlbum(Playlist albumPlaylist, Song song) {
    // Reset the song's album field so it no longer belongs to this album.
    final idx = _deviceSongs.indexWhere((s) => s.fileName == song.fileName);
    if (idx == -1) return;
    // Set album to empty string to remove from user-created album.
    setState(() {
      _deviceSongs[idx] = _deviceSongs[idx].copyWith(album: '');
    });
    if (kIsWeb) {
      WebLibraryCache.instance.saveSongs(_deviceSongs);
    }
  }

  Future<void> _showAddToPlaylistSheet(Song song) async {
    final theme = Theme.of(context);
    final playlists = _manualPlaylists.where((p) => p.id != null).toList();

    final result = await showModalBottomSheet<dynamic>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Add to Playlist',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              // New Playlist option
              ListTile(
                leading: Icon(Icons.add_rounded,
                    color: theme.colorScheme.primary),
                title: Text('New Playlist',
                    style: TextStyle(color: theme.colorScheme.onSurface)),
                onTap: () => Navigator.pop(ctx, 'new'),
              ),
              if (playlists.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No playlists yet',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                ...playlists.map((pl) => ListTile(
                      leading: Icon(Icons.playlist_play_rounded,
                          color: theme.colorScheme.primary),
                      title: Text(pl.name,
                          style:
                              TextStyle(color: theme.colorScheme.onSurface)),
                      subtitle: Text('${pl.songs.length} songs',
                          style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant)),
                      onTap: () => Navigator.pop(ctx, pl),
                    )),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (result == null) return;

    if (result == 'new') {
      // Create a new playlist then add the song
      await _showCreateEntryDialog(isPlaylist: true);
      // After creation, find the newest playlist and add the song
      final refreshed = await DatabaseHelper.instance.loadPlaylists();
      if (refreshed.isNotEmpty && refreshed.first.id != null) {
        await DatabaseHelper.instance
            .addSongsToPlaylist(refreshed.first.id!, [song]);
        await _refreshPlaylists();
      }
    } else if (result is Playlist && result.id != null) {
      await DatabaseHelper.instance
          .addSongsToPlaylist(result.id!, [song]);
      await _refreshPlaylists();
    }
  }

  Future<void> _showAddToAlbumSheet(Song song) async {
    final theme = Theme.of(context);
    final albumRows = await DatabaseHelper.instance.loadAlbums();

    if (!mounted) return;

    final result = await showModalBottomSheet<dynamic>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Add to Album',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(Icons.add_rounded,
                    color: theme.colorScheme.tertiary),
                title: Text('New Album',
                    style: TextStyle(color: theme.colorScheme.onSurface)),
                onTap: () => Navigator.pop(ctx, 'new'),
              ),
              if (albumRows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No albums yet',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                ...albumRows.map((row) => ListTile(
                      leading: Icon(Icons.album_rounded,
                          color: theme.colorScheme.tertiary),
                      title: Text(row['name'] as String,
                          style:
                              TextStyle(color: theme.colorScheme.onSurface)),
                      onTap: () => Navigator.pop(ctx, row),
                    )),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (result == null) return;

    if (result == 'new') {
      await _showCreateEntryDialog(isPlaylist: false);
      await _refreshPlaylists(); // also refreshes _manualAlbumNames
      // After creating a new album, find it and add the song to it.
      if (_manualAlbumNames.isNotEmpty) {
        final albumRows = await DatabaseHelper.instance.loadAlbums();
        if (albumRows.isNotEmpty) {
          final newestAlbumName = albumRows.first['name'] as String;
          final idx = _deviceSongs.indexWhere((s) => s.fileName == song.fileName);
          if (idx != -1) {
            setState(() {
              _deviceSongs[idx] = _deviceSongs[idx].copyWith(album: newestAlbumName);
            });
            if (kIsWeb) {
              WebLibraryCache.instance.saveSongs(_deviceSongs);
            }
          }
        }
      }
    } else if (result is Map<String, dynamic>) {
      // Update the song's album field to match the selected album name
      final albumName = result['name'] as String;
      final idx = _deviceSongs.indexWhere((s) => s.fileName == song.fileName);
      if (idx != -1) {
        setState(() {
          _deviceSongs[idx] = _deviceSongs[idx].copyWith(album: albumName);
        });
        if (kIsWeb) {
          WebLibraryCache.instance.saveSongs(_deviceSongs);
        }
      }
    }
  }

  void _onPlaylistReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final pl = _manualPlaylists.removeAt(oldIndex);
      _manualPlaylists.insert(newIndex, pl);
    });
  }

  void _onNavTap(int i) {
    setState(() => _currentTab = i);
  }

  Future<void> _refreshPlaylists() async {
    if (kIsWeb) return;
    final playlists = await DatabaseHelper.instance.loadPlaylists();
    // Resolve bare DB song records against the full library so playlist
    // songs carry duration, isFavorite, sampleRate, bitDepth, etc.
    final byFileName = <String, Song>{};
    for (final s in _deviceSongs) {
      byFileName[s.fileName] = s;
    }
    final enriched = playlists.map((pl) {
      final resolved = pl.songs.map((s) => byFileName[s.fileName] ?? s).toList();
      return Playlist(
        id: pl.id,
        name: pl.name,
        icon: pl.icon,
        songs: resolved,
        isSmart: pl.isSmart,
        coverArtPath: pl.coverArtPath,
        isManualCover: pl.isManualCover,
      );
    }).toList();
    setState(() => _manualPlaylists = enriched);

    // Also refresh user-created album names and cover art paths.
    final albumRows = await DatabaseHelper.instance.loadAlbums();
    final names = <String>{};
    final coverPaths = <String, String>{};
    for (final a in albumRows) {
      final name = a['name'] as String;
      names.add(name);
      final cover = a['cover_art_path'] as String?;
      if (cover != null && cover.isNotEmpty) {
        coverPaths[name] = cover;
      }
    }
    setState(() {
      _manualAlbumNames = names;
      _albumCoverArtPaths = coverPaths;
    });
  }

  // ── Create entry dialog (reusable for Playlist / Album) ──────────

  Future<void> _showCreateEntryDialog({required bool isPlaylist}) async {
    final nameController = TextEditingController();
    final type = isPlaylist ? 'Playlist' : 'Album';
    final accent = isPlaylist
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.tertiary;

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final isEmpty = nameController.text.trim().isEmpty;
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isPlaylist
                          ? Icons.queue_music_rounded
                          : Icons.album_rounded,
                      color: accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'New $type',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              content: TextField(
                controller: nameController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                cursorColor: accent,
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(
                  hintText: '$type name',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.07),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: accent.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: isEmpty
                      ? null
                      : () => Navigator.pop(ctx, nameController.text.trim()),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    disabledBackgroundColor: accent.withValues(alpha: 0.25),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Create',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (name == null || name.isEmpty) return;

    await DatabaseHelper.instance.saveNewContainer(name, isPlaylist: isPlaylist);
    await _refreshPlaylists();
  }

  Future<void> _showImportSheet() async {
    final confirmed = await _showImportConfirmDialog();
    if (confirmed != true) return;
    await _importFromFiles();
  }

  /// Shows a platform-adaptive confirmation dialog before launching the
  /// native audio file picker.
  Future<bool?> _showImportConfirmDialog() {
    final isApple = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
         defaultTargetPlatform == TargetPlatform.macOS);

    if (isApple) {
      return showCupertinoDialog<bool>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Import Music'),
          content: const Text(
            'Would you like to proceed with importing audio files '
            'from your device to the app?',
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Proceed'),
            ),
          ],
        ),
      );
    }

    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final accent = theme.colorScheme.primary;
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.library_music_rounded,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Import Music',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: Text(
            'Would you like to proceed with importing audio files '
            'from your device to the app?',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14.5,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Proceed',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _importFromFiles({Playlist? targetPlaylist}) async {
    // ── 1. Permission check (mobile only) ──────────────────────────
    if (!kIsWeb) {
      PermissionStatus status;
      if (Platform.isAndroid) {
        status = await Permission.audio.request();
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
      } else {
        status = await Permission.mediaLibrary.request();
      }

      if (status.isPermanentlyDenied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Audio permission permanently denied. '
                'Please enable it in Settings.',
              ),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Settings',
                onPressed: openAppSettings,
              ),
            ),
          );
        }
        return;
      }

      if (!status.isGranted && !status.isLimited) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Audio permission denied. Cannot import files.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }

    // ── 2. Pick files ──────────────────────────────────────────────
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg', 'wma', 'aiff', 'alac',
        ],
        allowMultiple: true,
        withData: kIsWeb,
      );
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import error: ${e.message ?? e.code}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (result == null || result.files.isEmpty) return;

    debugPrint('[WheedB Import] Picked ${result.files.length} file(s)');

    // ── 3. Optimistic insert: add placeholder songs immediately ────
    final placeholders = <Song>[];
    final pickedFiles = <PlatformFile>[];
    int skipped = 0;

    for (final file in result.files) {
      final String? filePath = kIsWeb ? null : file.path;
      final hasPath = filePath != null && filePath.isNotEmpty;
      final hasBytes = file.bytes != null && file.bytes!.isNotEmpty;

      if (!hasPath && !hasBytes) {
        skipped++;
        continue;
      }

      final fileName = file.name;
      final nameWithoutExt = p.basenameWithoutExtension(fileName);
      String title;
      String artist;
      if (nameWithoutExt.contains(' - ')) {
        final parts = nameWithoutExt.split(' - ');
        artist = parts.first.trim();
        title = parts.sublist(1).join(' - ').trim();
      } else {
        title = nameWithoutExt;
        artist = 'Unknown Artist';
      }

      placeholders.add(Song(
        title: title,
        artist: artist,
        album: 'Imported',
        fileName: fileName,
        filePath: filePath,
        audioBytes: kIsWeb ? file.bytes : null,
        importStatus: SongImportStatus.importing,
      ));
      pickedFiles.add(file);
    }

    if (placeholders.isEmpty) {
      if (mounted && skipped > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not access $skipped selected file${skipped == 1 ? '' : 's'}. '
              'Try selecting files from local storage.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // Insert placeholders into the list so the UI shows them instantly.
    if (kIsWeb) {
      final byName = {for (final s in _deviceSongs) s.fileName: s};
      for (final s in placeholders) {
        byName[s.fileName] = s;
      }
      setState(() => _deviceSongs = byName.values.toList());
    } else {
      setState(() => _deviceSongs = [..._deviceSongs, ...placeholders]);
    }

    // ── 4. Background: parse metadata per-track with error isolation ──
    int succeeded = 0;
    int failed = 0;

    for (int i = 0; i < placeholders.length; i++) {
      final placeholder = placeholders[i];
      final file = pickedFiles[i];

      try {
        // Parse header metadata.
        Uint8List headerBytes;
        int fileSize;

        if (kIsWeb) {
          headerBytes = file.bytes!;
          fileSize = file.bytes!.length;
        } else {
          final ioFile = File(placeholder.filePath!);
          fileSize = await ioFile.length();
          final raf = await ioFile.open(mode: FileMode.read);
          headerBytes = await raf.read(min(8192, fileSize));
          await raf.close();
        }

        final meta = AudioMetadataParser.parse(
          headerBytes, placeholder.fileName, fileSize: fileSize,
        );

        Duration duration = meta.duration ?? Duration.zero;

        // On web, fall back to Audio element probing for duration.
        if (kIsWeb && duration == Duration.zero && placeholder.audioBytes != null) {
          final probed = await AudioProber.probeDuration(
            bytes: placeholder.audioBytes,
            fileName: placeholder.fileName,
          );
          if (probed != null) duration = probed;
        }

        final ready = placeholder.copyWith(
          sampleRateHz: meta.sampleRateHz,
          bitDepth: meta.bitDepth,
          duration: duration,
          importStatus: SongImportStatus.ready,
        );

        // Swap the placeholder in the list (single-item update).
        _replaceSongByFileName(placeholder.fileName, ready);
        succeeded++;

        debugPrint('[WheedB Import] ✓ "${ready.title}" '
            '${meta.sampleRateHz}Hz/${meta.bitDepth}-bit '
            '${duration.inSeconds}s');
      } catch (e) {
        // Mark this single track as failed — other tracks keep going.
        debugPrint('[WheedB Import] ✗ "${placeholder.title}": $e');
        _replaceSongByFileName(
          placeholder.fileName,
          placeholder.copyWith(importStatus: SongImportStatus.failed),
        );
        failed++;
      }
    }

    // ── 5. Playlist association (mobile only) ──────────────────────
    final readySongs = _deviceSongs
        .where((s) => placeholders.any((p) => p.fileName == s.fileName) &&
            s.importStatus == SongImportStatus.ready)
        .toList();

    if (!kIsWeb && targetPlaylist != null && targetPlaylist.id != null &&
        readySongs.isNotEmpty) {
      await DatabaseHelper.instance
          .addSongsToPlaylist(targetPlaylist.id!, readySongs);

      if (!targetPlaylist.isManualCover) {
        final filePaths = readySongs
            .where((s) => s.filePath != null)
            .map((s) => s.filePath!)
            .toList();
        final artPath = await CoverArtExtractor.instance.extractAndSave(
          filePaths: filePaths,
          collectionId: targetPlaylist.id!,
          collectionType: 'playlist',
        );
        if (artPath != null) {
          await DatabaseHelper.instance.updateCoverArt(
            id: targetPlaylist.id!,
            isPlaylist: true,
            path: artPath,
          );
        }
      }
      await _refreshPlaylists();
    }

    // ── 6. Remove failed tracks, persist to IndexedDB ─────────────
    setState(() {
      _deviceSongs = _deviceSongs
          .where((s) => s.importStatus != SongImportStatus.failed)
          .toList();
    });

    if (kIsWeb) {
      WebLibraryCache.instance.saveSongs(_deviceSongs);
    }

    debugPrint('[WheedB Import] Done: $succeeded ok, $failed failed, '
        '$skipped skipped. Total: ${_deviceSongs.length}');

    if (mounted) {
      final parts = <String>[];
      if (succeeded > 0) {
        parts.add('Imported $succeeded song${succeeded == 1 ? '' : 's'}');
      }
      if (failed > 0) parts.add('$failed failed');
      if (skipped > 0) parts.add('$skipped skipped');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(parts.join(' · ')),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Swap a single song in [_deviceSongs] by fileName and trigger a
  /// minimal setState. Only the affected SongTile rebuilds because the
  /// list identity stays the same and RepaintBoundary isolates items.
  void _replaceSongByFileName(String fileName, Song replacement) {
    final idx = _deviceSongs.indexWhere((s) => s.fileName == fileName);
    if (idx == -1) return;
    setState(() {
      _deviceSongs[idx] = replacement;
    });
  }

  // ── Per-playlist card action handler ─────────────────────────────

  Future<void> _handlePlaylistCardAction(
      String playlistName, PlaylistCardAction action) async {
    // Look up the playlist id from the in-memory list.
    final pl = _manualPlaylists.cast<Playlist?>().firstWhere(
          (p) => p!.name == playlistName,
          orElse: () => null,
        );
    if (pl == null || pl.id == null) return;
    final item = (id: pl.id!, name: playlistName);

    switch (action) {
      case PlaylistCardAction.rename:
        await _showRenameForItem(item: item, isPlaylist: true);
      case PlaylistCardAction.addPicture:
        await _showAddPictureForItem(item: item, isPlaylist: true);
      case PlaylistCardAction.delete:
        await _showDeleteForItem(item: item, isPlaylist: true);
    }
  }

  // ── Per-album card action handler ────────────────────────────────

  Future<void> _handleAlbumCardAction(
      String albumName, AlbumCardAction action) async {
    // Look up the album id from the DB.
    final albums = await DatabaseHelper.instance.loadAlbums();
    final row = albums.cast<Map<String, dynamic>?>().firstWhere(
          (a) => a!['name'] as String == albumName,
          orElse: () => null,
        );
    if (row == null) return;
    final item = (id: row['id'] as int, name: albumName);

    switch (action) {
      case AlbumCardAction.rename:
        await _showRenameForItem(item: item, isPlaylist: false);
      case AlbumCardAction.addPicture:
        await _showAddPictureForItem(item: item, isPlaylist: false);
      case AlbumCardAction.delete:
        await _showDeleteForItem(item: item, isPlaylist: false);
    }
  }

  // ── Rename ───────────────────────────────────────────────────────

  Future<void> _showRenameForItem({
    required ({int id, String name}) item,
    required bool isPlaylist,
  }) async {
    final controller = TextEditingController(text: item.name);
    final type = isPlaylist ? 'Playlist' : 'Album';
    final accent = isPlaylist
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.tertiary;

    if (!mounted) return;
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final isEmpty = controller.text.trim().isEmpty;
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child:
                        Icon(Icons.edit_rounded, color: accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Rename $type',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              content: TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                cursorColor: accent,
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(
                  hintText: 'New name',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.07),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: accent.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: isEmpty
                      ? null
                      : () =>
                          Navigator.pop(ctx, controller.text.trim()),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    disabledBackgroundColor:
                        accent.withValues(alpha: 0.25),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Rename',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (newName == null || newName.isEmpty) return;
    await DatabaseHelper.instance
        .renameContainer(item.id, newName, isPlaylist: isPlaylist);
    await _refreshPlaylists();
  }

  // ── Add Picture ──────────────────────────────────────────────────

  Future<void> _showAddPictureForItem({
    required ({int id, String name}) item,
    required bool isPlaylist,
  }) async {

    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (image == null) return;

    if (kIsWeb) return; // File I/O not available on web

    final appDir = await getApplicationDocumentsDirectory();
    final type = isPlaylist ? 'playlist' : 'album';
    final destPath = '${appDir.path}/cover_art/${type}_${item.id}.jpg';
    final destFile = File(destPath);

    // Ensure the directory exists.
    await destFile.parent.create(recursive: true);

    // Remove any previous cover (auto or manual) before copying.
    if (destFile.existsSync()) {
      await destFile.delete();
    }

    await File(image.path).copy(destPath);

    // Persist path + manual flag so auto-extraction won't overwrite.
    await DatabaseHelper.instance.updateCoverArt(
      id: item.id,
      isPlaylist: isPlaylist,
      path: destPath,
      isManual: true,
    );
    await _refreshPlaylists();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cover updated for "${item.name}"'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Delete ───────────────────────────────────────────────────────

  Future<void> _showDeleteForItem({
    required ({int id, String name}) item,
    required bool isPlaylist,
  }) async {
    final type = isPlaylist ? 'Playlist' : 'Album';

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.delete_rounded,
                    color: Colors.redAccent, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'Delete $type',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to delete "${item.name}"?\n'
            'This action cannot be undone.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14.5,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Delete',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    await DatabaseHelper.instance
        .deleteContainer(item.id, isPlaylist: isPlaylist);
    await _refreshPlaylists();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: _currentTab == 1
            ? IconButton(
                icon: const Icon(Icons.add_rounded),
                tooltip: _libraryTabIndex == 0 ? 'Create Playlist' : 'Create Album',
                onPressed: () {
                  _showCreateEntryDialog(isPlaylist: _libraryTabIndex == 0);
                },
              )
            : IconButton(
                icon: const Icon(Icons.add_rounded),
                tooltip: 'Import files',
                onPressed: () => _showImportSheet(),
              ),
        title: Text(
          _currentTab == 0 ? 'MUSIC' : 'LIBRARY',
          style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.2),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_currentTab == 0)
            IconButton(
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: 'Options',
              onPressed: () => OptionsMenuSheet.show(context, _audioSettings),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListenableBuilder(
                    listenable: _playback,
                    builder: (context, _) {
                      final nowPlaying = _playback.currentSong;
                      return IndexedStack(
                        // Tab 0 = Music, Tab 2 = Library (1 is the create overlay).
                        index: _currentTab == 1 ? 1 : 0,
                        children: [
                          SongsScreen(
                            songs: _deviceSongs,
                            onSongTap: _playSong,
                            onReorder: _onSongReorder,
                            onFavoriteToggle: _toggleFavorite,
                            onMenuAction: _handleSongMenuAction,
                            nowPlaying: nowPlaying,
                          ),
                          LibraryPage(
                            library: _deviceSongs,
                            manualPlaylists: _manualPlaylists,
                            manualAlbumNames: _manualAlbumNames,
                            albumCoverArtPaths: _albumCoverArtPaths,
                            onSongTap: _playSong,
                            onFavoriteToggle: _toggleFavorite,
                            onMenuAction: _handleSongMenuAction,
                            onRemoveFromPlaylist: _handleRemoveFromPlaylist,
                            onRemoveFromAlbum: _handleRemoveFromAlbum,
                            nowPlaying: nowPlaying,
                            controller: _playback,
                            onTabChanged: (i) =>
                                setState(() => _libraryTabIndex = i),
                            onPlaylistReorder: _onPlaylistReorder,
                            onAlbumCardAction: _handleAlbumCardAction,
                            onPlaylistCardAction: _handlePlaylistCardAction,
                          ),
                        ],
                      );
                    },
                  ),
                ),
                RepaintBoundary(
                  child: PlaybackBar(controller: _playback, onSongMenuAction: _handleSongMenuAction, onFavoriteToggle: _toggleFavorite),
                ),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: _onNavTap,
        backgroundColor: theme.colorScheme.surfaceContainer,
        indicatorColor: theme.colorScheme.primary.withValues(alpha: 0.18),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.music_note_outlined),
            selectedIcon: Icon(Icons.music_note_rounded),
            label: 'Music',
          ),
          const NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music_rounded),
            label: 'Library',
          ),
        ],
      ),
    );
  }
}
