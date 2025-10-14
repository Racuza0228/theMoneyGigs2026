// lib/features/notes/views/notes_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:the_money_gigs/global_refresh_notifier.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart'; // Import Venue model
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';

class NotesPage extends StatefulWidget {
  // Can edit notes for a gig OR a venue. One of these must be provided.
  final String? editingGigId;
  final String? editingVenueId;

  const NotesPage({
    super.key,
    this.editingGigId,
    this.editingVenueId,
  }) : assert(editingGigId != null || editingVenueId != null,
  'Either editingGigId or editingVenueId must be provided.');

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  late final TextEditingController _notesController;
  late final TextEditingController _urlController;

  // Generic properties to hold the data, regardless of source
  String _displayName = '';
  String? _displaySubtext;
  String? _initialNotes;
  String? _initialUrl;

  // List to hold historical gig notes for the venue
  List<Gig> _historicalGigsForVenue = [];

  bool _isLoading = true;
  String _errorMessage = '';

  bool _isEditingUrl = false;
  bool _isSaving = false;
  bool _hasChanges = false;

  bool get _isEditingGig => widget.editingGigId != null;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController();
    _urlController = TextEditingController();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    try {
      if (_isEditingGig) {
        await _loadGigDetails();
      } else {
        await _loadVenueDetails();
      }

      if (mounted) {
        setState(() {
          _notesController.text = _initialNotes ?? '';
          _urlController.text = _initialUrl ?? '';
          _isEditingUrl = _initialUrl == null || _initialUrl!.isEmpty;
          _isLoading = false;

          _notesController.addListener(_onTextChanged);
          _urlController.addListener(_onTextChanged);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Error loading details: $e";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadGigDetails() async {
    final prefs = await SharedPreferences.getInstance();
    final gigsJsonString = prefs.getString('gigs_list') ?? '[]';
    final List<Gig> allGigs = Gig.decode(gigsJsonString);
    final gigIndex = allGigs.indexWhere((g) => g.id == widget.editingGigId);

    if (gigIndex != -1) {
      final gig = allGigs[gigIndex];
      _displayName = gig.venueName;
      _displaySubtext = DateFormat.yMMMEd().add_jm().format(gig.dateTime);
      _initialNotes = gig.notes;
      _initialUrl = gig.notesUrl;
    } else {
      throw Exception("Gig not found.");
    }
  }

  Future<void> _loadVenueDetails() async {
    final prefs = await SharedPreferences.getInstance();
    final venuesJson = prefs.getStringList('saved_locations') ?? [];
    final allVenues = venuesJson.map((v) => StoredLocation.fromJson(jsonDecode(v))).toList();
    final venueIndex = allVenues.indexWhere((v) => v.placeId == widget.editingVenueId);

    if (venueIndex != -1) {
      final venue = allVenues[venueIndex];
      _displayName = venue.name;
      _displaySubtext = venue.address;
      _initialNotes = venue.venueNotes;
      _initialUrl = venue.venueNotesUrl;

      // Load and filter gigs for historical notes
      final gigsJsonString = prefs.getString('gigs_list') ?? '[]';
      final List<Gig> allGigs = Gig.decode(gigsJsonString);

      _historicalGigsForVenue = allGigs
          .where((gig) =>
      gig.placeId == widget.editingVenueId && (gig.notes?.isNotEmpty ?? false))
          .toList();

      // Sort in reverse chronological order
      _historicalGigsForVenue.sort((a, b) => b.dateTime.compareTo(a.dateTime));

    } else {
      throw Exception("Venue not found.");
    }
  }

  @override
  void dispose() {
    _notesController.removeListener(_onTextChanged);
    _urlController.removeListener(_onTextChanged);
    _notesController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final bool notesChanged = _notesController.text.trim() != (_initialNotes ?? '');
    final bool urlChanged = _urlController.text.trim() != (_initialUrl ?? '');

    if (mounted && (notesChanged || urlChanged) != _hasChanges) {
      setState(() {
        _hasChanges = notesChanged || urlChanged;
      });
    }
  }

  Future<void> _saveNotesAndClose() async {
    if (!mounted) return;
    setState(() => _isSaving = true);

    try {
      if (_isEditingGig) {
        await _saveGigNotes();
      } else {
        await _saveVenueNotes();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notes saved successfully!'), backgroundColor: Colors.green),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving notes: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveGigNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final String gigsJsonString = prefs.getString('gigs_list') ?? '[]';
    List<Gig> currentGigs = Gig.decode(gigsJsonString);
    final gigIndex = currentGigs.indexWhere((g) => g.id == widget.editingGigId);

    if (gigIndex != -1) {
      final newNotes = _notesController.text.trim();
      final newUrl = _urlController.text.trim();
      currentGigs[gigIndex] = currentGigs[gigIndex].copyWith(
        notes: newNotes.isEmpty ? null : newNotes,
        notesUrl: newUrl.isEmpty ? null : newUrl,
      );
      await prefs.setString('gigs_list', Gig.encode(currentGigs));
      globalRefreshNotifier.notify();
    } else {
      throw Exception("Could not find gig to update.");
    }
  }

  Future<void> _saveVenueNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> venuesJson = prefs.getStringList('saved_locations') ?? [];
    List<StoredLocation> currentVenues = venuesJson.map((v) => StoredLocation.fromJson(jsonDecode(v))).toList();
    final venueIndex = currentVenues.indexWhere((v) => v.placeId == widget.editingVenueId);

    if (venueIndex != -1) {
      final newNotes = _notesController.text.trim();
      final newUrl = _urlController.text.trim();
      currentVenues[venueIndex] = currentVenues[venueIndex].copyWith(
        venueNotes: () => newNotes.isEmpty ? null : newNotes,
        venueNotesUrl: () => newUrl.isEmpty ? null : newUrl,
      );
      final List<String> updatedVenuesJson = currentVenues.map((v) => jsonEncode(v.toJson())).toList();
      await prefs.setStringList('saved_locations', updatedVenuesJson);
      globalRefreshNotifier.notify();
    } else {
      throw Exception("Could not find venue to update.");
    }
  }

  Future<void> _launchUrl() async {
    final urlString = _urlController.text.trim();
    if (urlString.isEmpty) return;
    final Uri? uri = Uri.tryParse(urlString.startsWith('http') ? urlString : 'https://$urlString');
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open link: $urlString'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine the titles based on the mode
    final String appBarTitle = _isEditingGig ? 'GIG NOTES' : 'VENUE NOTES';
    final String labelText = _isEditingGig ? 'Gig-Specific Notes' : 'General Venue Notes';
    final String hintText = _isEditingGig
        ? 'Load-in details, sound engineer name, etc.'
        : 'Gate codes, parking info, regular contact...';

    return Scaffold(
      appBar: AppBar(
        // *** THE FIX IS HERE ***
        // The title is now dynamic based on the context.
        title: Text(appBarTitle),
        centerTitle: true,
        automaticallyImplyLeading: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text(_errorMessage, style: const TextStyle(color: Colors.red))))
          : SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 120.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _displayName,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            if(_displaySubtext != null && _displaySubtext!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: Text(
                  _displaySubtext!,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey.shade600),
                ),
              ),
            const SizedBox(height: 20),
            TextField(
              controller: _notesController,
              autofocus: true,
              maxLines: 8,
              minLines: 5,
              decoration: InputDecoration(
                labelText: labelText,
                hintText: hintText,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Related Link', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Divider(),
            if (_isEditingUrl)
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'URL (Optional)',
                  hintText: 'e.g., venue-tech-specs.pdf',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
              )
            else
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _launchUrl,
                      child: Text(
                        _urlController.text.isEmpty ? '(No link)' : _urlController.text,
                        style: TextStyle(
                          color: _urlController.text.isEmpty ? Colors.grey : Theme.of(context).colorScheme.primary,
                          decoration: _urlController.text.isEmpty ? TextDecoration.none : TextDecoration.underline,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () {
                      setState(() {
                        _isEditingUrl = true;
                        _onTextChanged();
                      });
                    },
                    tooltip: 'Edit Link',
                  )
                ],
              ),

            // Historical Gig Notes Section
            if (!_isEditingGig && _historicalGigsForVenue.isNotEmpty) ...[
              const SizedBox(height: 32),
              const Text('Past Gig Notes at this Venue', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Divider(),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _historicalGigsForVenue.length,
                itemBuilder: (context, index) {
                  final gig = _historicalGigsForVenue[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat.yMMMEd().format(gig.dateTime),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        // Ensure notes are not null before displaying
                        Text(gig.notes ?? 'No notes for this gig.'),
                      ],
                    ),
                  );
                },
              ),
            ]
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(12.0),
        color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.95),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                child: const Text('CANCEL'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: (_hasChanges && !_isSaving && !_isLoading) ? _saveNotesAndClose : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ).copyWith(
                  backgroundColor: MaterialStateProperty.resolveWith<Color?>(
                        (Set<MaterialState> states) {
                      if (states.contains(MaterialState.disabled)) {
                        return Colors.grey.shade700;
                      }
                      return Theme.of(context).colorScheme.primary;
                    },
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_hasChanges ? 'SAVE CHANGES' : 'Notes Saved'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
