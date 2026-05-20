// lib/features/map_venues/repositories/venue_repository.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/venue_contact.dart';
import '../models/venue_model.dart';

class VenueRepository {
  FirebaseFirestore? _firestore;

  FirebaseFirestore get _firestoreInstance {
    if (_firestore != null) return _firestore!;
    if (Firebase.apps.isEmpty) {
      throw Exception(
          'Firebase not initialized. VenueRepository requires network mode.');
    }
    _firestore = FirebaseFirestore.instance;
    return _firestore!;
  }

  // ── Public venues ─────────────────────────────────────────────────────────

  Future<List<String>> getAllPublicVenueIds() async {
    try {
      final snapshot = await _firestoreInstance.collection('venues').get();
      return snapshot.docs.map((doc) => doc.id).toList();
    } catch (e) {
      print('Error fetching public venue IDs: $e');
      return [];
    }
  }

  Future<List<StoredLocation>> getAllPublicVenues(String userId) async {
    try {
      final venuesSnapshot =
      await _firestoreInstance.collection('venues').get();
      if (venuesSnapshot.docs.isEmpty) return [];

      final ratingsSnapshot = await _firestoreInstance
          .collection('venueRatings')
          .where('userId', isEqualTo: userId)
          .get();

      final userRatingsMap = {
        for (var doc in ratingsSnapshot.docs)
          doc.data()['placeId'] as String: doc.data()
      };

      return venuesSnapshot.docs.map((venueDoc) {
        final venueData = venueDoc.data();
        final placeId = venueData['placeId'] as String;
        final ratingData = userRatingsMap[placeId];
        return _venueFromFirestore(venueDoc,
            rating: ratingData?['rating'] as double?,
            comment: ratingData?['comment'] as String?);
      }).toList();
    } catch (e) {
      print('❌ Error fetching public venues: $e');
      return [];
    }
  }

  // ── Venue core ────────────────────────────────────────────────────────────

