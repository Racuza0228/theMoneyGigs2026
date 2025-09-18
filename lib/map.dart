// lib/map.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

// --- IMPORT THE MODELS & DIALOG ---
import 'venue_model.dart'; // Ensure StoredLocation has 'isArchived' and 'copyWith'
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

  // --- MODIFIED FOR VENUE ARCHIVING ---
  List<StoredLocation> _allKnownMapVenues = []; // All venues from SharedPreferences
  List<StoredLocation> _displayableMapVenues = []; // Non-archived venues for markers
  // --- END MODIFICATION ---

  bool _isLoading = false;

  static const String _googleApiKey = String.fromEnvironment('GOOGLE_API_KEY');
  static const String _keyGigsList = 'gigs_list';
  static const String _keySavedLocations = 'saved_locations';

  static const CameraPosition _kInitialPosition = CameraPosition(
    target: LatLng(39.103119, -84.512016),
    zoom: 13.0,
  );

  @override
  void initState() {
    super.initState();
    _loadSavedLocationsAndGigs();
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
      _loadSavedLocationsAndGigs();
    }
  }

  Future<void> _loadSavedLocationsAndGigs() async {
    // Primarily loads locations for map markers. Gigs are loaded on-demand for dialogs.
    await _loadSavedLocations();
  }

  Future<void> refreshLocationsAndMarkers() async { // Kept if called externally
    print("MapPage: Refreshing locations and markers...");
    await _loadSavedLocations();
  }

  Future<void> _loadSavedLocations() async {
    print("MapPage: Loading saved locations...");
    if (!mounted) return;

    // Set loading state at the beginning.
    // No need for another setState before this if it's the first thing you do that affects UI.
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      // Re-check if the widget is still mounted after the await.
      if (!mounted) {
        // If not mounted, and we had set _isLoading = true,
        // it's good practice to try and reset it if possible,
        // though typically the widget is gone.
        // However, since setState might not be safe here,
        // the initial `if (!mounted) return;` is the primary guard.
        return;
      }

      final List<String>? locationsJson = prefs.getStringList(_keySavedLocations);
      List<StoredLocation> loadedFromPrefs = [];

      if (locationsJson != null && locationsJson.isNotEmpty) {
        List<StoredLocation?> potentiallyNullLocations = locationsJson.map((jsonString) {
          try {
            return StoredLocation.fromJson(jsonDecode(jsonString));
          } catch (e) {
            print("Error decoding StoredLocation in MapPage: '$jsonString', Error: $e");
            // Optionally, show a specific error to the user for this item,
            // or log it more formally. For now, we'll just skip it.
            return null; // Return null for items that fail to parse
          }
        }).toList();

        // Filter out any nulls that resulted from parsing errors.
        loadedFromPrefs = potentiallyNullLocations.whereType<StoredLocation>().toList();
      }

      // Check mount again before the final setState, as processing might take time.
      if (!mounted) return;

      setState(() {
        _allKnownMapVenues = loadedFromPrefs;
        _displayableMapVenues = _allKnownMapVenues.where((venue) => !venue.isArchived).toList();
        _updateMarkers(); // This will use _displayableMapVenues
        _isLoading = false; // Data loaded (or tried to), stop loading indicator.
      });

      print("MapPage: Loaded ${_allKnownMapVenues.length} total venues from prefs, "
          "${_displayableMapVenues.length} are displayable. Markers updated.");

    } catch (e) {
      print("MapPage: Critical error loading saved locations: $e");
      if (mounted) {
        // Show a general error message to the user.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading saved venues: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        // Ensure UI is updated to reflect that loading has finished, even if with an error.
        setState(() {
          _isLoading = false;
          // Optionally, clear existing venue data if loading fails catastrophically
          // _allKnownMapVenues.clear();
          // _displayableMapVenues.clear();
          // _updateMarkers(); // To clear markers from the map
        });
      }
    }
  }


  // --- MODIFIED _updateMarkers FOR ARCHIVING ---
  void _updateMarkers() {
    Set<Marker> currentMarkers = {};
    // Use _displayableMapVenues to create markers
    for (var loc in _displayableMapVenues) {
      currentMarkers.add(Marker(
        markerId: MarkerId('saved_${loc.placeId}'),
        position: loc.coordinates,
        infoWindow: InfoWindow(
          title: loc.name,
          snippet: '${loc.address}${loc.rating > 0 ? " (${loc.rating.toStringAsFixed(1)} ★)" : ""}',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        onTap: () => _showLocationDetailsDialog(loc),
      ));
    }
    if (!mounted) return;
    setState(() {
      _markers = currentMarkers;
    });
  }
  // --- END MODIFICATION ---

  Future<void> _updateAndSaveLocationReview(StoredLocation updatedLocation) async {
    // Operates on _allKnownMapVenues for saving, then relies on global refresh
    int index = _allKnownMapVenues.indexWhere((loc) => loc.placeId == updatedLocation.placeId);
    if (index != -1) {
      List<StoredLocation> updatedAllVenues = List.from(_allKnownMapVenues);
      updatedAllVenues[index] = updatedLocation; // Assume updatedLocation includes isArchived status correctly

      final prefs = await SharedPreferences.getInstance();
      final List<String> locationsJson = updatedAllVenues.map((loc) => jsonEncode(loc.toJson())).toList();
      await prefs.setStringList(_keySavedLocations, locationsJson);

      globalRefreshNotifier.notify(); // Triggers reload and re-filtering

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Review for ${updatedLocation.name} saved!')));
      }
    }
  }

  Future<void> _saveLocation(PlaceApiResult placeToSave) async {
    // Check against _allKnownMapVenues to prevent duplicates of already saved (even if archived)
    if (_allKnownMapVenues.any((loc) => loc.placeId == placeToSave.placeId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${placeToSave.name} is already saved (possibly archived).')));
      // Optionally, find and show details if it exists, or offer to unarchive
      StoredLocation? existingLoc = _allKnownMapVenues.cast<StoredLocation?>().firstWhere((l) => l?.placeId == placeToSave.placeId, orElse: () => null);
      if (existingLoc != null) _showLocationDetailsDialog(existingLoc); // This dialog shows details of active/archived
      return;
    }

    final newLocation = StoredLocation(
      placeId: placeToSave.placeId,
      name: placeToSave.name,
      address: placeToSave.address,
      coordinates: placeToSave.coordinates,
      isArchived: false, // New locations are not archived
    );

    List<StoredLocation> updatedAllVenues = List.from(_allKnownMapVenues)..add(newLocation);

    final prefs = await SharedPreferences.getInstance();
    final List<String> locationsJson = updatedAllVenues.map((loc) => jsonEncode(loc.toJson())).toList();
    await prefs.setStringList(_keySavedLocations, locationsJson);

    globalRefreshNotifier.notify(); // Triggers reload and re-filtering

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${newLocation.name} added to saved venues!')));
    }
    // Show dialog for the newly added one (which will be displayable)
    _showLocationDetailsDialog(newLocation);
  }


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
      if (!mounted) { setState(() { _isLoading = false; }); return; } // Check mount before proceeding
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
    if (selectablePlaces.isEmpty) { /* ... */ return; }
    PlaceApiResult? userChoice = selectablePlaces.first; // Default selection

    PlaceApiResult? finalSelectedPlace = await showDialog<PlaceApiResult>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder( // To update the dropdown selection within the dialog
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
                  } else {
                    final scaffoldContext = Scaffold.maybeOf(dialogContext); // Use dialogContext
                    final messenger = scaffoldContext != null ? ScaffoldMessenger.of(scaffoldContext.context) : ScaffoldMessenger.of(dialogContext);
                    messenger.removeCurrentSnackBar();
                    messenger.showSnackBar(const SnackBar(content: Text('Please select a venue.')));
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
    // Check against _allKnownMapVenues, including archived ones
    final existingLocation = _allKnownMapVenues.cast<StoredLocation?>().firstWhere(
            (loc) => loc?.placeId == place.placeId,
        orElse: () => null
    );

    if (existingLocation != null) {
      _showLocationDetailsDialog(existingLocation); // Show details even if archived
    } else {
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Add to MoneyGigs?'),
            content: SingleChildScrollView(child: ListBody(children: <Widget>[
              Text(place.name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4), Text(place.address),
              // Coordinates can be shown here for confirmation before adding
              const SizedBox(height: 8),
              Text('Coordinates: ${place.coordinates.latitude.toStringAsFixed(5)}, ${place.coordinates.longitude.toStringAsFixed(5)}'),
            ])),
            actions: <Widget>[
              TextButton(child: const Text('Cancel'), onPressed: () { Navigator.of(dialogContext).pop(); }),
              TextButton(child: const Text('Add Venue'), onPressed: () {
                Navigator.of(dialogContext).pop();
                _saveLocation(place); // This will save it as non-archived
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
      print("MapPage: Saved new gig '${newGig.venueName}' from map booking.");
      globalRefreshNotifier.notify(); // For GigsPage mostly
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
    if (venueForBooking.isArchived) { // Prevent booking at archived venues
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
          onNewVenuePotentiallyAdded: () async {
            print("MapPage: BookingDialog's onNewVenuePotentiallyAdded for preselected venue.");
          },
        );
      },
    );
    if (bookedGig != null) {
      await _saveBookedGig(bookedGig);
    }
  }

  Future<void> _showLocationDetailsDialog(StoredLocation location) async {
    double currentRating = location.rating; // No ?? 0.0, use actual rating
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
                    if (location.isArchived) // Show archived status
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Center(
                          child: Text(
                            "(This venue is archived)",
                            style: TextStyle(fontStyle: FontStyle.italic, color: Colors.orange.shade700),
                          ),
                        ),
                      ),
                    const Divider(height: 20, thickness: 1),

                    if (nextUpcomingGig != null) ...[
                      const Text('Next Gig Here:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4.0),
                      Text(
                        '${DateFormat.MMMEd().format(nextUpcomingGig.dateTime)} at ${DateFormat.jm().format(nextUpcomingGig.dateTime)} (\$${nextUpcomingGig.pay.toStringAsFixed(0)})',
                        style: Theme.of(innerContext).textTheme.bodyMedium,
                      ),
                      const Divider(height: 20, thickness: 1),
                    ] else ...[
                      const Center(child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text("No upcoming gigs scheduled here.", style: TextStyle(fontStyle: FontStyle.italic)),
                      )),
                      const Divider(height: 20, thickness: 1),
                    ],

                    if (!location.isArchived) ...[ // Only show rating/booking for non-archived
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
                if (!location.isArchived) // Only show these actions for non-archived
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        child: const Text('SAVE REVIEW'),
                        onPressed: () {
                          final updatedLocationWithReview = location.copyWith( // Use copyWith
                            rating: currentRating,
                            comment: commentController.text.trim().isNotEmpty ? commentController.text.trim() : null,
                            // isArchived is not changed here
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
                // If you want an "Unarchive" button here for archived venues:
                if (location.isArchived)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.unarchive),
                    label: const Text('UNARCHIVE'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: () {
                      final unarchivedLocation = location.copyWith(isArchived: false);
                      _updateAndSaveLocationReview(unarchivedLocation); // Re-use save logic
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

