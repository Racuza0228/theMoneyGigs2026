// lib/features/map_venues/widgets/venue_tags_widget.dart

import 'package:flutter/material.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';
import 'package:the_money_gigs/features/map_venues/repositories/venue_repository.dart';
import 'package:the_money_gigs/core/services/auth_service.dart';

class VenueTagsWidget extends StatefulWidget {
  final StoredLocation venue;
  final Function(List<String> instruments, List<String> genres, List<String> actFormats) onTagsChanged;
  final bool isConnected;

  const VenueTagsWidget({
    super.key,
    required this.venue,
    required this.onTagsChanged,
    required this.isConnected,
  });

  @override
  State<VenueTagsWidget> createState() => _VenueTagsWidgetState();
}

class _VenueTagsWidgetState extends State<VenueTagsWidget> {
  final Set<String> _userSelectedGenres = {};
  final Set<String> _userSelectedInstruments = {};
  final Set<String> _userSelectedActFormats = {};

  // Firebase tags with vote counts: { tagName: { count: int, userVoted: bool } }
  Map<String, Map<String, dynamic>> _firebaseGenreTags = {};
  Map<String, Map<String, dynamic>> _firebaseInstrumentTags = {};
  Map<String, Map<String, dynamic>> _firebaseActFormatTags = {};

  final VenueRepository _venueRepository = VenueRepository();
  AuthService? _authService;
  bool _isLoading = true;

  // Tag category constants — match Firestore subcollection names
  static const String _catGenres = 'genres';
  static const String _catInstruments = 'instruments';
  static const String _catActFormats = 'actFormats';

  final List<String> _suggestedInstruments = [
    'Full PA', 'Front of House Only', 'House Sound Engineer',
    'Wedge Monitors', 'IEM Capability', 'Full Backline',
    'Guitar Amp', 'Bass Amp', 'Drum Kit', 'Piano/Keys Provided',
    'Vocal Mics',
  ];

  final List<String> _suggestedGenres = [
    'Rock', 'Pop', 'Country', 'Jazz', 'Blues', 'R&B/Soul', 'Hip Hop',
    'Electronic', 'Folk', 'Singer-Songwriter', 'Open Format', 'Metal',
  ];

  final List<String> _suggestedActFormats = [
    'Solo', 'Duo', 'Trio', 'Small Ensemble', 'Full Band',
    'Acoustic Only', 'Electric', 'DJ',
  ];

