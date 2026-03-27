import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'controllers/music_player_controller.dart';
import 'models/audio_settings.dart';
import 'models/playlist.dart';
import 'models/song.dart';
import 'screens/library_page.dart';
import 'screens/songs_screen.dart';
import 'services/database_helper.dart';
import 'services/cover_art_extractor.dart';
import 'services/device_music_scanner.dart';
import 'widgets/import_music_sheet.dart';
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
  }

  @override
  void dispose() {
    _playback.dispose();
    _audioSettings.dispose();
    super.dispose();
  }

  Future<void> _playSong(List<Song> queue, int index) async {
    await _playback.loadQueue(queue, startIndex: index);
    await _playback.togglePlayPause();
  }

  void _onNavTap(int i) {
    setState(() => _currentTab = i);
  }

  Future<void> _refreshPlaylists() async {
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
    final confirmed = await ImportMusicSheet.show(context);
    if (confirmed != true) return; // dismissed
    await _importFromFiles();
  }

  Future<void> _importFromFiles({Playlist? targetPlaylist}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'flac'],
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) return; // user cancelled

    final imported = <Song>[];
    for (final file in result.files) {
      if (file.path == null) continue;

      final fileName = file.name;
      final nameWithoutExt = p.basenameWithoutExtension(fileName);

      // Best-effort title/artist split on " - " convention.
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

      imported.add(Song(
        title: title,
        artist: artist,
        album: 'Imported',
        fileName: fileName,
        filePath: file.path,
      ));
    }

    if (imported.isEmpty) return;

    if (targetPlaylist != null && targetPlaylist.id != null) {
      // Add to specific playlist in the database.
      await DatabaseHelper.instance
          .addSongsToPlaylist(targetPlaylist.id!, imported);

      // Auto-extract cover art only when the user hasn't manually set one.
      if (!targetPlaylist.isManualCover) {
        final filePaths = imported
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

    // Always add to the in-memory library so songs are playable.
    setState(() {
      _deviceSongs = [..._deviceSongs, ...imported];
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
                      SongsScreen(songs: _deviceSongs, onSongTap: _playSong),
                      LibraryPage(
                        library: _deviceSongs,
                        manualPlaylists: _manualPlaylists,
                        onSongTap: _playSong,
                        onTabChanged: (i) =>
                            setState(() => _libraryTabIndex = i),
                      ),
                    ],
                  ),
                ),
                PlaybackBar(controller: _playback),
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
