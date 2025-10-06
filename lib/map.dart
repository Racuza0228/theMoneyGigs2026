// lib/map.dart

import 'dart:async';
import 'dart:convert';

// <<< NEW: Import for loading assets from the pubspec.yaml >>>
import 'package:flutter/services.dart' show rootBundle;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

// --- IMPORT THE MODELS & DIALOG ---
import 'venue_model.dart';
import 'gig_model.dart';
import 'booking_dialog.dart';

import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:the_money_gigs/global_refresh_notifier.dart';


class PlaceApiResult {
  final String placeId;
  final String name;
  final String address;
  final LatLng coordinates;
  final List<String> types;

  PlaceApiResult({
    required this.placeId,
    required this.name,
    required this.address,
    required this.coordinates,
    required this.types,
  });

  factory PlaceApiResult.fromJson(Map<String, dynamic> json, {bool isNearbySearch = true}) {
    String address = json['vicinity'] ?? json['formatted_address'] ?? 'Address not available';
    if (address == 'Address not available' && json['name'] != null && json['geometry'] != null) {
      address = json['name'];
    }
    return PlaceApiResult(
      placeId: json['place_id'] ?? 'api_error_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] ?? 'Unnamed Place',
      address: address,
      coordinates: LatLng(
        (json['geometry']?['location']?['lat'] as num?)?.toDouble() ?? 0.0,
        (json['geometry']?['location']?['lng'] as num?)?.toDouble() ?? 0.0,
      ),
      types: List<String>.from(json['types'] ?? []),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is PlaceApiResult &&
              runtimeType == other.runtimeType &&
              placeId == other.placeId;

  @override
  int get hashCode => placeId.hashCode;
}


class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final Completer<GoogleMapController> _controller = Completer<GoogleMapController>();
  Set<Marker> _markers = {};

  // --- DATA SOURCE LISTS ---
  List<StoredLocation> _allKnownMapVenues = []; // All user-saved venues from SharedPreferences
  List<StoredLocation> _displayableMapVenues = []; // Non-archived user venues for markers

  // <<< NEW: State variables for Jam Session layer >>>
  List<StoredLocation> _jamSessionVenues = []; // Holds venues from jam_sessions.json
  bool _showJamSessions = false; // Controls the toggle switch's state
  BitmapDescriptor _jamSessionMarkerIcon = BitmapDescriptor.defaultMarker; // The orange marker icon

  bool _isLoading = false;

  static const String _googleApiKey = String.fromEnvironment('GOOGLE_API_KEY');
  static const String _keyGigsList = 'gigs_list';
  static const String _keySavedLocations = 'saved_locations';

  static const CameraPosition _kInitialPosition = CameraPosition(
    target: LatLng(39.103119, -84.512016),
    zoom: 10.0, // Zoomed out to see a wider area of all jams
  );

  @override
  void initState() {
    super.initState();
    _loadAllMapData();
    globalRefreshNotifier.addListener(_handleGlobalRefresh);

    if (_googleApiKey.isEmpty || _googleApiKey == "YOUR_GOOGLE_PLACES_API_KEY_HERE") {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Warning: Google API Key is missing. Search/geocoding may fail.'),
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
    super.dispose();
  }

  void _handleGlobalRefresh() {
    print("MapPage: Received global refresh notification.");
    if (mounted) {
      _loadAllMapData();
    }
  }

  Future<void> _loadAllMapData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    await Future.wait([
      _loadSavedLocations(),
      _loadJamSessionAsset(),
    ]);

    _createCustomMarkers();
    _updateMarkers();

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadJamSessionAsset() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/jam_sessions.json');
      final List<dynamic> jsonList = json.decode(jsonString);
      final List<StoredLocation> allLoadedJams = jsonList.map((json) => StoredLocation.fromJson(json)).toList();

      // <<< FIX: Filter out duplicate venues to show only one marker per location >>>
      final Map<String, StoredLocation> uniqueVenues = {};
      for (final venue in allLoadedJams) {
        // The 'placeID' key from your JSON is parsed into the 'placeId' field in the model.
        if (venue.placeId.isNotEmpty) {
          // If we haven't seen this placeId before, add it to our map.
          // This keeps the FIRST entry for any given placeId.
          uniqueVenues.putIfAbsent(venue.placeId, () => venue);
        }
      }

      if (mounted) {
        setState(() {
          // Store the filtered list of unique venues.
          _jamSessionVenues = uniqueVenues.values.toList();
        });
        print("MapPage: Loaded ${allLoadedJams.length} total jams, filtered to ${_jamSessionVenues.length} unique venues for markers.");
      }
    } catch (e) {
      print("MapPage: Critical error loading jam_sessions.json: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load Jam Session data: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _createCustomMarkers() {
    _jamSessionMarkerIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
  }

  Future<void> _loadSavedLocations() async {
    print("MapPage: Loading saved locations from SharedPreferences...");
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? locationsJson = prefs.getStringList(_keySavedLocations);
      List<StoredLocation> loadedFromPrefs = [];

      if (locationsJson != null && locationsJson.isNotEmpty) {
        loadedFromPrefs = locationsJson.map((jsonString) {
          try {
            return StoredLocation.fromJson(jsonDecode(jsonString));
          } catch (e) {
            print("Error decoding StoredLocation in MapPage: '$jsonString', Error: $e");
            return null;
          }
        }).whereType<StoredLocation>().toList();
      }

      _allKnownMapVenues = loadedFromPrefs;
      _displayableMapVenues = _allKnownMapVenues.where((venue) => !venue.isArchived).toList();

      print("MapPage: Loaded ${_allKnownMapVenues.length} total venues from prefs, "
          "${_displayableMapVenues.length} are displayable.");

    } catch (e) {
      print("MapPage: Critical error loading saved locations: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading saved venues: ${e.toString()}')),
        );
      }
    }
  }

