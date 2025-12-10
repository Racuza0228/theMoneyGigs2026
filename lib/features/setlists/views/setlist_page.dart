import 'package:flutter/material.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:the_money_gigs/features/setlists/models/setlist_model.dart';
import 'package:the_money_gigs/features/setlists/models/song_model.dart';
import 'package:the_money_gigs/features/setlists/views/widgets/song_editor_dialog.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class SetlistPage extends StatefulWidget {
  final Gig gig;

  const SetlistPage({
    super.key,
    required this.gig,
  });

  @override
  State<SetlistPage> createState() => _SetlistPageState();
}

class _SetlistPageState extends State<SetlistPage> {
  late Setlist _setlist;
  late List<Song> _allSongs;
  late Gig _currentGig; // Local, mutable copy of the gig

  bool _isLoading = true;
  String _errorMessage = '';

  // FIX: Define all necessary preference keys
  static const String _setlistsPrefsKey = 'setlists';
  static const String _gigsPrefsKey = 'gigs_list';

  @override
  void initState() {
    super.initState();
    _currentGig = widget.gig; // Initialize the local copy from the widget
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      _allSongs = await Song.loadSongs();

      final setlistsJson = prefs.getString(_setlistsPrefsKey) ?? '[]';
      final List<Setlist> allSetlists = Setlist.decode(setlistsJson);

      final existingSetlist = allSetlists.cast<Setlist?>().firstWhere(
            (s) => s?.gigId == _currentGig.id,
        orElse: () => null,
      );

      if (existingSetlist != null) {
        _setlist = existingSetlist;

        // Migration Logic: If the gig object is missing the link, create it.
        if (_currentGig.setlistId == null || _currentGig.setlistId!.isEmpty) {
          final gigsJson = prefs.getString(_gigsPrefsKey) ?? '[]';
          List<Gig> allGigs = Gig.decode(gigsJson);
          final gigIndex = allGigs.indexWhere((g) => g.id == _currentGig.id);

          if (gigIndex != -1) {
            final updatedGig = allGigs[gigIndex].copyWith(setlistId: _setlist.id);
            allGigs[gigIndex] = updatedGig;
            print("MIGRATING: Linked setlist ${_setlist.id} to gig ${_currentGig.id}");
            await prefs.setString(_gigsPrefsKey, Gig.encode(allGigs));

            // Update the local state to reflect the migration
            setState(() {
              _currentGig = updatedGig;
            });
          }
        }
      } else {
        // No existing setlist was found, so create a brand new one in memory.
        _setlist = Setlist(
          id: const Uuid().v4(),
          name: '${_currentGig.venueName} Setlist',
          gigId: _currentGig.id,
          sets: [], // The constructor adds a default "Set 1"
        );
      }

      _cleanupSongIds();
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _errorMessage = "Failed to load page data: $e";
        _isLoading = false;
      });
    }
  }

  void _cleanupSongIds() {
    final allSongIdsSet = _allSongs.map((s) => s.id).toSet();
    for (var set in _setlist.sets) {
      set.songIds.retainWhere((songId) => allSongIdsSet.contains(songId));
    }
  }

  Future<void> _saveAllData() async {
    await Song.saveSongs(_allSongs);

    final prefs = await SharedPreferences.getInstance();
    final setlistsJson = prefs.getString(_setlistsPrefsKey) ?? '[]';
    final List<Setlist> allSetlists = Setlist.decode(setlistsJson);

    final index = allSetlists.indexWhere((s) => s.id == _setlist.id);
    if (index != -1) {
      allSetlists[index] = _setlist;
    } else {
      allSetlists.add(_setlist);
    }
    await prefs.setString(_setlistsPrefsKey, Setlist.encode(allSetlists));

    // Update the Gig with the setlistId
    final gigsJson = prefs.getString(_gigsPrefsKey) ?? '[]';
    List<Gig> allGigs = Gig.decode(gigsJson);
    final gigIndex = allGigs.indexWhere((g) => g.id == _currentGig.id);

    if (gigIndex != -1) {
      final updatedGig = allGigs[gigIndex].copyWith(setlistId: _setlist.id);
      allGigs[gigIndex] = updatedGig;
      await prefs.setString(_gigsPrefsKey, Gig.encode(allGigs));

      // Update the local state but do NOT pop the navigator here
      setState(() {
        _currentGig = updatedGig;
      });
    }
  }

  void _addSet() {
    setState(() {
      final newSetName = 'Set ${_setlist.sets.length + 1}';
      _setlist.sets.add(SongSet(id: const Uuid().v4(), name: newSetName, songIds: []));
    });
    _saveAllData();
  }

  void _renameSet(SongSet songSet) async {
    final newName = await _showRenameDialog(songSet.name);
    if (newName != null && newName.isNotEmpty && newName != songSet.name) {
      setState(() {
        songSet.name = newName;
      });
      _saveAllData();
    }
  }

  void _deleteSet(SongSet songSet) {
    if (_setlist.sets.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must have at least one set.'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() {
      _setlist.sets.removeWhere((s) => s.id == songSet.id);
    });
    _saveAllData();
  }

  void _renameSetlist() async {
    final newName = await _showRenameDialog(_setlist.name);
    if (newName != null && newName.isNotEmpty && newName != _setlist.name) {
      setState(() {
        _setlist.name = newName;
      });
      _saveAllData();
    }
  }

  void _showSongEditorDialog({Song? song, SongSet? targetSet}) async {
    final result = await showDialog<Song>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SongEditorDialog(
        song: song,
        allSongs: _allSongs,
      ),
    );

    if (result != null) {
      setState(() {
        final songIndex = _allSongs.indexWhere((s) => s.id == result.id);
        if (songIndex != -1) {
          _allSongs[songIndex] = result;
        } else {
          _allSongs.add(result);
          final set = targetSet ?? _setlist.sets.first;
          set.songIds.add(result.id);
        }
      });
      _saveAllData();
    }
  }

  void _deleteSong(String songId, SongSet fromSet) {
    setState(() {
      fromSet.songIds.remove(songId);
    });
    _saveAllData();
  }

  Duration _calculateSetDuration(SongSet songSet) {
    return songSet.songIds.fold(Duration.zero, (previousValue, songId) {
      final song = _getSongById(songId);
      return previousValue + (song.duration ?? Duration.zero);
    });
  }

  Song _getSongById(String id) {
    return _allSongs.firstWhere((s) => s.id == id, orElse: () => Song(id: 'err', title: 'Unknown Song'));
  }

  void _showLoadSetlistDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final setlistsJson = prefs.getString(_setlistsPrefsKey) ?? '[]';
    final List<Setlist> allSetlists = Setlist.decode(setlistsJson);

    final List<Setlist> availableSetlists = allSetlists.where((s) => s.id != _setlist.id).toList();

    final selectedSetlist = await showDialog<Setlist>(
      context: context,
      builder: (context) => _LoadSetlistDialog(setlists: availableSetlists),
    );

    if (selectedSetlist != null) {
      _importSetlist(selectedSetlist);
    }
  }

  void _importSetlist(Setlist importedSetlist) {
    setState(() {
      final newSets = importedSetlist.sets.map((set) {
        return SongSet(
          id: const Uuid().v4(),
          name: set.name,
          songIds: List<String>.from(set.songIds),
        );
      }).toList();

      _setlist.name = importedSetlist.name;
      _setlist.sets = newSets;

      _cleanupSongIds();
    });

    _saveAllData();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${importedSetlist.name}" loaded successfully.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String formatGigLength(double hours) {
      if (hours <= 0) return 'Gig Time: Not set';
      if (hours == hours.truncate()) {
        return 'Gig Time: ${hours.toInt()} hour${hours == 1 ? '' : 's'}';
      }
      return 'Gig Time: $hours hours';
    }

    const double fabHeight = 56.0;
    const double fabPadding = 16.0;
    const double bottomPaddingForFab = fabHeight + (fabPadding * 2);

    return Scaffold(
      appBar: AppBar(
        // This is the key to returning the updated gig object to the previous page
        leading: BackButton(onPressed: () => Navigator.pop(context, _currentGig)),
        title: Text(_isLoading ? 'SETLIST' : _setlist.name.toUpperCase()),
        centerTitle: true,
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Rename Setlist',
              onPressed: _renameSetlist,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.red)))
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentGig.venueName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat.yMMMEd().add_jm().format(_currentGig.dateTime),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 4),
                Text(
                  formatGigLength(_currentGig.gigLengthHours),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: bottomPaddingForFab),
              child: CustomScrollView(
                slivers: [
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                          (context, setIndex) {
                        final songSet = _setlist.sets[setIndex];
                        return _buildSetCard(songSet);
                      },
                      childCount: _setlist.sets.length,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            onPressed: _showLoadSetlistDialog,
            heroTag: 'load_setlist_fab',
            label: const Text('Load Setlist'),
            icon: const Icon(Icons.folder_open),
          ),
          const SizedBox(width: 16),
          FloatingActionButton.extended(
            onPressed: _addSet,
            heroTag: 'add_set_fab',
            label: const Text('Add Set'),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Widget _buildSetCard(SongSet songSet) {
    bool hasKeyWarning = false;
    bool hasTempoWarning = false;

    for (int i = 1; i < songSet.songIds.length; i++) {
      final currentSong = _getSongById(songSet.songIds[i]);
      final previousSong = _getSongById(songSet.songIds[i - 1]);

      if (!hasKeyWarning && currentSong.songKey != null && currentSong.songKey == previousSong.songKey) {
        hasKeyWarning = true;
      }

      if (!hasTempoWarning && currentSong.tempo != null && previousSong.tempo != null) {
        final double difference = (currentSong.tempo! - previousSong.tempo!).abs().toDouble();
        final double threshold = previousSong.tempo! * 0.1;
        if (difference <= threshold) {
          hasTempoWarning = true;
        }
      }

      if (hasKeyWarning && hasTempoWarning) break;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSetHeader(songSet),
          if (songSet.songIds.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(child: Text('No songs in ${songSet.name}.')),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: songSet.songIds.length,
              itemBuilder: (context, songIndex) {
                final songId = songSet.songIds[songIndex];
                final song = _getSongById(songId);
                return _buildSongTile(song, songSet, songIndex);
              },
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final String item = songSet.songIds.removeAt(oldIndex);
                  songSet.songIds.insert(newIndex, item);
                });
                _saveAllData();
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 0, 8.0, 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (hasKeyWarning)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.yellow.shade700, size: 18),
                            const SizedBox(width: 6),
                            Text('Same Key', style: TextStyle(color: Colors.yellow.shade700, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    if (hasTempoWarning)
                      Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.yellow.shade700, size: 18),
                          const SizedBox(width: 6),
                          Text('Same Tempo', style: TextStyle(color: Colors.yellow.shade700, fontWeight: FontWeight.bold)),
                        ],
                      ),
                  ],
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  label: const Text('Add Song'),
                  onPressed: () => _showSongEditorDialog(targetSet: songSet),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetHeader(SongSet songSet) {
    final setDuration = _calculateSetDuration(songSet);

    String formatSetDuration(Duration duration) {
      if (duration == Duration.zero) return '';
      String twoDigits(int n) => n.toString().padLeft(2, '0');
      final minutes = twoDigits(duration.inMinutes.remainder(60));
      final seconds = twoDigits(duration.inSeconds.remainder(60));
      return '$minutes:$seconds';
    }

    return Container(
      padding: const EdgeInsets.only(left: 16),
      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              songSet.name,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Row(
            children: [
              if (setDuration > Duration.zero)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Text(
                    formatSetDuration(setDuration),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.secondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              IconButton(icon: const Icon(Icons.edit, size: 20), tooltip: 'Rename Set', onPressed: () => _renameSet(songSet)),
              IconButton(icon: Icon(Icons.delete_forever, size: 20, color: Colors.red.shade400), tooltip: 'Delete Set', onPressed: () => _deleteSet(songSet)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSongTile(Song song, SongSet songSet, int index) {
    String formatDuration(Duration? d) => d == null ? '--:--' : '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

    bool showKeyWarning = false;
    bool showTempoWarning = false;

    if (index > 0) {
      final previousSong = _getSongById(songSet.songIds[index - 1]);
      if (song.songKey != null && song.songKey == previousSong.songKey) {
        showKeyWarning = true;
      }
      if (song.tempo != null && previousSong.tempo != null) {
        if ((song.tempo! - previousSong.tempo!).abs() <= previousSong.tempo! * 0.1) {
          showTempoWarning = true;
        }
      }
    }

    if (index < songSet.songIds.length - 1) {
      final nextSong = _getSongById(songSet.songIds[index + 1]);
      if (song.songKey != null && song.songKey == nextSong.songKey) {
        showKeyWarning = true;
      }
      if (song.tempo != null && nextSong.tempo != null) {
        if ((song.tempo! - nextSong.tempo!).abs() <= song.tempo! * 0.1) {
          showTempoWarning = true;
        }
      }
    }

    Widget buildSubtitle() {
      Widget separator() => const Text(' / ', style: TextStyle(color: Colors.grey));

      Widget warningText(String text, bool showWarning) {
        return Container(
          padding: showWarning ? const EdgeInsets.symmetric(horizontal: 4, vertical: 1) : EdgeInsets.zero,
          decoration: BoxDecoration(
            color: showWarning ? Colors.yellow.shade600 : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            text,
            style: TextStyle(color: showWarning ? Colors.black : null),
          ),
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (song.artist != null && song.artist!.isNotEmpty)
            Flexible(
              child: Text(song.artist!, overflow: TextOverflow.ellipsis, softWrap: false),
            ),

          if (song.songKey != null && song.songKey!.isNotEmpty) ...[
            if (song.artist != null && song.artist!.isNotEmpty) separator(),
            warningText(song.songKey!, showKeyWarning),
          ],

          if (song.tempo != null) ...[
            separator(),
            warningText('${song.tempo} bpm', showTempoWarning),
          ],
        ],
      );
    }

    return ListTile(
      key: ValueKey('${songSet.id}-${song.id}'),
      leading: CircleAvatar(child: Text('${index + 1}')),
      title: Text(song.title),
      subtitle: buildSubtitle(),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(formatDuration(song.duration)),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.edit_outlined, size: 20), tooltip: 'Edit Song', onPressed: () => _showSongEditorDialog(song: song)),
          IconButton(icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade300), tooltip: 'Remove from Set', onPressed: () => _deleteSong(song.id, songSet)),
        ],
      ),
    );
  }

  Future<String?> _showRenameDialog(String currentName) async {
    final controller = TextEditingController(text: currentName);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Set'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Rename')),
        ],
      ),
    );
  }
}

/// A dialog widget for searching and selecting a setlist to load.
class _LoadSetlistDialog extends StatefulWidget {
  final List<Setlist> setlists;

  const _LoadSetlistDialog({required this.setlists});

  @override
  State<_LoadSetlistDialog> createState() => _LoadSetlistDialogState();
}

class _LoadSetlistDialogState extends State<_LoadSetlistDialog> {
  late List<Setlist> _filteredSetlists;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredSetlists = widget.setlists;
    _searchController.addListener(_filterSetlists);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterSetlists() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredSetlists = widget.setlists.where((setlist) {
        return setlist.name.toLowerCase().contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Load a Previous Setlist'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Search setlists...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _filteredSetlists.isEmpty
                  ? const Center(child: Text('No matching setlists found.'))
                  : ListView.builder(
                shrinkWrap: true,
                itemCount: _filteredSetlists.length,
                itemBuilder: (context, index) {
                  final setlist = _filteredSetlists[index];
                  return Card(
                    child: ListTile(
                      title: Text(setlist.name),
                      subtitle: Text('${setlist.totalSongCount} songs in ${setlist.sets.length} sets'),
                      onTap: () {
                        // When tapped, pop the dialog and return the selected setlist
                        Navigator.of(context).pop(setlist);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
