// lib/features/map_venues/widgets/venue_tags_widget.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';
import 'package:the_money_gigs/features/map_venues/repositories/venue_repository.dart';
import 'package:the_money_gigs/core/services/auth_service.dart';

class VenueTagsWidget extends StatefulWidget {
  final StoredLocation venue;
  final Function(List<String> instruments, List<String> genres) onTagsChanged;
  final bool isConnected; // Whether user is connected to Firebase

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

  // Firebase tags with vote counts: { tagName: { count: int, userVoted: bool } }
  Map<String, Map<String, dynamic>> _firebaseGenreTags = {};
  Map<String, Map<String, dynamic>> _firebaseInstrumentTags = {};

  final VenueRepository _venueRepository = VenueRepository();
  AuthService? _authService;
  bool _isLoading = true;

  // Suggestions for venues (can differ from user profiles)
  final List<String> _suggestedInstruments = [
    'Full Backline', 'PA System', 'Acoustic', 'Electric', 'Drums',
    'Bass Amp', 'Guitar Amp', 'Keyboard', 'Piano', 'Vocal Mics'
  ];
  final List<String> _suggestedGenres = [
    'Rock', 'Pop', 'Country', 'Jazz', 'Blues', 'R&B/Soul', 'Hip Hop',
    'Electronic', 'Folk', 'Singer-Songwriter', 'Open Format', 'Metal'
  ];

