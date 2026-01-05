// lib/features/profile/views/reconciliation_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';
import 'package:the_money_gigs/features/map_venues/repositories/venue_repository.dart';
import 'package:the_money_gigs/features/profile/views/widgets/reconciliation_dialog.dart';
import 'package:the_money_gigs/global_refresh_notifier.dart';

class ReconciliationScreen extends StatefulWidget {
  const ReconciliationScreen({super.key});

  @override
  State<ReconciliationScreen> createState() => _ReconciliationScreenState();
}

class _ReconciliationScreenState extends State<ReconciliationScreen> {
  final VenueRepository _venueRepository = VenueRepository();
  List<StoredLocation> _venuesToReconcile = [];
  int _currentIndex = 0;
  bool _isLoading = true;

  // This key MUST match the one used in `map.dart`
  static const String _venuesKey = 'saved_locations';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAndProcessVenues();
    });
  }

  Future<void> _loadAndProcessVenues() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    // 1. Fetch all public venue IDs from Firestore first.
    final List<String> publicVenueIds = await _venueRepository.getAllPublicVenueIds();

    // 2. Load all venues stored locally on the device.
    final prefs = await SharedPreferences.getInstance();
    final List<String> locationsJson = prefs.getStringList(_venuesKey) ?? [];
    final allLocalVenues = locationsJson
        .map((jsonString) => StoredLocation.fromJson(jsonDecode(jsonString)))
        .toList();

    if (!mounted) return;

    // 3. Filter the local venues.
    // A venue needs reconciliation if it's NOT marked as private on the device
    // AND its ID is NOT in the list of public IDs we got from Firestore.
    final filteredVenues = allLocalVenues.where((localVenue) {
      final bool isAlreadyPublic = publicVenueIds.contains(localVenue.placeId);
      return !localVenue.isPrivate && !isAlreadyPublic;
    }).toList();

    setState(() {
      _venuesToReconcile = filteredVenues;
      _isLoading = false;
    });

    // 4. Start the dialog process if there's anything to reconcile.
    if (_venuesToReconcile.isNotEmpty) {
      _showNextReconciliationDialog();
    } else {
      _finishReconciliation(showNoVenuesMessage: true);
    }
  }

  void _showNextReconciliationDialog() {
    if (_currentIndex >= _venuesToReconcile.length) {
      _finishReconciliation();
      return;
    }

    final venue = _venuesToReconcile[_currentIndex];
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return ReconciliationDialog(
          venue: venue,
          onKeepPrivate: (updatedVenue) {
            Navigator.of(dialogContext).pop();
            _handleKeepPrivate(updatedVenue);
          },
          onPublish: (updatedVenue) {
            Navigator.of(dialogContext).pop();
            _handlePublish(updatedVenue);
          },
        );
      },
    );
  }

  Future<void> _handleKeepPrivate(StoredLocation venue) async {
    // Mark the venue as private locally so it's skipped next time.
    final privateVenue = venue.copyWith(isPrivate: true);
    await _updateLocalVenue(privateVenue);
    _moveToNextVenue();
  }

  // --- REVISED `_handlePublish` METHOD ---
  Future<void> _handlePublish(StoredLocation venue) async {
    // Mark the venue as public for local storage consistency
    final publicVenue = venue.copyWith(isPrivate: false);
    // NOTE: Replace with your actual user ID from your authentication provider
    const userId = 'current_user_id';

    // 1. Save the core venue data to the 'venues' collection.
    // The repository handles the translation (e.g., removing private fields).
    await _venueRepository.saveVenue(publicVenue, userId);

    // 2. If a rating or comment exists, save it to the 'venueRatings' collection.
    if ((publicVenue.comment?.isNotEmpty ?? false) || publicVenue.rating > 0) {
      await _venueRepository.saveVenueRating(
        userId: userId,
        placeId: publicVenue.placeId,
        comment: publicVenue.comment,
        rating: publicVenue.rating,
      );
    }

    // 3. Sync local tags to Firebase (NEW!)
    if (publicVenue.genreTags.isNotEmpty || publicVenue.instrumentTags.isNotEmpty) {
      print('🏷️ Syncing ${publicVenue.genreTags.length} genre tags and ${publicVenue.instrumentTags.length} instrument tags');
      await _venueRepository.syncLocalTagsToFirebase(
        placeId: publicVenue.placeId,
        userId: userId,
        genreTags: publicVenue.genreTags,
        instrumentTags: publicVenue.instrumentTags,
      );
    }

    // 4. Update the local StoredLocation to ensure isPrivate is false and
    // any edits to rating/comment are saved on the device.
    await _updateLocalVenue(publicVenue);
    _moveToNextVenue();
  }

  void _moveToNextVenue() {
    setState(() {
      _currentIndex++;
    });
    // This will either show the next dialog or finish the process.
    _showNextReconciliationDialog();
  }

  void _finishReconciliation({bool showNoVenuesMessage = false}) {
    if (!mounted) return;

    context.read<GlobalRefreshNotifier>().notify();

    final message = showNoVenuesMessage
        ? 'No new venues to reconcile.'
        : 'Venue reconciliation complete.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.of(context).pop();
  }

  Future<void> _updateLocalVenue(StoredLocation venueToUpdate) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> locationsJson = prefs.getStringList(_venuesKey) ?? [];

    List<StoredLocation> venues = locationsJson
        .map((jsonString) => StoredLocation.fromJson(jsonDecode(jsonString)))
        .toList();

    final index = venues.indexWhere((v) => v.placeId == venueToUpdate.placeId);

    if (index != -1) {
      venues[index] = venueToUpdate;
    } else {
      venues.add(venueToUpdate);
    }

    final updatedLocationsJson = venues.map((v) => jsonEncode(v.toJson())).toList();
    await prefs.setStringList(_venuesKey, updatedLocationsJson);
  }

  @override
  Widget build(BuildContext context) {
    int total = _venuesToReconcile.length;
    int current = _currentIndex + 1;
    if (current > total) current = total;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reconcile Venues'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : total > 0
            ? Text(
          'Processing venue $current of $total...',
          style: Theme.of(context).textTheme.headlineSmall,
        )
            : Text(
          'No new venues to reconcile.',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}