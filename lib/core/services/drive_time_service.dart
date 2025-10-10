// lib/drive_time_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_money_gigs/global_refresh_notifier.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart'; // This defines StoredLocation

class DriveTimeService {
  // --- <<< CHANGE: REMOVED 'final' KEYWORD FROM THESE PROPERTIES >>> ---
  String googleApiKey;
  String? userProfileAddress;
  List<StoredLocation> allKnownVenues;

  DriveTimeService({
    required this.googleApiKey,
    required this.userProfileAddress,
    required this.allKnownVenues,
  });

  // The rest of the file (fetchAndCacheDriveTime, _updateVenueInPrefs) is unchanged.
  // ...
// lib/drive_time_service.dart
// ... (imports remain the same)

// ... (class definition remains the same)
  Future<StoredLocation?> fetchAndCacheDriveTime(StoredLocation venue) async {
    // Condition 1: Don't fetch if we already have the data
    if (venue.driveDuration != null && venue.driveDuration!.isNotEmpty) {
      return null; // No update needed
    }

    // Condition 2: Don't fetch if prerequisites are missing
    if (userProfileAddress == null || userProfileAddress!.isEmpty) {
      print("Cannot fetch drive time: User profile address is missing.");
      return null;
    }
    if (googleApiKey.isEmpty || googleApiKey == "YOUR_GOOGLE_PLACES_API_KEY_HERE") {
      print("Cannot fetch drive time: Google API Key is not configured.");
      return null;
    }

    final String origin = Uri.encodeComponent(userProfileAddress!);
    final String destination = Uri.encodeComponent(venue.address);
    final String url = 'https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination&key=$googleApiKey';

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

          // Save the updated venue back to SharedPreferences
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
    return null; // Return null if fetch failed
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
  }
}