  @override
  void initState() {
    super.initState();
    _userSelectedGenres.addAll(widget.venue.genreTags);
    _userSelectedInstruments.addAll(widget.venue.instrumentTags);
    _userSelectedActFormats.addAll(widget.venue.actFormatTags);

    if (widget.isConnected) {
      _initializeAuthAndLoadTags();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _initializeAuthAndLoadTags() async {
    try {
      _authService = AuthService();
      await _loadFirebaseTags();
    } catch (e) {
      print('⚠️ Could not initialize auth: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadFirebaseTags() async {
    if (!widget.isConnected || _authService == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final userId = _authService!.currentUserId;

      final results = await Future.wait([
        _venueRepository.getVenueTagsByCategory(
          placeId: widget.venue.placeId,
          userId: userId,
          tagCategory: _catGenres,
        ),
        _venueRepository.getVenueTagsByCategory(
          placeId: widget.venue.placeId,
          userId: userId,
          tagCategory: _catInstruments,
        ),
        _venueRepository.getVenueTagsByCategory(
          placeId: widget.venue.placeId,
          userId: userId,
          tagCategory: _catActFormats,
        ),
      ]);

      if (mounted) {
        setState(() {
          _firebaseGenreTags = results[0];
          _firebaseInstrumentTags = results[1];
          _firebaseActFormatTags = results[2];
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading Firebase tags: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _notifyParent() {
    widget.onTagsChanged(
      _userSelectedInstruments.toList(),
      _userSelectedGenres.toList(),
      _userSelectedActFormats.toList(),
    );
  }

  String _categoryFor(String section) {
    switch (section) {
      case 'genres': return _catGenres;
      case 'instruments': return _catInstruments;
      case 'actFormats': return _catActFormats;
      default: return section;
    }
  }

  Set<String> _tagSetFor(String section) {
    switch (section) {
      case 'genres': return _userSelectedGenres;
      case 'instruments': return _userSelectedInstruments;
      case 'actFormats': return _userSelectedActFormats;
      default: return _userSelectedGenres;
    }
  }

  Map<String, Map<String, dynamic>> _firebaseTagsFor(String section) {
    switch (section) {
      case 'genres': return _firebaseGenreTags;
      case 'instruments': return _firebaseInstrumentTags;
      case 'actFormats': return _firebaseActFormatTags;
      default: return _firebaseGenreTags;
    }
  }

  List<String> _suggestionsFor(String section) {
    switch (section) {
      case 'genres': return _suggestedGenres;
      case 'instruments': return _suggestedInstruments;
      case 'actFormats': return _suggestedActFormats;
      default: return _suggestedGenres;
    }
  }

  Future<void> _toggleTag(String tag, String section) async {
    final tagSet = _tagSetFor(section);
    final isCurrentlySelected = tagSet.contains(tag);

    setState(() {
      if (isCurrentlySelected) {
        tagSet.remove(tag);
      } else {
        tagSet.add(tag);
      }
    });

    _notifyParent();

    if (widget.isConnected && _authService != null) {
      final userId = _authService!.currentUserId;
      final category = _categoryFor(section);

      if (isCurrentlySelected) {
        await _venueRepository.removeVoteForTagByCategory(
          placeId: widget.venue.placeId,
          userId: userId,
          tagName: tag,
          tagCategory: category,
        );
      } else {
        await _venueRepository.voteForTagByCategory(
          placeId: widget.venue.placeId,
          userId: userId,
          tagName: tag,
          tagCategory: category,
        );
      }

      await _loadFirebaseTags();
    }
  }

  Future<void> _showAddTagDialog(String title, String section) async {
    final tagSet = _tagSetFor(section);
    final suggestions = _suggestionsFor(section);
    final TextEditingController controller = TextEditingController();
    final availableSuggestions =
    suggestions.where((s) => !tagSet.contains(s)).toList();

    showDialog(
      context: context,
      useRootNavigator: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF3a3a3c),
          title: Text('Add $title',
              style: const TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'New ${title.singularize()}',
                    labelStyle:
                    TextStyle(color: Colors.orangeAccent.shade100),
                    enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey.shade600)),
                    focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                            color:
                            Theme.of(context).colorScheme.primary)),
                  ),
                  onSubmitted: (value) {
                    if (value.trim().isNotEmpty) {
                      _toggleTag(value.trim(), section);
                    }
                    Navigator.of(context).pop();
                  },
                ),
                const SizedBox(height: 20),
                if (availableSuggestions.isNotEmpty)
                  Text('Suggestions',
                      style: TextStyle(
                          color: Colors.orangeAccent.shade100,
                          fontWeight: FontWeight.bold)),
                if (availableSuggestions.isNotEmpty)
                  const SizedBox(height: 8),
                Wrap(
                  spacing: 8.0,
                  runSpacing: 4.0,
                  children: availableSuggestions.map((suggestion) {
                    return ActionChip(
                      label: Text(suggestion),
                      onPressed: () {
                        _toggleTag(suggestion, section);
                        Navigator.of(context).pop();
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: const Text('Add'),
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  _toggleTag(controller.text.trim(), section);
                }
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildTagSection(String title, String section) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final userTags = _tagSetFor(section);
    final firebaseTags = _firebaseTagsFor(section);
    final allTags = <String>{...userTags, ...firebaseTags.keys}.toList();

    allTags.sort((a, b) {
      final aCount = firebaseTags[a]?['count'] ?? 0;
      final bCount = firebaseTags[b]?['count'] ?? 0;
      if (aCount != bCount) return bCount.compareTo(aCount);
      return a.compareTo(b);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            IconButton(
              icon: Icon(Icons.add_circle_outline,
                  color: Colors.orangeAccent.shade100),
              tooltip: 'Add ${title.singularize()}',
              onPressed: () => _showAddTagDialog(title, section),
            ),
          ],
        ),
        const SizedBox(height: 8.0),
        allTags.isEmpty
            ? Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Text(
            'No ${title.toLowerCase()} specified.',
            style: TextStyle(
                color: Colors.grey.shade400,
                fontStyle: FontStyle.italic),
          ),
        )
            : Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: allTags.map((tag) {
            final isUserSelected = userTags.contains(tag);
            final voteCount = firebaseTags[tag]?['count'] ?? 0;
            final showCount = widget.isConnected && voteCount > 0;

            final chipColor = isUserSelected
                ? Theme.of(context)
                .colorScheme
                .primary
                .withOpacity(0.8)
                : Colors.orangeAccent.shade100.withOpacity(0.6);

            return InputChip(
              label: Text(
                showCount ? '$tag ($voteCount)' : tag,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold),
              ),
              backgroundColor: chipColor,
              selectedColor: chipColor,
              checkmarkColor: Colors.white,
              selected: isUserSelected,
              onSelected: (_) => _toggleTag(tag, section),
              onDeleted: isUserSelected
                  ? () => _toggleTag(tag, section)
                  : null,
              deleteIcon: isUserSelected
                  ? const Icon(Icons.cancel, size: 18)
                  : null,
              deleteIconColor: Colors.white70,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTagSection('Typical Genres', 'genres'),
        const SizedBox(height: 8),
        _buildTagSection('Typical Act Format', 'actFormats'),
        const SizedBox(height: 8),
        _buildTagSection('House Sound & Equipment', 'instruments'),
      ],
    );
  }
}

extension StringExtension on String {
  String singularize() {
    if (endsWith('s')) return substring(0, length - 1);
    return this;
  }
}