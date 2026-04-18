// lib/features/map_venues/views/map.dart
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle, Uint8List, ByteData;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
// permission_handler removed — LocationService owns location permissions
// via geolocator internally, avoiding the two-system conflict that caused
// the map to open in California even after the user granted access.
import 'package:geolocator/geolocator.dart';
import 'package:the_money_gigs/core/services/location_service.dart';

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
import 'package:visibility_detector/visibility_detector.dart';

import 'package:the_money_gigs/features/map_venues/repositories/venue_repository.dart';
import 'package:the_money_gigs/main.dart';
import 'package:the_money_gigs/features/app_demo/widgets/map_demo_overlay.dart';
import 'package:the_money_gigs/features/map_venues/widgets/map_tutorial_overlay.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

// This is a top-level helper function and can remain as is.
StoredLocation _mergeJamPreferences(
    StoredLocation publicVenue,
    StoredLocation localVenue,
    ) {
  if (localVenue.jamSessions.isEmpty) {
    return publicVenue;
  }
  final Map<String, bool> localPrefs = {
    for (var session in localVenue.jamSessions) session.id: session.showInGigsList,
  };
  final mergedSessions = publicVenue.jamSessions.map((pubSession) {
    final localPref = localPrefs[pubSession.id];
    if (localPref != null) {
      return pubSession.copyWith(showInGigsList: localPref);
    }
    return pubSession;
  }).toList();
  return publicVenue.copyWith(jamSessions: mergedSessions);
}

class _MapPageState extends State<MapPage> {
  // --- STATE VARIABLES ---
  final Completer<GoogleMapController> _controller = Completer<GoogleMapController>();
  Set<Marker> _markers = {};
  CameraPosition? _initialCameraPosition;
  late final PlacesService _placesService;

  // Status flags
  bool _isFullyInitialized = false;
  bool _isLoading = false;
  bool _showMapTutorial = false;

  // Search UI state
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _isSearchVisible = false;
  List<PlaceAutocompleteResult> _autocompleteResults = [];
  final GlobalKey _searchBarKey = GlobalKey();

  // Data state
  List<Gig> _allLoadedGigs = [];
  Set<String> _userSavedPlaceIds = {};
  List<StoredLocation> _allKnownMapVenues = [];

  // Filter state
  bool _showJamSessions = false;
  DayOfWeek? _selectedJamDay;

  // Marker icons
  BitmapDescriptor _jamSessionMarkerIcon = BitmapDescriptor.defaultMarker;
  BitmapDescriptor? _gigMarkerIcon;
  BitmapDescriptor _publicVenueMarkerIcon = BitmapDescriptor.defaultMarker;
  BitmapDescriptor _privateVenueMarkerIcon = BitmapDescriptor.defaultMarker;

  // Services and keys
  VenueRepository? _venueRepository;
  DemoProvider? _demoProvider;

  static const String _googleApiKey = String.fromEnvironment('GOOGLE_API_KEY');
  static const String _isConnectedKey = 'is_connected_to_network';
  static const String _keyGigsList = 'gigs_list';
  static const String _keySavedLocations = 'saved_locations';

  // --- INITIALIZATION & LIFECYCLE ---

  @override
  void initState() {
    super.initState();
    // Initialize services that don't depend on context or build.
    _placesService = PlacesService(apiKey: _googleApiKey);
    //_setInitialCameraPosition(); // Start fetching the map center immediately.
  }

  /// Shows a brief explanation dialog the very first time we are about to
  /// ask for location permission. After dismissal the OS dialog appears with
  /// context, so users understand exactly why we need it.
  Future<void> _showLocationRationaleIfNeeded() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final alreadyExplained =
        prefs.getBool('location_rationale_shown') ?? false;
    if (alreadyExplained) return;

    // If they already have a profile address we don't need GPS at all,
    // so there's no point showing this dialog.
    final city = prefs.getString('profile_city') ?? '';
    final zip  = prefs.getString('profile_zip_code') ?? '';
    if (city.isNotEmpty || zip.isNotEmpty) return;

