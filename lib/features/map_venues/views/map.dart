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
import 'package:the_money_gigs/features/map_venues/models/place_models.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_contact.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';
import 'package:the_money_gigs/features/map_venues/widgets/jam_open_mic_dialog.dart';
import 'package:the_money_gigs/features/map_venues/widgets/venue_contact_dialog.dart';
import 'package:the_money_gigs/features/map_venues/widgets/venue_details_dialog.dart';
import 'package:the_money_gigs/global_refresh_notifier.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  bool _isMapReady = false;

  final Completer<GoogleMapController> _controller = Completer<GoogleMapController>();
  Set<Marker> _markers = {};

  List<Gig> _allLoadedGigs = [];
  List<StoredLocation> _allKnownMapVenues = [];
  List<StoredLocation> _jamSessionVenues = [];
  bool _showJamSessions = false;
  BitmapDescriptor _jamSessionMarkerIcon = BitmapDescriptor.defaultMarker;
  BitmapDescriptor? _gigMarkerIcon;

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
    // Replace the multiple calls in initState with a single async method
    // to control the order of operations.
    _initializeMapPage();
  }

  /// This new method controls the initialization sequence to prevent race conditions.
  Future<void> _initializeMapPage() async {
    // 1. First, wait for the permission check to complete.
    await _checkAndRequestLocationPermission();

    // After an async gap, always check if the widget is still mounted.
    if (!mounted) return;

    // 2. Now that permissions are handled, initialize services and add listeners.
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

    // 3. Check for the Google API Key.
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

    // 4. Finally, with everything set up, load the map data.
    await _loadAllMapData();

    if (mounted) {
      setState(() {
        _isMapReady = true;
      });
    }
  }

  // --- END OF MODIFICATIONS ---

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

  Future<void> _loadCustomMarker() async {
    final Uint8List markerIconBytes = await _getBytesFromAsset('assets/mapmarker.png', 100);
    final BitmapDescriptor icon = BitmapDescriptor.fromBytes(markerIconBytes);

    if (mounted) {
      setState(() {
        _gigMarkerIcon = icon;
        _updateMarkers();
      });
    }
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
      _loadAllMapData();
    }
  }

  Future<void> _loadAllMapData() async {
    if (!mounted) return;
    setState(() { _isLoading = true; });

    await _loadCustomMarker();

    await Future.wait([
      _loadSavedLocations(),
      _loadJamSessionAsset(),
      _loadAllGigs(),
    ]);

    _setJamSessionMarkerStyle();

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

  void _setJamSessionMarkerStyle() {
    _jamSessionMarkerIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
  }

  Future<void> _loadSavedLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? locationsJson = prefs.getStringList(_keySavedLocations);
      List<StoredLocation> loadedFromPrefs = [];
      if (locationsJson != null) {
        loadedFromPrefs = locationsJson.map((jsonString) => StoredLocation.fromJson(jsonDecode(jsonString))).toList();
      }
      if (mounted) {
        setState(() {
          _allKnownMapVenues = loadedFromPrefs;
          _updateMarkers();
        });
      }
    } catch (e) {
      // Handle error
    }
  }

  Future<List<Gig>> _loadAllGigs() async {
    final prefs = await SharedPreferences.getInstance();
    final String? gigsJsonString = prefs.getString(_keyGigsList);
    final gigs = (gigsJsonString != null) ? Gig.decode(gigsJsonString) : <Gig>[];
    if (mounted) {
      setState(() {
        _allLoadedGigs = gigs;
        _updateMarkers();
      });
    }
    return gigs;
  }

  void _updateMarkers() {
    if (!mounted || _gigMarkerIcon == null) {
      return;
    }
    final Set<Marker> newMarkers = {};
    final Set<String> placedMarkerIds = {};
    final now = DateTime.now();
    final upcomingGigVenuePlaceIds = _allLoadedGigs
        .where((gig) => gig.dateTime.isAfter(now))
        .map((gig) => gig.placeId)
        .toSet();

    final currentDisplayableVenues = _allKnownMapVenues.where((v) => !v.isArchived).toList();
    for (var loc in currentDisplayableVenues) {
      final bool hasUpcomingGig = upcomingGigVenuePlaceIds.contains(loc.placeId);
      String snippetText = loc.address;
      if (loc.rating > 0) {
        final String formattedRating = loc.rating.toStringAsFixed(1);
        snippetText = '${loc.address}  $formattedRating ⭐';
      }
      newMarkers.add(Marker(
        markerId: MarkerId('saved_${loc.placeId}'),
        position: loc.coordinates,
        infoWindow: InfoWindow(title: loc.name, snippet: snippetText),
        icon: hasUpcomingGig
            ? _gigMarkerIcon!
            : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
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

    final Gig? bookedGig = await showDialog<Gig>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BookingDialog(preselectedVenue: venue, googleApiKey: _googleApiKey, existingGigs: existingGigs),
    );

    if (bookedGig != null) {
      await _saveBookedGig(bookedGig);
    }
    return bookedGig;
  }

  Future<void> _archiveVenue(StoredLocation venueToArchive) async {
    final index = _allKnownMapVenues.indexWhere((v) => v.placeId == venueToArchive.placeId);
    if (index != -1) {
      final updatedVenue = _allKnownMapVenues[index].copyWith(isArchived: true);
      await _updateAndSaveLocationReview(updatedVenue);
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${venueToArchive.name} archived.')));
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
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
    );
  }
}