  void _updateMarkers() {
    if (!mounted) return;

    final Set<Marker> newMarkers = {};
    final Set<String> placedMarkerIds = {};

    // 1. Add user's saved, non-archived venues (Azure Blue)
    for (var loc in _displayableMapVenues) {
      newMarkers.add(Marker(
        markerId: MarkerId('saved_${loc.placeId}'),
        position: loc.coordinates,
        infoWindow: InfoWindow(
          title: loc.name,
          snippet: '${loc.address}${loc.rating > 0 ? " (${loc.rating.toStringAsFixed(1)} ★)" : ""}',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        onTap: () => _showLocationDetailsDialog(loc),
      ));
      placedMarkerIds.add(loc.placeId);
    }

    // 2. If toggled on, add the unique jam session venues (Orange)
    if (_showJamSessions) {
      for (var jamVenue in _jamSessionVenues) {
        if (!placedMarkerIds.contains(jamVenue.placeId)) {
          newMarkers.add(Marker(
            // Now that we've filtered the list, using the placeId is safe again.
            markerId: MarkerId('jam_${jamVenue.placeId}'),
            position: jamVenue.coordinates,
            icon: _jamSessionMarkerIcon,
            infoWindow: InfoWindow(
              title: jamVenue.name,
              snippet: jamVenue.jamOpenMicDisplayString(context),
            ),
            onTap: () => _showLocationDetailsDialog(jamVenue),
          ));
        }
      }
    }

    setState(() {
      _markers = newMarkers;
    });
    print("MapPage: Markers updated. Total markers now: ${_markers.length}");
  }

  Future<void> _updateAndSaveLocationReview(StoredLocation updatedLocation) async {
    int index = _allKnownMapVenues.indexWhere((loc) => loc.placeId == updatedLocation.placeId);
    if (index != -1) {
      List<StoredLocation> updatedAllVenues = List.from(_allKnownMapVenues);
      updatedAllVenues[index] = updatedLocation;

      final prefs = await SharedPreferences.getInstance();
      final List<String> locationsJson = updatedAllVenues.map((loc) => jsonEncode(loc.toJson())).toList();
      await prefs.setStringList(_keySavedLocations, locationsJson);

      globalRefreshNotifier.notify();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Review for ${updatedLocation.name} saved!')));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note: Reviews for pre-loaded jam sessions are not saved.')));
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

    // <<< FIX: Provide default values for all required fields to prevent crash >>>
    final newLocation = StoredLocation(
      placeId: placeToSave.placeId,
      name: placeToSave.name,
      address: placeToSave.address,
      coordinates: placeToSave.coordinates,
      isArchived: false,
      hasJamOpenMic: false, // Newly saved venues don't have jam info by default
      jamStyle: null,      // No default style
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

  // --- UNMODIFIED LOGIC BELOW ---
  // The rest of the file (map tap handling, dialogs, build method) is correct
  // and does not need to be changed. It is included here for completeness.

  Future<void> _handleMapTap(LatLng tappedPoint) async {
    if (_googleApiKey.isEmpty || _googleApiKey == "YOUR_GOOGLE_PLACES_API_KEY_HERE") {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('API Key not configured.'), backgroundColor: Colors.orange));
      return;
    }
    if (!mounted) return;
    setState(() { _isLoading = true; });
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Searching for venues near tap...'), duration: Duration(seconds: 4)));

    final String typesToSearch = "restaurant|bar|cafe|night_club|music_venue|performing_arts_theater|stadium";
    final String url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${tappedPoint.latitude},${tappedPoint.longitude}&radius=75&type=$typesToSearch&key=$_googleApiKey';