    await prefs.setBool('location_rationale_shown', true);
    if (!mounted) return;

    // Push the dialog below the status bar + AppBar.
    // extendBodyBehindAppBar is true in main.dart, so without this the
    // dialog floats up behind the AppBar.
    final double topClearance =
        MediaQuery.of(context).padding.top + kToolbarHeight + 8;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        insetPadding: EdgeInsets.fromLTRB(24, topClearance, 24, 24),
        title: const Text('Finding venues near you'),
        content: const Text(
          'MoneyGigs uses your location to center the map on your area '
              'so you can find nearby venues where musicians play.\n\n'
              "We'll ask for location access now. You can also set your home "
              'city in Profile instead if you prefer.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<void> _setInitialCameraPosition() async {
    final locationService = LocationService();
    final LatLng center = await locationService.getInitialMapCenter();
    if (mounted) {
      setState(() {
        _initialCameraPosition = CameraPosition(target: center, zoom: 12.0);
      });
    }
  }

  /// Called after [onMapCreated] so we can animate to the real GPS fix even
  /// if [_setInitialCameraPosition] settled for the service's fallback coords.
  /// Uses geolocator (same as LocationService) so there is no two-system conflict.
  Future<void> _recenterOnActualLocation(GoogleMapController controller) async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) return;

      final locationService = LocationService();
      final LatLng actual = await locationService.getInitialMapCenter();

      if (mounted) {
        await controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: actual, zoom: 12.0),
          ),
        );
      }
    } catch (e) {
      // Non-fatal — user can always tap the my-location button.
      print('⚠️ Could not re-center on actual location: $e');
    }
  }

  /// This is called by VisibilityDetector when the page becomes visible.
  /// It runs all the async setup and data loading.
  Future<void> _initializeAndLoadData() async {
    if (_isFullyInitialized) return;

    // Show a one-time explanation before the OS location dialog appears.
    // This gives users context so the permission request doesn't feel random.
    await _showLocationRationaleIfNeeded();

    // LocationService.getInitialMapCenter() handles permissions internally
    // via geolocator (priority: profile address → GPS → Cincinnati default).
    await _setInitialCameraPosition();

    if (!mounted) return;

    // Set up listeners.
    globalRefreshNotifier.addListener(_handleGlobalRefresh);

    _demoProvider = Provider.of<DemoProvider>(context, listen: false);
    _demoProvider?.addListener(_onDemoStateChanged);

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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Warning: Google API Key is missing. Map search will fail.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      });
    }

    // Now load all the data for the map.
    await _loadAllMapData();

    if (mounted) {
      setState(() {
        _isFullyInitialized = true;
      });
    }

    // Check demo state once everything is ready.
    _onDemoStateChanged();

    // Show the first-time tutorial after a short delay so the map markers
    // have rendered and the user can see what we're explaining.
    if (mounted && await MapTutorialOverlay.shouldShow()) {
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) setState(() => _showMapTutorial = true);
    }
  }

  @override
  void dispose() {
    globalRefreshNotifier.removeListener(_handleGlobalRefresh);
    // Use try-catch as the provider might be disposed during hot restart.
    try {
      if (mounted) {
        Provider.of<DemoProvider>(context, listen: false).removeListener(_onDemoStateChanged);
      }
    } catch (e) {
      // Ignore error during dispose.
    }
    _demoProvider?.removeListener(_onDemoStateChanged);

    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // --- DEMO ---
  void _onDemoStateChanged() {
    if (!mounted) return;

    final demoProvider = Provider.of<DemoProvider>(context, listen: false);

    // Onboarding just finished — initialize the map now that the user has
    // seen the welcome screen and understands what the app does.
    if (!demoProvider.isDemoModeActive && !_isFullyInitialized) {
      _initializeAndLoadData();
      return;
    }

    if (!demoProvider.isDemoModeActive) return;

    // Manage UI state for any legacy guided tour steps.
    setState(() {
      if (demoProvider.currentStep == DemoStep.mapVenueSearch) {
        _isSearchVisible = true;
      }
    });
  }

  // --- MARKERS & DATA LOADING ---

  Future<BitmapDescriptor> _loadCustomMarker() async {
    final Uint8List markerIconBytes = await _getBytesFromAsset('assets/mapmarker.png', 100);
    return BitmapDescriptor.fromBytes(markerIconBytes);
  }

  Future<Uint8List> _getBytesFromAsset(String path, int width) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
    ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  }

  void _handleGlobalRefresh() {
    if (mounted) {
      print("🗺️ MapPage received global refresh signal. Reloading all map data.");
      _loadAllMapData();
      // Re-center in case the user just saved a new profile address.
      // This runs in parallel with the data reload — no blocking.
      _recenterMapFromProfile();
    }
  }

  /// Re-reads location priority (profile address → GPS → default) and
  /// animates the camera to the result. Safe to call at any time.
  Future<void> _recenterMapFromProfile() async {
    final locationService = LocationService();
    final LatLng newCenter = await locationService.getInitialMapCenter();
    if (!mounted) return;

    // Update the stored position so a hot-reload also gets the right coords.
    setState(() {
      _initialCameraPosition = CameraPosition(target: newCenter, zoom: 12.0);
    });

    // Animate only if the map controller is already ready.
    if (_controller.isCompleted) {
      final controller = await _controller.future;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: newCenter, zoom: 12.0),
        ),
      );
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

    Map<String, StoredLocation> finalVenuesMap = { for (var venue in localVenues) venue.placeId: venue };
    for (var jamVenue in localJamVenues) {
      if (!finalVenuesMap.containsKey(jamVenue.placeId)) {
        finalVenuesMap[jamVenue.placeId] = jamVenue;
      }
    }

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
            final mergedVenue = _mergeJamPreferences(publicVenue, localVenue);
            finalVenuesMap[publicVenue.placeId] = localVenue.copyWith(
              isPublic: true,
              rating: publicVenue.rating,
              comment: publicVenue.comment,
              averageRating: publicVenue.averageRating,
              totalRatings: publicVenue.totalRatings,
              jamSessions: mergedVenue.jamSessions,
            );
          } else {
            finalVenuesMap[publicVenue.placeId] = publicVenue;
          }
        }
      }
    } else {
      print("🚫 No network. Using local SharedPreferences data only.");
      for (var entry in finalVenuesMap.entries) {
        finalVenuesMap[entry.key] = entry.value.copyWith(isPublic: false);
      }
    }

    if (mounted) {
      setState(() {
        _gigMarkerIcon = loadedGigIcon;
        _allKnownMapVenues = finalVenuesMap.values.toList();
        _allLoadedGigs = localGigs;
      });
    }

    _updateMarkers();

    if (mounted) { setState(() { _isLoading = false; }); }
  }

  Future<void> _refreshVenuesFromFirebase() async {
    if (_venueRepository == null) {
      print("⚠️ Cannot refresh from Firebase, repository not initialized. (User may be offline).");
      return;
    }

    print("🔄 Refreshing venues from Firebase...");
    try {
      const String userId = 'current_user_id'; // TODO: Get from FirebaseAuth
      final publicVenues = await _venueRepository!.getAllPublicVenues(userId);
      if (!mounted) return;

      setState(() {
        for (var publicVenue in publicVenues) {
          final index = _allKnownMapVenues.indexWhere((v) => v.placeId == publicVenue.placeId);
          if (index != -1) {
            final existingVenue = _allKnownMapVenues[index];
            final mergedVenue = publicVenue.copyWith(
              instrumentTags: existingVenue.instrumentTags.isNotEmpty ? existingVenue.instrumentTags : publicVenue.instrumentTags,
              genreTags: existingVenue.genreTags.isNotEmpty ? existingVenue.genreTags : publicVenue.genreTags,
            );
            _allKnownMapVenues[index] = mergedVenue;
          }
        }
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
    _jamSessionMarkerIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
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
    return [];
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

  // --- UI & INTERACTION ---

  void _updateMarkers() {
    if (!mounted || _gigMarkerIcon == null) return;

    final Set<Marker> newMarkers = {};
    final now = DateTime.now();
    final upcomingGigVenuePlaceIds = _allLoadedGigs.where((gig) => gig.dateTime.isAfter(now)).map((gig) => gig.placeId).toSet();
    final currentDisplayableVenues = _allKnownMapVenues.where((v) => !v.isArchived).toList();

    List<StoredLocation> venuesToShow;
    if (_showJamSessions) {
      venuesToShow = currentDisplayableVenues.where((v) {
        if (v.jamSessions.isEmpty) return false;
        if (_selectedJamDay != null) {
          return v.jamSessions.any((session) => session.day == _selectedJamDay);
        }
        return true;
      }).toList();
    } else {
      venuesToShow = currentDisplayableVenues.where((v) {
        return v.isPublic || _userSavedPlaceIds.contains(v.placeId);
      }).toList();
    }

    for (var loc in venuesToShow) {
      final bool hasUpcomingGig = upcomingGigVenuePlaceIds.contains(loc.placeId);
      String snippetText = loc.address;

      if (_showJamSessions && loc.jamSessions.isNotEmpty) {
        snippetText = loc.jamOpenMicDisplayString(context);
      } else if (loc.rating > 0) {
        snippetText = '${loc.address}  ${loc.rating.toStringAsFixed(1)} ⭐';
      }

      BitmapDescriptor venueIcon;
      if (hasUpcomingGig) {
        venueIcon = _gigMarkerIcon!;
      } else if (_showJamSessions) {
        venueIcon = _jamSessionMarkerIcon;
      } else if (loc.isPublic) {
        venueIcon = _publicVenueMarkerIcon;
      } else {
        venueIcon = _privateVenueMarkerIcon;
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

  Future<void> _fetchAutocompleteResults(String input) async {
    final results = await _placesService.fetchAutocompleteResults(input);
    if (mounted) {
      setState(() { _autocompleteResults = results; });
    }
  }

  Future<void> _selectPlaceAndMoveCamera(PlaceAutocompleteResult selectedPlace) async {
    final demoProvider = Provider.of<DemoProvider>(context, listen: false);
    if (demoProvider.isDemoModeActive && demoProvider.currentStep == DemoStep.mapVenueSearch) {
      print("🎬 DEMO: Search step complete. Advancing to mapAddVenue.");
      demoProvider.nextStep();
    }

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
                          return DropdownMenuItem<dynamic>(value: result, child: Text(name, overflow: TextOverflow.ellipsis));
                        }).toList(),
                        onChanged: (newValue) => setDialogState(() => selectedResult = newValue!),
                      ),
                      actions: [
                        TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(dialogContext).pop()),
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
    final demoProvider = Provider.of<DemoProvider>(context, listen: false);
    final existingLocations = _allKnownMapVenues.where((loc) => loc.placeId == place.placeId);

    if (existingLocations.isNotEmpty) {
      if (demoProvider.isDemoModeActive && demoProvider.currentStep == DemoStep.mapAddVenue) {
        print("🎬 DEMO: Existing venue found. Advancing from 'mapAddVenue' to 'mapBookGig'.");
        demoProvider.nextStep();
      }
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
              TextButton(
                child: const Text('Add'),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  if (demoProvider.isDemoModeActive && demoProvider.currentStep == DemoStep.mapAddVenue) {
                    print("🎬 DEMO: Advancing from 'mapAddVenue' to 'mapBookGig' BEFORE showing dialog.");
                    demoProvider.nextStep();
                  }
                  _saveLocation(place);
                },
              ),
            ],
          );
        },
      );
    }
  }

  Future<void> _updateAndSaveLocationReview(StoredLocation updatedLocation) async {
    try {
      print('🏷️ MAP: _updateAndSaveLocationReview called');
      final prefs = await SharedPreferences.getInstance();
      final List<String>? existingSavedJson = prefs.getStringList(_keySavedLocations);
      List<StoredLocation> userSavedVenues = [];

      if (existingSavedJson != null) {
        userSavedVenues = existingSavedJson.map((jsonString) => StoredLocation.fromJson(jsonDecode(jsonString))).toList();
      }

      int index = userSavedVenues.indexWhere((loc) => loc.placeId == updatedLocation.placeId);
      if (index != -1) {
        userSavedVenues[index] = updatedLocation;
      } else {
        userSavedVenues.add(updatedLocation);
      }

      final memoryIndex = _allKnownMapVenues.indexWhere((loc) => loc.placeId == updatedLocation.placeId);
      if (memoryIndex != -1) {
        setState(() => _allKnownMapVenues[memoryIndex] = updatedLocation);
      }

      _userSavedPlaceIds = userSavedVenues.map((v) => v.placeId).toSet();

      final List<String> locationsJson = userSavedVenues.map((loc) => jsonEncode(loc.toJson())).toList();
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

  Future<void> _saveLocation(PlaceApiResult placeToSave) async {
    if (_allKnownMapVenues.any((loc) => loc.placeId == placeToSave.placeId)) {
      final existingLoc = _allKnownMapVenues.firstWhere((l) => l.placeId == placeToSave.placeId);
      _showLocationDetailsDialog(existingLoc);
      return;
    }

    final newLocation = StoredLocation(
      placeId: placeToSave.placeId,
      name: placeToSave.name,
      address: placeToSave.address,
      coordinates: placeToSave.coordinates,
    );

    final prefs = await SharedPreferences.getInstance();
    final List<String>? existingSavedJson = prefs.getStringList(_keySavedLocations);
    List<StoredLocation> userSavedVenues = [];

    if (existingSavedJson != null) {
      userSavedVenues = existingSavedJson.map((jsonString) => StoredLocation.fromJson(jsonDecode(jsonString))).toList();
    }

    userSavedVenues.add(newLocation);
    _userSavedPlaceIds.add(newLocation.placeId);

    final List<String> locationsJson = userSavedVenues.map((loc) => jsonEncode(loc.toJson())).toList();
    await prefs.setStringList(_keySavedLocations, locationsJson);

    globalRefreshNotifier.notify();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${newLocation.name} added to saved venues!')));
    }
    _showLocationDetailsDialog(newLocation);
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

    final demoProvider = Provider.of<DemoProvider>(context, listen: false);

    if (demoProvider.isDemoModeActive && demoProvider.currentStep == DemoStep.mapBookGig) {
      demoProvider.nextStep(); // mapBookGig -> bookingFormValue
    }

    final demoStep = demoProvider.isDemoModeActive ? demoProvider.currentStep : null;

    final GigEditResult? result = await showDialog<GigEditResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BookingDialog(
        preselectedVenue: venue,
        googleApiKey: _googleApiKey,
        existingGigs: existingGigs,
        currentDemoStep: demoStep,
      ),
    );

    if (result != null && result.action == GigEditResultAction.updated && result.gig != null) {
      if (demoProvider.isDemoModeActive && demoProvider.currentStep == DemoStep.bookingFormAction) {
        demoProvider.nextStep();
      }
      await _saveBookedGig(result.gig!);
      return result.gig;
    } else {
      if (demoProvider.isDemoModeActive) {
        demoProvider.endDemo();
      }
    }
    return null;
  }

  Future<void> _archiveVenue(StoredLocation venueToArchive) async {
    final index = _allKnownMapVenues.indexWhere((v) => v.placeId == venueToArchive.placeId);
    if (index != -1) {
      final currentVenue = _allKnownMapVenues[index];
      final updatedVenue = currentVenue.copyWith(isArchived: !currentVenue.isArchived);
      await _updateAndSaveLocationReview(updatedVenue);
      if (mounted) {
        final action = updatedVenue.isArchived ? 'archived' : 'restored';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${venueToArchive.name} $action.')));
      }
    }
  }

  Future<void> _editVenueContact(StoredLocation venue) async {
    final updatedContact = await showDialog<VenueContact>(context: context, builder: (_) => VenueContactDialog(venue: venue));
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

    final demoProvider = Provider.of<DemoProvider>(context, listen: false);
    final demoStep = demoProvider.isDemoModeActive ? demoProvider.currentStep : null;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return VenueDetailsDialog(
          venue: location,
          nextGig: nextUpcomingGig,
          currentDemoStep: demoStep,
          onArchive: () {
            Navigator.of(dialogContext).pop();
            _archiveVenue(location);
          },
          onBook: (venueToSaveAndBook) async {
            await _updateAndSaveLocationReview(venueToSaveAndBook);
            final newGig = await _launchBookingDialogForVenue(venueToSaveAndBook);
            if (mounted) Navigator.of(dialogContext).pop();
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
            final result = await showDialog<JamOpenMicDialogResult>(context: context, builder: (_) => JamOpenMicDialog(venue: location));
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

  // --- BUILD METHOD ---

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: const Key('map_page_visibility_detector'),
      onVisibilityChanged: (visibilityInfo) {
        if (visibilityInfo.visibleFraction > 0 && !_isFullyInitialized) {
          // Don't initialize while onboarding is active. The map is tab 0
          // so VisibilityDetector fires before the welcome screen appears,
          // which causes OS location dialogs to show before the user has
          // seen any context for why we need location access.
          // _onDemoStateChanged() will trigger initialization once done.
          final demoProvider =
          Provider.of<DemoProvider>(context, listen: false);
          if (demoProvider.isDemoModeActive) return;
          _initializeAndLoadData();
        }
      },
      child: buildMapContent(),
    );
  }

  /// Builds the actual UI for the map page.
  Widget buildMapContent() {
    // Show a loading screen until BOTH the initial camera position is ready
    // AND the main data has been loaded.
    if (_initialCameraPosition == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Finding your spot on the map..."),
          ],
        ),
      );
    }

    // Once ready, build the full map UI.
    return Consumer<DemoProvider>(
      builder: (context, demoProvider, child) {
        final bool isDemoSearchStep = demoProvider.isDemoModeActive &&
            demoProvider.currentStep == DemoStep.mapVenueSearch;

        return Stack(
          children: [
            GoogleMap(
              mapType: MapType.normal,
              initialCameraPosition: _initialCameraPosition!,
              onMapCreated: (GoogleMapController controller) {
                if (!_controller.isCompleted) {
                  _controller.complete(controller);
                  // ✅ FIX: Re-center after the controller is ready.
                  // This covers the race where _setInitialCameraPosition ran
                  // before the OS returned the real GPS fix, and ensures the
                  // user always lands on their actual location.
                  _recenterOnActualLocation(controller);
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
            ),
            Positioned(
              top: 12.0,
              left: 12.0,
              right: 12.0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    type: MaterialType.transparency,
                    child: Card(
                      key: _searchBarKey,
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
                              child: const Text('Search Map',
                                  style: TextStyle(fontSize: 16, color: Colors.black54)),
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
                                  _selectedJamDay = isSelected ? null : day;
                                  _updateMarkers();
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isSelected ? Colors.orange.shade600 : Colors.lightBlue,
                                  borderRadius: BorderRadius.circular(8.0),
                                ),
                                child: Text(
                                  day.toString().split('.').last.substring(0, 3),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? Colors.white : Colors.black54,
                                  ),
                                ),
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
            if (isDemoSearchStep)
              MapDemoOverlay(
                searchBarKey: _searchBarKey,
              ),

            // First-time tutorial — shown once after map fully loads
            if (_showMapTutorial && _isFullyInitialized)
              MapTutorialOverlay(
                searchBarKey: _searchBarKey,
                onDismiss: () => setState(() => _showMapTutorial = false),
              ),
          ],
        );
      },
    );
  }
}