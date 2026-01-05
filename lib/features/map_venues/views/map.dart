// lib/features/map_venues/views/map.dart
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/services.dart' show rootBundle, Uint8List, ByteData;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

// --- Project Imports ---
import 'package:the_money_gigs/core/services/places_service.dart';
import 'package:the_money_gigs/features/app_demo/providers/demo_provider.dart';
import 'package:the_money_gigs/features/gigs/models/gig_model.dart';
import 'package:the_money_gigs/features/gigs/widgets/booking_dialog.dart';
import 'package:the_money_gigs/core/models/enums.dart';
import 'package:the_money_gigs/features/map_venues/models/place_models.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_contact.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';
import 'package:the_money_gigs/features/map_venues/widgets/jam_open_mic_dialog.dart';
import 'package:the_money_gigs/features/map_venues/widgets/venue_contact_dialog.dart';
import 'package:the_money_gigs/features/map_venues/widgets/venue_details_dialog.dart';
import 'package:the_money_gigs/global_refresh_notifier.dart';
import 'package:visibility_detector/visibility_detector.dart'; // <-- 1. ADD THIS IMPORT

import 'package:the_money_gigs/features/map_venues/repositories/venue_repository.dart';
import 'package:the_money_gigs/main.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

StoredLocation _mergeJamPreferences(
    StoredLocation publicVenue,
    StoredLocation localVenue,
    ) {
  if (localVenue.jamSessions.isEmpty) {
    return publicVenue; // No local preferences to preserve
  }

  // Create map of local jam preferences by session ID
  final Map<String, bool> localPrefs = {
    for (var session in localVenue.jamSessions)
      session.id: session.showInGigsList,
  };

  // Merge: Use public jam data but preserve local showInGigsList
  final mergedSessions = publicVenue.jamSessions.map((pubSession) {
    final localPref = localPrefs[pubSession.id];
    if (localPref != null) {
      return pubSession.copyWith(showInGigsList: localPref);
    }
    return pubSession; // New session, use default
  }).toList();

  return publicVenue.copyWith(jamSessions: mergedSessions);
}

class _MapPageState extends State<MapPage> {
  bool _isMapReady = false;

  final Completer<GoogleMapController> _controller = Completer<GoogleMapController>();
  Set<Marker> _markers = {};

  List<Gig> _allLoadedGigs = [];
  Set<String> _userSavedPlaceIds = {};
  List<StoredLocation> _allKnownMapVenues = [];
  bool _showJamSessions = false;
  DayOfWeek? _selectedJamDay;
  BitmapDescriptor _jamSessionMarkerIcon = BitmapDescriptor.defaultMarker;
  BitmapDescriptor? _gigMarkerIcon;

  VenueRepository? _venueRepository;

  BitmapDescriptor _publicVenueMarkerIcon = BitmapDescriptor.defaultMarker;
  BitmapDescriptor _privateVenueMarkerIcon = BitmapDescriptor.defaultMarker;

  static const String _isConnectedKey = 'is_connected_to_network';


  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _isSearchVisible = false;
  List<PlaceAutocompleteResult> _autocompleteResults = [];

  late final PlacesService _placesService;
  bool _isLoading = false;

  static const String _googleApiKey = String.fromEnvironment('GOOGLE_API_KEY');
  static const String _keyGigsList = 'gigs_list';
  static const String _keySavedLocations = 'saved_locations';
  static const CameraPosition _kInitialPosition = CameraPosition(
    target: LatLng(39.103119, -84.512016), // Cincinnati, OH
    zoom: 10.0,
  );

  // --- START OF MODIFICATIONS ---

  @override
  void initState() {
    super.initState();
    _initializeMapPage();
  }

