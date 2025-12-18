// lib/features/setlists/views/widgets/song_editor_dialog.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/song_model.dart';
import 'package:the_money_gigs/core/services/music_facts_service.dart';
import 'package:uuid/uuid.dart';

class SongEditorDialog extends StatefulWidget {
  final Song? song; // If null, we're creating a new song
  final List<Song> allSongs;
  final String? venueCity; // Optional: City where performance is happening

  const SongEditorDialog({
    super.key,
    this.song,
    required this.allSongs,
    this.venueCity,
  });

  @override
  State<SongEditorDialog> createState() => _SongEditorDialogState();
}

class _SongEditorDialogState extends State<SongEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _artistController;
  late TextEditingController _tempoController;
  late TextEditingController _durationMinController;
  late TextEditingController _durationSecController;
  late TextEditingController _notesController;

  // This will hold the song selected from the autocomplete list.
  Song? _selectedExistingSong;
  Timer? _debounce;
  bool _isLoadingFacts = false;

  String? _selectedKeyNote;
  bool _isMinor = false;
  final List<String> _validKeyNotes = [
    'C', 'C#', 'Db', 'D', 'D#', 'Eb', 'E', 'F', 'F#', 'Gb', 'G', 'G#', 'Ab', 'A', 'A#', 'Bb', 'B'
  ];

  bool get _isEditing => widget.song != null;

  @override
  void initState() {
    super.initState();
    final initialSong = widget.song;

    // Initialize controllers
    _titleController = TextEditingController(text: initialSong?.title);
    _artistController = TextEditingController(text: initialSong?.artist);
    _tempoController = TextEditingController(text: initialSong?.tempo?.toString());
    _notesController = TextEditingController(text: initialSong?.notes);

    // If we are editing, lock the song selection to the initial song
    if (_isEditing) {
      _selectedExistingSong = initialSong;
    }

    // Parse initial song key
    if (initialSong?.songKey != null && initialSong!.songKey!.isNotEmpty) {
      final note = initialSong.songKey!.replaceAll('m', '');
      if (_validKeyNotes.contains(note)) {
        _selectedKeyNote = note;
      }
      _isMinor = initialSong.songKey!.endsWith('m');
    }

    // Parse initial duration
    final currentDuration = initialSong?.duration;
    final minutes = currentDuration?.inMinutes.toString() ?? '';
    final seconds = currentDuration != null
        ? (currentDuration.inSeconds % 60).toString().padLeft(2, '0')
        : '';

    _durationMinController = TextEditingController(text: minutes);
    _durationSecController = TextEditingController(text: seconds);

    // Add listeners for auto-fetching facts
    _titleController.addListener(_onTextChanged);
    _artistController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    // If a song has been selected from autocomplete, don't fetch facts.
    if (_selectedExistingSong != null) return;

    // Cancel the old timer if it exists
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    // Start a new timer (2 seconds after user stops typing)
    _debounce = Timer(const Duration(seconds: 2), () {
      final title = _titleController.text.trim();
      final artist = _artistController.text.trim();

      if (title.isNotEmpty && artist.isNotEmpty) {
        _fetchAndSetSongFacts(title, artist);
      }
    });
  }

  Future<void> _fetchAndSetSongFacts(String title, String artist) async {
    if (_isLoadingFacts) return; // Prevent multiple simultaneous calls

    setState(() {
      _isLoadingFacts = true;
    });

    try {
      final facts = await MusicFactsService.fetchSongFacts(
        title,
        artist,
        venueCity: widget.venueCity ?? 'Cincinnati', // Default to Cincinnati
      );

      if (facts != null && mounted) {
        final factsText = _buildFactsText(facts);

        setState(() {
          _notesController.text = factsText;
        });
      }
    } catch (e) {
      print('Error fetching song facts: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingFacts = false;
        });
      }
    }
  }

  /// Build formatted facts text from API response
  String _buildFactsText(Map<String, dynamic> facts) {
    final buffer = StringBuffer();

    // SONG-SPECIFIC DETAILS FIRST
    final songDetails = facts['songDetails'] as Map<String, dynamic>?;

    if (songDetails != null) {
      final composers = songDetails['composers'] as List<String>?;
      final lyricists = songDetails['lyricists'] as List<String>?;
      final producers = songDetails['producers'] as List<String>?;

      if (composers != null && composers.isNotEmpty) {
        buffer.writeln('Written by: ${composers.join(", ")}');
      }

      if (lyricists != null && lyricists.isNotEmpty &&
          (composers == null || !composers.any((c) => lyricists.contains(c)))) {
        buffer.writeln('Lyrics by: ${lyricists.join(", ")}');
      }

      if (producers != null && producers.isNotEmpty) {
        buffer.writeln('Produced by: ${producers.join(", ")}');
      }

      // Release year for the song
      final releaseYear = facts['releaseYear'] as String?;
      if (releaseYear != null) {
        buffer.writeln('Released: $releaseYear');
      }

      if (buffer.isNotEmpty) {
        buffer.writeln(); // Add spacing after song details
      }
    }

    // Artist location info (but not the artist name - they already know that!)
    final hometown = facts['hometown'] as String?;
    final country = facts['country'] as String?;

    if (hometown != null || country != null) {
      if (hometown != null && country != null) {
        buffer.writeln('Artist from: $hometown, $country');
      } else if (hometown != null) {
        buffer.writeln('Artist from: $hometown');
      } else if (country != null) {
        buffer.writeln('Artist from: $country');
      }
    }

    // Location connections (highlighted)
    final locationFacts = facts['locationFacts'] as List<String>?;
    if (locationFacts != null && locationFacts.isNotEmpty) {
      buffer.writeln('\n🎸 LOCAL CONNECTION:');
      for (var fact in locationFacts) {
        buffer.writeln('  $fact');
      }
    }

    // Band members with interesting details
    final bandMembers = facts['bandMembers'] as List<Map<String, dynamic>>?;
    if (bandMembers != null && bandMembers.isNotEmpty) {
      buffer.writeln('\nBand Members:');
      for (var member in bandMembers.take(5)) {
        final name = member['name'] as String;
        final instruments = member['instruments'] as List?;
        final memberHometown = member['hometown'] as String?;

        final instrumentStr = instruments != null && instruments.isNotEmpty
            ? ' (${instruments.join(", ")})'
            : '';
        final hometownStr = memberHometown != null ? ' - from $memberHometown' : '';

        buffer.writeln('  • $name$instrumentStr$hometownStr');
      }
    }

    // Collaborations
    final collaborators = facts['collaborators'] as List<String>?;
    if (collaborators != null && collaborators.isNotEmpty) {
      buffer.writeln('\nAlso played with:');
      buffer.writeln('  ${collaborators.take(4).join(", ")}');
    }

    // Wikipedia summary (first interesting sentence)
    final wikiSummary = facts['wikiSummary'] as String?;
    if (wikiSummary != null && wikiSummary.isNotEmpty) {
      final sentences = wikiSummary.split('. ');
      if (sentences.length > 1) {
        buffer.writeln('\nFun Fact:');
        buffer.writeln('  ${sentences[1].trim()}');
      }
    }

    return buffer.toString().trim();
  }

  /// Populates all form fields based on a selected song.
  void _populateFieldsFromSong(Song song) {
    setState(() {
      _selectedExistingSong = song;
      _titleController.text = song.title;
      _artistController.text = song.artist ?? '';
      _tempoController.text = song.tempo?.toString() ?? '';
      _notesController.text = song.notes ?? '';

      final minutes = song.duration?.inMinutes.toString() ?? '';
      final seconds = song.duration != null
          ? (song.duration!.inSeconds % 60).toString().padLeft(2, '0')
          : '';
      _durationMinController.text = minutes;
      _durationSecController.text = seconds;

      // Parse and set the key
      _selectedKeyNote = null;
      _isMinor = false;
      if (song.songKey != null && song.songKey!.isNotEmpty) {
        final note = song.songKey!.replaceAll('m', '');
        if (_validKeyNotes.contains(note)) {
          _selectedKeyNote = note;
        }
        _isMinor = song.songKey!.endsWith('m');
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleController.removeListener(_onTextChanged);
    _artistController.removeListener(_onTextChanged);

    _titleController.dispose();
    _artistController.dispose();
    _tempoController.dispose();
    _durationMinController.dispose();
    _durationSecController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    // If a user selected an existing song from the list (and isn't in editing mode),
    // just return that song directly.
    if (_selectedExistingSong != null && !_isEditing) {
      Navigator.of(context).pop(_selectedExistingSong);
      return;
    }

    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      final minutes = int.tryParse(_durationMinController.text) ?? 0;
      final seconds = int.tryParse(_durationSecController.text) ?? 0;
      final totalDuration = (minutes * 60) + seconds > 0
          ? Duration(minutes: minutes, seconds: seconds)
          : null;

      // Assemble the song key string
      String? finalSongKey;
      if (_selectedKeyNote != null) {
        finalSongKey = _selectedKeyNote!;
        if (_isMinor) {
          finalSongKey += 'm';
        }
      }

      final songToSave = Song(
        // Use existing ID if editing, otherwise generate a new one.
        id: _selectedExistingSong?.id ?? const Uuid().v4(),
        title: _titleController.text.trim(),
        artist: _artistController.text.trim().isNotEmpty ? _artistController.text.trim() : null,
        songKey: finalSongKey,
        tempo: int.tryParse(_tempoController.text.trim()),
        duration: totalDuration,
        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
      );

      Navigator.of(context).pop(songToSave);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Edit Song' : 'Add Song'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- Autocomplete Title Field ---
              Autocomplete<Song>(
                initialValue: TextEditingValue(text: _titleController.text),
                displayStringForOption: (Song option) => option.title,
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty || _isEditing) {
                    return const Iterable<Song>.empty();
                  }
                  return widget.allSongs.where((Song option) {
                    return option.title
                        .toLowerCase()
                        .contains(textEditingValue.text.toLowerCase());
                  });
                },
                onSelected: (Song selection) {
                  // When a user taps a suggestion, populate all fields.
                  _populateFieldsFromSong(selection);
                  FocusScope.of(context).unfocus(); // Hide keyboard
                },
                fieldViewBuilder: (BuildContext context,
                    TextEditingController fieldTextEditingController,
                    FocusNode fieldFocusNode,
                    VoidCallback onFieldSubmitted) {
                  // Sync our controller with the autocomplete's internal one
                  _titleController = fieldTextEditingController;
                  return TextFormField(
                    controller: fieldTextEditingController,
                    focusNode: fieldFocusNode,
                    // Only autofocus when creating a new song
                    autofocus: !_isEditing,
                    // --- FIX: Prevent editing title if a song is selected or being edited ---
                    readOnly: _isEditing || _selectedExistingSong != null,
                    decoration: const InputDecoration(
                      labelText: 'Song Title *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Title is required' : null,
                  );
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _artistController,
                decoration: const InputDecoration(
                  labelText: 'Composer / Artist',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      value: _selectedKeyNote,
                      hint: const Text('Key'),
                      isExpanded: true,
                      items: _validKeyNotes.map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (newValue) {
                        setState(() {
                          _selectedKeyNote = newValue;
                        });
                      },
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _isMinor = !_isMinor),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      child: Row(
                        children: [
                          Switch(
                            value: _isMinor,
                            onChanged: (value) {
                              setState(() {
                                _isMinor = value;
                              });
                            },
                          ),
                          const Text('Minor'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _tempoController,
                      decoration: const InputDecoration(
                        labelText: 'Tempo (BPM)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _durationMinController,
                      decoration: const InputDecoration(
                        labelText: 'Min',
                        border: OutlineInputBorder(),
                      ),
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(':', style: TextStyle(fontSize: 24)),
                  ),
                  Expanded(
                    child: TextFormField(
                      controller: _durationSecController,
                      decoration: const InputDecoration(
                        labelText: 'Sec',
                        border: OutlineInputBorder(),
                      ),
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    flex: 2,
                    child: Text('Duration', style: TextStyle(color: Colors.grey)),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Song Notes with manual refresh button
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Song Notes',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  if (_titleController.text.isNotEmpty &&
                      _artistController.text.isNotEmpty)
                    TextButton.icon(
                      onPressed: _isLoadingFacts
                          ? null
                          : () => _fetchAndSetSongFacts(
                        _titleController.text.trim(),
                        _artistController.text.trim(),
                      ),
                      icon: _isLoadingFacts
                          ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Icon(Icons.refresh, size: 16),
                      label: Text(
                        _isLoadingFacts ? 'Loading...' : 'Get Facts',
                        style: const TextStyle(fontSize: 11),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Auto-populated with interesting facts...',
                ),
                maxLines: 6,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(_isEditing ? 'Save Changes' : 'Add Song'),
        ),
      ],
    );
  }
}