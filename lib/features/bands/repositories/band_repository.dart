// lib/features/bands/repositories/band_repository.dart
//
// Band/Project Expansion v3.0.0 — Sprint Task 3
//
// CRUD against the top-level 'bands' Firestore collection. Mirrors the
// lazy-init + try/catch/log pattern used in VenueRepository.
//
// Member add/remove are implemented as read-modify-write on the whole
// `members` array rather than FieldValue.arrayUnion/arrayRemove — arrayRemove
// requires an exact map match, and BandMember maps contain a Timestamp
// (invitedAt) that makes exact-match removal fragile. Reading the doc,
// mutating the Dart list, and writing members + memberEmails +
// memberNetworkIds back together also guarantees the two-array sync rule
// (spec 2.3) can never drift, since all three are written in one call.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:the_money_gigs/core/utils/logger.dart';
import '../models/band_model.dart';

class BandRepository {
  FirebaseFirestore? _firestore;

  FirebaseFirestore get _firestoreInstance {
    if (_firestore != null) return _firestore!;
    if (Firebase.apps.isEmpty) {
      throw Exception(
          'Firebase not initialized. BandRepository requires network mode.');
    }
    _firestore = FirebaseFirestore.instance;
    return _firestore!;
  }

  CollectionReference<Map<String, dynamic>> get _bandsCollection =>
      _firestoreInstance.collection('bands');

  // ── Create ────────────────────────────────────────────────────────────────

