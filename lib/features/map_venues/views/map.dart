// lib/map.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';

// --- <<< REFACTORED IMPORTS >>> ---
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
// CORRECT
import 'package:the_money_gigs/features/gigs/widgets/booking_dialog.dart';
import 'package:the_money_gigs/global_refresh_notifier.dart';
import 'package:the_money_gigs/features/map_venues/models/place_models.dart';   // Import the separated models
import 'package:the_money_gigs/core/services/places_service.dart'; // Import the new service

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final Completer<GoogleMapController> _controller = Completer<GoogleMapController>();
  Set<Marker> _markers = {};

  // --- DATA SOURCE LISTS ---
  List<StoredLocation> _allKnownMapVenues = [];
  List<StoredLocation> _jamSessionVenues = [];
  bool _showJamSessions = false;
  BitmapDescriptor _jamSessionMarkerIcon = BitmapDescriptor.defaultMarker;

  // --- REFACTORED: Search UI State ---
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _isSearchVisible = false;
  List<PlaceAutocompleteResult> _autocompleteResults = [];

  // Service for handling Places API calls
  late final PlacesService _placesService;

  bool _isLoading = false;

  // --- CONSTANTS ---
  static const String _googleApiKey = String.fromEnvironment('GOOGLE_API_KEY');
  static const String _keyGigsList = 'gigs_list';
  static const String _keySavedLocations = 'saved_locations';
  static const CameraPosition _kInitialPosition = CameraPosition(
    target: LatLng(39.103119, -84.512016),
    zoom: 10.0,
  );

  @override
  void initState() {
    super.initState();
    _placesService = PlacesService(apiKey: _googleApiKey); // Initialize the service

    _loadAllMapData();
    globalRefreshNotifier.addListener(_handleGlobalRefresh);

    _searchController.addListener(() {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), () {
        if (_searchController.text.isNotEmpty) {
          _fetchAutocompleteResults(_searchController.text);
        } else {
          if (mounted) setState(() => _autocompleteResults = []);
        }
      });
    });

    if (_googleApiKey.isEmpty || _googleApiKey == "YOUR_GOOGLE_PLACES_API_KEY_HERE") {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Warning: Google API Key is missing. Search will fail.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 7),
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    globalRefreshNotifier.removeListener(_handleGlobalRefresh);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // --- REFACTORED: Methods now use PlacesService ---

  Future<void> _fetchAutocompleteResults(String input) async {
    final results = await _placesService.fetchAutocompleteResults(input);
    if (mounted) {
      setState(() {
        _autocompleteResults = results;
      });
    }
  }

  Future<void> _selectPlaceAndMoveCamera(PlaceAutocompleteResult selectedPlace) async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _isSearchVisible = false;
        _autocompleteResults = [];
        _searchController.clear();
      });
    }
    FocusScope.of(context).unfocus();

    final placeDetails = await _placesService.fetchPlaceDetails(selectedPlace.placeId);

    if (mounted && placeDetails != null) {
      final GoogleMapController controller = await _controller.future;
      controller.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: placeDetails.coordinates, zoom: 16.0),
      ));
      _askToAddOrViewVenue(placeDetails);
    }

    if (mounted) setState(() => _isLoading = false);
  }

  // --- ALL ORIGINAL HELPER METHODS ARE NOW INCLUDED ---

  void _handleGlobalRefresh() {
    if (mounted) {
      _loadAllMapData();
    }
  }

  Future<void> _loadAllMapData() async {
    if (!mounted) return;
    setState(() { _isLoading = true; });
    await Future.wait([_loadSavedLocations(), _loadJamSessionAsset()]);
    _createCustomMarkers();
    _updateMarkers();
    if (mounted) { setState(() { _isLoading = false; }); }
  }

  Future<void> _loadJamSessionAsset() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/jam_sessions.json');
      final List<dynamic> jsonList = json.decode(jsonString);
      final List<StoredLocation> allLoadedJams = jsonList.map((json) => StoredLocation.fromJson(json)).toList();
      final Map<String, StoredLocation> uniqueVenues = {};
      for (final venue in allLoadedJams) {
        if (venue.placeId.isNotEmpty) {
          uniqueVenues.putIfAbsent(venue.placeId, () => venue);
        }
      }
      if (mounted) {
        setState(() { _jamSessionVenues = uniqueVenues.values.toList(); });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load Jam Session data: ${e.toString()}'), backgroundColor: Colors.red));
      }
    }
  }

  void _createCustomMarkers() {
    _jamSessionMarkerIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
  }

  Future<void> _loadSavedLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? locationsJson = prefs.getStringList(_keySavedLocations);
      List<StoredLocation> loadedFromPrefs = [];
      if (locationsJson != null && locationsJson.isNotEmpty) {
        loadedFromPrefs = locationsJson.map((jsonString) {
          try { return StoredLocation.fromJson(jsonDecode(jsonString)); }
          catch (e) { return null; }
        }).whereType<StoredLocation>().toList();
      }
      _allKnownMapVenues = loadedFromPrefs;
    } catch (e) {
      print("MapPage: Critical error loading saved locations: $e");
    }
  }

  void _updateMarkers() {
    if (!mounted) return;
    final Set<Marker> newMarkers = {};
    final Set<String> placedMarkerIds = {};
    final currentDisplayableVenues = _allKnownMapVenues.where((v) => !v.isArchived).toList();
    for (var loc in currentDisplayableVenues) {
      newMarkers.add(Marker(
        markerId: MarkerId('saved_${loc.placeId}'),
        position: loc.coordinates,
        infoWindow: InfoWindow(title: loc.name, snippet: '${loc.address}${loc.rating > 0 ? " (${loc.rating.toStringAsFixed(1)} ★)" : ""}'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        onTap: () => _showLocationDetailsDialog(loc),
      ));
      placedMarkerIds.add(loc.placeId);
    }
    if (_showJamSessions) {
      for (var jamVenue in _jamSessionVenues) {
        if (!placedMarkerIds.contains(jamVenue.placeId)) {
          newMarkers.add(Marker(
            markerId: MarkerId('jam_${jamVenue.placeId}'),
            position: jamVenue.coordinates,
            icon: _jamSessionMarkerIcon,
            infoWindow: InfoWindow(title: jamVenue.name, snippet: jamVenue.jamOpenMicDisplayString(context)),
            onTap: () => _showLocationDetailsDialog(jamVenue),
          ));
          placedMarkerIds.add(jamVenue.placeId);
        }
      }
    }
    setState(() { _markers = newMarkers; });
  }

  Future<void> _updateAndSaveLocationReview(StoredLocation updatedLocation) async {
    List<StoredLocation> updatedAllVenues = List.from(_allKnownMapVenues);
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
          SnackBar(content: Text('${updatedLocation.name} saved to your venues!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving venue: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _saveLocation(PlaceApiResult placeToSave) async {
    if (_allKnownMapVenues.any((loc) => loc.placeId == placeToSave.placeId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${placeToSave.name} is already saved.')));
      StoredLocation? existingLoc = _allKnownMapVenues.cast<StoredLocation?>().firstWhere((l) => l?.placeId == placeToSave.placeId, orElse: () => null);
      if (existingLoc != null) _showLocationDetailsDialog(existingLoc);
      return;
    }
    final newLocation = StoredLocation(
      placeId: placeToSave.placeId,
      name: placeToSave.name,
      address: placeToSave.address,
      coordinates: placeToSave.coordinates,
      isArchived: false,
      hasJamOpenMic: false,
      jamStyle: null,
    );
    List<StoredLocation> updatedAllVenues = List.from(_allKnownMapVenues)..add(newLocation);
    final prefs = await SharedPreferences.getInstance();
    final List<String> locationsJson = updatedAllVenues.map((loc) => jsonEncode(loc.toJson())).toList();
    await prefs.setStringList(_keySavedLocations, locationsJson);
    globalRefreshNotifier.notify();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${newLocation.name} added to saved venues!')));
    }
    _showLocationDetailsDialog(newLocation);
  }

  Future<void> _handleMapTap(LatLng tappedPoint) async {
    if (_googleApiKey.isEmpty || _googleApiKey == "YOUR_GOOGLE_PLACES_API_KEY_HERE") {
      return;
    }
    if (!mounted) return;
    setState(() { _isLoading = true; });
    final String typesToSearch = "restaurant|bar|cafe|night_club|music_venue|performing_arts_theater|stadium";
    final String url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${tappedPoint.latitude},${tappedPoint.longitude}&radius=75&type=$typesToSearch&key=$_googleApiKey';
    try {
      final response = await http.get(Uri.parse(url));
      if (!mounted) { setState(() { _isLoading = false; }); return; }
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'OK' && data['results'] is List) {
          List<dynamic> results = data['results'];
          List<PlaceApiResult> foundPlaces = results.map((p) => PlaceApiResult.fromJson(p)).where((p) => p.name.isNotEmpty && p.name != p.address && p.placeId.isNotEmpty).toList();
          if (foundPlaces.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No specific places found.')));
          } else if (foundPlaces.length == 1) {
            _askToAddOrViewVenue(foundPlaces.first);
          } else {
            _showPlaceSelectionDialog(foundPlaces);
          }
        }
      }
    } catch (e) {
      print('Search error: $e');
    } finally {
      if(mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _showPlaceSelectionDialog(List<PlaceApiResult> selectablePlaces) async {
    PlaceApiResult? userChoice = selectablePlaces.first;
    PlaceApiResult? finalSelectedPlace = await showDialog<PlaceApiResult>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Select a Place Nearby'),
              content: DropdownButtonFormField<PlaceApiResult>(
                decoration: const InputDecoration(labelText: 'Choose a venue', border: OutlineInputBorder()),
                value: userChoice,
                isExpanded: true,
                onChanged: (PlaceApiResult? newValue) => setDialogState(() => userChoice = newValue),
                items: selectablePlaces.map<DropdownMenuItem<PlaceApiResult>>((p) => DropdownMenuItem<PlaceApiResult>(value: p, child: Tooltip(message: p.address, child: Text(p.name, overflow: TextOverflow.ellipsis)))).toList(),
              ),
              actions: [
                TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(dialogContext).pop()),
                TextButton(child: const Text('Confirm'), onPressed: () { if (userChoice != null) Navigator.of(dialogContext).pop(userChoice); }),
              ],
            );
          },
        );
      },
    );
    if (finalSelectedPlace != null) { _askToAddOrViewVenue(finalSelectedPlace); }
  }

  Future<void> _askToAddOrViewVenue(PlaceApiResult place) async {
    final existingLocation = _allKnownMapVenues.cast<StoredLocation?>().firstWhere((loc) => loc?.placeId == place.placeId, orElse: () => null);
    if (existingLocation != null) {
      _showLocationDetailsDialog(existingLocation);
    } else {
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Add to MoneyGigs?'),
            content: SingleChildScrollView(child: ListBody(children: [Text(place.name, style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 4), Text(place.address)])),
            actions: [
              TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(dialogContext).pop()),
              TextButton(child: const Text('Add Venue'), onPressed: () { Navigator.of(dialogContext).pop(); _saveLocation(place); }),
            ],
          );
        },
      );
    }
  }

  Future<List<Gig>> _loadAllGigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? gigsJsonString = prefs.getString(_keyGigsList);
      return (gigsJsonString != null && gigsJsonString.isNotEmpty) ? Gig.decode(gigsJsonString) : [];
    } catch (e) {
      return [];
    }
  }

  Future<void> _saveBookedGig(Gig newGig) async {
    if (!mounted) return;
    final StoredLocation gigVenue = StoredLocation(
      placeId: newGig.placeId!, name: newGig.venueName, address: newGig.address,
      coordinates: LatLng(newGig.latitude, newGig.longitude), hasJamOpenMic: true,
    );
    await _updateAndSaveLocationReview(gigVenue);
    try {
      final prefs = await SharedPreferences.getInstance();
      List<Gig> existingGigs = await _loadAllGigs();
      existingGigs.add(newGig);
      existingGigs.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      await prefs.setString(_keyGigsList, Gig.encode(existingGigs));
      globalRefreshNotifier.notify();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gig booked at ${newGig.venueName}!'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving booked gig: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _launchBookingDialogForVenue(StoredLocation venueForBooking) async {
    if (!mounted) return;
    if (venueForBooking.isArchived) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${venueForBooking.name} is archived. Unarchive it first to book gigs.'), backgroundColor: Colors.orange));
      return;
    }
    setState(() { _isLoading = true; });
    List<Gig> existingGigs = await _loadAllGigs();
    if (!mounted) { setState(() { _isLoading = false; }); return; }
    setState(() { _isLoading = false; });
    final Gig? bookedGig = await showDialog<Gig>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return BookingDialog(preselectedVenue: venueForBooking, googleApiKey: _googleApiKey, existingGigs: existingGigs, onNewVenuePotentiallyAdded: () async {});
      },
    );
    if (bookedGig != null) {
      await _saveBookedGig(bookedGig);
    }
  }

  Future<void> _showLocationDetailsDialog(StoredLocation passedInLocation) async {
    final location = _allKnownMapVenues.firstWhere((loc) => loc.placeId == passedInLocation.placeId, orElse: () => passedInLocation);
    double currentRating = location.rating;
    TextEditingController commentController = TextEditingController(text: location.comment);
    if (!mounted) return;
    setState(() { _isLoading = true; });
    List<Gig> allGigs = await _loadAllGigs();
    List<Gig> upcomingGigsForVenue = allGigs.where((gig) {
      bool placeIdMatch = gig.placeId != null && gig.placeId!.isNotEmpty && gig.placeId == location.placeId;
      bool nameMatch = (gig.placeId == null || gig.placeId!.isEmpty) && gig.venueName.toLowerCase() == location.name.toLowerCase();
      return (placeIdMatch || nameMatch) && gig.dateTime.isAfter(DateTime.now().subtract(const Duration(hours: 1)));
    }).toList();
    upcomingGigsForVenue.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    Gig? nextUpcomingGig = upcomingGigsForVenue.isNotEmpty ? upcomingGigsForVenue.first : null;
    if (!mounted) { setState(() { _isLoading = false; }); return; }
    setState(() { _isLoading = false; });

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext innerContext, StateSetter setDialogState) {
            return AlertDialog(
              title: Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(location.name, textAlign: TextAlign.center)),
              contentPadding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 0.0),
              actionsPadding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 12.0),
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    Center(child: Text(location.address, style: Theme.of(innerContext).textTheme.bodySmall)),
                    if (location.isArchived) Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Center(child: Text("(This venue is archived)", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.orange.shade700)))),
                    if (location.hasJamOpenMic) ...[
                      const Divider(height: 20, thickness: 1),
                      const Text('Jam Session Info:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4.0),
                      Text(location.jamOpenMicDisplayString(context), style: Theme.of(innerContext).textTheme.bodyMedium),
                    ],
                    if (nextUpcomingGig != null) ...[
                      const Divider(height: 20, thickness: 1),
                      const Text('Next Gig Here:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4.0),
                      Text('${DateFormat.MMMEd().format(nextUpcomingGig.dateTime)} at ${DateFormat.jm().format(nextUpcomingGig.dateTime)} (\$${nextUpcomingGig.pay.toStringAsFixed(0)})', style: Theme.of(innerContext).textTheme.bodyMedium),
                    ] else if (!location.hasJamOpenMic) ...[
                      const Divider(height: 20, thickness: 1),
                      const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Text("No upcoming gigs scheduled here.", style: TextStyle(fontStyle: FontStyle.italic)))),
                    ],
                    const Divider(height: 20, thickness: 1),
                    if (!location.isArchived) ...[
                      const Text('Rate this Venue:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Center(child: RatingBar.builder(initialRating: currentRating, minRating: 0, direction: Axis.horizontal, allowHalfRating: true, itemCount: 5, itemPadding: const EdgeInsets.symmetric(horizontal: 4.0), itemBuilder: (context, _) => const Icon(Icons.star, color: Colors.amber), onRatingUpdate: (rating) => setDialogState(() => currentRating = rating))),
                      const SizedBox(height: 4),
                      Center(child: Text(currentRating == 0 ? "Not Rated" : "${currentRating.toStringAsFixed(1)} Stars", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(innerContext).colorScheme.primary))),
                      const SizedBox(height: 16),
                      const Text('Your Comments:', style: TextStyle(fontWeight: FontWeight.bold)),
                      TextField(controller: commentController, decoration: const InputDecoration(hintText: 'e.g., Great sound, load-in info...', border: OutlineInputBorder()), maxLines: 3, textCapitalization: TextCapitalization.sentences),
                    ],
                  ],
                ),
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: <Widget>[
                TextButton(child: const Text('CLOSE'), onPressed: () => Navigator.of(dialogContext).pop()),
                if (!location.isArchived)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(child: const Text('SAVE'), onPressed: () {
                        final updatedLocationWithReview = location.copyWith(rating: currentRating, comment: commentController.text.trim().isNotEmpty ? commentController.text.trim() : null);
                        _updateAndSaveLocationReview(updatedLocationWithReview);
                        Navigator.of(dialogContext).pop();
                      }),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(icon: const Icon(Icons.calendar_today, size: 18), label: const Text('BOOK'), style: ElevatedButton.styleFrom(backgroundColor: Theme.of(innerContext).colorScheme.primary, foregroundColor: Theme.of(innerContext).colorScheme.onPrimary, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), textStyle: const TextStyle(fontSize: 14)), onPressed: () {
                        final updatedLocationWithReview = location.copyWith(rating: currentRating, comment: commentController.text.trim().isNotEmpty ? commentController.text.trim() : null);
                        _updateAndSaveLocationReview(updatedLocationWithReview);
                        Navigator.of(dialogContext).pop();
                        _launchBookingDialogForVenue(updatedLocationWithReview);
                      }),
                    ],
                  ),
                if (location.isArchived)
                  ElevatedButton.icon(icon: const Icon(Icons.unarchive), label: const Text('UNARCHIVE'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green), onPressed: () {
                    final unarchivedLocation = location.copyWith(isArchived: false);
                    _updateAndSaveLocationReview(unarchivedLocation);
                    Navigator.of(dialogContext).pop();
                  }),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GoogleMap(
          mapType: MapType.normal,
          initialCameraPosition: _kInitialPosition,
          onMapCreated: (GoogleMapController controller) {
            if (!_controller.isCompleted) _controller.complete(controller);
          },
          markers: _markers,
          onTap: (tappedPoint) {
            if (_isSearchVisible) {
              setState(() {
                _isSearchVisible = false;
                _autocompleteResults = [];
                _searchController.clear();
                _placesService.endSession();
                FocusScope.of(context).unfocus();
              });
            } else {
              _handleMapTap(tappedPoint);
            }
          },
          myLocationButtonEnabled: true,
          myLocationEnabled: true,
          padding: EdgeInsets.only(
              top: _isSearchVisible ? 120 : 70,
              bottom: Theme.of(context).platform == TargetPlatform.iOS ? 90 : 60
          ),
        ),

        Positioned(
          top: 12.0,
          left: 12.0,
          right: 12.0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Card(
                elevation: 4.0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28.0)),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(_isSearchVisible ? Icons.arrow_back : Icons.search),
                      onPressed: () {
                        setState(() {
                          _isSearchVisible = !_isSearchVisible;
                          _autocompleteResults = [];
                          if (_isSearchVisible) {
                            _placesService.startSession();
                          } else {
                            _searchController.clear();
                            _placesService.endSession();
                            FocusScope.of(context).unfocus();
                          }
                        });
                      },
                    ),
                    Expanded(
                      child: _isSearchVisible
                          ? TextField(
                        controller: _searchController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Search address or venue...',
                          border: InputBorder.none,
                        ),
                      )
                          : GestureDetector(
                          onTap: () => setState(() {
                            _isSearchVisible = true;
                            _placesService.startSession();
                          }),
                          child: const Text(
                            'Search Map',
                            style: TextStyle(fontSize: 16, color: Colors.black54),
                          )),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const VerticalDivider(width: 1, indent: 10, endIndent: 10),
                        Icon(Icons.music_note, color: Colors.orange.shade700, size: 20),
                        const SizedBox(width: 2),
                        const Text('Jams'),
                        Switch(
                          value: _showJamSessions,
                          onChanged: (bool value) {
                            setState(() {
                              _showJamSessions = value;
                              _updateMarkers();
                            });
                          },
                          activeColor: Colors.orange.shade600,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              if (_isSearchVisible && _autocompleteResults.isNotEmpty)
                Card(
                  margin: const EdgeInsets.only(top: 8.0),
                  elevation: 4.0,
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: _autocompleteResults.length,
                    itemBuilder: (context, index) {
                      final result = _autocompleteResults[index];
                      return ListTile(
                        leading: const Icon(Icons.location_pin),
                        title: Text(result.mainText),
                        subtitle: Text(result.secondaryText),
                        onTap: () {
                          _selectPlaceAndMoveCamera(result);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),

        if (_isLoading)
          Positioned.fill(
            child: Container(
              color: Colors.black.withAlpha(128),
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}
