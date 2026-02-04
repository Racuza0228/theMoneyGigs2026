// lib/core/services/location_service.dart

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

// 🎯 1. IMPORT BOTH PACKAGES
import 'package:geolocator/geolocator.dart'; // For getting current device position
import 'package:geocoding/geocoding.dart';    // For converting address string to coordinates

class LocationService {
  // Define the keys used in profile.dart to access address info
  static const String _keyCity = 'profile_city';
  static const String _keyState = 'profile_state';
  static const String _keyZipCode = 'profile_zip_code';

  // The ultimate fallback coordinates (Cincinnati, OH)
  static const LatLng _defaultCenter = LatLng(39.103119, -84.512016);

  /// Determines the initial map center with a priority system.
  /// 1. User's saved profile address (City, State, or ZIP).
  /// 2. User's current GPS location.
  /// 3. A hardcoded default location (Cincinnati, OH).
  Future<LatLng> getInitialMapCenter() async {
    // Priority 1: Try to use the user's saved profile address.
    try {
      final prefs = await SharedPreferences.getInstance();
      final city = prefs.getString(_keyCity);
      final state = prefs.getString(_keyState);
      final zip = prefs.getString(_keyZipCode);

      String? addressString;

      if (city != null && city.isNotEmpty && state != null && state.isNotEmpty) {
        addressString = '$city, $state';
      } else if (zip != null && zip.isNotEmpty) {
        addressString = zip;
      }

      if (addressString != null) {
        if (kDebugMode) print('📍 LocationService: Geocoding profile address: "$addressString"');

        // 🎯 2. USE THE CORRECT METHOD from the `geocoding` package
        List<Location> locations = await locationFromAddress(addressString);

        if (locations.isNotEmpty) {
          if (kDebugMode) print('✅ LocationService: Found coordinates from profile address.');
          // The `geocoding` package returns a `Location` object.
          return LatLng(locations.first.latitude, locations.first.longitude);
        }
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ LocationService: Could not geocode profile address. Reason: $e');
    }

    // Priority 2: Try to use the device's current location (using `geolocator`).
    try {
      if (kDebugMode) print('📍 LocationService: Trying to get current device location...');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        final Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
        if (kDebugMode) print('✅ LocationService: Found coordinates from device location.');
        // The `geolocator` package returns a `Position` object.
        return LatLng(position.latitude, position.longitude);
      } else {
        if (kDebugMode) print('⚠️ LocationService: Location permission denied.');
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ LocationService: Could not get device location. Reason: $e');
    }

    // Priority 3: Fallback to the default coordinates.
    if (kDebugMode) print('📍 LocationService: Falling back to default coordinates.');
    return _defaultCenter;
  }
}