  /// This new method controls the initialization sequence to prevent race conditions.
  Future<void> _initializeMapPage() async {
    await _checkAndRequestLocationPermission();

    if (!mounted) return;

    _placesService = PlacesService(apiKey: _googleApiKey);
    globalRefreshNotifier.addListener(_handleGlobalRefresh);
    Provider.of<DemoProvider>(context, listen: false)
        .addListener(_onDemoStateChanged);

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

    if (_googleApiKey.isEmpty) {
      // Use addPostFrameCallback to ensure the widget is built before showing a SnackBar.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Warning: Google API Key is missing. Map search will fail.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 7),
            ),
          );
        }
      });
    }

    await _loadAllMapData();

    if (mounted) {
      setState(() {
        _isMapReady = true;
      });
    }
  }

  Future<void> _checkAndRequestLocationPermission() async {
    var status = await Permission.location.status;
    // Check if the permission is already granted
    if (status.isGranted) {
      print("Location permission is already granted.");
      return; // No need to do anything else
    }

    // If permission is denied, request it
    if (status.isDenied) {
      // We await the request itself.
      var result = await Permission.location.request();
      if (result.isGranted) {
        print("Location permission granted after request.");
      } else {
        print("Location permission was denied by the user.");
      }
    }

    // If permission is permanently denied, guide user to app settings
    if (status.isPermanentlyDenied) {
      print("Location permission is permanently denied. Showing a dialog.");
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Location Permission Required"),
            content: const Text(
                "This app needs location permission to show your position on the map. Please enable it in the app settings."),
            actions: [
              TextButton(
                child: const Text("Cancel"),
                onPressed: () => Navigator.of(context).pop(),
              ),
              TextButton(
                child: const Text("Open Settings"),
                onPressed: () {
                  openAppSettings();
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    globalRefreshNotifier.removeListener(_handleGlobalRefresh);
    Provider.of<DemoProvider>(context, listen: false)
        .removeListener(_onDemoStateChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onDemoStateChanged() {
    final demoProvider = Provider.of<DemoProvider>(context, listen: false);
    if (demoProvider.isDemoModeActive && demoProvider.currentStep == 12) {
      // If we're on the map step, make sure the demo marker is visible
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusOnDemoGigLocation();
      });
    } else {
      // If the demo has ended OR has moved to a different step, remove the marker
      if (mounted) {
        setState(() {
          // Find and remove the marker whose ID matches the static demo gig ID
          _markers.removeWhere((marker) => marker.markerId.value == DemoProvider.demoGigId);
        });
      }
    }
  }

  Future<void> _focusOnDemoGigLocation() async {
    if (!_controller.isCompleted || _gigMarkerIcon == null) return;

    final GoogleMapController mapController = await _controller.future;

    const LatLng demoGigLocation = LatLng(39.1602761, -84.429593);

    final demoMarker = Marker(
      markerId: MarkerId(DemoProvider.demoGigId),
      position: demoGigLocation,
      icon: _gigMarkerIcon!,
      infoWindow: const InfoWindow(
        title: 'Kroger Marketplace',
        snippet: 'Your newly booked demo gig!',
      ),
    );

    if (mounted) {
      setState(() {
        _markers.add(demoMarker);
      });
    }
    mapController.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: demoGigLocation, zoom: 15.0),
      ),
    );
  }

  Future<BitmapDescriptor> _loadCustomMarker() async {
    final Uint8List markerIconBytes = await _getBytesFromAsset('assets/mapmarker.png', 100);
    // Just return the descriptor. Do not set state or update markers here.
    return BitmapDescriptor.fromBytes(markerIconBytes);
  }

  Future<Uint8List> _getBytesFromAsset(String path, int width) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
    ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  }


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

  void _handleGlobalRefresh() {
    if (mounted) {
      print("🗺️ MapPage received global refresh signal. Reloading all map data.");
      _loadAllMapData();
    }
  }


  Future<void> _loadAllMapData() async {
    if (!mounted) return;
    setState(() { _isLoading = true; });

    _setCustomMarkerStyles();
    final loadedGigIcon = await _loadCustomMarker();
    final localVenues = await _loadSavedLocations();
    final localGigs = await _loadAllGigs();
    final localJamVenues = await _loadJamSessionAsset();

    _userSavedPlaceIds = localVenues.map((v) => v.placeId).toSet();

    // ✅ ADD DEBUG LOGGING
    print("🔍 DEBUG: Loaded ${localVenues.length} venues from SharedPreferences");
    for (var v in localVenues) {
      print("   - ${v.name} (${v.placeId})");
    }
    print("🔍 DEBUG: _userSavedPlaceIds has ${_userSavedPlaceIds.length} items:");
    for (var id in _userSavedPlaceIds) {
      print("   - $id");
    }

    Map<String, StoredLocation> finalVenuesMap = {
      for (var venue in localVenues) venue.placeId: venue
    };

    for (var jamVenue in localJamVenues) {
      if (!finalVenuesMap.containsKey(jamVenue.placeId)) {
        finalVenuesMap[jamVenue.placeId] = jamVenue;
      }
    }

    // 3. Check for network connection.
    final prefs = await SharedPreferences.getInstance();
    final bool isConnected = prefs.getBool(_isConnectedKey) ?? false;

    if (isConnected) {
      print("🔌 Network connection detected. Fetching public data to merge...");
      await initializeNetworkServices();

      const String userId = 'default_user_id'; // Placeholder for your auth service

      if (mounted){
        _venueRepository = VenueRepository();
        final publicVenues = await _venueRepository!.getAllPublicVenues(userId);
        print("✅ Fetched ${publicVenues.length} public venues from Firebase.");

        for (var publicVenue in publicVenues) {
          if (finalVenuesMap.containsKey(publicVenue.placeId)) {
            final localVenue = finalVenuesMap[publicVenue.placeId]!;

            // First merge jam preferences
            final mergedVenue = _mergeJamPreferences(publicVenue, localVenue);

            finalVenuesMap[publicVenue.placeId] = localVenue.copyWith(
              isPublic: true,
              rating: publicVenue.rating,    // User's personal rating from DB
              comment: publicVenue.comment,  // User's personal comment from DB
              averageRating: publicVenue.averageRating,  // Community average
              totalRatings: publicVenue.totalRatings,    // Rating count
              jamSessions: mergedVenue.jamSessions,      // ✅ MERGED jam sessions
            );
          } else {
            // New public venue not in local storage
            finalVenuesMap[publicVenue.placeId] = publicVenue;
          }
        }
      } else {
        print("🚫 No network. Using local SharedPreferences data only.");
        // If offline, iterate through the loaded local venues and ensure they are all marked as not public.
        for (var entry in finalVenuesMap.entries) {
          finalVenuesMap[entry.key] = entry.value.copyWith(isPublic: false);
        }
      }
    }


    // 5. Commit all loaded and merged data to the state in a single call.
    if (mounted) {
      setState(() {
        _gigMarkerIcon = loadedGigIcon;
        _allKnownMapVenues = finalVenuesMap.values.toList();
        _allLoadedGigs = localGigs;
        // Removed: _jamSessionVenues now filtered dynamically from _allKnownMapVenues
      });
    }

    // 6. Now that the state is fully set, update the map markers.
    print("--- All data loaded and merged. Triggering a single marker update. ---");
    _updateMarkers();
    print("🔍 DEBUG: _allKnownMapVenues has ${_allKnownMapVenues.length} venues");
    print("🔍 DEBUG: Created ${_markers.length} markers on map");

    // --- END: CORRECTED LOADING AND MERGING LOGIC ---

    if (mounted) { setState(() { _isLoading = false; }); }
  }

  Future<void> _refreshVenuesFromFirebase() async {
    if (_venueRepository == null) {
      print("⚠️ Cannot refresh from Firebase, repository not initialized. (User may be offline).");
      return; // Exit the function safely.
    }

    print("🔄 Refreshing venues from Firebase...");
    try {
      const String userId = 'current_user_id'; // TODO: Get from FirebaseAuth

      // Fetch updated venues with user's ratings
      final publicVenues = await _venueRepository!.getAllPublicVenues(userId);

      if (!mounted) return;

      setState(() {
        // Update only the venues that exist in both lists
        for (var publicVenue in publicVenues) {
          final index = _allKnownMapVenues.indexWhere(
                  (v) => v.placeId == publicVenue.placeId
          );
          if (index != -1) {
            final existingVenue = _allKnownMapVenues[index];

            // 🏷️ CRITICAL: Preserve local tags when refreshing from Firebase!
            // Firebase doesn't have tags yet (they're only stored locally),
            // so we need to merge them with the Firebase data
            final mergedVenue = publicVenue.copyWith(
              instrumentTags: existingVenue.instrumentTags.isNotEmpty
                  ? existingVenue.instrumentTags
                  : publicVenue.instrumentTags,
              genreTags: existingVenue.genreTags.isNotEmpty
                  ? existingVenue.genreTags
                  : publicVenue.genreTags,
            );

            //print('🏷️ MAP: Merging venue ${publicVenue.name}');
            if (existingVenue.instrumentTags.isNotEmpty || existingVenue.genreTags.isNotEmpty) {
              print('   - Preserved local tags: genres=${existingVenue.genreTags}, instruments=${existingVenue.instrumentTags}');
            }

            // Replace with merged venue (has Firebase rating/comment + local tags)
            _allKnownMapVenues[index] = mergedVenue;
          }
        }

        // Rebuild markers with updated data
        _updateMarkers();
      });

      print("✅ Venues refreshed: ${publicVenues.length} public venues updated");
    } catch (e) {
      print("❌ Error refreshing venues: $e");
    }
  }



  Future<List<StoredLocation>> _loadJamSessionAsset() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/jam_sessions.json');
      final List<dynamic> jsonList = json.decode(jsonString);
      final Map<String, StoredLocation> uniqueVenues = {};
      final allLoadedJams = jsonList.map((json) => StoredLocation.fromJson(json)).toList();
      for (final venue in allLoadedJams) {
        if (venue.placeId.isNotEmpty) {
          uniqueVenues.putIfAbsent(venue.placeId, () => venue);
        }
      }
      return uniqueVenues.values.toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load Jam Session data: ${e.toString()}'), backgroundColor: Colors.red));
      }
    }
    return [];
  }

  void _setCustomMarkerStyles() {
    // Set style for Jam Sessions
    _jamSessionMarkerIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);

    // VVV DEFINE PUBLIC AND PRIVATE MARKER STYLES VVV
    _publicVenueMarkerIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
    _privateVenueMarkerIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
  }

  Future<List<StoredLocation>> _loadSavedLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? locationsJson = prefs.getStringList(_keySavedLocations);
      if (locationsJson != null) {
        return locationsJson.map((jsonString) => StoredLocation.fromJson(jsonDecode(jsonString))).toList();
      }
    } catch (e) {
      print("Error loading saved locations: $e");
    }
    return []; // Return empty list on error or if null
  }

  Future<List<Gig>> _loadAllGigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? gigsJsonString = prefs.getString(_keyGigsList);
      if (gigsJsonString != null) {
        return Gig.decode(gigsJsonString);
      }
    } catch (e) {
      print("Error loading gigs: $e");
    }
    return [];
  }

  void _updateMarkers() {
    if (!mounted || _gigMarkerIcon == null) {
      return;
    }
    final Set<Marker> newMarkers = {};
    final now = DateTime.now();
    final upcomingGigVenuePlaceIds = _allLoadedGigs
        .where((gig) => gig.dateTime.isAfter(now))
        .map((gig) => gig.placeId)
        .toSet();

    // Exclude archived venues from display
    final currentDisplayableVenues = _allKnownMapVenues.where((v) => !v.isArchived).toList();

    // FILTER: Determine which venues to show based on Jams toggle
    List<StoredLocation> venuesToShow;

    if (_showJamSessions) {
      // Jams Toggle ON: Show venues with jam sessions
      venuesToShow = currentDisplayableVenues.where((v) {
        if (v.jamSessions.isEmpty) return false;

        // Apply day filter if selected
        if (_selectedJamDay != null) {
          return v.jamSessions.any((session) => session.day == _selectedJamDay);
        }
        return true;
      }).toList();
    } else {
      // Jams Toggle OFF: Show only user-saved venues and public venues
      venuesToShow = currentDisplayableVenues.where((v) {
        // Show public venues from network edition
        if (v.isPublic) {
          return true;
        }

        // Show if user explicitly saved this venue
        return _userSavedPlaceIds.contains(v.placeId);
      }).toList();
    }

    print("🔍 DEBUG _updateMarkers:");
    print("   - Jams toggle: $_showJamSessions");
    print("   - Total venues in memory: ${_allKnownMapVenues.length}");
    print("   - After archive filter: ${currentDisplayableVenues.length}");
    print("   - Venues to show: ${venuesToShow.length}");
    print("   - User saved IDs: $_userSavedPlaceIds");
    //for (var v in venuesToShow) {
    // print("   - Will show: ${v.name} (public=${v.isPublic}, placeId=${v.placeId})");
    //}

    // Create markers for all venues to show
    for (var loc in venuesToShow) {
      final bool hasUpcomingGig = upcomingGigVenuePlaceIds.contains(loc.placeId);
      String snippetText = loc.address;

      if (_showJamSessions && loc.jamSessions.isNotEmpty) {
        // Show jam session info in snippet
        snippetText = loc.jamOpenMicDisplayString(context);
      } else if (loc.rating > 0) {
        snippetText = '${loc.address}  ${loc.rating.toStringAsFixed(1)} ⭐';
      }

      // MARKER COLOR LOGIC
      BitmapDescriptor venueIcon;

      if (hasUpcomingGig) {
        venueIcon = _gigMarkerIcon!; // RED/CUSTOM for upcoming gigs
      } else if (_showJamSessions) {
        venueIcon = _jamSessionMarkerIcon; // ORANGE for jam sessions
      } else if (loc.isPublic) {
        venueIcon = _publicVenueMarkerIcon; // GREEN for public/network venues
      } else {
        venueIcon = _privateVenueMarkerIcon; // BLUE for user-saved venues
      }

      newMarkers.add(Marker(
        markerId: MarkerId(loc.placeId),
        position: loc.coordinates,
        infoWindow: InfoWindow(title: loc.name, snippet: snippetText),
        icon: venueIcon,
        onTap: () => _showLocationDetailsDialog(loc),
      ));
    }

    setState(() { _markers = newMarkers; });
  }


  Future<void> _updateAndSaveLocationReview(StoredLocation updatedLocation) async {
    try {
      print('🏷️ MAP: _updateAndSaveLocationReview called');
      print('   - Venue: ${updatedLocation.name}');
      print('   - Genre tags: ${updatedLocation.genreTags}');
      print('   - Instrument tags: ${updatedLocation.instrumentTags}');

      final prefs = await SharedPreferences.getInstance();

      // Load ONLY user-saved venues from SharedPreferences
      final List<String>? existingSavedJson = prefs.getStringList(_keySavedLocations);
      List<StoredLocation> userSavedVenues = [];

      if (existingSavedJson != null) {
        userSavedVenues = existingSavedJson
            .map((jsonString) => StoredLocation.fromJson(jsonDecode(jsonString)))
            .toList();
      }

      // Update or add the modified venue
      int index = userSavedVenues.indexWhere((loc) => loc.placeId == updatedLocation.placeId);
      if (index != -1) {
        print('🏷️ MAP: Updating existing venue in SharedPreferences list');
        userSavedVenues[index] = updatedLocation;
      } else {
        print('🏷️ MAP: Adding new venue to SharedPreferences list');
        userSavedVenues.add(updatedLocation);
      }

      // ✅ ALSO update the in-memory venue list so reopening the dialog shows latest tags!
      final memoryIndex = _allKnownMapVenues.indexWhere((loc) => loc.placeId == updatedLocation.placeId);
      if (memoryIndex != -1) {
        print('🏷️ MAP: Updating venue in _allKnownMapVenues');
        print('   - Before: ${_allKnownMapVenues[memoryIndex].genreTags}');
        setState(() {
          _allKnownMapVenues[memoryIndex] = updatedLocation;
        });
        print('   - After: ${_allKnownMapVenues[memoryIndex].genreTags}');
        print('✅ Updated venue in _allKnownMapVenues with latest tags');
      } else {
        print('⚠️ MAP: Venue not found in _allKnownMapVenues!');
      }

      // ✅ Save ALL user-saved venues (no filter needed)
      // They're already filtered by being user-saved!
      _userSavedPlaceIds = userSavedVenues.map((v) => v.placeId).toSet();

      // Save back to SharedPreferences
      final List<String> locationsJson = userSavedVenues
          .map((loc) => jsonEncode(loc.toJson()))
          .toList();
      await prefs.setStringList(_keySavedLocations, locationsJson);
      print('🏷️ MAP: Saved to SharedPreferences');

      print('🏷️ MAP: Calling globalRefreshNotifier.notify()');
      globalRefreshNotifier.notify();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${updatedLocation.name} saved!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ MAP: Error in _updateAndSaveLocationReview: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving venue: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  Future<void> _saveLocation(PlaceApiResult placeToSave) async {
    // Check if venue already exists in memory
    if (_allKnownMapVenues.any((loc) => loc.placeId == placeToSave.placeId)) {
      final existingLoc = _allKnownMapVenues.firstWhere((l) => l.placeId == placeToSave.placeId);
      _showLocationDetailsDialog(existingLoc);
      return;
    }

    // Create new venue
    final newLocation = StoredLocation(
      placeId: placeToSave.placeId,
      name: placeToSave.name,
      address: placeToSave.address,
      coordinates: placeToSave.coordinates,
    );

    // ✅ CRITICAL: Load ONLY user-saved venues from SharedPreferences
    // DO NOT save jam_sessions.json or public venues
    final prefs = await SharedPreferences.getInstance();
    final List<String>? existingSavedJson = prefs.getStringList(_keySavedLocations);
    List<StoredLocation> userSavedVenues = [];

    if (existingSavedJson != null) {
      userSavedVenues = existingSavedJson
          .map((jsonString) => StoredLocation.fromJson(jsonDecode(jsonString)))
          .toList();
    }

    // Add new venue to user's saved list
    userSavedVenues.add(newLocation);

    // ✅ Track this venue as user-saved
    _userSavedPlaceIds.add(newLocation.placeId);

    // Save ONLY user-saved venues back to SharedPreferences
    final List<String> locationsJson = userSavedVenues
        .map((loc) => jsonEncode(loc.toJson()))
        .toList();
    await prefs.setStringList(_keySavedLocations, locationsJson);

    // Trigger global refresh to reload map
    globalRefreshNotifier.notify();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${newLocation.name} added to saved venues!'))
      );
    }

    // Show venue details dialog
    _showLocationDetailsDialog(newLocation);
  }

  Future<void> _handleMapTap(LatLng tappedPoint) async {
    if (_googleApiKey.isEmpty) return;
    if (mounted) setState(() { _isLoading = true; });
    try {
      const String typesToSearch = "restaurant|bar|cafe|night_club|music_venue|performing_arts_theater|stadium";
      final String url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${tappedPoint.latitude},${tappedPoint.longitude}&radius=50&type=$typesToSearch&key=$_googleApiKey';
      final response = await http.get(Uri.parse(url));
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'OK' && data['results'] is List && (data['results'] as List).isNotEmpty) {
          final List<dynamic> venues = data['results'];
          if (venues.length == 1) {
            final placeDetails = await _placesService.fetchPlaceDetails(venues[0]['place_id']);
            if (placeDetails != null) {
              _askToAddOrViewVenue(placeDetails);
            }
          } else {
            dynamic selectedResult = venues[0];
            await showDialog<void>(
              context: context,
              builder: (BuildContext dialogContext) {
                return StatefulBuilder(
                  builder: (context, setDialogState) {
                    return AlertDialog(
                      title: const Text('Select a Nearby Venue'),
                      content: DropdownButton<dynamic>(
                        value: selectedResult,
                        isExpanded: true,
                        items: venues.map<DropdownMenuItem<dynamic>>((result) {
                          final String name = result['name'] ?? 'Unknown';
                          return DropdownMenuItem<dynamic>(
                            value: result,
                            child: Text(name, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (newValue) {
                          setDialogState(() {
                            selectedResult = newValue!;
                          });
                        },
                      ),
                      actions: [
                        TextButton(
                          child: const Text('Cancel'),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                        ElevatedButton(
                          child: const Text('Select'),
                          onPressed: () async {
                            Navigator.of(dialogContext).pop();
                            if (selectedResult != null) {
                              final placeDetails = await _placesService.fetchPlaceDetails(selectedResult['place_id']);
                              if (placeDetails != null) {
                                _askToAddOrViewVenue(placeDetails);
                              }
                            }
                          },
                        ),
                      ],
                    );
                  },
                );
              },
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No matching venues found nearby.')));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error contacting Google Places: ${response.statusCode}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('An error occurred: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _askToAddOrViewVenue(PlaceApiResult place) async {
    final existingLocations = _allKnownMapVenues.where((loc) => loc.placeId == place.placeId);
    if (existingLocations.isNotEmpty) {
      _showLocationDetailsDialog(existingLocations.first);
    } else {
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Add Venue?'),
            content: Text(place.name),
            actions: [
              TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(dialogContext).pop()),
              TextButton(child: const Text('Add'), onPressed: () { Navigator.of(dialogContext).pop(); _saveLocation(place); }),
            ],
          );
        },
      );
    }
  }

  Future<void> _saveBookedGig(Gig newGig) async {
    if (!mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      List<Gig> existingGigs = await _loadAllGigs();
      existingGigs.add(newGig);
      await prefs.setString(_keyGigsList, Gig.encode(existingGigs));
      globalRefreshNotifier.notify();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gig booked at ${newGig.venueName}!'), backgroundColor: Colors.green));
    } catch (e) {
      // Handle error
    }
  }

  Future<Gig?> _launchBookingDialogForVenue(StoredLocation venue) async {
    if (venue.isArchived) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${venue.name} is archived.'), backgroundColor: Colors.orange));
      return null;
    }
    List<Gig> existingGigs = await _loadAllGigs();
    if (!mounted) return null;

    final GigEditResult? result = await showDialog<GigEditResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BookingDialog(preselectedVenue: venue, googleApiKey: _googleApiKey, existingGigs: existingGigs),
    );

    if (result != null && result.action == GigEditResultAction.updated && result.gig != null) {
      await _saveBookedGig(result.gig!);
      return result.gig;
    }
    return null;
  }

  Future<void> _archiveVenue(StoredLocation venueToArchive) async {
    final index = _allKnownMapVenues.indexWhere((v) => v.placeId == venueToArchive.placeId);
    if (index != -1) {
      // ✅ FIXED: Toggle based on CURRENT state in memory, not the parameter
      final currentVenue = _allKnownMapVenues[index];
      final updatedVenue = currentVenue.copyWith(
          isArchived: !currentVenue.isArchived  // ← Use current state from memory
      );

      await _updateAndSaveLocationReview(updatedVenue);

      if(mounted) {
        final action = updatedVenue.isArchived ? 'archived' : 'restored';
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${venueToArchive.name} $action.'))
        );
      }
    }
  }

  Future<void> _editVenueContact(StoredLocation venue) async {
    final updatedContact = await showDialog<VenueContact>(
      context: context,
      builder: (_) => VenueContactDialog(venue: venue),
    );
    if (updatedContact != null && mounted) {
      final index = _allKnownMapVenues.indexWhere((v) => v.placeId == venue.placeId);
      if (index != -1) {
        final updatedVenue = _allKnownMapVenues[index].copyWith(contact: updatedContact);
        await _updateAndSaveLocationReview(updatedVenue);
      }
    }
  }

  Future<void> _updateVenueJamNightSettings(StoredLocation updatedVenue) async {
    await _updateAndSaveLocationReview(updatedVenue);
  }

  Future<void> _showLocationDetailsDialog(StoredLocation passedInLocation) async {
    final location = _allKnownMapVenues.firstWhere((loc) => loc.placeId == passedInLocation.placeId, orElse: () => passedInLocation);
    if (!mounted) return;

    setState(() { _isLoading = true; });
    List<Gig> allGigs = await _loadAllGigs();
    List<Gig> upcomingGigsForVenue = allGigs.where((gig) => gig.placeId == location.placeId && gig.dateTime.isAfter(DateTime.now())).toList();
    upcomingGigsForVenue.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    Gig? nextUpcomingGig = upcomingGigsForVenue.isNotEmpty ? upcomingGigsForVenue.first : null;
    setState(() { _isLoading = false; });

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return VenueDetailsDialog(
          venue: location,
          nextGig: nextUpcomingGig,
          onArchive: () {
            Navigator.of(dialogContext).pop();
            _archiveVenue(location);
          },
          onBook: (venueToSaveAndBook) async {
            await _updateAndSaveLocationReview(venueToSaveAndBook);
            final newGig = await _launchBookingDialogForVenue(venueToSaveAndBook);
            if(mounted) Navigator.of(dialogContext).pop();
            if (newGig != null) {
              await Future.delayed(const Duration(milliseconds: 100));
              _showLocationDetailsDialog(venueToSaveAndBook);
            }
          },
          onSave: (updatedVenue) {
            _updateAndSaveLocationReview(updatedVenue);
          },
          onEditContact: () {
            Navigator.of(dialogContext).pop();
            _editVenueContact(location);
          },
          onEditJamSettings: () async {
            Navigator.of(dialogContext).pop();
            final result = await showDialog<JamOpenMicDialogResult>(
              context: context,
              builder: (_) => JamOpenMicDialog(venue: location),
            );
            if (result != null && result.settingsChanged && result.updatedVenue != null) {
              await _updateVenueJamNightSettings(result.updatedVenue!);
            }
          },
          onDataChanged: () async {
            await _refreshVenuesFromFirebase();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: const Key('map_page_visibility_detector'),
      onVisibilityChanged: (visibilityInfo) {
        // We only care when the widget becomes fully visible.
        if (visibilityInfo.visibleFraction == 1.0) {
          print("🗺️ MapPage is now visible. Triggering data refresh.");
          // Call the same data loading function used in initState.
          // This ensures the map always has the freshest data when viewed.
          _loadAllMapData();
        }
      },
      child: Stack(
        children: [
          // Use the _isMapReady flag to control what gets built.
          _isMapReady
              ? GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: _kInitialPosition,
            onMapCreated: (GoogleMapController controller) {
              if (!_controller.isCompleted) {
                _controller.complete(controller);
              }
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
              bottom: Theme.of(context).platform == TargetPlatform.iOS ? 90 : 60,
            ),
          )
          // If the map is NOT ready, show a loading circle instead.
          // This prevents the GoogleMap widget from ever being created in a bad state.
              : const Center(
            child: CircularProgressIndicator(),
          ),

          // The rest of your UI overlay is built on top, which is correct.
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
                            if (_isSearchVisible) {
                              _placesService.startSession();
                            } else {
                              _searchController.clear();
                              _autocompleteResults = [];
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
                          child: const Text('Search Map', style: TextStyle(fontSize: 16, color: Colors.black54)),
                        ),
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
                            activeThumbColor: Colors.orange.shade600,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_showJamSessions)
                  Card(
                    margin: const EdgeInsets.only(top: 6.0),
                    elevation: 2.0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: DayOfWeek.values.map((day) {
                          final bool isSelected = _selectedJamDay == day;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selectedJamDay = null; // Unselect if tapped again
                                } else {
                                  _selectedJamDay = day;
                                }
                                _updateMarkers(); // Refresh markers with new filter
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.orange.shade600 : Colors.lightBlue,
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              child: Text(day.toString().split('.').last.substring(0, 3), style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black54)),
                            ),
                          );
                        }).toList(),
                      ),
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
                          onTap: () => _selectPlaceAndMoveCamera(result),
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
      ),
    );
  }
}