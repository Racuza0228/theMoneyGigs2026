// lib/features/gigs/repositories/jam_attendance_repository.dart
//
// Network-edition companion to the local Going/Interested/Not Going jam
// attendance feature (see GigsPage._setJamAttendance / _removeJamInstance
// in gigs.dart). When the user is connected to the network AND signed in,
// their attendance choice on a specific jam occurrence is mirrored here so
// everyone else who has that venue/session can see how many people are
// going/interested before they show up. Standalone (not connected) users
// never touch this file at all — their local 'gigs_list' SharedPreferences
// record stays the sole source of truth for their own device, same as
// today.
//
// Mirrors BandRepository's lazy-init + try/catch/log pattern (see
// features/bands/repositories/band_repository.dart) for consistency with
// the rest of the network-edition code.
//
// ── Data model (rewritten 8/26/26 — see FIX note below) ────────────────────
//
//   jamAttendance/{occurrenceId}/attendees/{userId}
//     status:     'going' | 'interested'
//     updatedAt:  Timestamp (server)
//
// [occurrenceId] is the SAME id the local Gig record for that occurrence
// already uses ('jam_{placeId}_{sessionId}_{yyyyMMdd}') — no separate ID
// scheme, so a given occurrence's local record and its network doc are
// always a one-to-one lookup by the same string. [userId] as the doc ID
// (rather than a field inside a shared map) means Firestore rules can
// enforce "you can only write your own vote" with a plain doc-ID match —
// see the rule suggested in the class doc below.
//
// Going/Interested counts are computed by reading this subcollection and
// counting client-side (see getCounts) rather than maintaining a separate
// aggregate counter field. Deliberate choice, not just "simplest for now":
//
// FIX (8/26/26): the original version stored one doc per OCCURRENCE with
// an embedded attendees map plus denormalized goingCount/interestedCount
// fields, updated via a signed delta — decrement whatever the user's
// previous status was, increment the new one. That broke the first time
// it hit a gig whose local attendanceStatus predated this feature (e.g. a
// GO JAM add, which has always set attendanceStatus: 'going' locally) but
// had never actually been written to Firestore: tapping INTERESTED read
// oldStatus == 'going' and decremented a goingCount that was never
// incremented server-side to begin with, landing on Going (-1) /
// Interested (1). Any local/server drift — a reinstall, an earlier failed
// write, this exact stale-local-data case — hits the same failure mode,
// because the counter's correctness depends on every prior write having
// landed and been read back correctly. There is no way to make that
// self-healing without a server-side reconciliation job (a Cloud Function
// this project doesn't have set up).
//
// The per-user-document model removes the whole failure class instead of
// mitigating it: GOING/INTERESTED is an idempotent set() of one document,
// NOT GOING is a delete() of that same document, and the displayed count
// is just "how many documents currently exist with this status" — it is
// definitionally correct at read time, with no running total that can
// drift from reality, no delta math, and no dependency on the client
// knowing what the server previously stored.
//
// Cost/efficiency: this reads every attendee doc for one occurrence on
// every dialog open, instead of one cheap counter read. For a jam session
// — realistically single digits to a few dozen people, not a stadium show
// — that's a handful of document reads (Firestore's free tier alone covers
// 50k reads/day), effectively free at MoneyGigs' current and foreseeable
// scale. If a single occurrence ever routinely drew hundreds of attendees,
// Firestore's native count() aggregation query (billed ~1 read per 1000
// matched docs) or a Cloud-Function-maintained counter would be the next
// optimization — not worth the added complexity before that's a real
// problem.
//
// ── Security rules (add in the Firebase console) ───────────────────────────
//   match /jamAttendance/{occurrenceId}/attendees/{userId} {
//     allow read: if request.auth != null;
//     allow write: if request.auth != null && request.auth.uid == userId;
//   }
// Simpler and stricter than the map-based version this replaces — since
// the vote's own document ID IS the user's uid, "you can only touch your
// own vote" is a plain ID match instead of a map-diff/affectedKeys check.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:the_money_gigs/core/utils/logger.dart';

class JamAttendanceCounts {
  final int going;
  final int interested;