  /// Creates a new band led by [leaderId]. Returns the saved BandProject
  /// (with its real Firestore-assigned bandId) or null on failure.
  Future<BandProject?> createBand({
    required String name,
    required String leaderId,
    List<BandMember> initialMembers = const [],
  }) async {
    try {
      final docRef = _bandsCollection.doc(); // pre-generate the ID
      final band = BandProject(
        bandId: docRef.id,
        name: name,
        leaderId: leaderId,
        members: initialMembers,
      );

      await docRef.set(band.toFirestore());
      log('✅ Band created: ${band.name} (${band.bandId}) led by $leaderId');
      return band;
    } catch (e) {
      log('❌ Error creating band "$name": $e');
      return null;
    }
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Bands [userId] leads AND bands they belong to as a member, merged into
  /// one deduped list. Two separate queries per spec section 4.1 — a single
  /// query can't express "leaderId == X OR memberNetworkIds contains X".
  Future<List<BandProject>> getBandsForUser(String userId) async {
    try {
      final results = await Future.wait([
        _bandsCollection.where('leaderId', isEqualTo: userId).get(),
        _bandsCollection
            .where('memberNetworkIds', arrayContains: userId)
            .get(),
      ]);

      final ledDocs = results[0].docs;
      final memberDocs = results[1].docs;

      // Dedupe by bandId in case a leader is somehow also listed in their
      // own members[] (e.g. added themselves as a player).
      final byId = <String, BandProject>{};
      for (final doc in [...ledDocs, ...memberDocs]) {
        final band = BandProject.fromFirestore(doc);
        byId[band.bandId] = band;
      }
      return byId.values.toList();
    } catch (e) {
      log('❌ Error fetching bands for user $userId: $e');
      return [];
    }
  }

  /// Single-band fetch — not in the original task list, but Band Detail
  /// (Task 6) and Notify Band (Task 8) both need to load one band by ID
  /// without re-running the two-query merge above.
  Future<BandProject?> getBand(String bandId) async {
    try {
      final doc = await _bandsCollection.doc(bandId).get();
      if (!doc.exists) {
        log('⚠️ Band not found: $bandId');
        return null;
      }
      return BandProject.fromFirestore(doc);
    } catch (e) {
      log('❌ Error fetching band $bandId: $e');
      return null;
    }
  }

  // ── Update ────────────────────────────────────────────────────────────────

  Future<bool> renameBand({
    required String bandId,
    required String newName,
  }) async {
    try {
      await _bandsCollection.doc(bandId).update({
        'name': newName,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
      log('✅ Band $bandId renamed to "$newName"');
      return true;
    } catch (e) {
      log('❌ Error renaming band $bandId: $e');
      return false;
    }
  }

  /// Adds [member] to the band. If a member with the same email already
  /// exists, replaces that entry instead of duplicating it.
  Future<bool> addMember({
    required String bandId,
    required BandMember member,
  }) async {
    try {
      final band = await getBand(bandId);
      if (band == null) return false;

      final updatedMembers = [
        ...band.members.where((m) =>
        m.email.toLowerCase() != member.email.toLowerCase()),
        member,
      ];

      await _writeMembers(bandId: bandId, members: updatedMembers);
      log('✅ Added member ${member.email} to band $bandId');
      return true;
    } catch (e) {
      log('❌ Error adding member to band $bandId: $e');
      return false;
    }
  }

  /// Removes the member matching [memberLocalId] from the band.
  Future<bool> removeMember({
    required String bandId,
    required String memberLocalId,
  }) async {
    try {
      final band = await getBand(bandId);
      if (band == null) return false;

      final updatedMembers =
      band.members.where((m) => m.localId != memberLocalId).toList();

      await _writeMembers(bandId: bandId, members: updatedMembers);
      log('✅ Removed member $memberLocalId from band $bandId');
      return true;
    } catch (e) {
      log('❌ Error removing member from band $bandId: $e');
      return false;
    }
  }

  /// Writes members[] plus the derived memberEmails / memberNetworkIds
  /// arrays together, so the two-array sync rule (spec 2.3) is enforced by
  /// construction — there's no code path that updates one without the other.
  Future<void> _writeMembers({
    required String bandId,
    required List<BandMember> members,
  }) async {
    final memberEmails = members.map((m) => m.email).toList();
    final memberNetworkIds =
    members.map((m) => m.networkMemberId).whereType<String>().toList();

    await _bandsCollection.doc(bandId).update({
      'members': members.map((m) => m.toMap()).toList(),
      'memberEmails': memberEmails,
      'memberNetworkIds': memberNetworkIds,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  // ── Network status check (spec section 8) ───────────────────────────────
  //
  // Lightweight read used when a band leader enters a member's email during
  // Create Band / add-member (Task 5), on blur/submit of the email field.
  // Lives here rather than in Task 5's UI code because it's a raw Firestore
  // read like everything else in this file.

  /// Returns the matching NetworkMember doc ID (== networkMemberId) if
  /// [email] belongs to an existing app user, or null if not found.
  Future<String?> checkNetworkStatusForEmail(String email) async {
    try {
      final snapshot = await _firestoreInstance
          .collection('networkMembers')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;
      return snapshot.docs.first.id; // doc ID == userId, per NetworkMember
    } catch (e) {
      log('❌ Error checking network status for $email: $e');
      return null;
    }
  }

  /// Distinguishes spec section 8's third UI state ('Already in your
  /// network') from a fresh match: true if [email] already sits in a band
  /// this leader created, anywhere. Single query — Firestore allows one
  /// equality clause plus one arrayContains clause together.
  Future<bool> isEmailInLeadersBands({
    required String leaderId,
    required String email,
  }) async {
    try {
      final snapshot = await _bandsCollection
          .where('leaderId', isEqualTo: leaderId)
          .where('memberEmails', arrayContains: email)
          .limit(1)
          .get();
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      log("❌ Error checking leader's bands for $email: $e");
      return false;
    }
  }

  // ── Gig notifications (spec section 7.1) — Sprint Task 8 ────────────────
  //
  // This writes the notification document only. Sending the actual emails
  // to members is a separate Firebase Cloud Function (Task 9) that triggers
  // off this write server-side — nothing in the Flutter app calls an email
  // API directly.

  /// Writes a gig-notification doc to bands/{bandId}/gigNotifications.
  /// Takes primitive fields rather than a Gig object so this repository
  /// doesn't need to depend on the gigs feature's model.
  Future<bool> notifyBandOfGig({
    required String bandId,
    required String gigId,
    required String venueName,
    required DateTime dateTime,
    required double pay,
    required String address,
  }) async {
    try {
      await _bandsCollection.doc(bandId).collection('gigNotifications').add({
        'gigId': gigId,
        'venueName': venueName,
        'dateTime': Timestamp.fromDate(dateTime),
        'pay': pay,
        'address': address,
        'sentAt': FieldValue.serverTimestamp(),
      });
      log('✅ Gig notification written: band $bandId, gig $gigId');
      return true;
    } catch (e) {
      log('❌ Error writing gig notification for band $bandId: $e');
      return false;
    }
  }
}