    try {
      final response = await http.get(Uri.parse(url));
      if (!mounted) { setState(() { _isLoading = false; }); return; }
      setState(() { _isLoading = false; });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'OK' && data['results'] is List) {
          List<dynamic> results = data['results'];
          List<PlaceApiResult> foundPlaces = results
              .map((placeJson) => PlaceApiResult.fromJson(placeJson))
              .where((place) => place.name.isNotEmpty && place.name != place.address && place.placeId.isNotEmpty)
              .toList();
          if (foundPlaces.isEmpty) {
            ScaffoldMessenger.of(context).removeCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No specific places found.')));
          } else if (foundPlaces.length == 1) {
            _askToAddOrViewVenue(foundPlaces.first);
          } else {
            _showPlaceSelectionDialog(foundPlaces);
          }
        } else if (data['status'] == 'ZERO_RESULTS') {
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No places found nearby.')));
        } else {
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Place details error: ${data['error_message'] ?? data['status']}')));
        }
      } else {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('API Error: ${response.statusCode}')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _isLoading = false; });
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Search error: $e')));
    }
  }

  Future<void> _showPlaceSelectionDialog(List<PlaceApiResult> selectablePlaces) async {
    if (selectablePlaces.isEmpty) { return; }
    PlaceApiResult? userChoice = selectablePlaces.first;

    PlaceApiResult? finalSelectedPlace = await showDialog<PlaceApiResult>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateDialog) {
            return AlertDialog(
              title: const Text('Select a Place Nearby'),
              content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text("We found ${selectablePlaces.length} place(s) near your tap:"),
                const SizedBox(height: 16),
                DropdownButtonFormField<PlaceApiResult>(
                  decoration: const InputDecoration(labelText: 'Choose a venue', border: OutlineInputBorder()),
                  value: userChoice,
                  isExpanded: true,
                  hint: const Text('Select a venue'),
                  onChanged: (PlaceApiResult? newValue) {
                    setStateDialog(() { userChoice = newValue; });
                  },
                  items: selectablePlaces.map<DropdownMenuItem<PlaceApiResult>>((PlaceApiResult place) {
                    return DropdownMenuItem<PlaceApiResult>(
                        value: place,
                        child: Tooltip(message: place.address, child: Text(place.name, overflow: TextOverflow.ellipsis))
                    );
                  }).toList(),
                ),
              ]),
              actions: <Widget>[
                TextButton(child: const Text('Cancel'), onPressed: () { Navigator.of(dialogContext).pop(); }),
                TextButton(child: const Text('Confirm'), onPressed: () {
                  if (userChoice != null) {
                    Navigator.of(dialogContext).pop(userChoice);
                  }
                }),
              ],
            );
          },
        );
      },
    );
    if (finalSelectedPlace != null) { _askToAddOrViewVenue(finalSelectedPlace); }
  }

  Future<void> _askToAddOrViewVenue(PlaceApiResult place) async {
    final existingLocation = _allKnownMapVenues.cast<StoredLocation?>().firstWhere(
            (loc) => loc?.placeId == place.placeId,
        orElse: () => null
    );

    if (existingLocation != null) {
      _showLocationDetailsDialog(existingLocation);
    } else {
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Add to MoneyGigs?'),
            content: SingleChildScrollView(child: ListBody(children: <Widget>[
              Text(place.name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4), Text(place.address),
              const SizedBox(height: 8),
              Text('Coordinates: ${place.coordinates.latitude.toStringAsFixed(5)}, ${place.coordinates.longitude.toStringAsFixed(5)}'),
            ])),
            actions: <Widget>[
              TextButton(child: const Text('Cancel'), onPressed: () { Navigator.of(dialogContext).pop(); }),
              TextButton(child: const Text('Add Venue'), onPressed: () {
                Navigator.of(dialogContext).pop();
                _saveLocation(place);
              }),
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
      if (gigsJsonString != null && gigsJsonString.isNotEmpty) {
        return Gig.decode(gigsJsonString);
      }
      return [];
    } catch (e) {
      print("Error loading all gigs: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading gigs: $e'), backgroundColor: Colors.orange));
      return [];
    }
  }

  Future<void> _saveBookedGig(Gig newGig) async {
    if (!mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      List<Gig> existingGigs = await _loadAllGigs();
      existingGigs.add(newGig);
      existingGigs.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      await prefs.setString(_keyGigsList, Gig.encode(existingGigs));
      globalRefreshNotifier.notify();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gig booked at ${newGig.venueName}!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      print("Error saving booked gig from map: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving booked gig: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _launchBookingDialogForVenue(StoredLocation venueForBooking) async {
    if (!mounted) return;
    if (venueForBooking.isArchived) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${venueForBooking.name} is archived. Unarchive it first to book gigs.'), backgroundColor: Colors.orange),
      );
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
        return BookingDialog(
          preselectedVenue: venueForBooking,
          googleApiKey: _googleApiKey,
          existingGigs: existingGigs,
          onNewVenuePotentiallyAdded: () async {},
        );
      },
    );
    if (bookedGig != null) {
      await _saveBookedGig(bookedGig);
    }
  }

  Future<void> _showLocationDetailsDialog(StoredLocation location) async {
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
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext innerContext, StateSetter setDialogState) {
            return AlertDialog(
              title: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(location.name, textAlign: TextAlign.center),
              ),
              contentPadding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 0.0),
              actionsPadding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 12.0),
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    Center(child: Text(location.address, style: Theme.of(innerContext).textTheme.bodySmall)),
                    if (location.isArchived)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Center(
                          child: Text(
                            "(This venue is archived)",
                            style: TextStyle(fontStyle: FontStyle.italic, color: Colors.orange.shade700),
                          ),
                        ),
                      ),
                    if (location.hasJamOpenMic) ...[
                      const Divider(height: 20, thickness: 1),
                      const Text('Jam Session Info:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4.0),
                      Text(
                        location.jamOpenMicDisplayString(context),
                        style: Theme.of(innerContext).textTheme.bodyMedium,
                      ),
                    ],
                    if (nextUpcomingGig != null) ...[
                      const Divider(height: 20, thickness: 1),
                      const Text('Next Gig Here:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4.0),
                      Text(
                        '${DateFormat.MMMEd().format(nextUpcomingGig.dateTime)} at ${DateFormat.jm().format(nextUpcomingGig.dateTime)} (\$${nextUpcomingGig.pay.toStringAsFixed(0)})',
                        style: Theme.of(innerContext).textTheme.bodyMedium,
                      ),
                    ] else if (!location.hasJamOpenMic) ...[
                      const Divider(height: 20, thickness: 1),
                      const Center(child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text("No upcoming gigs scheduled here.", style: TextStyle(fontStyle: FontStyle.italic)),
                      )),
                    ],
                    const Divider(height: 20, thickness: 1),
                    if (!location.isArchived) ...[
                      const Text('Rate this Venue:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Center(
                        child: RatingBar.builder(
                          initialRating: currentRating,
                          minRating: 0,
                          direction: Axis.horizontal,
                          allowHalfRating: true,
                          itemCount: 5,
                          itemPadding: const EdgeInsets.symmetric(horizontal: 4.0),
                          itemBuilder: (context, _) => const Icon(Icons.star, color: Colors.amber),
                          onRatingUpdate: (rating) {
                            setDialogState(() { currentRating = rating; });
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                      Center(
                          child: Text(
                              currentRating == 0 ? "Not Rated" : "${currentRating.toStringAsFixed(1)} Stars",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(innerContext).colorScheme.primary)
                          )
                      ),
                      const SizedBox(height: 16),
                      const Text('Your Comments:', style: TextStyle(fontWeight: FontWeight.bold)),
                      TextField(
                        controller: commentController,
                        decoration: const InputDecoration(hintText: 'e.g., Great sound, load-in info...', border: OutlineInputBorder()),
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ],
                  ],
                ),
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: <Widget>[
                TextButton(
                  child: const Text('CLOSE'),
                  onPressed: () { Navigator.of(dialogContext).pop(); },
                ),
                if (!location.isArchived)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        child: const Text('SAVE REVIEW'),
                        onPressed: () {
                          final updatedLocationWithReview = location.copyWith(
                            rating: currentRating,
                            comment: commentController.text.trim().isNotEmpty ? commentController.text.trim() : null,
                          );
                          _updateAndSaveLocationReview(updatedLocationWithReview);
                          Navigator.of(dialogContext).pop();
                        },
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: const Text('BOOK GIG'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(innerContext).colorScheme.primary,
                            foregroundColor: Theme.of(innerContext).colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            textStyle: const TextStyle(fontSize: 14)
                        ),
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          _launchBookingDialogForVenue(location);
                        },
                      ),
                    ],
                  ),
                if (location.isArchived)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.unarchive),
                    label: const Text('UNARCHIVE'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: () {
                      final unarchivedLocation = location.copyWith(isArchived: false);
                      _updateAndSaveLocationReview(unarchivedLocation);
                      Navigator.of(dialogContext).pop();
                    },
                  ),
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
            if (!_controller.isCompleted) {
              _controller.complete(controller);
            }
          },
          markers: _markers,
          onTap: _handleMapTap,
          myLocationButtonEnabled: true,
          myLocationEnabled: true,
          padding: EdgeInsets.only(bottom: Theme.of(context).platform == TargetPlatform.iOS ? 90 : 60),
        ),
        Positioned(
          top: 12.0,
          right: 12.0,
          child: Card(
            elevation: 4.0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.0)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: Row(
                children: [
                  Icon(Icons.music_note, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 4),
                  const Text('Jams', style: TextStyle(fontWeight: FontWeight.bold)),
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
            ),
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
