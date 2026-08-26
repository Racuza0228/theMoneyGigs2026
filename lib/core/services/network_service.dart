// lib/core/services/network_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'dart:async';
import 'dart:math';
import 'package:the_money_gigs/core/utils/logger.dart';

class NetworkMember {
  final String userId;
  final String email;
  final String displayName;
  final String inviteCodeUsed;
  final String invitedBy;
  final DateTime joinedAt;
  final String subscriptionStatus;
  final List<String> myInviteCodes;

  NetworkMember({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.inviteCodeUsed,
    required this.invitedBy,
    required this.joinedAt,
    required this.subscriptionStatus,
    required this.myInviteCodes,
  });

  factory NetworkMember.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NetworkMember(
      userId: doc.id,
      email: data['email'] as String,
      displayName: data['displayName'] as String? ?? '',
      inviteCodeUsed: data['inviteCodeUsed'] as String,
      invitedBy: data['invitedBy'] as String,
      joinedAt: (data['joinedAt'] as Timestamp).toDate(),
      subscriptionStatus: data['subscriptionStatus'] as String? ?? 'active',
      myInviteCodes: (data['myInviteCodes'] as List?)?.cast<String>() ?? [],
    );
  }

  Map<String, dynamic> toFirestore() => {
    'userId': userId,
    'email': email,
    'displayName': displayName,
    'inviteCodeUsed': inviteCodeUsed,
    'invitedBy': invitedBy,
    'joinedAt': Timestamp.fromDate(joinedAt),
    'subscriptionStatus': subscriptionStatus,
    'myInviteCodes': myInviteCodes,
  };
}

class InviteCode {
  final String code;
  final String createdBy;
  final DateTime createdAt;
  final bool isFounderCode;
  final int maxUses;
  final int timesUsed;
  final List<String> usedBy;

  InviteCode({
    required this.code,
    required this.createdBy,
    required this.createdAt,
    required this.isFounderCode,
    required this.maxUses,
    required this.timesUsed,
    required this.usedBy,
  });

  factory InviteCode.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return InviteCode(
      code: data['code'] as String,
      createdBy: data['createdBy'] as String,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      isFounderCode: data['isFounderCode'] as bool? ?? false,
      maxUses: data['maxUses'] as int? ?? 50,
      timesUsed: data['timesUsed'] as int? ?? 0,
      usedBy: (data['usedBy'] as List?)?.cast<String>() ?? [],
    );
  }

  bool get isAvailable => timesUsed < maxUses;
}

