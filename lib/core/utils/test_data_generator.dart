import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

class TestDataGenerator {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Generate fake ratings for ALL venues in the database
  Future<void> generateRatingsForAllVenues({
    int ratingsPerVenue = 8,
  }) async {
    print('🧪 Starting test data generation...');

    // Get all venue IDs
    final venuesSnapshot = await _firestore.collection('venues').get();

    if (venuesSnapshot.docs.isEmpty) {
      print('❌ No venues found in database');
      return;
    }

    print('📍 Found ${venuesSnapshot.docs.length} venues');

    // Generate ratings for each venue
    for (var venueDoc in venuesSnapshot.docs) {
      final placeId = venueDoc.id;
      final venueName = venueDoc.data()['name'] as String? ?? 'Unknown';

      print('\n🎯 Generating $ratingsPerVenue ratings for: $venueName');

      await generateFakeRatings(
        placeId: placeId,
        count: ratingsPerVenue,
      );
    }

    print('\n🎉 Complete! Generated ratings for ${venuesSnapshot.docs.length} venues');
  }

  /// Generate fake ratings for a specific venue
  /// Returns the list of fake userIds created (so you can delete them later)
  Future<List<String>> generateFakeRatings({
    required String placeId,
    required int count,
  }) async {
    final random = Random();
    final fakeUserIds = <String>[];

    final comments = [
      'Great venue with excellent sound system!',
      'Load-in was easy, staff was friendly.',
      'Good crowd, decent pay, would play here again.',
      'Parking was a bit tricky but overall great experience.',
      'Sound guy really knew his stuff!',
      'Small stage but good acoustics.',
      'Tips were good, audience was engaged.',
      'Great local spot, very supportive crowd.',
      'Well-organized, professional staff.',
      'Nice atmosphere, good food too!',
      'Easy load-in through the back entrance.',
      'Manager was very professional and punctual with payment.',
      'Decent green room, clean bathrooms.',
      'Crowd was a bit quiet but attentive.',
      'Great beer selection, good vibe.',
      'Perfect for acoustic sets, intimate setting.',
      'Had to bring my own PA, but otherwise solid.',
      'Regular crowd, they know their music.',
      'Good mix of ages in the audience.',
      'Bar staff was helpful and accommodating.',
    ];

    for (int i = 0; i < count; i++) {
      // Create fake userId
      final fakeUserId = 'test_user_${DateTime.now().millisecondsSinceEpoch}_${random.nextInt(10000)}';
      fakeUserIds.add(fakeUserId);

      // Random rating between 3.0 and 5.0 (realistic distribution, slightly positive)
      final rating = 3.0 + (random.nextInt(5) * 0.5);

      // 70% chance of having a comment
      final comment = random.nextDouble() > 0.3
          ? comments[random.nextInt(comments.length)]
          : null;

      // Save to Firestore
      final docId = '${placeId}_$fakeUserId';
      await _firestore.collection('venueRatings').doc(docId).set({
        'placeId': placeId,
        'userId': fakeUserId,
        'rating': rating,
        'comment': comment,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('   ✅ Rating ${i + 1}/$count: ${rating.toStringAsFixed(1)} stars');

      // Small delay to avoid rate limiting
      await Future.delayed(Duration(milliseconds: 50));
    }

    // Now update the venue's aggregate rating
    await _updateVenueAggregate(placeId);

    return fakeUserIds;
  }

  /// Recalculate venue's aggregate rating from all ratings
  Future<void> _updateVenueAggregate(String placeId) async {
    final ratingsSnapshot = await _firestore
        .collection('venueRatings')
        .where('placeId', isEqualTo: placeId)
        .get();

    if (ratingsSnapshot.docs.isEmpty) {
      // Reset to 0 if no ratings
      await _firestore.collection('venues').doc(placeId).update({
        'averageRating': 0.0,
        'totalRatings': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    double sum = 0;
    int count = 0;

    for (var doc in ratingsSnapshot.docs) {
      final rating = (doc.data()['rating'] as num).toDouble();
      sum += rating;
      count++;
    }

    final average = sum / count;

    await _firestore.collection('venues').doc(placeId).update({
      'averageRating': average,
      'totalRatings': count,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    print('   📊 Updated aggregate: ${average.toStringAsFixed(2)} ($count ratings)');
  }

  /// Delete ALL fake ratings from the entire database
  Future<void> deleteAllFakeRatings() async {
    print('🗑️ Deleting ALL fake ratings...');

    // Get all ratings
    final ratingsSnapshot = await _firestore
        .collection('venueRatings')
        .get();

    int deleted = 0;
    final affectedVenues = <String>{};

    for (var doc in ratingsSnapshot.docs) {
      final userId = doc.data()['userId'] as String;
      if (userId.startsWith('test_user_')) {
        final placeId = doc.data()['placeId'] as String;
        affectedVenues.add(placeId);
        await doc.reference.delete();
        deleted++;
      }
    }

    print('✅ Deleted $deleted fake ratings from ${affectedVenues.length} venues');

    // Recalculate aggregates for all affected venues
    print('📊 Recalculating aggregates...');
    for (var placeId in affectedVenues) {
      await _updateVenueAggregate(placeId);
    }

    print('🎉 Cleanup complete!');
  }

  /// Get statistics about test data
  Future<Map<String, dynamic>> getTestDataStats() async {
    final ratingsSnapshot = await _firestore
        .collection('venueRatings')
        .get();

    int totalRatings = ratingsSnapshot.docs.length;
    int fakeRatings = 0;

    for (var doc in ratingsSnapshot.docs) {
      final userId = doc.data()['userId'] as String;
      if (userId.startsWith('test_user_')) {
        fakeRatings++;
      }
    }

    return {
      'totalRatings': totalRatings,
      'fakeRatings': fakeRatings,
      'realRatings': totalRatings - fakeRatings,
    };
  }
}