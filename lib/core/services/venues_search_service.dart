// lib/features/map_venues/services/venue_search_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:the_money_gigs/features/map_venues/models/place_models.dart';
import 'package:the_money_gigs/features/map_venues/models/venue_model.dart';
// Import your existing Google Places service

class VenueSearchService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // final GooglePlacesService _googlePlaces = GooglePlacesService();

  /// Search for venues - checks Firebase FIRST, then Google if needed
  Future<List<PlaceAutocompleteResult>> searchVenues(String query) async {
    // Step 1: Search Firebase (FREE!)
    final firebaseResults = await _searchFirebase(query);

    if (firebaseResults.isNotEmpty) {
      print('✅ Found ${firebaseResults.length} venues in MoneyGigs database (FREE!)');
      return firebaseResults;
    }

    // Step 2: Not in Firebase, search Google (COSTS MONEY)
    print('⚠️ Not in MoneyGigs DB, calling Google Places API (costs money)');
    final googleResults = await _searchGooglePlaces(query);

    return googleResults;
  }

  /// Search Firebase venues by name (FREE!)
  Future<List<PlaceAutocompleteResult>> _searchFirebase(String query) async {
    try {
      // Simple text search (case-insensitive)
      final queryLower = query.toLowerCase();

      final snapshot = await _firestore
          .collection('venues')
          .where('visibility', isEqualTo: 'public')
          .where('isArchived', isEqualTo: false)
          .get();

      // Filter by name match
      final matches = snapshot.docs.where((doc) {
        final name = (doc.data()['name'] as String).toLowerCase();
        return name.contains(queryLower);
      }).map((doc) {
        final data = doc.data();
        return PlaceAutocompleteResult(
          placeId: doc.id,
          mainText: data['name'] ?? 'Unknown',
          secondaryText: data['address'] ?? '',
        );
      }).toList();

      return matches;
    } catch (e) {
      print('Error searching Firebase: $e');
      return [];
    }
  }

  /// Search Google Places (COSTS MONEY - only if not in Firebase)
  Future<List<PlaceAutocompleteResult>> _searchGooglePlaces(String query) async {
    // Use your existing Google Places autocomplete implementation
    // return await _googlePlaces.getAutocomplete(query);

    // For now, return empty (you'll integrate your existing Google Places code)
    return [];
  }

  /// Get venue details - checks Firebase FIRST
  Future<StoredLocation?> getVenueDetails(String placeId) async {
    // Step 1: Check Firebase (FREE!)
    final firebaseVenue = await _getFromFirebase(placeId);

    if (firebaseVenue != null) {
      print('✅ Loaded venue from MoneyGigs database (FREE!)');
      return firebaseVenue;
    }

    // Step 2: Not in Firebase, get from Google (COSTS MONEY)
    print('⚠️ Getting venue from Google Places API (costs money)');
    final googleVenue = await _getFromGooglePlaces(placeId);

    if (googleVenue != null) {
      // Save to Firebase so next user gets it for free
      await _cacheToFirebase(googleVenue);
    }

    return googleVenue;
  }

  /// Get venue from Firebase (FREE!)
  Future<StoredLocation?> _getFromFirebase(String placeId) async {
    try {
      final doc = await _firestore.collection('venues').doc(placeId).get();

      if (!doc.exists) return null;

      final data = doc.data()!;
      final geoPoint = data['coordinates'] as GeoPoint;

      return StoredLocation.fromJson({
        ...data,
        'latitude': geoPoint.latitude,
        'longitude': geoPoint.longitude,
      });
    } catch (e) {
      print('Error loading from Firebase: $e');
      return null;
    }
  }

  /// Get venue from Google Places (COSTS MONEY)
  Future<StoredLocation?> _getFromGooglePlaces(String placeId) async {
    // Use your existing Google Place Details implementation
    // final details = await _googlePlaces.getPlaceDetails(placeId);
    // return StoredLocation.fromGooglePlace(details);

    return null; // Placeholder - integrate your existing code
  }

  /// Cache Google result to Firebase (so next user gets it free)
  Future<void> _cacheToFirebase(StoredLocation venue) async {
    try {
      await _firestore.collection('venues').doc(venue.placeId).set({
        'placeId': venue.placeId,
        'name': venue.name,
        'address': venue.address,
        'coordinates': GeoPoint(
          venue.coordinates.latitude,
          venue.coordinates.longitude,
        ),
        'visibility': 'public',
        'isArchived': false,
        'hasJamSessions': false,
        'jamSessions': [],
        'createdBy': 'google_places_cache',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'communityRating': 0.0,
        'totalRatings': 0,
        'totalComments': 0,
      });

      print('✅ Cached venue to MoneyGigs database for future users');
    } catch (e) {
      print('Error caching to Firebase: $e');
    }
  }
}