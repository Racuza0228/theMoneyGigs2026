// lib/core/services/network_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

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
        print('❌ User $userId not found in networkMembers');
        return null;
      }

      print('✅ User $userId found in networkMembers');
      return NetworkMember.fromFirestore(doc);
    } catch (e) {
      print('❌ Error checking membership: $e');
      return null;
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
        print('❌ Invite code not found: $code');
        return null;
      }

      final inviteCode = InviteCode.fromFirestore(doc);

      if (!inviteCode.isAvailable) {
        print('❌ Invite code exhausted: $code (${inviteCode.timesUsed}/${inviteCode.maxUses})');
        return null;
      }

      print('✅ Invite code valid: $code (isFounder: ${inviteCode.isFounderCode})');
      return inviteCode;
    } catch (e) {
      print('❌ Error validating invite code: $e');
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
      print('🔵 Creating member with code: $inviteCode');

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

      print('✅ New member created: $userId with codes: $newMemberCodes');
      return true;
    } catch (e) {
      print('❌ Error creating member: $e');
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