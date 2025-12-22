import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class VenueDiscoveryService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _googleApiKey = 'AIzaSyCjyQbNWIXnY5L9AHXhZrhzqsDwYAZPKVo'; // This key should be secured

  // --- START: NEW DELETION METHOD ---

  /// Deletes all venues from the 'venues' collection that were created by the system.
  /// This is useful for cleaning up data added by the syncLiveMusicVenues script.
  Future<void> deleteSystemVenues() async {
    print("🔥 Starting deletion of 'system' created venues...");

    try {
      // 1. Create a query to find all documents where 'createdBy' is 'system'.
      final querySnapshot = await _db
          .collection('venues')
          .where('createdBy', isEqualTo: 'system')
          .get();

      final int documentsToDelete = querySnapshot.docs.length;

      if (documentsToDelete == 0) {
        print("✅ No venues with 'createdBy: system' found. Nothing to delete.");
        return;
      }

      print("Found $documentsToDelete system-created venues to delete.");

      // 2. Firestore limits batch writes to 500 operations.
      // We process the deletion in chunks to handle more than 500 documents safely.
      var i = 0;
      WriteBatch batch = _db.batch();

      for (var doc in querySnapshot.docs) {
        batch.delete(doc.reference);
        i++;
        // If we've hit the 500-operation limit, commit the batch and start a new one.
        if (i == 500) {
          await batch.commit();
          print("...committed a batch of 500 deletions.");
          batch = _db.batch();
          i = 0;
        }
      }

      // 3. Commit any remaining operations in the last batch.
      if (i > 0) {
        await batch.commit();
        print("...committed the final batch of $i deletions.");
      }

      print("✅ Successfully deleted $documentsToDelete system-created venues.");

    } catch (e) {
      print("❌ An error occurred during deletion: $e");
    }
  }

  // --- END: NEW DELETION METHOD ---


  Future<void> syncLiveMusicVenues(String region) async {
    // ... your existing syncLiveMusicVenues method is here ...
    // Remember to update this method to include the 'coordinates' field
    // before you run it again.

    final String query = Uri.encodeComponent("live music venues in $region");
    final String url = 'https://maps.googleapis.com/maps/api/place/textsearch/json'
        '?query=$query'
        '&key=$_googleApiKey';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] != 'OK' && data['status'] != 'ZERO_RESULTS') {
          print("Google API Error Status: ${data['status']}");
          return;
        }

        List venues = data['results'] ?? [];
        print("Found ${venues.length} potential venues.");

        WriteBatch batch = _db.batch();
        int newVenuesCount = 0;

        for (var venue in venues) {
          String placeId = venue['place_id'];
          DocumentReference docRef = _db.collection('venues').doc(placeId);
          DocumentSnapshot doc = await docRef.get();

          if (!doc.exists) {
            // This is the corrected data structure
            final location = venue['geometry']['location'];
            final lat = location['lat'];
            final lng = location['lng'];

            batch.set(docRef, {
              'placeId': placeId,
              'name': venue['name'],
              'address': venue['formatted_address'],
              'coordinates': GeoPoint(lat, lng), // ✅ The fix is here
              'createdBy': 'system',
              'averageRating': 0,
              'totalRatings': 0,
              'jamSessions': [],
              'createdAt': FieldValue.serverTimestamp(),
            });
            newVenuesCount++;
            print("Marked for addition: ${venue['name']}");
          }
        }

        if (newVenuesCount > 0) {
          await batch.commit();
          print("Successfully added $newVenuesCount new venues.");
        } else {
          print("No new venues to add.");
        }
      }
    } catch (e) {
      print("Error during sync: $e");
    }
  }
}
