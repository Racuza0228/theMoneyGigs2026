// lib/features/profile/views/widgets/tags_widget.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TagsWidget extends StatefulWidget {
  const TagsWidget({super.key});

  @override
  State<TagsWidget> createState() => _TagsWidgetState();
}

class _TagsWidgetState extends State<TagsWidget> {
  // SharedPreferences keys
  static const String _keyInstrumentTags = 'profile_instrument_tags';
  static const String _keyGenreTags = 'profile_genre_tags';

  // State
  final Set<String> _instrumentTags = {};
  final Set<String> _genreTags = {};
  bool _isLoading = true;

  // Pre-populated suggestions
  final List<String> _suggestedInstruments = [
    'Vocals', 'Acoustic Guitar', 'Electric Guitar', 'Bass Guitar', 'Drums',
    'Percussion', 'Keyboard', 'Piano', 'Saxophone', 'Trumpet', 'Violin', 'Cello'
  ];
  final List<String> _suggestedGenres = [
    'Rock', 'Pop', 'Country', 'Jazz', 'Blues', 'R&B/Soul', 'Hip Hop',
    'Electronic', 'Folk', 'Classical', 'Reggae', 'Metal'
  ];

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final instrumentTags = prefs.getStringList(_keyInstrumentTags) ?? [];
    final genreTags = prefs.getStringList(_keyGenreTags) ?? [];

    setState(() {
      _instrumentTags.addAll(instrumentTags);
      _genreTags.addAll(genreTags);
      _isLoading = false;
    });
  }

  Future<void> _saveTags() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyInstrumentTags, _instrumentTags.toList());
    await prefs.setStringList(_keyGenreTags, _genreTags.toList());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your skills have been updated!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _addTag(String tag, Set<String> tagSet) {
    if (tag.isNotEmpty) {
      setState(() {
        tagSet.add(tag);
      });
      _saveTags();
    }
  }

  void _removeTag(String tag, Set<String> tagSet) {
    setState(() {
      tagSet.remove(tag);
    });
    _saveTags();
  }

  Future<void> _showAddTagDialog(String title, Set<String> tagSet, List<String> suggestions) async {
    final TextEditingController controller = TextEditingController();
    final availableSuggestions = suggestions.where((s) => !tagSet.contains(s)).toList();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2c2c2e), // Dark background
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
                    labelText: 'New $title',
                    labelStyle: TextStyle(color: Colors.orangeAccent.shade100),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade600)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.primary)),
                  ),
                  onSubmitted: (value) {
                    _addTag(value.trim(), tagSet);
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
                        _addTag(suggestion, tagSet);
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
                _addTag(controller.text.trim(), tagSet);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildTagSection(String title, Set<String> tags, List<String> suggestions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            IconButton(
              icon: Icon(Icons.add_circle_outline, color: Colors.orangeAccent.shade100),
              tooltip: 'Add $title',
              onPressed: () => _showAddTagDialog(title, tags, suggestions),
            ),
          ],
        ),
        const SizedBox(height: 8.0),
        tags.isEmpty
            ? Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
          child: Text(
            'No ${title.toLowerCase()} added yet. Tap the + icon to add some!',
            style: TextStyle(color: Colors.grey.shade400, fontStyle: FontStyle.italic),
          ),
        )
            : Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: tags.map((tag) {
            return Chip(
              label: Text(tag, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.8),
              onDeleted: () => _removeTag(tag, tags),
              deleteIcon: const Icon(Icons.cancel, size: 18),
              deleteIconColor: Colors.white70,
            );
          }).toList(),
        ),
        const Divider(height: 30, thickness: 1, color: Colors.white24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          _buildTagSection('Instruments & Skills', _instrumentTags, _suggestedInstruments),
          _buildTagSection('Genres', _genreTags, _suggestedGenres),
        ],
      ),
    );
  }
}
