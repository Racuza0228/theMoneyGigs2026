// lib/core/services/drive_time_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart'; // <<< NEW IMPORT
import 'package:the_money_gigs/global_refresh_notifier.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';

class DriveTimeService {
  final String googleApiKey;
  final List<StoredLocation> allKnownVenues;
  final String? address1;
  final String? city;
  final String? state;
  final String? zipCode;


  DriveTimeService({
    required this.googleApiKey,
    required this.allKnownVenues,
    this.address1,
    this.city,
    this.state,
    this.zipCode,
   });

  Future<String?> _getBestOrigin() async {
    // --- CHANGE 2: Simplified and clarified logic ---

    // Clean up potentially null strings to avoid "null" in the final output
    final cleanAddress = address1 ?? '';
    final cleanCity = city ?? '';
    final cleanState = state ?? '';
    final cleanZip = zipCode ?? '';

    // Priority 1: A specific street address is provided.
    if (cleanAddress.trim().isNotEmpty) {
      print("DriveTimeService: Using specific profile address as origin.");
      return '$cleanAddress, $cleanCity, $cleanState $cleanZip'.trim();
    }

    // Priority 2: A partial, non-specific address (city, state, zip) is provided.
    if (cleanCity.trim().isNotEmpty || cleanState.trim().isNotEmpty || cleanZip.trim().isNotEmpty) {
      print("DriveTimeService: Using partial profile address as origin.");
      return '$cleanCity, $cleanState $cleanZip'.trim();
    }

    // Priority 3: FINAL FALLBACK. If no address info exists at all, try current location.
    print("DriveTimeService: No profile address found. Falling back to current device location.");

    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('DriveTimeService: Location services are disabled.');
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('DriveTimeService: Location permissions were denied.');
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      print('DriveTimeService: Location permissions are permanently denied.');
      return null;
    }

    try {
      print("DriveTimeService: Attempting to get current GPS position...");
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 10));

      print("DriveTimeService: Successfully retrieved GPS position.");
      return '${position.latitude},${position.longitude}';
    } catch (e) {
      print("DriveTimeService: Error getting current location (or timed out): $e");
      return null;
    }
  }

  // ... no other changes are needed in the rest of the file ...
  Future<StoredLocation?> fetchAndCacheDriveTime(StoredLocation venue) async {
    if (venue.driveDuration != null && venue.driveDuration!.isNotEmpty) {
      return null;
    }

    if (googleApiKey.isEmpty || googleApiKey == "YOUR_GOOGLE_PLACES_API_KEY_HERE") {
      print("Cannot fetch drive time: Google API Key is not configured.");
      return null;
    }

    final String? origin = await _getBestOrigin();

    if (origin == null || origin.trim().isEmpty) {
      print("Cannot fetch drive time: No valid origin (user address or current location) is available.");
      return null;
    }

    final String encodedOrigin = Uri.encodeComponent(origin);
    final String destination = Uri.encodeComponent(venue.address);
    final String url = 'https://maps.googleapis.com/maps/api/directions/json?origin=$encodedOrigin&destination=$destination&key=$googleApiKey';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && (data['routes'] as List).isNotEmpty) {
          final leg = data['routes'][0]['legs'][0];
          final String distance = leg['distance']['text'];
          final String duration = leg['duration']['text'];

          final updatedVenue = venue.copyWith(
            driveDuration: () => duration,
            driveDistance: () => distance,
          );

          await _updateVenueInPrefs(updatedVenue);
          return updatedVenue;
        } else {
          print("Directions API Error: ${data['status']} - ${data['error_message'] ?? 'No routes found.'}");
        }
      } else {
        print("Error contacting Directions API: ${response.statusCode}");
      }
    } catch (e) {
      print("An error occurred while fetching drive time: $e");
    }
    return null;
  }

  Future<void> _updateVenueInPrefs(StoredLocation venueToUpdate) async {
    final prefs = await SharedPreferences.getInstance();
    List<StoredLocation> currentVenues = List.from(allKnownVenues);
    int index = currentVenues.indexWhere((v) => v.placeId == venueToUpdate.placeId);

    if (index != -1) {
      currentVenues[index] = venueToUpdate;
      final List<String> updatedLocationsJson = currentVenues.map((loc) => jsonEncode(loc.toJson())).toList();
      await prefs.setStringList('saved_locations', updatedLocationsJson);
      globalRefreshNotifier.notify();
    }
  }}
