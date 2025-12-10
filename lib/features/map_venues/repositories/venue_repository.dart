// lib/features/map_venues/repositories/venue_repository.dart
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/venue_model.dart';

class VenueRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Fetch all public venue IDs
  Future<List<String>> getAllPublicVenueIds() async {
    try {
      final snapshot = await _firestore.collection('venues').get();
      return snapshot.docs.map((doc) => doc.id).toList();
    } catch (e) {
      print('Error fetching public venue IDs: $e');
      return [];
    }
  }

  /// Fetches all public venues and merges them with user's ratings
  Future<List<StoredLocation>> getAllPublicVenues(String userId) async {
    try {
      // 1. Fetch all public venue documents
      final venuesSnapshot = await _firestore.collection('venues').get();
      if (venuesSnapshot.docs.isEmpty) return [];

      // 2. Fetch all ratings submitted by the current user
      final ratingsSnapshot = await _firestore
          .collection('venueRatings')
          .where('userId', isEqualTo: userId)
          .get();

      // 3. Create a quick-lookup map of placeId -> rating data
      final userRatingsMap = {
        for (var doc in ratingsSnapshot.docs)
          doc.data()['placeId'] as String: doc.data()
      };

      // 4. Map venue documents to StoredLocation objects
      return venuesSnapshot.docs.map((venueDoc) {
        final venueData = venueDoc.data();
        final placeId = venueData['placeId'] as String;
        final ratingData = userRatingsMap[placeId];

        return _venueFromFirestore(
          venueDoc,
          rating: ratingData?['rating'] as double?,
          comment: ratingData?['comment'] as String?,
        );
      }).toList();

    } catch (e) {
      print('❌ Error fetching full public venues: $e');
      return [];
    }
  }

  /// Saves or updates a venue's core data
  Future<void> saveVenue(StoredLocation venue, String userId) async {
    final venueRef = _firestore.collection('venues').doc(venue.placeId);

    final Map<String, dynamic> venueData = {
      'name': venue.name,
      'address': venue.address,
      'coordinates': GeoPoint(venue.coordinates.latitude, venue.coordinates.longitude),
      'placeId': venue.placeId,
    };

    final doc = await venueRef.get();
    if (doc.exists) {
      // Venue exists, just update timestamp
      await venueRef.update({'updatedAt': FieldValue.serverTimestamp()});
    } else {
      // New venue - add with initial rating fields
      venueData['createdAt'] = FieldValue.serverTimestamp();
      venueData['createdBy'] = userId;
      venueData['updatedAt'] = FieldValue.serverTimestamp();
      venueData['averageRating'] = 0.0;  // ← NEW: Initialize
      venueData['totalRatings'] = 0;     // ← NEW: Initialize
      await venueRef.set(venueData);
    }
  }

  /// Save or update user's rating - NOW UPDATES VENUE'S AVERAGE!
  Future<bool> saveVenueRating({
    required String userId,
    required String placeId,
    required double rating,
    String? comment,
  }) async {
    final docId = '${placeId}_$userId';

    try {
      print("--- 🔵 DEBUG [Repository]: Attempting to save rating ---");
      print("   - Document ID: $docId");

      // Start a batch write to update both collections atomically
      final batch = _firestore.batch();

      // 1. Get the current rating (if it exists)
      final ratingRef = _firestore.collection('venueRatings').doc(docId);
      final existingRatingDoc = await ratingRef.get();
      final oldRating = existingRatingDoc.exists
          ? (existingRatingDoc.data()!['rating'] as num).toDouble()
          : null;

      // 2. Save/update the rating
      final Map<String, dynamic> dataToSave = {
        'placeId': placeId,
        'userId': userId,
        'rating': rating,
        'comment': comment,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      batch.set(ratingRef, dataToSave, SetOptions(merge: true));
      print("   - Rating data prepared for save");

      // 3. Update the venue's aggregate rating
      final venueRef = _firestore.collection('venues').doc(placeId);
      final venueDoc = await venueRef.get();

      if (!venueDoc.exists) {
        print('⚠️ Cannot rate non-existent venue: $placeId');
        return false;
      }

      final venueData = venueDoc.data()!;

      // ← FIX: Handle NaN and missing fields!
      var currentAverage = (venueData['averageRating'] as num?)?.toDouble() ?? 0.0;
      var currentTotal = venueData['totalRatings'] as int? ?? 0;

      // If averageRating is NaN, reset to 0
      if (currentAverage.isNaN) {
        print("   - ⚠️ Found NaN averageRating, resetting to 0");
        currentAverage = 0.0;
        currentTotal = 0; // Also reset total
      }

      double newAverage;
      int newTotal;

      if (oldRating != null && currentTotal > 0) {
        // User is UPDATING their rating
        final sum = currentAverage * currentTotal;
        newAverage = (sum - oldRating + rating) / currentTotal;
        newTotal = currentTotal; // Total stays the same
        print("   - Updating existing rating: $oldRating → $rating");
      } else {
        // User is ADDING a new rating (or fixing corrupt data)
        final sum = currentAverage * currentTotal;
        newTotal = currentTotal + 1;
        newAverage = (sum + rating) / newTotal;
        print("   - Adding new rating: $rating");
      }

      // Update venue's aggregated rating
      batch.update(venueRef, {
        'averageRating': newAverage,
        'totalRatings': newTotal,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 4. Commit the batch
      await batch.commit();
      print("   - ✅ Batch committed successfully");
      print("   - New average: ${newAverage.toStringAsFixed(2)} ($newTotal ratings)");

      // 5. Verify the save
      final docSnapshot = await ratingRef.get();
      if (docSnapshot.exists) {
        print("   - ✅ VERIFIED: Rating saved successfully");
        return true;
      } else {
        print("   - 🔥 VERIFICATION FAILED: Document doesn't exist after save");
        return false;
      }

    } catch (e) {
      print("❌ DEBUG [Repository]: Error during save: $e");
      return false;
    }
  }

  /// Helper to convert Firestore document to StoredLocation
  StoredLocation _venueFromFirestore(
      DocumentSnapshot doc,
      {double? rating, String? comment}
      ) {
    final data = doc.data() as Map<String, dynamic>;
    final geoPoint = data['coordinates'] as GeoPoint;

    // Convert GeoPoint to LatLng
    data['latitude'] = geoPoint.latitude;
    data['longitude'] = geoPoint.longitude;

    // Create the venue object from JSON
    final venue = StoredLocation.fromJson(data);

    // Return with user-specific rating data merged in
    return venue.copyWith(
      isPublic: true,
      rating: rating ?? venue.rating,      // User's personal rating
      comment: comment ?? venue.comment,   // User's personal comment
    );
  }

  // Helper methods
  bool _isWithinRadius(double lat1, double lon1, double lat2, double lon2, double radiusMiles) {
    const double earthRadius = 3959; // miles
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
            sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    final distance = earthRadius * c;
    return distance <= radiusMiles;
  }

  double _toRadians(double degrees) => degrees * pi / 180;
}