  @override
  void initState() {
    super.initState();

    // Initialize user's local selections
    _userSelectedGenres.addAll(widget.venue.genreTags);
    _userSelectedInstruments.addAll(widget.venue.instrumentTags);

    // Load Firebase tags if connected
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

      // Load both genre and instrument tags from Firebase
      final genres = await _venueRepository.getVenueTags(
        placeId: widget.venue.placeId,
        userId: userId,
        isGenre: true,
      );

      final instruments = await _venueRepository.getVenueTags(
        placeId: widget.venue.placeId,
        userId: userId,
        isGenre: false,
      );

      if (mounted) {
        setState(() {
          _firebaseGenreTags = genres;
          _firebaseInstrumentTags = instruments;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading Firebase tags: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _notifyParent() {
    print('🏷️ VenueTagsWidget: Notifying parent of tag changes');
    print('   - Genres: $_userSelectedGenres');
    print('   - Instruments: $_userSelectedInstruments');
    widget.onTagsChanged(_userSelectedInstruments.toList(), _userSelectedGenres.toList());
  }

  Future<void> _toggleTag(String tag, bool isGenre) async {
    print('🏷️ VenueTagsWidget: Toggling tag "$tag" (${isGenre ? "genre" : "instrument"})');
    final tagSet = isGenre ? _userSelectedGenres : _userSelectedInstruments;
    final isCurrentlySelected = tagSet.contains(tag);
    print('   - Was selected: $isCurrentlySelected');

    // Update local state immediately for responsive UI
    setState(() {
      if (isCurrentlySelected) {
        tagSet.remove(tag);
      } else {
        tagSet.add(tag);
      }
    });

    print('   - Now selected: ${tagSet.contains(tag)}');
    _notifyParent();

    // If connected to Firebase, sync the vote
    if (widget.isConnected && _authService != null) {
      final userId = _authService!.currentUserId;

      if (isCurrentlySelected) {
        // Remove vote
        await _venueRepository.removeVoteForTag(
          placeId: widget.venue.placeId,
          userId: userId,
          tagName: tag,
          isGenre: isGenre,
        );
      } else {
        // Add vote
        await _venueRepository.voteForTag(
          placeId: widget.venue.placeId,
          userId: userId,
          tagName: tag,
          isGenre: isGenre,
        );
      }

      // Reload Firebase tags to get updated counts
      await _loadFirebaseTags();
    }
  }

  Future<void> _showAddTagDialog(String title, bool isGenre) async {
    final tagSet = isGenre ? _userSelectedGenres : _userSelectedInstruments;
    final suggestions = isGenre ? _suggestedGenres : _suggestedInstruments;
    final TextEditingController controller = TextEditingController();
    final availableSuggestions = suggestions.where((s) => !tagSet.contains(s)).toList();

    showDialog(
      context: context,
      useRootNavigator: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF3a3a3c),
          title: Text('Add $title', style: const TextStyle(color: Colors.white)),
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
                    labelStyle: TextStyle(color: Colors.orangeAccent.shade100),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade600)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.primary)),
                  ),
                  onSubmitted: (value) {
                    if (value.trim().isNotEmpty) {
                      _toggleTag(value.trim(), isGenre);
                    }
                    Navigator.of(context).pop();
                  },
                ),
                const SizedBox(height: 20),
                if (availableSuggestions.isNotEmpty)
                  Text('Suggestions', style: TextStyle(color: Colors.orangeAccent.shade100, fontWeight: FontWeight.bold)),
                if (availableSuggestions.isNotEmpty)
                  const SizedBox(height: 8),
                Wrap(
                  spacing: 8.0,
                  runSpacing: 4.0,
                  children: availableSuggestions.map((suggestion) {
                    return ActionChip(
                      label: Text(suggestion),
                      onPressed: () {
                        _toggleTag(suggestion, isGenre);
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
                  _toggleTag(controller.text.trim(), isGenre);
                }
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildTagSection(String title, bool isGenre) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Combine local and Firebase tags
    final userTags = isGenre ? _userSelectedGenres : _userSelectedInstruments;
    final firebaseTags = isGenre ? _firebaseGenreTags : _firebaseInstrumentTags;

    // All unique tags (from user + Firebase)
    final allTags = <String>{...userTags, ...firebaseTags.keys}.toList();

    // Sort: Most popular first, then alphabetically
    allTags.sort((a, b) {
      final aCount = firebaseTags[a]?['count'] ?? 0;
      final bCount = firebaseTags[b]?['count'] ?? 0;

      if (aCount != bCount) {
        return bCount.compareTo(aCount); // Descending by count
      }
      return a.compareTo(b); // Alphabetically
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            IconButton(
              icon: Icon(Icons.add_circle_outline, color: Colors.orangeAccent.shade100),
              tooltip: 'Add ${title.singularize()}',
              onPressed: () => _showAddTagDialog(title, isGenre),
            ),
          ],
        ),
        const SizedBox(height: 8.0),
        allTags.isEmpty
            ? Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Text(
            'No ${title.toLowerCase()} specified.',
            style: TextStyle(color: Colors.grey.shade400, fontStyle: FontStyle.italic),
          ),
        )
            : Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: allTags.map((tag) {
            final isUserSelected = userTags.contains(tag);
            final voteCount = firebaseTags[tag]?['count'] ?? 0;
            final showCount = widget.isConnected && voteCount > 0;

            // Color: Purple if user selected, Orange if not
            final chipColor = isUserSelected
                ? Theme.of(context).colorScheme.primary.withOpacity(0.8)  // Purple
                : Colors.orangeAccent.shade100.withOpacity(0.6);           // Orange

            return InputChip(
              label: Text(
                showCount ? '$tag ($voteCount)' : tag,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              backgroundColor: chipColor,
              selectedColor: chipColor,
              checkmarkColor: Colors.white,
              selected: isUserSelected,
              onSelected: (_) {
                print('🏷️ VenueTagsWidget: Chip tapped for "$tag"');
                _toggleTag(tag, isGenre);
              },
              onDeleted: isUserSelected ? () {
                print('🏷️ VenueTagsWidget: Delete icon tapped for "$tag"');
                _toggleTag(tag, isGenre);
              } : null,
              deleteIcon: isUserSelected ? const Icon(Icons.cancel, size: 18) : null,
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
        _buildTagSection('Typical Genres', true),
        const SizedBox(height: 8),
        _buildTagSection('Instrumentation', false),
      ],
    );
  }
}

// Helper extension to make dialog titles cleaner
extension StringExtension on String {
  String singularize() {
    if (endsWith('s')) {
      return substring(0, length - 1);
    }
    return this;
  }
}