class NetworkService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Check if user has network access
  Future<NetworkMember?> getMember(String userId) async {
    try {
      final doc = await _firestore.collection('networkMembers').doc(userId).get();

      if (!doc.exists) {
        log('❌ User $userId not found in networkMembers');
        return null;
      }

      log('✅ User $userId found in networkMembers');
      return NetworkMember.fromFirestore(doc);
    } catch (e) {
      log('❌ Error checking membership: $e');
      return null;
    }
  }

  /// Rolls back a member created by createMemberWithInviteCode() — called
  /// when the user declines the $2/mo purchase dialog or the purchase fails.
  ///
  /// Fixed 8/21/26: this used to only delete the networkMembers doc, leaving
  /// the invite code's timesUsed/usedBy permanently incremented even on a
  /// clean decline — every failed/declined redemption silently "spent" a use
  /// of the code forever. Confirmed against INV-NASHV (Nashville, 8/14):
  /// timesUsed showed 2 with only one live member, and that member's
  /// subscriptionStatus still read 'active' though she never completed
  /// payment — meaning this rollback either never ran or failed silently
  /// for her. Now reverses the invite-code write atomically with the
  /// member delete, and a rollback failure is recorded via Crashlytics
  /// instead of just logged — same fix pattern as logAppleSignInFailed
  /// (8/17), since a silent failure here leaves a ghost "active" member
  /// with zero trace anywhere retrievable.
  Future<void> deleteMember(String userId) async {
    try {
      final memberRef = _firestore.collection('networkMembers').doc(userId);
      final doc = await memberRef.get();

      final batch = _firestore.batch();
      batch.delete(memberRef);

      if (doc.exists) {
        final inviteCodeUsed = doc.data()?['inviteCodeUsed'] as String?;
        if (inviteCodeUsed != null && inviteCodeUsed.isNotEmpty) {
          batch.update(
            _firestore.collection('inviteCodes').doc(inviteCodeUsed),
            {
              'timesUsed': FieldValue.increment(-1),
              'usedBy': FieldValue.arrayRemove([userId]),
            },
          );
        }
      }

      await batch.commit();
      log('✅ Rolled back and deleted member: $userId (invite code usage reversed)');
    } catch (e, stack) {
      log('❌ Error rolling back member creation for user $userId: $e');
      // Even if this fails, we don't block the user — but a failed rollback
      // here means a ghost "active" networkMembers doc with no paid
      // subscription behind it, and no trace unless we record it.
      unawaited(FirebaseCrashlytics.instance.recordError(
        'Member rollback (deleteMember) failed for $userId: $e',
        stack,
        fatal: false,
      ));
    }
  }

  /// Check if user has access (simple boolean check)
  Future<bool> hasNetworkAccess(String userId) async {
    final member = await getMember(userId);
    return member != null && member.subscriptionStatus == 'active';
  }

  /// Validate an invite code exists and is available
  Future<InviteCode?> validateInviteCode(String code) async {
    try {
      final doc = await _firestore.collection('inviteCodes').doc(code).get();

      if (!doc.exists) {
        log('❌ Invite code not found: $code');
        return null;
      }

      final inviteCode = InviteCode.fromFirestore(doc);

      if (!inviteCode.isAvailable) {
        log('❌ Invite code exhausted: $code (${inviteCode.timesUsed}/${inviteCode.maxUses})');
        return null;
      }

      log('✅ Invite code valid: $code (isFounder: ${inviteCode.isFounderCode})');
      return inviteCode;
    } catch (e) {
      log('❌ Error validating invite code: $e');
      return null;
    }
  }

  /// Create new member with invite code
  Future<bool> createMemberWithInviteCode({
    required String userId,
    required String email,
    required String inviteCode,
  }) async {
    try {
      log('🔵 Creating member with code: $inviteCode');

      // 1. Validate invite code
      final inviteCodeDoc = await validateInviteCode(inviteCode);
      if (inviteCodeDoc == null) {
        return false;
      }

      // 2. Generate new invite codes for this member (always regular codes)
      final newMemberCodes = _generateInviteCodes(userId);

      // 3. Extract display name from email
      final displayName = email.split('@')[0];

      // 4. Create new member document
      final newMember = NetworkMember(
        userId: userId,
        email: email,
        displayName: displayName,
        inviteCodeUsed: inviteCode,
        invitedBy: inviteCodeDoc.createdBy,
        joinedAt: DateTime.now(),
        subscriptionStatus: 'active',
        myInviteCodes: newMemberCodes,
      );

      // Use batch write for atomicity
      final batch = _firestore.batch();

      // 5. Create member
      batch.set(
        _firestore.collection('networkMembers').doc(userId),
        newMember.toFirestore(),
      );

      // 6. Update invite code usage
      batch.update(
        _firestore.collection('inviteCodes').doc(inviteCode),
        {
          'timesUsed': FieldValue.increment(1),
          'usedBy': FieldValue.arrayUnion([userId]),
        },
      );

      // 7. Create invite code documents for new member
      // All generated codes are REGULAR codes (isFounderCode: false)
      for (final code in newMemberCodes) {
        batch.set(
          _firestore.collection('inviteCodes').doc(code),
          {
            'code': code,
            'createdBy': userId,
            'createdAt': FieldValue.serverTimestamp(),
            'isFounderCode': false,
            'maxUses': 50,
            'timesUsed': 0,
            'usedBy': [],
          },
        );
      }

      // Commit batch
      await batch.commit();

      log('✅ New member created: $userId with codes: $newMemberCodes');
      return true;
    } catch (e) {
      log('❌ Error creating member: $e');
      return false;
    }
  }

  /// Generate secure invite codes
  List<String> _generateInviteCodes(String userId) {
    final codes = <String>[];
    for (int i = 0; i < 3; i++) {
      codes.add(_generateSecureCode());
    }
    return codes;
  }

  /// Generate a single secure code: INV-8KJ3MP
  String _generateSecureCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // No confusing chars
    final random = Random.secure();
    final code = List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
    return 'INV-$code';
  }
}