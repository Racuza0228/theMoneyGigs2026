// lib/gigs.dart
import 'dart:collection'; // For LinkedHashMap (used by TableCalendar for events)
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'; // <<< ADD THIS IMPORT
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart'; // Import TableCalendar
import 'package:the_money_gigs/global_refresh_notifier.dart'; // Import the notifier
import 'package:url_launcher/url_launcher.dart';

// Import your models
import 'gig_model.dart';    // For Gigs
import 'venue_model.dart'; // For Venues (make sure StoredLocation has 'isArchived' and 'copyWith')
import 'booking_dialog.dart'; // Make sure this is imported


// Enum for Gigs view type
enum GigsViewType { list, calendar }

class GigsPage extends StatefulWidget {
  const GigsPage({super.key});

  @override
  State<GigsPage> createState() => _GigsPageState();
}

class _GigsPageState extends State<GigsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Gig> _loadedGigs = [];
  Map<DateTime, List<Gig>> _calendarEvents = {};

  // --- MODIFIED FOR VENUE ARCHIVING ---
  List<StoredLocation> _allKnownVenues = []; // Stores ALL venues from SharedPreferences
  List<StoredLocation> _displayableVenues = []; // Venues filtered for display (not archived)
  // --- END MODIFICATION ---

  bool _isLoadingGigs = true;
  bool _isLoadingVenues = true;

  GigsViewType _gigsViewType = GigsViewType.list;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  List<Gig> _selectedDayGigs = [];
  static const String _keyGigsList = 'gigs_list';
  static const String _keySavedLocations = 'saved_locations';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedDay = _focusedDay;
    _tabController.addListener(_handleTabSelection);
    _loadAllDataForGigsPage();
    globalRefreshNotifier.addListener(_handleGlobalRefresh);
  }

  void _handleGlobalRefresh() {
    print("GigsPage: Received global refresh notification.");
    if (mounted) {
      _loadAllDataForGigsPage();
    }
  }

  Future<void> _loadAllDataForGigsPage() async {
    print("GigsPage: Loading all data...");
    await Future.wait([
      _loadGigs(),
      _loadVenues(),
    ]);
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging ||
        (_tabController.animation != null && _tabController.animation!.value != _tabController.index.toDouble())) {
      return;
    }
    if (mounted) {
      if (_tabController.index == 0) {
        print("Gigs tab selected. Explicitly refreshing gigs.");
        _loadGigs(); // _prepareCalendarEvents & _onDaySelected are called within _loadGigs
      } else if (_tabController.index == 1) {
        print("Venues tab selected. Explicitly refreshing venues.");
        _loadVenues();
      }
    }
  }

  @override
  void dispose() {
    globalRefreshNotifier.removeListener(_handleGlobalRefresh);
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadGigs() async {
    print("GigsPage: _loadGigs called");
    if (!mounted) return;
    setState(() { _isLoadingGigs = true; });
    final prefs = await SharedPreferences.getInstance();
    final String? gigsJsonString = prefs.getString(_keyGigsList);
    List<Gig> gigs = [];
    if (gigsJsonString != null && gigsJsonString.isNotEmpty) {
      try {
        gigs = Gig.decode(gigsJsonString);
        gigs.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading gigs: $e')));
      }
    }
    if (mounted) {
      setState(() {
        _loadedGigs = gigs;
        _isLoadingGigs = false;
      });
      _prepareCalendarEvents();
      _onDaySelected(_selectedDay ?? _focusedDay, _focusedDay);
    }
  }

  void _prepareCalendarEvents() {
    final events = LinkedHashMap<DateTime, List<Gig>>(equals: isSameDay, hashCode: getHashCode);
    for (var gig in _loadedGigs) {
      final date = DateTime.utc(gig.dateTime.year, gig.dateTime.month, gig.dateTime.day);
      events.putIfAbsent(date, () => []).add(gig);
    }
    if (mounted) setState(() { _calendarEvents = events; });
  }

  int getHashCode(DateTime key) => key.day * 1000000 + key.month * 10000 + key.year;

  List<Gig> _getEventsForDay(DateTime day) {
    final normalizedDay = DateTime.utc(day.year, day.month, day.day);
    return _calendarEvents[normalizedDay] ?? [];
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    final normalizedNewSelectedDay = DateTime.utc(selectedDay.year, selectedDay.month, selectedDay.day);
    final normalizedCurrentSelectedDay = _selectedDay != null ? DateTime.utc(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day) : null;

    if (!isSameDay(normalizedCurrentSelectedDay, normalizedNewSelectedDay)) {
      if (!mounted) return;
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
        _selectedDayGigs = _getEventsForDay(selectedDay);
      });
    } else {
      if (!mounted) return;
      setState(() { _selectedDayGigs = _getEventsForDay(selectedDay); });
    }
  }

  // --- MODIFIED _loadVenues FOR ARCHIVING ---
  Future<void> _loadVenues() async {
    print("GigsPage: _loadVenues called");
    if (!mounted) return;
    setState(() { _isLoadingVenues = true; });
    final prefs = await SharedPreferences.getInstance();
    final List<String>? venuesJson = prefs.getStringList(_keySavedLocations);
    List<StoredLocation> loadedFromPrefs = [];
    if (venuesJson != null) {
      try {
        loadedFromPrefs = venuesJson.map((jsonString) => StoredLocation.fromJson(jsonDecode(jsonString))).toList();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading venues: $e')));
      }
    }
    if (mounted) {
      setState(() {
        _allKnownVenues = loadedFromPrefs; // Store all venues read from prefs
        _displayableVenues = _allKnownVenues.where((venue) => !venue.isArchived).toList(); // Filter for display
        _isLoadingVenues = false;
      });
    }
  }
  // --- END MODIFICATION ---

  Future<void> _deleteGig(Gig gigToDelete) async {
    if (!mounted) return;

    // Create a new list without the gig to delete
    final List<Gig> updatedGigs = List.from(_loadedGigs)..removeWhere((gig) => gig.id == gigToDelete.id);

    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGigsList, Gig.encode(updatedGigs));

    // Update local state for immediate UI reflection
    if (mounted) {
      setState(() {
        _loadedGigs = updatedGigs;
        _prepareCalendarEvents(); // Update calendar events
        _onDaySelected(_selectedDay ?? _focusedDay, _focusedDay); // Update selected day's gigs
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gig "${gigToDelete.venueName}" cancelled.'), backgroundColor: Colors.orange));
      // globalRefreshNotifier.notify() will be called by the caller if needed (e.g., _launchBookingDialogForGig)
    }
  }

  Future<void> _launchBookingDialogForGig(Gig gigToEdit) async {
    if (!mounted) return;

    const String googleApiKey = String.fromEnvironment('GOOGLE_API_KEY');

    final result = await showDialog<dynamic>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return BookingDialog(
          editingGig: gigToEdit,
          preselectedVenue: StoredLocation(
              name: gigToEdit.venueName,
              address: gigToEdit.address,
              coordinates: LatLng(gigToEdit.latitude, gigToEdit.longitude),
              placeId: gigToEdit.placeId ?? 'edited_${gigToEdit.id}',
              isArchived: _allKnownVenues.firstWhere(
                      (v) => (gigToEdit.placeId != null && v.placeId == gigToEdit.placeId) || (v.name == gigToEdit.venueName && v.address == gigToEdit.address),
                  orElse: () => StoredLocation(name: '', address: '', coordinates: LatLng(0,0), placeId: '', isArchived: false)
              ).isArchived
          ),
          googleApiKey: googleApiKey,
          existingGigs: _loadedGigs,
        );
      },
    );

    bool needsUIRefresh = false; // Flag to indicate if local UI elements need rebuilding

    if (result is GigEditResult) {
      if (result.action == GigEditResultAction.updated && result.gig != null) {
        final updatedGig = result.gig!;
        final List<Gig> currentGigs = List.from(_loadedGigs);
        final int gigIndex = currentGigs.indexWhere((g) => g.id == updatedGig.id);

        if (gigIndex != -1) {
          currentGigs[gigIndex] = updatedGig;
          currentGigs.sort((a, b) => a.dateTime.compareTo(b.dateTime));

          // Save to SharedPreferences
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_keyGigsList, Gig.encode(currentGigs));

          // Update local state for immediate UI reflection
          if (mounted) {
            setState(() {
              _loadedGigs = currentGigs;
              // These are needed to update calendar and selected day gigs list
              _prepareCalendarEvents();
              _onDaySelected(_selectedDay ?? _focusedDay, _focusedDay);
            });
            needsUIRefresh = true;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Gig "${updatedGig.venueName}" updated.'), backgroundColor: Colors.green),
            );
          }
        }
      } else if (result.action == GigEditResultAction.deleted && result.gig != null) {
        // The _deleteGig method will handle SharedPreferences and setState for _loadedGigs
        await _deleteGig(result.gig!);
        needsUIRefresh = true; // _deleteGig will also update _loadedGigs and call _prepareCalendarEvents
      } else if (result.action == GigEditResultAction.noChange) {
        print("Gig edit/booking was closed with no changes.");
      }
    } else if (result is Gig) { // This means a NEW gig was created (though this path isn't hit by editing)
      // This case would be for a new gig booked from a hypothetical "+ Book New Gig" button
      // directly on GigsPage that used BookingDialog without an editingGig.
      // For now, _launchBookingDialogForGig is only for editing.
      // If a new gig IS somehow returned here, we should add it.
      List<Gig> currentGigs = List.from(_loadedGigs);
      currentGigs.add(result);
      currentGigs.sort((a, b) => a.dateTime.compareTo(b.dateTime));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyGigsList, Gig.encode(currentGigs));

      if (mounted) {
        setState(() {
          _loadedGigs = currentGigs;
          _prepareCalendarEvents();
          _onDaySelected(_selectedDay ?? _focusedDay, _focusedDay);
        });
        needsUIRefresh = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('New gig "${result.venueName}" booked.'), backgroundColor: Colors.green),
        );
      }
    } else {
      print("BookingDialog closed without specific action or unexpected result type.");
    }

    if (needsUIRefresh) {
      globalRefreshNotifier.notify(); // Notify for other parts of the app
    }
  }

  // --- MODIFIED FOR VENUE ARCHIVING: Renamed from _deleteVenue ---
  Future<void> _archiveVenue(StoredLocation venueToArchive) async {
    if (!mounted) return;

    // Get upcoming gigs for this venue to mention in the dialog
    List<Gig> upcomingGigsAtVenue = _getGigsForVenue(venueToArchive, futureOnly: true);
    String dialogMessage = 'Are you sure you want to archive "${venueToArchive.name}"?';
    if (upcomingGigsAtVenue.isNotEmpty) {
      dialogMessage += '\n\nThis will also DELETE ${upcomingGigsAtVenue.length} upcoming gig(s) scheduled here.';
    } else {
      dialogMessage += '\nIt will be hidden from lists but not permanently deleted.';
    }

    final bool confirmArchive = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Confirm Archive: ${venueToArchive.name}'),
          content: Text(dialogMessage),
          actions: <Widget>[
            TextButton(child: const Text('CANCEL'), onPressed: () => Navigator.of(dialogContext).pop(false)),
            TextButton(
                child: Text('ARCHIVE & DELETE GIGS', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onPressed: () => Navigator.of(dialogContext).pop(true)),
          ],
        );
      },
    ) ?? false;

    if (confirmArchive) {
      setState(() {
        _isLoadingVenues = true; // For venue operation
        _isLoadingGigs = true; // For gig operation
      });

      final prefs = await SharedPreferences.getInstance();
      bool venueArchivedSuccessfully = false;
      bool gigsDeletedSuccessfully = false;

      // 1. Delete associated upcoming gigs
      if (upcomingGigsAtVenue.isNotEmpty) {
        List<String> gigIdsToDelete = upcomingGigsAtVenue.map((gig) => gig.id).toList();
        List<Gig> currentAllGigs = List.from(_loadedGigs); // Make a mutable copy
        currentAllGigs.removeWhere((gig) => gigIdsToDelete.contains(gig.id));

        try {
          await prefs.setString(_keyGigsList, Gig.encode(currentAllGigs));
          gigsDeletedSuccessfully = true;
          print("GigsPage: Deleted ${gigIdsToDelete.length} upcoming gigs for archived venue '${venueToArchive.name}'.");
        } catch (e) {
          print("GigsPage: Error deleting gigs for archived venue: $e");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting associated gigs: $e'), backgroundColor: Colors.red));
          }
        }
      } else {
        gigsDeletedSuccessfully = true; // No gigs to delete, so operation is successful in that regard
      }

      // 2. Archive the venue
      int index = _allKnownVenues.indexWhere((v) => v.placeId == venueToArchive.placeId);
      if (index != -1) {
        List<StoredLocation> updatedAllVenues = List.from(_allKnownVenues);
        updatedAllVenues[index] = updatedAllVenues[index].copyWith(isArchived: true);

        try {
          final List<String> updatedVenuesJson = updatedAllVenues.map((v) => jsonEncode(v.toJson())).toList();
          await prefs.setStringList(_keySavedLocations, updatedVenuesJson);
          venueArchivedSuccessfully = true;
          print("GigsPage: Archived venue '${venueToArchive.name}'.");
        } catch (e) {
          print("GigsPage: Error archiving venue: $e");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error archiving venue: $e'), backgroundColor: Colors.red));
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: Could not find venue to archive.'), backgroundColor: Colors.red));
        }
      }

      // 3. Notify and update UI
      if (venueArchivedSuccessfully || gigsDeletedSuccessfully) { // Notify if any part was successful
        globalRefreshNotifier.notify(); // This will trigger _loadAllDataForGigsPage

        if (mounted) {
          String snackbarMessage = 'Venue "${venueToArchive.name}" archived.';
          if (gigsDeletedSuccessfully && upcomingGigsAtVenue.isNotEmpty) {
            snackbarMessage += ' ${upcomingGigsAtVenue.length} upcoming gig(s) deleted.';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(snackbarMessage), backgroundColor: Colors.orange),
          );
        }
      }

      // Reset loading states after operations, notification will handle UI refresh
      if (mounted) {
        setState(() {
          _isLoadingVenues = false;
          _isLoadingGigs = false;
        });
      }
    }
  }

  List<Gig> _getGigsForVenue(StoredLocation venue, {bool futureOnly = false}) {
    DateTime comparisonDate = DateTime.now();
    return _loadedGigs.where((gig) {
      bool placeIdMatch = gig.placeId != null && gig.placeId!.isNotEmpty && gig.placeId == venue.placeId;
      bool nameMatch = (gig.placeId == null || gig.placeId!.isEmpty) && gig.venueName.toLowerCase() == venue.name.toLowerCase();
      bool dateMatch = futureOnly ? gig.dateTime.isAfter(comparisonDate) : true;
      return (placeIdMatch || nameMatch) && dateMatch;
    }).toList();
  }

  // --- MODIFIED FOR VENUE ARCHIVING: Uses _archiveVenue ---
  Future<void> _showVenueDetailsDialog(StoredLocation venue) async {
    List<Gig> upcomingGigsAtVenue = _getGigsForVenue(venue, futureOnly: true);
    upcomingGigsAtVenue.sort((a,b) => a.dateTime.compareTo(b.dateTime)); // Sort to find the next one
    Gig? nextUpcomingGig = upcomingGigsAtVenue.isNotEmpty ? upcomingGigsAtVenue.first : null;

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(venue.name),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text("Address: ${venue.address.isNotEmpty ? venue.address : 'Not specified'}"),
                const SizedBox(height: 8),
                if (venue.rating > 0) // Simplified rating display
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Row(children: [
                      const Text("Rating: "),
                      Icon(Icons.star, color: Colors.amber, size: 20),
                      const SizedBox(width: 4),
                      Text('${venue.rating.toStringAsFixed(1)} / 5.0'),
                    ]),
                  ),
                if (venue.comment != null && venue.comment!.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 4.0), child: Text("Comment: ${venue.comment!}")),
                const Divider(height: 20, thickness: 1),

                // --- Display Next Upcoming Gig ---
                if (nextUpcomingGig != null) ...[
                  const Text('Next Gig Here:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4.0),
                  Text(
                    '${DateFormat.MMMEd().format(nextUpcomingGig.dateTime)} at ${DateFormat.jm().format(nextUpcomingGig.dateTime)}',
                    style: Theme.of(dialogContext).textTheme.bodyMedium,
                  ),
                ] else ...[
                  const Text("No upcoming gigs scheduled here.", style: TextStyle(fontStyle: FontStyle.italic)),
                ],
                const SizedBox(height: 16),
                // --- Open in Maps Button ---
                ElevatedButton.icon(
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Open in Maps'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(dialogContext).colorScheme.secondary,
                    foregroundColor: Theme.of(dialogContext).colorScheme.onSecondary,
                  ),
                  onPressed: () async {
                    Navigator.of(dialogContext).pop(); // Close dialog first
                    await _openVenueInMap(venue);
                  },
                ),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: <Widget>[
            TextButton(
              child: Text('ARCHIVE', style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
              onPressed: () { Navigator.of(dialogContext).pop(); _archiveVenue(venue); },
            ),
            TextButton(child: const Text('Close'), onPressed: () => Navigator.of(dialogContext).pop()),
          ],
        );
      },
    );
  }

  Future<void> _openVenueInMap(StoredLocation venue) async {
    final lat = venue.coordinates.latitude;
    final lng = venue.coordinates.longitude;
    final String query = Uri.encodeComponent(venue.address.isNotEmpty ? venue.address : venue.name);

    // Universal map link that should work on both iOS and Android
    // It tries to open with a specific query, falling back to just lat/lng
    Uri mapUri = Uri.parse('https://maps.google.com/maps?q=$query&ll=$lat,$lng');
    // For iOS, you can use: Uri.parse('maps://?q=$query&ll=$lat,$lng');
    // For Android, you can use: Uri.parse('geo:$lat,$lng?q=$query');
    // The https link is more universal as a first attempt.

    if (await canLaunchUrl(mapUri)) {
      await launchUrl(mapUri, mode: LaunchMode.externalApplication);
    } else {
      // Fallback if the specific query link doesn't work, try just lat/lng (less specific)
      Uri fallbackMapUri = Uri.parse('https://maps.google.com/maps?q=$lat,$lng');
      if (await canLaunchUrl(fallbackMapUri)) {
        await launchUrl(fallbackMapUri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open map application.')),
          );
        }
        print('Could not launch $mapUri or $fallbackMapUri');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: 0,
          child: TabBar(
            controller: _tabController,
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Theme.of(context).colorScheme.primary,
            tabs: const [
              Tab(icon: Icon(Icons.event_note), text: 'Upcoming Gigs'),
              Tab(icon: Icon(Icons.location_city), text: 'Saved Venues'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildGigsTabContent(),
              _buildVenuesList(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGigsTabContent() {
    if (_isLoadingGigs && _loadedGigs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_isLoadingGigs && _loadedGigs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(padding: const EdgeInsets.all(8.0), child: _buildGigsViewToggle()),
            const Expanded(child: Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text('No upcoming gigs booked yet.\nCalculate and book one!', textAlign: TextAlign.center)))),
          ],
        ),
      );
    }
    return Column(
      children: [
        Padding(padding: const EdgeInsets.only(top: 8.0, left: 8.0, right: 8.0, bottom: 8.0), child: _buildGigsViewToggle()),
        if (_isLoadingGigs && _loadedGigs.isNotEmpty) // Show small loader if gigs are already loaded but refreshing
          const Padding(padding: EdgeInsets.all(8.0), child: Center(child: SizedBox(width:24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)))),
        Expanded(child: _gigsViewType == GigsViewType.list ? _buildGigsListView() : _buildGigsCalendarView()),
      ],
    );
  }

  Widget _buildGigsViewToggle() {
    return SegmentedButton<GigsViewType>(
      segments: const <ButtonSegment<GigsViewType>>[
        ButtonSegment<GigsViewType>(value: GigsViewType.list, label: Text('List'), icon: Icon(Icons.list)),
        ButtonSegment<GigsViewType>(value: GigsViewType.calendar, label: Text('Calendar'), icon: Icon(Icons.calendar_today)),
      ],
      selected: <GigsViewType>{_gigsViewType},
      onSelectionChanged: (Set<GigsViewType> newSelection) { if (!mounted) return; setState(() { _gigsViewType = newSelection.first; }); },
    );
  }

  Widget _buildGigsListView() {
    if (_loadedGigs.isEmpty) return const Center(child: Text('No gigs to display in list view.', textAlign: TextAlign.center));
    return ListView.builder(
      itemCount: _loadedGigs.length,
      itemBuilder: (context, index) {
        final gig = _loadedGigs[index];
        bool isPast = gig.dateTime.isBefore(DateTime.now().subtract(const Duration(days:1)));
        return Card(
          elevation: isPast ? 1 : 2,
          color: isPast ? Colors.grey.shade200 : Theme.of(context).cardColor,
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isPast ? Colors.grey.shade400 : Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              child: Text(DateFormat('d').format(gig.dateTime)),
            ),
            title: Text(gig.venueName, style: TextStyle(fontWeight: FontWeight.bold, color: isPast ? Colors.grey.shade700 : Theme.of(context).textTheme.titleLarge?.color)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${DateFormat.yMMMEd().format(gig.dateTime)} at ${DateFormat.jm().format(gig.dateTime)}', style: TextStyle(color: isPast ? Colors.grey.shade600 : Theme.of(context).textTheme.bodyMedium?.color)),
              Text('Pay: \$${gig.pay.toStringAsFixed(2)} - ${gig.gigLengthHours.toStringAsFixed(1)} hrs (+ ${gig.rehearsalLengthHours.toStringAsFixed(1)} hrs rehearsal)', style: TextStyle(color: isPast ? Colors.grey.shade600 : Theme.of(context).textTheme.bodyMedium?.color)),
              if (gig.address.isNotEmpty) Text(gig.address, style: TextStyle(fontSize: 12, color: isPast ? Colors.grey.shade500 : Colors.grey.shade600)),
            ]),
            isThreeLine: true,
            onTap: () => _launchBookingDialogForGig(gig),
          ),
        );
      },
    );
  }

  Widget _buildGigsCalendarView() {
    if (_isLoadingGigs && _calendarEvents.isEmpty) return const Center(child: CircularProgressIndicator());
    return Column(children: [ // Removed fixed Container to allow Column to size naturally
      Container(
        color: Colors.white, // Consider Theme.of(context).cardColor or similar for theming
        padding: const EdgeInsets.only(bottom: 8.0),
        child: TableCalendar<Gig>(
          firstDay: DateTime.utc(DateTime.now().year - 1, 1, 1),
          lastDay: DateTime.utc(DateTime.now().year + 5, 12, 31),
          focusedDay: _focusedDay,
          calendarFormat: _calendarFormat,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          eventLoader: _getEventsForDay,
          startingDayOfWeek: StartingDayOfWeek.sunday,
          calendarStyle: CalendarStyle(
            defaultTextStyle: const TextStyle(color: Colors.black87), weekendTextStyle: TextStyle(color: Colors.red.shade700), outsideTextStyle: TextStyle(color: Colors.grey.shade400),
            disabledTextStyle: TextStyle(color: Colors.grey.shade300), todayDecoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer.withAlpha(128), shape: BoxShape.circle),
            todayTextStyle: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer), selectedDecoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
            selectedTextStyle: TextStyle(color: Theme.of(context).colorScheme.onPrimary), markerDecoration: BoxDecoration(color: Theme.of(context).colorScheme.secondary, shape: BoxShape.circle),
          ),
          daysOfWeekStyle: DaysOfWeekStyle(weekdayStyle: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold), weekendStyle: TextStyle(color: Colors.red.shade600, fontWeight: FontWeight.bold)),
          headerStyle: HeaderStyle(
            titleTextStyle: const TextStyle(color: Colors.black87, fontSize: 17.0, fontWeight: FontWeight.bold), formatButtonVisible: true, titleCentered: true, formatButtonShowsNext: false,
            formatButtonTextStyle: TextStyle(color: Theme.of(context).colorScheme.primary), formatButtonDecoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.primary), borderRadius: BorderRadius.circular(12.0)),
            leftChevronIcon: Icon(Icons.chevron_left, color: Colors.black54), rightChevronIcon: Icon(Icons.chevron_right, color: Colors.black54),
          ),
          onDaySelected: _onDaySelected,
          onFormatChanged: (format) { if (_calendarFormat != format) { if (!mounted) return; setState(() { _calendarFormat = format; }); } },
          onPageChanged: (focusedDay) { if (!mounted) return; setState(() { _focusedDay = focusedDay; }); _onDaySelected(focusedDay, focusedDay); },
        ),
      ),
      Expanded(
        child: _selectedDayGigs.isNotEmpty
            ? ListView.builder(
          itemCount: _selectedDayGigs.length,
          itemBuilder: (context, index) {
            final gig = _selectedDayGigs[index];
            bool isPast = gig.dateTime.isBefore(DateTime.now().subtract(const Duration(days:1)));
            return Card(
              elevation: isPast ? 0.5 : 1, color: isPast ? Colors.white.withOpacity(0.7) : Colors.white, margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              child: ListTile(
                title: Text(gig.venueName, style: TextStyle(fontWeight: FontWeight.bold, color: isPast ? Colors.grey.shade600 : Colors.black87)),
                subtitle: Text('${DateFormat.jm().format(gig.dateTime)} - \$${gig.pay.toStringAsFixed(2)}', style: TextStyle(color: isPast ? Colors.grey.shade500 : Colors.black54)),
                onTap: () => _launchBookingDialogForGig(gig),
              ),
            );
          },
        )
            : Center(child: Text(_selectedDay != null ? 'No gigs for ${DateFormat.yMMMEd().format(_selectedDay!)}.' : 'Select a day to see gigs.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87))),
      ),
    ]);
  }

  // --- MODIFIED _buildVenuesList FOR ARCHIVING ---
  Widget _buildVenuesList() {
    if (_isLoadingVenues && _displayableVenues.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_displayableVenues.isEmpty) {
      return Center( /* ... (no change to empty message) ... */ );
    }

    List<StoredLocation> sortedDisplayableVenues = List.from(_displayableVenues)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return ListView.builder(
      itemCount: sortedDisplayableVenues.length,
      itemBuilder: (context, index) {
        final venue = sortedDisplayableVenues[index];
        final double? rating = venue.rating;
        // Get count of future gigs for this venue
        final List<Gig> futureGigsForVenue = _getGigsForVenue(venue, futureOnly: true);
        final int futureGigsCount = futureGigsForVenue.length;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: ListTile(
            leading: Icon(Icons.business, color: Theme.of(context).colorScheme.secondary),
            title: Row( // Use Row to add gig count next to name
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(venue.name, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                if (futureGigsCount > 0)
                  Text(
                    ' ($futureGigsCount upcoming)',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontStyle: FontStyle.italic),
                  ),
              ],
            ),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(venue.address.isNotEmpty ? venue.address : 'Address not specified'),
              if (rating != null && rating > 0)
                Row(children: [
                  Icon(Icons.star, color: Colors.amber, size: 16),
                  const SizedBox(width: 4),
                  Text(
                      '${venue.rating!.toStringAsFixed(1)} ★ ${venue.comment != null && venue.comment!.isNotEmpty ? "(${venue.comment})" : ""}',
                      style: const TextStyle(fontSize: 12))
                ])
              else if (venue.comment != null && venue.comment!.isNotEmpty)
                Text("Comment: ${venue.comment}", style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic))
              else
                const Text("Not yet rated or commented", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
            ]),
            onTap: () => _showVenueDetailsDialog(venue),
          ),
        );
      },
    );
  }
// --- END MODIFICATION ---
}
