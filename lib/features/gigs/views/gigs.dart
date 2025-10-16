// lib/gigs.dart
import 'dart:collection'; // For LinkedHashMap (used by TableCalendar for events)
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart'; // Import TableCalendar
import 'package:the_money_gigs/global_refresh_notifier.dart'; // Import the notifier

// Import your models
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:the_money_gigs/features/map_venues/models/jam_session_model.dart'; // <<<--- IMPORT THE NEW MODEL
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';
import 'package:the_money_gigs/features/gigs/widgets/booking_dialog.dart';
import 'package:the_money_gigs/features/map_venues/widgets/jam_open_mic_dialog.dart';
import 'package:the_money_gigs/features/notes/views/notes_page.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_contact.dart';
import 'package:the_money_gigs/core/services/gig_embed_service.dart';
// Add this line with your other imports
import 'package:the_money_gigs/features/map_venues/widgets/venue_contact_dialog.dart';
import 'package:the_money_gigs/features/map_venues/widgets/venue_details_dialog.dart';

import '../../app_demo/providers/demo_provider.dart';



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

  List<StoredLocation> _allKnownVenues = [];
  List<StoredLocation> _displayableVenues = [];

  bool _isLoadingGigs = true;
  bool _isLoadingVenues = true;

  GigsViewType _gigsViewType = GigsViewType.list;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  List<Gig> _selectedDayGigs = [];
  static const String _keyGigsList = 'gigs_list';
  static const String _keySavedLocations = 'saved_locations';

  final Gig _demoGig = Gig(
    id: DemoProvider.demoGigId,
    venueName: 'Kroger Marketplace',
    address: '4613 Marburg Ave, Cincinnati, OH 45209',
    placeId: DemoProvider.demoVenuePlaceId,
    latitude: 39.1602761,
    longitude: -84.429593,
    dateTime: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 20, 0),
    pay: 250,
    gigLengthHours: 3,
    driveSetupTimeHours: 2.5,
    rehearsalLengthHours: 2,
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedDay = _focusedDay;
    _tabController.addListener(_handleTabSelection);
    _loadAllDataForGigsPage();
    globalRefreshNotifier.addListener(_handleGlobalRefresh);

    // Listen for changes in the demo state.
    Provider.of<DemoProvider>(context, listen: false)
        .addListener(_onDemoStateChanged);
  }

  @override
  void dispose() {
    globalRefreshNotifier.removeListener(_handleGlobalRefresh);
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();

    Provider.of<DemoProvider>(context, listen: false)
        .removeListener(_onDemoStateChanged);
    super.dispose();
  }

  void _onDemoStateChanged() {
    final demoProvider = Provider.of<DemoProvider>(context, listen: false);

    if (!mounted) return;

    setState(() {
      // When we get to the "My Gigs" step, add the demo gig to the list.
      if (demoProvider.isDemoModeActive && demoProvider.currentStep == 13) {
        // Ensure it's not already in the list to prevent duplicates.
        _loadedGigs.removeWhere((g) => g.id == _demoGig.id);
        _loadedGigs.insert(0, _demoGig); // Add to the top of the list.
        _loadedGigs.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      }
      // When the demo ends, remove the demo gig.
      else if (!demoProvider.isDemoModeActive) {
        _loadedGigs.removeWhere((g) => g.id == _demoGig.id);
      }

      // Refresh the calendar events after modifying the list.
      _prepareCalendarEvents();
      _onDaySelected(_selectedDay ?? _focusedDay, _focusedDay);
    });
  }

  void _handleGlobalRefresh() {
    if (mounted) {
      _loadAllDataForGigsPage();
    }
  }

  Future<void> _loadAllDataForGigsPage() async {
    await _loadVenues();

    // This is the critical change: by checking `mounted` again,
    // we ensure that the state update from `_loadVenues` has had a chance
    // to complete before we proceed to load the gigs.
    if (mounted) {
      await _loadGigs();
    }
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging ||
        (_tabController.animation != null && _tabController.animation!.value != _tabController.index.toDouble())) {
      return;
    }
  }

  Future<void> _loadGigs() async {
    if (!mounted) return;
    setState(() { _isLoadingGigs = true; });
    final prefs = await SharedPreferences.getInstance();
    final String? gigsJsonString = prefs.getString(_keyGigsList);
    List<Gig> actualGigs = [];
    if (gigsJsonString != null && gigsJsonString.isNotEmpty) {
      try {
        actualGigs = Gig.decode(gigsJsonString);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading actual gigs: $e')));
      }
    }
    // --- START OF FIX: Add [PRIVATE] prefix to actual gigs ---
    List<Gig> processedActualGigs = actualGigs.map((gig) {
      final sourceVenue = _allKnownVenues.firstWhere(
            (v) => v.placeId == gig.placeId,
        orElse: () => StoredLocation(placeId: '', name: gig.venueName, address: '', coordinates: const LatLng(0,0)),
      );
      if (sourceVenue.isPrivate) {
        return gig.copyWith(venueName: '[PRIVATE] ${gig.venueName}');
      }
      return gig;
    }).toList();
    // --- END OF FIX ---

    List<Gig> jamOpenMicGigs = _generateJamOpenMicGigs();
    List<Gig> allDisplayGigs = [...processedActualGigs, ...jamOpenMicGigs]; // Use processed list
    allDisplayGigs.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    if (mounted) {
      setState(() {
        _loadedGigs = allDisplayGigs;
        _isLoadingGigs = false;
      });
      _prepareCalendarEvents();
      _onDaySelected(_selectedDay ?? _focusedDay, _focusedDay);
    }
  }

  List<Gig> _generateJamOpenMicGigs() {
    List<Gig> jamGigs = [];
    DateTime today = DateTime.now();
    DateTime calculationStartDate = DateTime(today.year, today.month, today.day);
    DateTime rangeEndDate = DateTime(today.year, today.month + 6, today.day);

    for (var venue in _allKnownVenues) {
      if (venue.isArchived || venue.isMuted) {
        continue;
      }
      // Iterate over each session configured for the venue
      for (var session in venue.jamSessions) {
        if (!session.showInGigsList) {
          continue;
        }

        int targetWeekday = session.day.index + 1;

        if (session.frequency == JamFrequencyType.weekly) {
          DateTime currentDate = calculationStartDate;
          while (currentDate.isBefore(rangeEndDate) || isSameDay(currentDate, rangeEndDate)) {
            if (currentDate.weekday == targetWeekday) {
              _addJamGigIfApplicable(jamGigs, venue, session, currentDate);
            }
            currentDate = currentDate.add(const Duration(days: 1));
          }
        } else if (session.frequency == JamFrequencyType.biWeekly) {
          DateTime firstPossibleOccurrence = _findNextDayOfWeek(calculationStartDate, targetWeekday);
          DateTime cycleAnchorDate = _findNextDayOfWeek(DateTime(2020, 1, 1), targetWeekday);
          DateTime currentTestDate = firstPossibleOccurrence;
          while (currentTestDate.isBefore(rangeEndDate) || isSameDay(currentTestDate, rangeEndDate)) {
            if (currentTestDate.weekday == targetWeekday) {
              int weeksDifference = currentTestDate.difference(cycleAnchorDate).inDays ~/ 7;
              if (weeksDifference % 2 == 0) {
                _addJamGigIfApplicable(jamGigs, venue, session, currentTestDate);
              }
            }
            // Smartly jump to the next week's target day to optimize
            currentTestDate = currentTestDate.add(const Duration(days: 7));
          }
        } else if (session.frequency == JamFrequencyType.customNthDay && session.nthValue != null && session.nthValue! > 0) {
          int nth = session.nthValue!;
          DateTime firstPossibleOccurrence = _findNextDayOfWeek(calculationStartDate, targetWeekday);
          DateTime cycleAnchorDate = _findNextDayOfWeek(DateTime(2020, 1, 1), targetWeekday);
          DateTime currentTestDate = firstPossibleOccurrence;
          while (currentTestDate.isBefore(rangeEndDate) || isSameDay(currentTestDate, rangeEndDate)) {
            if (currentTestDate.weekday == targetWeekday) {
              int weeksDifference = currentTestDate.difference(cycleAnchorDate).inDays ~/ 7;
              if (weeksDifference % nth == 0) {
                _addJamGigIfApplicable(jamGigs, venue, session, currentTestDate);
              }
            }
            currentTestDate = currentTestDate.add(const Duration(days: 7));
          }
        } else if (session.frequency == JamFrequencyType.monthlySameDay && session.nthValue != null && session.nthValue! > 0) {
          int nthOccurrence = session.nthValue!;
          DateTime monthIterator = DateTime(calculationStartDate.year, calculationStartDate.month, 1);
          while (monthIterator.isBefore(rangeEndDate) || (monthIterator.year == rangeEndDate.year && monthIterator.month == rangeEndDate.month)) {
            DateTime? nthDayInMonth = _findNthSpecificWeekdayOfMonth(monthIterator.year, monthIterator.month, targetWeekday, nthOccurrence);
            if (nthDayInMonth != null) {
              if (!nthDayInMonth.isBefore(calculationStartDate)) {
                _addJamGigIfApplicable(jamGigs, venue, session, nthDayInMonth);
              }
            }
            monthIterator = DateTime(monthIterator.year, monthIterator.month + 1, 1);
          }
        }
      }
    }
    return jamGigs;
  }

  void _addJamGigIfApplicable(List<Gig> jamGigs, StoredLocation venue, JamSession session, DateTime dateOfJam) {
    DateTime jamDateTime = DateTime(
      dateOfJam.year,
      dateOfJam.month,
      dateOfJam.day,
      session.time.hour,
      session.time.minute,
    );
    DateTime now = DateTime.now();

    if (jamDateTime.isAfter(now)) {
      // Create a more unique ID that includes the session ID
      final String uniqueId = 'jam_${venue.placeId}_${session.id}_${DateFormat('yyyyMMddHHmm').format(jamDateTime)}';
      bool alreadyExists = jamGigs.any((g) => g.id == uniqueId);

      if (!alreadyExists) {
        // --- START OF FIX: Add [PRIVATE] prefix to jam gigs ---
        String venueName = venue.name;
        if (venue.isPrivate) {
          venueName = '[PRIVATE] $venueName';
        }
        venueName = '[JAM] $venueName'; // Prepend [JAM] after [PRIVATE]
        // --- END OF FIX ---

        if(session.style != null && session.style!.isNotEmpty){
          venueName += " (${session.style})";
        }
        jamGigs.add(
          Gig(
            id: uniqueId,
            venueName: venueName,
            latitude: venue.coordinates.latitude,
            longitude: venue.coordinates.longitude,
            address: venue.address,
            placeId: venue.placeId,
            dateTime: jamDateTime,
            pay: 0,
            gigLengthHours: 2, // Assuming a default length
            driveSetupTimeHours: 0,
            rehearsalLengthHours: 0,
            isJamOpenMic: true,
          ),
        );
      }
    }
  }

  DateTime _findNextDayOfWeek(DateTime startDate, int targetWeekday) {
    DateTime date = DateTime(startDate.year, startDate.month, startDate.day);
    while (date.weekday != targetWeekday) {
      date = date.add(const Duration(days: 1));
    }
    return date;
  }

  DateTime? _findNthSpecificWeekdayOfMonth(int year, int month, int targetWeekday, int nth) {
    if (nth < 1 || nth > 5) return null;
    int occurrences = 0;
    for (int day = 1; day <= DateTime(year, month + 1, 0).day; day++) {
      DateTime currentDate = DateTime(year, month, day);
      if (currentDate.weekday == targetWeekday) {
        occurrences++;
        if (occurrences == nth) {
          return currentDate;
        }
      }
    }
    return null;
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
      if (mounted) setState(() { _selectedDayGigs = _getEventsForDay(selectedDay); });
    }
  }

  Future<void> _loadVenues() async {
    if (!mounted) return;
    setState(() { _isLoadingVenues = true; });
    final prefs = await SharedPreferences.getInstance();
    final List<String>? venuesJson = prefs.getStringList(_keySavedLocations);
    List<StoredLocation> loadedFromPrefs = [];
    if (venuesJson != null) {
      try {
        loadedFromPrefs = venuesJson.map((jsonString) {
          try {
            return StoredLocation.fromJson(jsonDecode(jsonString));
          } catch (e) {
            print("Error decoding a single venue: $jsonString. Error: $e");
            return null;
          }
        }).whereType<StoredLocation>().toList();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading some venues: $e')));
      }
    }
    if (mounted) {
      setState(() {
        _allKnownVenues = loadedFromPrefs;
        _displayableVenues = _allKnownVenues.where((venue) => !venue.isArchived).toList();
        _isLoadingVenues = false;
      });
    }
  }

  void _launchNotesPageForGig(Gig gig) {
    if (gig.isJamOpenMic) return;
    // Strip [PRIVATE] from the gig name before passing to dialog, if needed, though ID is primary
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NotesPage(editingGigId: gig.id),
      ),
    );
  }

  Future<void> _launchBookingDialogForGig(Gig gigToEdit) async {
    // We must use the original gig data for editing, not the one with a modified name.
    final String? originalGigId = gigToEdit.isJamOpenMic ? null : gigToEdit.id;
    Gig? originalGig;
    if (originalGigId != null) {
      final prefs = await SharedPreferences.getInstance();
      final gigsJson = prefs.getString(_keyGigsList) ?? '[]';
      final allGigs = Gig.decode(gigsJson);
      originalGig = allGigs.firstWhere((g) => g.id == originalGigId, orElse: () => gigToEdit);
    } else {
      originalGig = gigToEdit;
    }


    if (originalGig.isJamOpenMic) {
      final sourceVenue = _allKnownVenues.firstWhere(
            (v) => v.placeId == originalGig!.placeId,
        orElse: () => StoredLocation(placeId: '', name: '', address: '', coordinates: const LatLng(0,0)),
      );
      if (sourceVenue.placeId.isEmpty) return;
      await showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: Text(sourceVenue.name),
            content: const Text('This is a recurring Jam/Open Mic session.'),
            actions: <Widget>[
              TextButton(
                child: const Text('CLOSE'),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              TextButton(
                child: const Text('VIEW VENUE DETAILS'),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _showVenueDetailsDialog(sourceVenue);
                },
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.errorContainer),
                child: Text('HIDE FROM MY GIGS', style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await _setVenueMutedState(sourceVenue, true);
                },
              ),
            ],
          );
        },
      );
      return;
    }
    if (!mounted) return;
    const String googleApiKey = String.fromEnvironment('GOOGLE_API_KEY');
    final result = await showDialog<dynamic>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return BookingDialog(
          editingGig: originalGig, // Pass the original gig object
          googleApiKey: googleApiKey,
          existingGigs: _loadedGigs.where((g) => !g.isJamOpenMic).toList(),
        );
      },
    );

    // --- START OF REVISED CODE ---
    if (result is GigEditResult && result.action != GigEditResultAction.noChange) {
      if (result.action == GigEditResultAction.updated && result.gig != null) {
        // This part for updating is correct and does not need to change.
        // It's good practice to notify and reload.
        globalRefreshNotifier.notify();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gig "${result.gig!.venueName}" updated.'), backgroundColor: Colors.green));

      } else if (result.action == GigEditResultAction.deleted && result.gig != null) {
        // THIS IS THE FIX: Call the _deleteGig method.
        await _deleteGig(result.gig!);

        // Show the confirmation SnackBar *after* the deletion has been processed.
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gig "${result.gig!.venueName}" cancelled.'), backgroundColor: Colors.orange));
      }
    } else if (result is Gig) {
      // This part for handling a newly booked gig is also correct.
      // It's good practice to notify and reload.
      globalRefreshNotifier.notify();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('New gig "${result.venueName}" booked.'), backgroundColor: Colors.green));
    }
    // --- END OF REVISED CODE ---
  }

  Future<void> _deleteGig(Gig gigToDelete) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Get the current list of gigs from SharedPreferences
      final String? gigsJsonString = prefs.getString(_keyGigsList);
      List<Gig> allGigs = (gigsJsonString != null) ? Gig.decode(gigsJsonString) : [];

      // Remove the gig with the matching ID
      allGigs.removeWhere((g) => g.id == gigToDelete.id);

      // Save the updated list back to SharedPreferences
      await prefs.setString(_keyGigsList, Gig.encode(allGigs));

      // Notify the rest of the app (like the map) that data has changed
      globalRefreshNotifier.notify();

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cancelling gig: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _setVenueMutedState(StoredLocation venue, bool isMuted) async {
    final int index = _allKnownVenues.indexWhere((v) => v.placeId == venue.placeId);
    if (index != -1) {
      _allKnownVenues[index] = _allKnownVenues[index].copyWith(isMuted: isMuted);
      final prefs = await SharedPreferences.getInstance();
      final List<String> updatedVenuesJson = _allKnownVenues.map((v) => jsonEncode(v.toJson())).toList();
      await prefs.setStringList(_keySavedLocations, updatedVenuesJson);
      globalRefreshNotifier.notify();
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isMuted ? 'Jam sessions for ${venue.name} will be hidden from the gigs list.' : 'Jam sessions for ${venue.name} will now be shown in the gigs list.'),
            backgroundColor: Colors.blueAccent,
          ),
        );
      }
    }
  }

  Future<void> _archiveVenue(StoredLocation venueToArchive) async {
    if (!mounted) return;
    // CORRECTED: Only check for REAL, non-jam gigs.
    List<Gig> upcomingActualGigsAtVenue = _getGigsForVenue(venueToArchive, futureOnly: true)
        .where((gig) => !gig.isJamOpenMic)
        .toList();

    String dialogMessage = 'Are you sure you want to archive "${venueToArchive.name}"?';
    if (upcomingActualGigsAtVenue.isNotEmpty) {
      dialogMessage += '\n\nThis will also DELETE ${upcomingActualGigsAtVenue.length} upcoming actual gig(s) scheduled here.';
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
                child: Text('ARCHIVE', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onPressed: () => Navigator.of(dialogContext).pop(true)),
          ],
        );
      },
    ) ?? false;

    if (confirmArchive) {
      setState(() { _isLoadingVenues = true; _isLoadingGigs = true; });
      final prefs = await SharedPreferences.getInstance();
      if (upcomingActualGigsAtVenue.isNotEmpty) {
        List<String> gigIdsToDelete = upcomingActualGigsAtVenue.map((gig) => gig.id).toList();
        final String? gigsJsonString = prefs.getString(_keyGigsList);
        List<Gig> currentAllActualGigs = (gigsJsonString != null) ? Gig.decode(gigsJsonString) : [];
        currentAllActualGigs.removeWhere((gig) => gigIdsToDelete.contains(gig.id));
        await prefs.setString(_keyGigsList, Gig.encode(currentAllActualGigs));
      }
      int index = _allKnownVenues.indexWhere((v) => v.placeId == venueToArchive.placeId);
      if (index != -1) {
        List<StoredLocation> updatedAllVenues = List.from(_allKnownVenues);
        updatedAllVenues[index] = updatedAllVenues[index].copyWith(isArchived: true);
        final List<String> updatedVenuesJson = updatedAllVenues.map((v) => jsonEncode(v.toJson())).toList();
        await prefs.setStringList(_keySavedLocations, updatedVenuesJson);
      }
      globalRefreshNotifier.notify();
      if (mounted) {
        String snackbarMessage = 'Venue "${venueToArchive.name}" archived.';
        if (upcomingActualGigsAtVenue.isNotEmpty) {
          snackbarMessage += ' ${upcomingActualGigsAtVenue.length} upcoming actual gig(s) deleted.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(snackbarMessage), backgroundColor: Colors.orange),
        );
      }
    }
  }

  Future<void> _editVenueContact(StoredLocation venue) async {
    final updatedContact = await showDialog<VenueContact>(
      context: context,
      barrierDismissible: false,
      builder: (_) => VenueContactDialog(venue: venue),
    );
    if (updatedContact != null && mounted) {
      final int index = _allKnownVenues.indexWhere((v) => v.placeId == venue.placeId);
      if (index != -1) {
        _allKnownVenues[index] = _allKnownVenues[index].copyWith(contact: updatedContact);
        final prefs = await SharedPreferences.getInstance();
        final List<String> updatedVenuesJson = _allKnownVenues.map((v) => jsonEncode(v.toJson())).toList();
        await prefs.setStringList(_keySavedLocations, updatedVenuesJson);
        globalRefreshNotifier.notify();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Contact updated for ${venue.name}.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _updateVenueJamNightSettings(StoredLocation updatedVenue) async {
    final prefs = await SharedPreferences.getInstance();
    int index = _allKnownVenues.indexWhere((v) => v.placeId == updatedVenue.placeId);
    if (index != -1) {
      List<StoredLocation> updatedAllVenuesList = List.from(_allKnownVenues);
      updatedAllVenuesList[index] = updatedVenue;
      final List<String> updatedVenuesJson = updatedAllVenuesList.map((v) => jsonEncode(v.toJson())).toList();
      await prefs.setStringList(_keySavedLocations, updatedVenuesJson);
      if (mounted) {
        globalRefreshNotifier.notify();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Jam/Open Mic settings updated for ${updatedVenue.name}.'), backgroundColor: Colors.green),
        );
      }
    }
  }

  List<Gig> _getGigsForVenue(StoredLocation venue, {bool futureOnly = false}) {
    DateTime comparisonDate = DateTime.now();
    return _loadedGigs.where((gig) {
      bool venueMatch = (gig.placeId != null && gig.placeId!.isNotEmpty && gig.placeId == venue.placeId) ||
          (gig.placeId == null && gig.venueName.toLowerCase().contains(venue.name.toLowerCase()));
      bool dateMatch = true;
      if (futureOnly) {
        DateTime gigDayStart = DateTime(gig.dateTime.year, gig.dateTime.month, gig.dateTime.day);
        DateTime todayStart = DateTime(comparisonDate.year, comparisonDate.month, comparisonDate.day);
        dateMatch = !gigDayStart.isBefore(todayStart);
      }
      return venueMatch && dateMatch;
    }).toList();
  }

  Future<void> _showVenueDetailsDialog(StoredLocation venue) async {
    if (!mounted) return;

    List<Gig> upcomingGigsAtVenue = _getGigsForVenue(venue, futureOnly: true)
        .where((g) => !g.isJamOpenMic)
        .toList();
    upcomingGigsAtVenue.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    Gig? nextUpcomingGig = upcomingGigsAtVenue.isNotEmpty ? upcomingGigsAtVenue.first : null;

    await showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return VenueDetailsDialog(
            venue: venue,
            nextGig: nextUpcomingGig,
            onArchive: () {
              Navigator.of(dialogContext).pop();
              _archiveVenue(venue);
            },
            onBook: (venueToSaveAndBook) async {
              await _updateAndSaveLocationReview(venueToSaveAndBook);

              final newGig = await _launchBookingDialogForVenue(venueToSaveAndBook);

              if(mounted) Navigator.of(dialogContext).pop();

              if (newGig != null) {
                await Future.delayed(const Duration(milliseconds: 100));
                _showVenueDetailsDialog(venueToSaveAndBook);
              }
            },
            onSave: (updatedVenue) {
              _updateAndSaveLocationReview(updatedVenue);
            },
            onEditContact: () {
              Navigator.of(dialogContext).pop();
              _editVenueContact(venue);
            },
            onEditJamSettings: () async {
              Navigator.of(dialogContext).pop();
              final result = await showDialog<JamOpenMicDialogResult>(
                context: context,
                builder: (_) => JamOpenMicDialog(venue: venue),
              );
              if (result != null && result.settingsChanged && result.updatedVenue != null) {
                await _updateVenueJamNightSettings(result.updatedVenue!);
              }
            },
          );
        });
  }

  Future<void> _updateAndSaveLocationReview(StoredLocation updatedLocation) async {
    List<StoredLocation> updatedAllVenues = List.from(_allKnownVenues);
    int index = updatedAllVenues.indexWhere((loc) => loc.placeId == updatedLocation.placeId);

    if (index != -1) {
      updatedAllVenues[index] = updatedLocation;
    } else {
      updatedAllVenues.add(updatedLocation);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> locationsJson = updatedAllVenues.map((loc) => jsonEncode(loc.toJson())).toList();
      await prefs.setStringList(_keySavedLocations, locationsJson);
      globalRefreshNotifier.notify();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${updatedLocation.name} saved!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving venue: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<Gig?> _launchBookingDialogForVenue(StoredLocation venue) async {
    const String googleApiKey = String.fromEnvironment('GOOGLE_API_KEY');
    return await showDialog<Gig>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return BookingDialog(
          preselectedVenue: venue,
          googleApiKey: googleApiKey,
          existingGigs: _loadedGigs.where((g) => !g.isJamOpenMic).toList(),
        );
      },
    );
  }

  void _showEmbedCodeDialog() {
    // --- START OF FIX: Filter private gigs before exporting ---
    final publicGigs = _loadedGigs.where((gig) {
      final sourceVenue = _allKnownVenues.firstWhere(
            (v) => v.placeId == gig.placeId,
        orElse: () => StoredLocation(placeId: '', name: '', address: '', coordinates: const LatLng(0,0)),
      );
      return !sourceVenue.isPrivate;
    }).toList();
    final String embedCode = GigEmbedService.generateEmbedCode(publicGigs);
    // --- END OF FIX ---

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Embed Gigs on Your Website'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Copy the HTML code below and paste it into your website editor. This will display a list of your upcoming public gigs.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.grey[200],
                  child: SelectableText(
                    embedCode,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.black),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Copy to Clipboard'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: embedCode));
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Embed code copied to clipboard!'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            ),
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
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
    bool hasUpcomingGigs =
    _loadedGigs.any((gig) => !gig.isJamOpenMic && gig.dateTime.isAfter(DateTime.now()));

    if (_isLoadingGigs && _loadedGigs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_isLoadingGigs && _loadedGigs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Wrap(
                spacing: 8.0, runSpacing: 8.0, alignment: WrapAlignment.center,
                children: [ _buildGigsViewToggle(), ],
              ),
            ),
            const Expanded(child: Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text('No upcoming gigs or jam nights scheduled.\nBook a gig or set up a jam night for a venue!', textAlign: TextAlign.center)))),
          ],
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8.0, left: 8.0, right: 8.0, bottom: 8.0),
          child: Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildGigsViewToggle(),
              if (hasUpcomingGigs)
                OutlinedButton.icon(
                  icon: const Icon(Icons.code, size: 18),
                  label: const Text('Export Gigs'),
                  onPressed: _showEmbedCodeDialog,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Theme.of(context).colorScheme.primary),
                  ),
                ),
            ],
          ),
        ),
        if (_isLoadingGigs && _loadedGigs.isNotEmpty)
          const Padding(padding: EdgeInsets.all(8.0), child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)))),
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
    if (_loadedGigs.isEmpty) return const Center(child: Text('No gigs or jam nights to display.', textAlign: TextAlign.center));
    return ListView.builder(
      itemCount: _loadedGigs.length,
      itemBuilder: (context, index) {
        final gig = _loadedGigs[index];
        bool isPast;
        if (!gig.isJamOpenMic) {
          DateTime gigEndTime = gig.dateTime.add(Duration(minutes: (gig.gigLengthHours * 60).toInt()));
          isPast = gigEndTime.isBefore(DateTime.now());
        } else {
          isPast = gig.dateTime.isBefore(DateTime.now());
        }
        bool isJam = gig.isJamOpenMic;
        bool hasNotes = (gig.notes?.isNotEmpty ?? false) || (gig.notesUrl?.isNotEmpty ?? false);

        return Card(
          elevation: isPast ? 0.5 : (isJam ? 1.5 : 2),
          color: isPast ? Colors.grey.shade300 : (isJam ? Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.7) : Theme.of(context).cardColor),
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isJam ? Theme.of(context).colorScheme.tertiary : (isPast ? Colors.grey.shade400 : Theme.of(context).colorScheme.primary),
              foregroundColor: isJam? Theme.of(context).colorScheme.onTertiary : Colors.white,
              child: isJam ? const Icon(Icons.music_note, size: 20) : Text(DateFormat('d').format(gig.dateTime)),
            ),
            title: Text(
              gig.venueName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isPast ? Colors.grey.shade700 : (isJam ? Theme.of(context).colorScheme.onSecondaryContainer : Theme.of(context).textTheme.titleLarge?.color),
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${DateFormat.yMMMEd().format(gig.dateTime)} at ${DateFormat.jm().format(gig.dateTime)}',
                  style: TextStyle(color: isPast ? Colors.grey.shade600 : (isJam ? Theme.of(context).colorScheme.onSecondaryContainer.withOpacity(0.8) : Theme.of(context).textTheme.bodyMedium?.color)),
                ),
                if (!isJam)
                  Text(
                    'Pay: \$${gig.pay.toStringAsFixed(0)} - ${gig.gigLengthHours.toStringAsFixed(1)} hrs',
                    style: TextStyle(color: isPast ? Colors.grey.shade600 : Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.9)),
                  )
                else
                  const Text(
                    "Open Mic / Jam Session",
                    style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                  ),
              ],
            ),
            trailing: isJam
                ? null
                : IconButton(
              icon: Icon(
                hasNotes ? Icons.speaker_notes : Icons.speaker_notes_off_outlined,
                color: hasNotes ? Theme.of(context).colorScheme.primary : Colors.grey,
              ),
              onPressed: () => _launchNotesPageForGig(gig),
              tooltip: 'View/Edit Notes',
            ),
            onTap: () => _launchBookingDialogForGig(gig),
          ),
        );
      },
    );
  }

  Widget _buildGigsCalendarView() {
    if (_isLoadingGigs && _calendarEvents.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(children: [
      Container(
        color: Colors.white,
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
            defaultTextStyle: const TextStyle(color: Colors.black87),
            weekendTextStyle: TextStyle(color: Colors.red.shade700),
            outsideTextStyle: TextStyle(color: Colors.grey.shade400),
            disabledTextStyle: TextStyle(color: Colors.grey.shade300),
            todayDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withAlpha(128),
                shape: BoxShape.circle),
            todayTextStyle: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
            selectedDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
            selectedTextStyle: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
            markerDecoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondary,
              shape: BoxShape.circle,
            ),
          ),
          daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold),
              weekendStyle: TextStyle(color: Colors.red.shade600, fontWeight: FontWeight.bold)),
          headerStyle: HeaderStyle(
            titleTextStyle: const TextStyle(
                color: Colors.black87, fontSize: 17.0, fontWeight: FontWeight.bold),
            formatButtonVisible: true,
            titleCentered: true,
            formatButtonShowsNext: false,
            formatButtonTextStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
            formatButtonDecoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.primary),
                borderRadius: BorderRadius.circular(12.0)),
            leftChevronIcon: Icon(Icons.chevron_left, color: Colors.black54),
            rightChevronIcon: Icon(Icons.chevron_right, color: Colors.black54),
          ),
          onDaySelected: _onDaySelected,
          onFormatChanged: (format) {
            if (_calendarFormat != format) {
              if (!mounted) return;
              setState(() { _calendarFormat = format; });
            }
          },
          onPageChanged: (focusedDay) {
            if (!mounted) return;
            setState(() { _focusedDay = focusedDay; });
            _onDaySelected(focusedDay, focusedDay);
          },
          calendarBuilders: CalendarBuilders<Gig>(
            markerBuilder: (context, date, events) {
              if (events.isEmpty) return null;

              final List<Gig> gigEvents = events.cast<Gig>();
              bool hasActualGig = gigEvents.any((gig) => !gig.isJamOpenMic);
              bool hasJam = gigEvents.any((gig) => gig.isJamOpenMic);
              List<Widget> markers = [];
              if (hasActualGig) {
                markers.add(_buildEventsMarker(Theme.of(context).colorScheme.secondary));
              }
              if (hasJam) {
                if (markers.isNotEmpty) markers.add(SizedBox(width: markers.length * 1.5));
                markers.add(_buildEventsMarker(Theme.of(context).colorScheme.tertiary));
              }
              if (markers.isEmpty) return null;
              return Positioned(
                bottom: 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: markers,
                ),
              );
            },
          ),
        ),
      ),
      Expanded(
        child: _selectedDayGigs.isNotEmpty
            ? ListView.builder(
          itemCount: _selectedDayGigs.length,
          itemBuilder: (context, index) {
            final gig = _selectedDayGigs[index];
            bool isPast;
            if (!gig.isJamOpenMic) {
              DateTime gigEndTime = gig.dateTime.add(Duration(minutes: (gig.gigLengthHours * 60).toInt()));
              isPast = gigEndTime.isBefore(DateTime.now());
            } else {
              isPast = gig.dateTime.isBefore(DateTime.now());
            }
            bool isJam = gig.isJamOpenMic;
            return Card(
              elevation: isPast ? 0.5 : (isJam ? 1.0 : 1.5),
              color: isPast
                  ? Colors.grey.shade200.withOpacity(0.7)
                  : (isJam
                  ? Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.6)
                  : Colors.white),
              margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              child: ListTile(
                leading: isJam ? Icon(Icons.music_note, color: isPast ? Colors.grey.shade500 : Theme.of(context).colorScheme.tertiary) : Icon(Icons.event, color: isPast ? Colors.grey.shade500 : Theme.of(context).colorScheme.primary),
                title: Text(
                  gig.venueName,
                  style: TextStyle(fontWeight: FontWeight.bold, color: isPast ? Colors.grey.shade600 : Colors.black87),
                ),
                subtitle: Text(
                  isJam ? '${DateFormat.jm().format(gig.dateTime)} - Jam/Open Mic' : '${DateFormat.jm().format(gig.dateTime)} - \$${gig.pay.toStringAsFixed(0)}',
                  style: TextStyle(color: isPast ? Colors.grey.shade500 : Colors.black54),
                ),
                onTap: () => _launchBookingDialogForGig(gig),
              ),
            );
          },
        )
            : Center(
          child: Text(
            _selectedDay != null ? 'No events for ${DateFormat.yMMMEd().format(_selectedDay!)}.' : 'Select a day to see events.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    ]);
  }

  Widget _buildEventsMarker(Color markerColor) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: markerColor,
      ),
      width: 7.0,
      height: 7.0,
      margin: const EdgeInsets.symmetric(horizontal: 0.5),
    );
  }


  Widget _buildVenuesList() {
    if (_isLoadingVenues && _displayableVenues.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_displayableVenues.isEmpty) {
      return const Center( child: Text("No venues saved yet. Add a new venue when booking a gig!", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey)) );
    }
    List<StoredLocation> sortedDisplayableVenues = List.from(_displayableVenues)..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return ListView.builder(
      itemCount: sortedDisplayableVenues.length,
      itemBuilder: (context, index) {
        final venue = sortedDisplayableVenues[index];
        final int futureGigsCount = _getGigsForVenue(venue, futureOnly: true).where((g) => !g.isJamOpenMic).toList().length;
        final bool hasVenueNotes = (venue.venueNotes?.isNotEmpty ?? false) || (venue.venueNotesUrl?.isNotEmpty ?? false);
        final venueContact = venue.contact;

        // --- START OF FIX: Add [PRIVATE] prefix to venue name ---
        String venueDisplayName = venue.isPrivate ? '[PRIVATE] ${venue.name}' : venue.name;
        // --- END OF FIX ---

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: ListTile(
            leading: Icon(Icons.business, color: Theme.of(context).colorScheme.secondary),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(venueDisplayName, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                if (futureGigsCount > 0)
                  Text(
                    ' ($futureGigsCount upcoming)',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontStyle: FontStyle.italic),
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(venue.address.isNotEmpty ? venue.address : 'Address not specified', style: TextStyle(color: Colors.grey.shade600)),
                if (venueContact != null && venueContact.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${venueContact.name} ${venueContact.phone}'.trim(),
                    style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                  if (venueContact.email.isNotEmpty)
                    Text(
                      venueContact.email,
                      style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                ]
              ],
            ),
            trailing: IconButton(
              icon: Icon(
                hasVenueNotes ? Icons.speaker_notes : Icons.speaker_notes_off_outlined,
                color: hasVenueNotes ? Theme.of(context).colorScheme.primary : Colors.grey,
              ),
              tooltip: 'View/Edit Venue Notes',
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => NotesPage(editingVenueId: venue.placeId),
                ));
              },
            ),
            onTap: () => _showVenueDetailsDialog(venue),
          ),
        );
      },
    );
  }
}
