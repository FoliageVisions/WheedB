import 'dart:io';
import 'dart:math' show min;
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'controllers/music_player_controller.dart';
import 'models/audio_settings.dart';
import 'models/playlist.dart';
import 'models/song.dart';
import 'screens/library_page.dart';
import 'screens/songs_screen.dart';
import 'services/audio_metadata.dart';
import 'services/audio_prober.dart';
import 'services/database_helper.dart';
import 'services/cover_art_extractor.dart';
import 'services/device_music_scanner.dart';
import 'services/web_library_cache.dart';
import 'widgets/options_menu_sheet.dart';
import 'widgets/playback_bar.dart';

void main() {
  runApp(const WheedBApp());
}

class WheedBApp extends StatelessWidget {
  const WheedBApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WheedB',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

/// Actions available from the Library three-dots menu.
enum _LibraryAction { rename, addPicture, delete }

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
        final playlists = await DatabaseHelper.instance.loadPlaylists();
        setState(() {
          _deviceSongs = songs;
          _manualPlaylists = playlists;
          _loading = false;
        });
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
    setState(() => _manualPlaylists = playlists);
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

  // ── Library three-dots action handlers ───────────────────────────

  void _handleLibraryAction(_LibraryAction action) {
    final isPlaylist = _libraryTabIndex == 0;
    switch (action) {
      case _LibraryAction.rename:
        _showRenameDialog(isPlaylist: isPlaylist);
      case _LibraryAction.addPicture:
        _showAddPictureFlow(isPlaylist: isPlaylist);
      case _LibraryAction.delete:
        _showDeleteDialog(isPlaylist: isPlaylist);
    }
  }

  /// Shows a picker bottom sheet and returns the selected item, or null.
  Future<({int id, String name})?> _pickItem({
    required bool isPlaylist,
  }) async {
    final type = isPlaylist ? 'playlist' : 'album';
    List<({int id, String name})> items;

    if (isPlaylist) {
      items = _manualPlaylists
          .where((p) => p.id != null)
          .map((p) => (id: p.id!, name: p.name))
          .toList();
    } else {
      final albums = await DatabaseHelper.instance.loadAlbums();
      items = albums
          .map((a) => (id: a['id'] as int, name: a['name'] as String))
          .toList();
    }

    if (items.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No ${type}s to manage'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return null;
    }

    // Skip picker if there's only one item.
    if (items.length == 1) return items.first;

    if (!mounted) return null;
    return showModalBottomSheet<({int id, String name})>(
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
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Select ${type[0].toUpperCase()}${type.substring(1)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              for (final item in items)
                ListTile(
                  leading: Icon(
                    isPlaylist
                        ? Icons.queue_music_rounded
                        : Icons.album_rounded,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  title: Text(
                    item.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.pop(ctx, item),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ── Rename ───────────────────────────────────────────────────────

  Future<void> _showRenameDialog({required bool isPlaylist}) async {
    final item = await _pickItem(isPlaylist: isPlaylist);
    if (item == null) return;

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

  Future<void> _showAddPictureFlow({required bool isPlaylist}) async {
    final item = await _pickItem(isPlaylist: isPlaylist);
    if (item == null) return;

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

  Future<void> _showDeleteDialog({required bool isPlaylist}) async {
    final item = await _pickItem(isPlaylist: isPlaylist);
    if (item == null) return;

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
            ? PopupMenuButton<bool>(
                icon: const Icon(Icons.add_rounded),
                tooltip: 'Create new',
                color: const Color(0xFF1E1E1E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                offset: const Offset(8, 48),
                onSelected: (isPlaylist) {
                  _showCreateEntryDialog(isPlaylist: isPlaylist);
                },
                itemBuilder: (context) => [
                  _buildPopupItem(
                    icon: Icons.queue_music_rounded,
                    label: 'Create Playlist',
                    color: theme.colorScheme.primary,
                    value: true,
                  ),
                  _buildPopupItem(
                    icon: Icons.album_rounded,
                    label: 'Create Album',
                    color: theme.colorScheme.tertiary,
                    value: false,
                  ),
                ],
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
            )
          else
            PopupMenuButton<_LibraryAction>(
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: 'Actions',
              color: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              offset: const Offset(-8, 48),
              onSelected: _handleLibraryAction,
              itemBuilder: (_) {
                final label =
                    _libraryTabIndex == 0 ? 'Playlist' : 'Album';
                return [
                  _buildPopupItem<_LibraryAction>(
                    icon: Icons.edit_rounded,
                    label: 'Rename $label',
                    color: theme.colorScheme.primary,
                    value: _LibraryAction.rename,
                  ),
                  _buildPopupItem<_LibraryAction>(
                    icon: Icons.image_rounded,
                    label: 'Add $label Picture',
                    color: theme.colorScheme.secondary,
                    value: _LibraryAction.addPicture,
                  ),
                  _buildPopupItem<_LibraryAction>(
                    icon: Icons.delete_rounded,
                    label: 'Delete $label',
                    color: Colors.redAccent,
                    value: _LibraryAction.delete,
                  ),
                ];
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: IndexedStack(
                    // Tab 0 = Music, Tab 2 = Library (1 is the create overlay).
                    index: _currentTab == 1 ? 1 : 0,
                    children: [
                      SongsScreen(
                        songs: _deviceSongs,
                        onSongTap: _playSong,
                        onReorder: _onSongReorder,
                      ),
                      LibraryPage(
                        library: _deviceSongs,
                        manualPlaylists: _manualPlaylists,
                        onSongTap: _playSong,
                        onTabChanged: (i) =>
                            setState(() => _libraryTabIndex = i),
                        onPlaylistReorder: _onPlaylistReorder,
                      ),
                    ],
                  ),
                ),
                RepaintBoundary(
                  child: PlaybackBar(controller: _playback),
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

  PopupMenuEntry<T> _buildPopupItem<T>({
    required IconData icon,
    required String label,
    required Color color,
    required T value,
  }) {
    return PopupMenuItem<T>(
      value: value,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14.5,
            ),
          ),
        ],
      ),
    );
  }
}
