// lib/features/bands/models/band_model.dart
//
// Band/Project Expansion v3.0.0 — Sprint Task 2
//
// BandProject lives in a top-level Firestore collection ('bands') — not
// subcollected under networkMembers. This is required because a member needs
// to query bands they belong to but don't lead, which is impossible if band
// documents are nested under another user's record. See spec section 2.1.
//
// BandMember is an embedded object inside BandProject.members — not its own
// subcollection — so a band's full member list comes back on a single
// document fetch. See spec section 2.2.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:the_money_gigs/core/models/person_model.dart';

/// One member of a band/project. Embedded inside [BandProject.members] —
/// there is no separate Firestore document per member.
///
/// FIX (8/26/26): now composes a shared [Person] internally (see
/// core/models/person_model.dart) instead of owning name/email/phone/
/// instruments directly — the same fields the new networking Contact
/// feature needed, so rather than let the two drift into separate copies
/// they share one definition. This is a Dart-level refactor ONLY: every
/// public getter/setter below has the exact same name and type as before
/// (still plain fields as far as any calling code can tell), and toMap()/
/// fromMap() still read and write the exact same flat top-level Firestore
/// keys ('name', 'email', 'phone', 'instruments' — no nested 'person' map).
/// Every existing band already saved in Firestore, and every other file
/// that constructs or reads a BandMember, needed zero changes for this.
class BandMember {
  final Person _person;
  String? networkMemberId; // null until matched on join (see spec section 6)
  String status; // 'invited' | 'active'
  DateTime? invitedAt; // when first invite email sent
  String? inviteCodeSent; // which code was included in the invite

  BandMember({
    required String localId,
    required String name,
    required String email,
    String? phone,
    List<String> instruments = const [],
    this.networkMemberId,
    this.status = 'invited',
    this.invitedAt,
    this.inviteCodeSent,
  }) : _person = Person(
    localId: localId,
    name: name,
    email: email,
    phone: phone,
    instruments: instruments,
  );

  // ── Forwarding accessors — same names/types/mutability as before ────────
  String get localId => _person.localId;
  String get name => _person.name;
  set name(String value) => _person.name = value;
  // Person.email is nullable (a bare Contact might not have one); BandMember
  // has always required one (band invites go out by email), so the getter
  // falls back to '' rather than exposing null to callers that never had to
  // handle it.
  String get email => _person.email ?? '';
  set email(String value) => _person.email = value;
  String? get phone => _person.phone;
  set phone(String? value) => _person.phone = value;
  List<String> get instruments => _person.instruments;
  set instruments(List<String> value) => _person.instruments = value;

  bool get isActive => status == 'active';

  BandMember copyWith({
    String? name,
    String? email,
    String? phone,
    List<String>? instruments,
    String? networkMemberId,
    String? status,
    DateTime? invitedAt,
    String? inviteCodeSent,
  }) {
    return BandMember(
      localId: localId,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      instruments: instruments ?? this.instruments,
      networkMemberId: networkMemberId ?? this.networkMemberId,
      status: status ?? this.status,
      invitedAt: invitedAt ?? this.invitedAt,
      inviteCodeSent: inviteCodeSent ?? this.inviteCodeSent,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'localId': localId,
      'name': name,
      'email': email,
      'phone': phone,
      'instruments': instruments,
      'networkMemberId': networkMemberId,
      'status': status,
      'invitedAt': invitedAt != null ? Timestamp.fromDate(invitedAt!) : null,
      'inviteCodeSent': inviteCodeSent,
    };
  }

  factory BandMember.fromMap(Map<String, dynamic> map) {
    return BandMember(
      localId: map['localId'] as String,
      name: map['name'] as String? ?? '',
      email: map['email'] as String,
      phone: map['phone'] as String?,
      instruments: (map['instruments'] as List?)?.cast<String>() ?? [],
      networkMemberId: map['networkMemberId'] as String?,
      status: map['status'] as String? ?? 'invited',
      invitedAt: map['invitedAt'] != null
          ? (map['invitedAt'] as Timestamp).toDate()
          : null,
      inviteCodeSent: map['inviteCodeSent'] as String?,
    );
  }
}

/// A band or project — the top-level, queryable Firestore entity a gig can
/// reference via Gig.bandId. See spec section 2.1.
class BandProject {
  final String bandId; // Firestore document ID (empty until first save)
  String name;
  final String leaderId; // networkMembers userId of creator
  List<BandMember> members;
  DateTime createdAt;
  DateTime updatedAt;

  BandProject({
    required this.bandId,
    required this.name,
    required this.leaderId,
    this.members = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  int get memberCount => members.length;

  bool isLeader(String userId) => leaderId == userId;

  bool isMember(String userId) =>
      members.any((m) => m.networkMemberId == userId);

  /// Every email in [members], always — flat and queryable.
  /// Kept in sync with [members] per the two-array sync rule (spec 2.3):
  /// write both memberEmails and memberNetworkIds whenever members change.
  List<String> get memberEmails => members.map((m) => m.email).toList();

  /// Only confirmed app users — flat and queryable. Populated by the
  /// join-time reverse handshake (spec section 6).
  List<String> get memberNetworkIds => members
      .map((m) => m.networkMemberId)
      .whereType<String>()
      .toList();

  BandProject copyWith({
    String? name,
    List<BandMember>? members,
    DateTime? updatedAt,
  }) {
    return BandProject(
      bandId: bandId,
      name: name ?? this.name,
      leaderId: leaderId,
      members: members ?? this.members,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  /// Note: memberEmails and memberNetworkIds are written explicitly here
  /// (not derived at read time) so Firestore's arrayContains / == queries in
  /// BandRepository (spec section 4.1) can filter on them directly.
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'leaderId': leaderId,
      'members': members.map((m) => m.toMap()).toList(),
      'memberEmails': memberEmails,
      'memberNetworkIds': memberNetworkIds,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory BandProject.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BandProject(
      bandId: doc.id,
      name: data['name'] as String? ?? 'Untitled Band',
      leaderId: data['leaderId'] as String,
      members: (data['members'] as List?)
          ?.map((m) => BandMember.fromMap(m as Map<String, dynamic>))
          .toList() ??
          [],
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }
}