  Future<void> saveVenue(StoredLocation venue, String userId) async {
    final venueRef =
    _firestoreInstance.collection('venues').doc(venue.placeId);

    final Map<String, dynamic> venueData = {
      'name': venue.name,
      'address': venue.address,
      'coordinates':
      GeoPoint(venue.coordinates.latitude, venue.coordinates.longitude),
      'placeId': venue.placeId,
      'jamSessions': venue.jamSessions.map((js) => js.toJson()).toList(),
    };

    final doc = await venueRef.get();
    if (doc.exists) {
      await venueRef.update({
        'jamSessions': venueData['jamSessions'],
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      venueData['createdAt'] = FieldValue.serverTimestamp();
      venueData['createdBy'] = userId;
      venueData['updatedAt'] = FieldValue.serverTimestamp();
      venueData['averageRating'] = 0.0;
      venueData['totalRatings'] = 0;
      await venueRef.set(venueData);
    }
  }

  // ── Contact ───────────────────────────────────────────────────────────────

  /// Saves the venue contact and optional booking info to Firestore.
  ///
  /// Firebase schema:
  ///   venues/{placeId}.contact = { name, phone, email, preferredMethod, notes,
  ///     isSharedWithNetwork, sharedBy, lastConfirmed (serverTimestamp),
  ///     lastConfirmedBy, confirmationCount }
  ///
  ///   venues/{placeId}.bookingInfo = { leadsOutWeeks, dealType, notes }
  ///     — present only when isSharedWithNetwork == true
  ///
  /// Security rule: only the user whose userId matches sharedBy may flip
  /// isSharedWithNetwork back to false.
  Future<void> saveVenueContact({
    required String placeId,
    required String userId,
    required VenueContact contact,
    BookingInfo? bookingInfo,
  }) async {
    final venueRef = _firestoreInstance.collection('venues').doc(placeId);

    // Preserve original sharedBy; stamp with userId on first share.
    String? resolvedSharedBy;
    if (contact.isSharedWithNetwork) {
      final existingDoc = await venueRef.get();
      final existingSharedBy =
      (existingDoc.data()?['contact']?['sharedBy']) as String?;
      resolvedSharedBy = existingSharedBy ?? userId;
    }

    final contactData = <String, dynamic>{
      'name': contact.name,
      'phone': contact.phone,
      'email': contact.email,
      'preferredMethod': contact.preferredMethod,
      'notes': contact.notes,
      'isSharedWithNetwork': contact.isSharedWithNetwork,
      'sharedBy': resolvedSharedBy,
      'lastConfirmed': FieldValue.serverTimestamp(),
      'lastConfirmedBy': userId,
      'confirmationCount': contact.confirmationCount,
    };

    final updates = <String, dynamic>{
      'contact': contactData,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (bookingInfo != null && contact.isSharedWithNetwork) {
      updates['bookingInfo'] = bookingInfo.toJson();
    } else if (!contact.isSharedWithNetwork) {
      updates['bookingInfo'] = FieldValue.delete();
    }

    await venueRef.set(updates, SetOptions(merge: true));
    print(
        '✅ Saved contact for $placeId (shared: ${contact.isSharedWithNetwork})');
  }

  // ── Contact confirmations ─────────────────────────────────────────────────
  //
  // Firestore layout (mirrors the tag-voting subcollection pattern):
  //
  //   venues/{placeId}/contactConfirmations/{userId} = { confirmedAt: timestamp }
  //   venues/{placeId}.contact.confirmationCount  (aggregated integer)
  //
  // The subcollection lets us check whether a specific user has confirmed
  // without loading all confirmer IDs into the contact document.

  /// Returns `{ count: int, userConfirmed: bool }` for the given venue + user.
  Future<Map<String, dynamic>> getContactConfirmationState({
    required String placeId,
    required String userId,
  }) async {
    try {
      final venueRef = _firestoreInstance.collection('venues').doc(placeId);
      final confRef =
      venueRef.collection('contactConfirmations').doc(userId);

      final results = await Future.wait([
        venueRef.get(),
        confRef.get(),
      ]);

      final venueDoc = results[0] as DocumentSnapshot;
      final userConfDoc = results[1] as DocumentSnapshot;

      final venueData = venueDoc.data() as Map<String, dynamic>?;
      final count =
          (venueData?['contact']?['confirmationCount'] as int?) ?? 0;

      return {
        'count': count,
        'userConfirmed': userConfDoc.exists,
      };
    } catch (e) {
      print('❌ Error fetching confirmation state: $e');
      return {'count': 0, 'userConfirmed': false};
    }
  }

  /// Adds the current user's confirmation. Idempotent — safe to call twice.
  Future<void> confirmVenueContact({
    required String placeId,
    required String userId,
  }) async {
    final venueRef = _firestoreInstance.collection('venues').doc(placeId);
    final confRef = venueRef.collection('contactConfirmations').doc(userId);

    await _firestoreInstance.runTransaction((tx) async {
      final confDoc = await tx.get(confRef);

      if (confDoc.exists) {
        // Already confirmed — no-op (idempotent)
        return;
      }

      // Write the user's confirmation record
      tx.set(confRef, {'confirmedAt': FieldValue.serverTimestamp()});

      // Increment the aggregate count and refresh lastConfirmed
      tx.update(venueRef, {
        'contact.confirmationCount': FieldValue.increment(1),
        'contact.lastConfirmed': FieldValue.serverTimestamp(),
        'contact.lastConfirmedBy': userId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    print('✅ Contact confirmed for $placeId by $userId');
  }

  /// Removes the current user's confirmation (undo / toggle off).
  Future<void> removeContactConfirmation({
    required String placeId,
    required String userId,
  }) async {
    final venueRef = _firestoreInstance.collection('venues').doc(placeId);
    final confRef = venueRef.collection('contactConfirmations').doc(userId);

    await _firestoreInstance.runTransaction((tx) async {
      final confDoc = await tx.get(confRef);

      if (!confDoc.exists) return; // Nothing to remove

      tx.delete(confRef);

      // Decrement — floor at 0 to guard against any data inconsistency
      final venueDoc = await tx.get(venueRef);
      final existingData = venueDoc.data();
      final currentCount =
          (existingData?['contact']?['confirmationCount'] as int?) ?? 0;

      tx.update(venueRef, {
        'contact.confirmationCount':
        currentCount > 0 ? FieldValue.increment(-1) : 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    print('✅ Contact confirmation removed for $placeId by $userId');
  }

  // ── Ratings ───────────────────────────────────────────────────────────────

  Future<bool> saveVenueRating({
    required String userId,
    required String placeId,
    required double rating,
    String? comment,
  }) async {
    final docId = '${placeId}_$userId';

    try {
      final batch = _firestoreInstance.batch();

      final ratingRef =
      _firestoreInstance.collection('venueRatings').doc(docId);
      final existingRatingDoc = await ratingRef.get();
      final oldRating = existingRatingDoc.exists
          ? (existingRatingDoc.data()!['rating'] as num).toDouble()
          : null;

      batch.set(ratingRef, {
        'placeId': placeId,
        'userId': userId,
        'rating': rating,
        'comment': comment,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final venueRef = _firestoreInstance.collection('venues').doc(placeId);
      final venueDoc = await venueRef.get();

      if (!venueDoc.exists) {
        print('⚠️ Cannot rate non-existent venue: $placeId');
        return false;
      }

      final venueData = venueDoc.data()!;
      var currentAverage =
          (venueData['averageRating'] as num?)?.toDouble() ?? 0.0;
      var currentTotal = venueData['totalRatings'] as int? ?? 0;

      if (currentAverage.isNaN) {
        currentAverage = 0.0;
        currentTotal = 0;
      }

      double newAverage;
      int newTotal;

      if (oldRating != null && currentTotal > 0) {
        newAverage =
            (currentAverage * currentTotal - oldRating + rating) / currentTotal;
        newTotal = currentTotal;
      } else {
        newTotal = currentTotal + 1;
        newAverage = (currentAverage * currentTotal + rating) / newTotal;
      }

      batch.update(venueRef, {
        'averageRating': newAverage,
        'totalRatings': newTotal,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      final verified = await ratingRef.get();
      return verified.exists;
    } catch (e) {
      print('❌ Error saving rating: $e');
      return false;
    }
  }

  // ── Tag voting ────────────────────────────────────────────────────────────

  Future<bool> voteForTag({
    required String placeId,
    required String userId,
    required String tagName,
    required bool isGenre,
  }) async {
    try {
      final tagType = isGenre ? 'genres' : 'instruments';
      final tagRef = _firestoreInstance
          .collection('venues')
          .doc(placeId)
          .collection('tags')
          .doc(tagType)
          .collection('items')
          .doc(tagName);

      await _firestoreInstance.runTransaction((tx) async {
        final tagDoc = await tx.get(tagRef);
        if (tagDoc.exists) {
          final voters =
          List<String>.from(tagDoc.data()?['voters'] ?? []);
          if (voters.contains(userId)) return;
          voters.add(userId);
          tx.update(tagRef, {
            'count': FieldValue.increment(1),
            'voters': voters,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          tx.set(tagRef, {
            'count': 1,
            'voters': [userId],
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });

      return true;
    } catch (e) {
      print('❌ Error voting for tag: $e');
      return false;
    }
  }

  Future<bool> removeVoteForTag({
    required String placeId,
    required String userId,
    required String tagName,
    required bool isGenre,
  }) async {
    try {
      final tagType = isGenre ? 'genres' : 'instruments';
      final tagRef = _firestoreInstance
          .collection('venues')
          .doc(placeId)
          .collection('tags')
          .doc(tagType)
          .collection('items')
          .doc(tagName);

      await _firestoreInstance.runTransaction((tx) async {
        final tagDoc = await tx.get(tagRef);
        if (!tagDoc.exists) return;

        final voters =
        List<String>.from(tagDoc.data()?['voters'] ?? []);
        if (!voters.contains(userId)) return;
        voters.remove(userId);

        if (voters.isEmpty) {
          tx.delete(tagRef);
        } else {
          tx.update(tagRef, {
            'count': FieldValue.increment(-1),
            'voters': voters,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });

      return true;
    } catch (e) {
      print('❌ Error removing tag vote: $e');
      return false;
    }
  }

  Future<Map<String, Map<String, dynamic>>> getVenueTags({
    required String placeId,
    required String userId,
    required bool isGenre,
  }) async {
    try {
      final tagType = isGenre ? 'genres' : 'instruments';
      final snapshot = await _firestoreInstance
          .collection('venues')
          .doc(placeId)
          .collection('tags')
          .doc(tagType)
          .collection('items')
          .get();

      final Map<String, Map<String, dynamic>> tags = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final voters = List<String>.from(data['voters'] ?? []);
        tags[doc.id] = {
          'count': data['count'] as int,
          'userVoted': voters.contains(userId),
        };
      }
      return tags;
    } catch (e) {
      print('❌ Error fetching tags: $e');
      return {};
    }
  }

  Future<void> syncLocalTagsToFirebase({
    required String placeId,
    required String userId,
    required List<String> genreTags,
    required List<String> instrumentTags,
    List<String> actFormatTags = const [],  // ADD THIS
  }) async {
    try {
      for (final genre in genreTags) {
        await voteForTagByCategory(
            placeId: placeId, userId: userId, tagName: genre, tagCategory: 'genres');
      }
      for (final instrument in instrumentTags) {
        await voteForTagByCategory(
            placeId: placeId, userId: userId, tagName: instrument, tagCategory: 'instruments');
      }
      for (final format in actFormatTags) {
        await voteForTagByCategory(
            placeId: placeId, userId: userId, tagName: format, tagCategory: 'actFormats');
      }
    } catch (e) {
      print('❌ Error syncing tags: $e');
    }
  }

  // ── Category-based tag methods (paymentMethods, taxArrangements, etc.) ───
  // These mirror voteForTag / removeVoteForTag / getVenueTags but accept a
  // free-form tagCategory string so new tag types can be added without
  // touching the repository again.

  Future<bool> voteForTagByCategory({
    required String placeId,
    required String userId,
    required String tagName,
    required String tagCategory,
  }) async {
    try {
      final tagRef = _firestoreInstance
          .collection('venues')
          .doc(placeId)
          .collection('tags')
          .doc(tagCategory)
          .collection('items')
          .doc(tagName);

      await _firestoreInstance.runTransaction((tx) async {
        final tagDoc = await tx.get(tagRef);
        if (tagDoc.exists) {
          final voters = List<String>.from(tagDoc.data()?['voters'] ?? []);
          if (voters.contains(userId)) return;
          voters.add(userId);
          tx.update(tagRef, {
            'count': FieldValue.increment(1),
            'voters': voters,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          tx.set(tagRef, {
            'count': 1,
            'voters': [userId],
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
      return true;
    } catch (e) {
      print('❌ Error voting for tag ($tagCategory): $e');
      return false;
    }
  }

  Future<bool> removeVoteForTagByCategory({
    required String placeId,
    required String userId,
    required String tagName,
    required String tagCategory,
  }) async {
    try {
      final tagRef = _firestoreInstance
          .collection('venues')
          .doc(placeId)
          .collection('tags')
          .doc(tagCategory)
          .collection('items')
          .doc(tagName);

      await _firestoreInstance.runTransaction((tx) async {
        final tagDoc = await tx.get(tagRef);
        if (!tagDoc.exists) return;
        final voters = List<String>.from(tagDoc.data()?['voters'] ?? []);
        if (!voters.contains(userId)) return;
        voters.remove(userId);
        if (voters.isEmpty) {
          tx.delete(tagRef);
        } else {
          tx.update(tagRef, {
            'count': FieldValue.increment(-1),
            'voters': voters,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
      return true;
    } catch (e) {
      print('❌ Error removing tag vote ($tagCategory): $e');
      return false;
    }
  }

  Future<Map<String, Map<String, dynamic>>> getVenueTagsByCategory({
    required String placeId,
    required String userId,
    required String tagCategory,
  }) async {
    try {
      final snapshot = await _firestoreInstance
          .collection('venues')
          .doc(placeId)
          .collection('tags')
          .doc(tagCategory)
          .collection('items')
          .get();

      final Map<String, Map<String, dynamic>> tags = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final voters = List<String>.from(data['voters'] ?? []);
        tags[doc.id] = {
          'count': data['count'] as int,
          'userVoted': voters.contains(userId),
        };
      }
      return tags;
    } catch (e) {
      print('❌ Error fetching tags ($tagCategory): $e');
      return {};
    }
  }

  // ── Comments ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getRecentComments({
    required String placeId,
    int limit = 3,
  }) async {
    try {
      final snapshot = await _firestoreInstance
          .collection('venueRatings')
          .where('placeId', isEqualTo: placeId)
          .get();

      final withText = snapshot.docs
          .where((doc) {
        final c = doc.data()['comment'];
        return c != null && c.toString().trim().isNotEmpty;
      })
          .map((doc) => {
        'comment': doc.data()['comment'] as String,
        'rating': (doc.data()['rating'] as num).toDouble(),
        'updatedAt': doc.data()['updatedAt'] as Timestamp?,
      })
          .toList();

      withText.sort((a, b) {
        final aTime = a['updatedAt'] as Timestamp?;
        final bTime = b['updatedAt'] as Timestamp?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      return withText.take(limit).toList();
    } catch (e) {
      print('❌ Error fetching comments: $e');
      return [];
    }
  }

  // ── Firestore helpers ─────────────────────────────────────────────────────

  StoredLocation _venueFromFirestore(DocumentSnapshot doc,
      {double? rating, String? comment}) {
    final data = doc.data() as Map<String, dynamic>;
    final geoPoint = data['coordinates'] as GeoPoint;
    data['latitude'] = geoPoint.latitude;
    data['longitude'] = geoPoint.longitude;
    final venue = StoredLocation.fromJson(data);
    return venue.copyWith(
      isPublic: true,
      rating: rating ?? venue.rating,
      comment: comment ?? venue.comment,
    );
  }

  bool _isWithinRadius(
      double lat1, double lon1, double lat2, double lon2, double radiusMiles) {
    const double earthRadius = 3959;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a)) <= radiusMiles;
  }

  double _toRadians(double degrees) => degrees * pi / 180;
}