  /// This user's own recorded status for the occurrence, if [getCounts]
  /// was asked to look for one via `forUserId` — null either because
  /// nobody asked, or because that user has no attendee doc yet. Lets a
  /// caller detect drift against its own local record without a second
  /// query (see GigsPage._launchBookingDialogForGig's self-heal-on-open).
  final String? myStatus;

  const JamAttendanceCounts({
    this.going = 0,
    this.interested = 0,
    this.myStatus,
  });
}

class JamAttendanceRepository {
  FirebaseFirestore? _firestore;

  FirebaseFirestore get _firestoreInstance {
    if (_firestore != null) return _firestore!;
    if (Firebase.apps.isEmpty) {
      throw Exception(
          'Firebase not initialized. JamAttendanceRepository requires network mode.');
    }
    _firestore = FirebaseFirestore.instance;
    return _firestore!;
  }

  CollectionReference<Map<String, dynamic>> _attendeesFor(String occurrenceId) =>
      _firestoreInstance
          .collection('jamAttendance')
          .doc(occurrenceId)
          .collection('attendees');

  /// Fetches the current Going/Interested counts for one jam occurrence by
  /// reading its attendees subcollection and counting by status. Returns
  /// zeros (not an error) when nobody has responded yet, or when the fetch
  /// itself fails — this is a nice-to-have display number, never something
  /// worth surfacing an error dialog over.
  ///
  /// Pass [forUserId] to also get that user's own status back in the
  /// result's [JamAttendanceCounts.myStatus] — free, since the whole
  /// subcollection is already being read to build the counts anyway.
  Future<JamAttendanceCounts> getCounts(
    String occurrenceId, {
    String? forUserId,
  }) async {
    try {
      final snapshot = await _attendeesFor(occurrenceId).get();
      int going = 0;
      int interested = 0;
      String? myStatus;
      for (final doc in snapshot.docs) {
        final status = doc.data()['status'] as String?;
        switch (status) {
          case 'going':
            going++;
            break;
          case 'interested':
            interested++;
            break;
        }
        if (forUserId != null && doc.id == forUserId) {
          myStatus = status;
        }
      }
      return JamAttendanceCounts(
        going: going,
        interested: interested,
        myStatus: myStatus,
      );
    } catch (e) {
      log('❌ Error fetching jam attendance counts for $occurrenceId: $e');
      return const JamAttendanceCounts();
    }
  }

  /// Records [userId]'s attendance for one jam occurrence: writes their own
  /// attendee document when [newStatus] is 'going'/'interested', or deletes
  /// it entirely for NOT GOING / clearing a previous vote ([newStatus] ==
  /// null). Idempotent either way — no previous-status bookkeeping needed,
  /// which is the whole point (see the FIX note in the file header).
  ///
  /// Fire-and-forget by design from the call site — a failure here must
  /// never block or roll back the local write, which is already the
  /// user's source of truth for their own device.
  Future<void> setAttendance({
    required String occurrenceId,
    required String userId,
    required String? newStatus,
  }) async {
    try {
      final docRef = _attendeesFor(occurrenceId).doc(userId);
      if (newStatus == null) {
        await docRef.delete();
      } else {
        await docRef.set({
          'status': newStatus,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      log('✅ Jam attendance mirrored: $occurrenceId / $userId -> '
          '${newStatus ?? "(removed)"}');
    } catch (e, stack) {
      log('❌ Error mirroring jam attendance for $occurrenceId: $e');
      // This write is fire-and-forget from the call site (gigs.dart never
      // awaits it), which means a failure here — most likely missing/too
      // strict Firestore security rules on the 'jamAttendance' collection
      // — would otherwise be completely invisible: log() is a no-op in
      // release builds (see main.dart). Same lesson as
      // _recordAppleSignInFailure in auth_service.dart and the
      // deleteMember rollback in network_service.dart: record it
      // somewhere retrievable instead of only logging.
      try {
        await FirebaseCrashlytics.instance.recordError(
          'Jam attendance mirror failed for $occurrenceId ($userId -> '
          '${newStatus ?? "removed"}): $e',
          stack,
          fatal: false,
          reason: 'jam_attendance_mirror_failed',
        );
      } catch (_) {}
    }
  }
}
